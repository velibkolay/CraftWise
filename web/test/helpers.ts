import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { vi } from "vitest";
import { hashToken, newToken, resetAccessKeys } from "../src/auth";
import worker from "../src/index";

export const ORIGIN = "https://wow.velikopter.com";
export const TEAM = "velikopter.cloudflareaccess.com";
export const REALM = "CAMWOW EU4 Realm 8 PvP";
export const HORDE = `${REALM}|H`;
export const BOOTY = `${REALM}|N:BootyBay`;

export function now(): number {
	return Math.floor(Date.now() / 1000);
}

export async function call(
	method: string,
	path: string,
	opts: { body?: unknown; raw?: string; headers?: Record<string, string> } = {},
): Promise<Response> {
	const headers: Record<string, string> = { ...opts.headers };
	let body: string | undefined;
	if (opts.raw !== undefined) body = opts.raw;
	else if (opts.body !== undefined) body = JSON.stringify(opts.body);
	if (body !== undefined && !headers["content-type"]) headers["content-type"] = "application/json";
	const request = new Request<unknown, IncomingRequestCfProperties>(ORIGIN + path, { method, headers, body });
	const ctx = createExecutionContext();
	const res = await worker.fetch(request, env, ctx);
	await waitOnExecutionContext(ctx);
	return res;
}

export async function makeToken(scopes = "public private", name = "test"): Promise<string> {
	const token = newToken();
	await env.DB.prepare("INSERT INTO tokens (hash, prefix, name, scopes, created) VALUES (?1, ?2, ?3, ?4, ?5)")
		.bind(await hashToken(token), token.slice(0, 7), name, scopes, now())
		.run();
	return token;
}

export function bearer(token: string): Record<string, string> {
	return { authorization: `Bearer ${token}` };
}

export function houses() {
	return {
		[HORDE]: { realm: REALM, kind: "faction", faction: "Horde", label: "Horde AH" },
		[BOOTY]: { realm: REALM, kind: "neutral", label: "Booty Bay" },
	};
}

// Uploads a test shorthand (see `body` below).
export async function upload(token: string, short: Short): Promise<Response> {
	return call("POST", "/api/upload", { body: body(short), headers: bearer(token) });
}

// ------------------------------------------------------------------------------------------
// Cloudflare Access: a test signing key served at the team's certs URL.
// ------------------------------------------------------------------------------------------

function b64url(bytes: Uint8Array | string): string {
	const s = typeof bytes === "string" ? bytes : String.fromCharCode(...bytes);
	return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export interface AccessKey {
	kid: string;
	privateKey: CryptoKey;
	jwk: JsonWebKey & { kid: string };
}

export async function accessKey(kid = "test-key"): Promise<AccessKey> {
	const pair = (await crypto.subtle.generateKey(
		{ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
		true,
		["sign", "verify"],
	)) as CryptoKeyPair;
	const jwk = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as JsonWebKey;
	return { kid, privateKey: pair.privateKey, jwk: { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", kid } };
}

// Serves `keys` at https://<team>/cdn-cgi/access/certs; counts the fetches.
export function serveAccessKeys(keys: AccessKey[], reset = true) {
	if (reset) resetAccessKeys();
	vi.restoreAllMocks();
	const calls = { n: 0 };
	vi.spyOn(globalThis, "fetch").mockImplementation(async (input: RequestInfo | URL) => {
		const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
		if (url === `https://${TEAM}/cdn-cgi/access/certs`) {
			calls.n++;
			return new Response(JSON.stringify({ keys: keys.map((k) => k.jwk) }), { headers: { "content-type": "application/json" } });
		}
		throw new Error(`unexpected fetch ${url}`);
	});
	return calls;
}

export async function accessJwt(key: AccessKey, claims: Record<string, unknown> = {}): Promise<string> {
	const t = now();
	const header = b64url(JSON.stringify({ alg: "RS256", kid: key.kid, typ: "JWT" }));
	const payload = b64url(
		JSON.stringify({ iss: `https://${TEAM}`, aud: ["test-aud"], sub: "user-1", email: "veli@example.com", iat: t, nbf: t, exp: t + 3600, ...claims }),
	);
	const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key.privateKey, new TextEncoder().encode(`${header}.${payload}`)));
	return `${header}.${payload}.${b64url(sig)}`;
}

export function access(jwt: string, extra: Record<string, string> = {}): Record<string, string> {
	return { "cf-access-jwt-assertion": jwt, ...extra };
}

// Empties every table (storage is shared by the tests of one file).
export async function clearData(): Promise<void> {
	const tables = ["houses", "items", "item_words", "prices", "points", "daily", "scans", "cache", "tokens", "usage", "characters", "snapshots", "auctions", "fishing", "ledger"];
	await env.DB.batch(tables.map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
}

// Test shorthand -> the upload contract (web/docs/api.md):
//   scans: [{ house, ... }]                      -> scans: { [house]: [...] }
//   items: { [id]: { n, q, i, c, s } }           -> names + itemInfo
//   prices: [{ item, house, last, raw, days }]   -> items: { [item]: { [house]: entry } }
//   raw tiers [p, q, p, q]                        -> [{ price, qty }]; days [{ day, ... }] -> { [day]: ... }
export interface Short {
	v?: number;
	houses?: unknown;
	scans?: ({ house: string } & Record<string, unknown>)[];
	items?: Record<string, { n?: string; q?: number; i?: number; c?: number; s?: number }>;
	prices?: {
		item: string;
		house: string;
		last?: unknown;
		raw?: ({ tiers: number[] } & Record<string, unknown>)[];
		days?: ({ day: number } & Record<string, unknown>)[];
	}[];
}

export function body(s: Short): Record<string, unknown> {
	const out: Record<string, unknown> = { v: s.v ?? 1, houses: s.houses ?? houses() };
	if (s.scans) {
		const scans: Record<string, unknown[]> = {};
		for (const { house, ...rest } of s.scans) (scans[house] ??= []).push(rest);
		out.scans = scans;
	}
	if (s.items) {
		const names: Record<string, string> = {};
		const itemInfo: Record<string, unknown> = {};
		for (const [id, { n, ...info }] of Object.entries(s.items)) {
			if (n !== undefined) names[id] = n;
			if (Object.keys(info).length) itemInfo[id] = info;
		}
		out.names = names;
		out.itemInfo = itemInfo;
	}
	if (s.prices) {
		const items: Record<string, Record<string, unknown>> = {};
		for (const p of s.prices) {
			const entry: Record<string, unknown> = {};
			if (p.last) entry.last = p.last;
			if (p.raw) {
				entry.raw = p.raw.map(({ tiers, ...r }) => ({
					...r,
					tiers: Array.from({ length: tiers.length / 2 }, (_, i) => ({ price: tiers[2 * i], qty: tiers[2 * i + 1] })),
				}));
			}
			if (p.days) entry.days = Object.fromEntries(p.days.map(({ day, ...d }) => [String(day), d]));
			(items[p.item] ??= {})[p.house] = entry;
		}
		out.items = items;
	}
	return out;
}
