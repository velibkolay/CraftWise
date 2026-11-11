// Upload tokens (bearer, hashed in D1) and the Cloudflare Access check for /me and /api/me/*.
import type { Env } from "./env";
import { HttpError } from "./http";
import { DAY, UPLOADS_PER_MINUTE, WRITE_BUDGET } from "./limits";

export type Scope = "public" | "private";
export const SCOPES: readonly Scope[] = ["public", "private"];

const TOKEN = /^cw_[A-Za-z0-9_-]{43}$/;

function hex(buf: ArrayBuffer): string {
	return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function base64url(bytes: Uint8Array): string {
	let s = "";
	for (const b of bytes) s += String.fromCharCode(b);
	return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function hashToken(token: string): Promise<string> {
	return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)));
}

// "cw_" + 32 random bytes. Shown once; only its SHA-256 is stored.
export function newToken(): string {
	return "cw_" + base64url(crypto.getRandomValues(new Uint8Array(32)));
}

// Checks the bearer token, counts the request against the token's per-minute limit and reads
// today's rows written. One D1 batch; an unknown or revoked token writes nothing.
export async function uploadAuth(request: Request, env: Env, scope: Scope, now: number): Promise<{ tokenId: number; written: number }> {
	const m = /^Bearer (\S+)$/.exec(request.headers.get("authorization") ?? "");
	if (!m || !TOKEN.test(m[1]!)) {
		throw new HttpError(401, "unauthorized", "missing or malformed bearer token", { "www-authenticate": "Bearer" });
	}
	const hash = await hashToken(m[1]!);
	const minute = Math.floor(now / 60);
	const [tok, usage] = await env.DB.batch<{ id: number; scopes: string; rl_count: number } & { rows_written: number }>([
		env.DB.prepare(
			`UPDATE tokens SET last_used = ?2,
				rl_count = CASE WHEN rl_window = ?3 THEN rl_count + 1 ELSE 1 END, rl_window = ?3
			WHERE hash = ?1 AND revoked IS NULL RETURNING id, scopes, rl_count`,
		).bind(hash, now, minute),
		env.DB.prepare("SELECT rows_written FROM usage WHERE day = ?1").bind(Math.floor(now / DAY)),
	]);
	const row = tok?.results[0];
	if (!row) {
		throw new HttpError(401, "unauthorized", "unknown or revoked token", { "www-authenticate": "Bearer" });
	}
	if (!row.scopes.split(" ").includes(scope)) {
		throw new HttpError(403, "forbidden", `token lacks the "${scope}" scope`);
	}
	if (row.rl_count > UPLOADS_PER_MINUTE) {
		throw new HttpError(429, "rate_limited", `more than ${UPLOADS_PER_MINUTE} uploads a minute`, {
			"retry-after": String(60 - (now % 60)),
		});
	}
	const written = usage?.results[0]?.rows_written ?? 0;
	if (written >= WRITE_BUDGET) {
		throw new HttpError(429, "write_budget", `daily write budget (${WRITE_BUDGET} rows) used up; resets 00:00 UTC`, {
			"retry-after": String(DAY - (now % DAY)),
		});
	}
	return { tokenId: row.id, written };
}

// Refuses an upload whose rows (an upper bound: rows that don't change are not written) would take
// today's total over the budget. A refused upload writes nothing; the companion retries after
// Retry-After (00:00 UTC). D1 itself stops all writes at 100,000 rows a day on the free plan.
export function checkBudget(written: number, estimate: number, now: number): void {
	if (written + estimate > WRITE_BUDGET) {
		throw new HttpError(429, "write_budget", `upload needs up to ${estimate} rows, ${WRITE_BUDGET - written} left today; resets 00:00 UTC`, {
			"retry-after": String(DAY - (now % DAY)),
		});
	}
}

// Adds D1's rows written for an upload or the cron job to today's total.
export function usageStatement(env: Env, now: number, rowsWritten: number, uploads: number): D1PreparedStatement {
	return env.DB.prepare(
		`INSERT INTO usage (day, rows_written, uploads) VALUES (?1, ?2, ?3)
		ON CONFLICT (day) DO UPDATE SET rows_written = rows_written + excluded.rows_written, uploads = uploads + excluded.uploads`,
	).bind(Math.floor(now / DAY), rowsWritten, uploads);
}

export function rowsWritten(results: D1Result[]): number {
	return results.reduce((sum, r) => sum + (r.meta?.rows_written ?? 0), 0);
}

// ---------------------------------------------------------------------------------------------
// Cloudflare Access: the Access app in front of /me* and /api/me/* signs every request it lets
// through (Cf-Access-Jwt-Assertion, RS256). The Worker checks it too, so a missing or
// misconfigured Access app never opens the private data.
// ---------------------------------------------------------------------------------------------

interface Jwk extends JsonWebKey {
	kid?: string;
}

const JWKS_TTL_MS = 10 * 60 * 1000;
let jwksCache: { team: string; at: number; keys: Jwk[] } | null = null;

async function accessKeys(team: string, force: boolean): Promise<Jwk[]> {
	if (!force && jwksCache && jwksCache.team === team && Date.now() - jwksCache.at < JWKS_TTL_MS) {
		return jwksCache.keys;
	}
	const res = await fetch(`https://${team}/cdn-cgi/access/certs`);
	if (!res.ok) throw new HttpError(503, "access_keys", `Access keys unavailable (${res.status})`);
	const body = (await res.json()) as { keys?: Jwk[] };
	const keys = Array.isArray(body.keys) ? body.keys : [];
	jwksCache = { team, at: Date.now(), keys };
	return keys;
}

function b64urlBytes(s: string): Uint8Array {
	const b = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4));
	const out = new Uint8Array(b.length);
	for (let i = 0; i < b.length; i++) out[i] = b.charCodeAt(i);
	return out;
}

function b64urlJson(s: string): Record<string, unknown> {
	try {
		const v: unknown = JSON.parse(new TextDecoder().decode(b64urlBytes(s)));
		if (typeof v === "object" && v !== null && !Array.isArray(v)) return v as Record<string, unknown>;
	} catch {
		// falls through
	}
	throw new HttpError(403, "access_denied", "malformed Access token");
}

export interface AccessUser {
	email: string | null;
	sub: string;
}

export async function verifyAccess(request: Request, env: Env, now: number): Promise<AccessUser> {
	const team = env.ACCESS_TEAM_DOMAIN;
	const aud = env.ACCESS_AUD;
	if (!team || !aud) {
		throw new HttpError(503, "access_not_configured", "ACCESS_TEAM_DOMAIN / ACCESS_AUD not set");
	}
	const jwt = request.headers.get("cf-access-jwt-assertion");
	if (!jwt) throw new HttpError(403, "access_denied", "no Access token (Cf-Access-Jwt-Assertion)");
	const parts = jwt.split(".");
	if (parts.length !== 3) throw new HttpError(403, "access_denied", "malformed Access token");
	const [h, p, s] = parts as [string, string, string];
	const header = b64urlJson(h);
	const payload = b64urlJson(p);
	if (header.alg !== "RS256" || typeof header.kid !== "string") {
		throw new HttpError(403, "access_denied", "unexpected Access token algorithm");
	}

	let keys = await accessKeys(team, false);
	let jwk = keys.find((k) => k.kid === header.kid);
	if (!jwk) {
		keys = await accessKeys(team, true); // keys rotate
		jwk = keys.find((k) => k.kid === header.kid);
	}
	if (!jwk) throw new HttpError(403, "access_denied", "unknown Access signing key");
	const key = await crypto.subtle.importKey(
		"jwk",
		{ kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
		{ name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
		false,
		["verify"],
	);
	const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, b64urlBytes(s), new TextEncoder().encode(`${h}.${p}`));
	if (!ok) throw new HttpError(403, "access_denied", "bad Access token signature");

	if (payload.iss !== `https://${team}`) throw new HttpError(403, "access_denied", "wrong Access issuer");
	const auds = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
	if (!auds.includes(aud)) throw new HttpError(403, "access_denied", "wrong Access audience");
	const skew = 60;
	if (typeof payload.exp !== "number" || payload.exp + skew < now) throw new HttpError(403, "access_denied", "Access token expired");
	if (typeof payload.nbf === "number" && payload.nbf - skew > now) throw new HttpError(403, "access_denied", "Access token not valid yet");
	if (typeof payload.sub !== "string") throw new HttpError(403, "access_denied", "Access token without subject");
	return { email: typeof payload.email === "string" ? payload.email : null, sub: payload.sub };
}

// For tests: forget cached Access keys.
export function resetAccessKeys(): void {
	jwksCache = null;
}
