// Private API under /api/me/* (Cloudflare Access + JWT check in index.ts): characters, their
// snapshot / auctions / fishing documents, the ledger, upload tokens, today's write usage.
import { hashToken, newToken, SCOPES, type AccessUser, type Scope } from "./auth";
import type { Env } from "./env";
import { HttpError, intParam, json, parseJson, readBody } from "./http";
import { DAY, MAX_ACTIVE_TOKENS, parseWriteBudget, softBudget } from "./limits";

const PRIVATE = { "cache-control": "private, no-store" };

export async function characters(env: Env): Promise<Response> {
	const { results } = await env.DB.prepare(
		`SELECT c.*, s.t AS snapshot_t, a.t AS auctions_t, f.t AS fishing_t FROM characters c
		LEFT JOIN snapshots s ON s.char = c.key LEFT JOIN auctions a ON a.char = c.key LEFT JOIN fishing f ON f.char = c.key
		ORDER BY c.key`,
	).all<Record<string, string | number | null>>();
	return json(
		{
			characters: results.map((c) => ({
				key: c.key,
				realm: c.realm,
				name: c.name,
				surname: c.surname,
				faction: c.faction,
				race: c.race,
				class: c.class,
				level: c.level,
				snapshotT: c.snapshot_t,
				auctionsT: c.auctions_t,
				fishingT: c.fishing_t,
			})),
		},
		200,
		PRIVATE,
	);
}

export async function character(env: Env, key: string): Promise<Response> {
	const db = env.DB;
	const [c, s, a, f] = await db.batch([
		db.prepare("SELECT * FROM characters WHERE key = ?1").bind(key),
		db.prepare("SELECT t, data FROM snapshots WHERE char = ?1").bind(key),
		db.prepare("SELECT t, data FROM auctions WHERE char = ?1").bind(key),
		db.prepare("SELECT t, data FROM fishing WHERE char = ?1").bind(key),
	]);
	if (!c!.results.length) throw new HttpError(404, "not_found", "unknown character");
	const doc = (r: D1Result) => {
		const row = r.results[0] as { t: number; data: string } | undefined;
		return row ? { t: row.t, data: JSON.parse(row.data) as unknown } : null;
	};
	return json({ key, snapshot: doc(s!), auctions: doc(a!), fishing: doc(f!) }, 200, PRIVATE);
}

// The addon's watch list (#165), newest first: [{ item, added }].
export async function watch(env: Env): Promise<Response> {
	const { results } = await env.DB.prepare("SELECT item, added FROM watch ORDER BY added DESC, item DESC").all<{ item: number; added: number }>();
	return json({ watch: results }, 200, PRIVATE);
}

export async function ledger(env: Env, url: URL): Promise<Response> {
	const char = url.searchParams.get("char");
	const since = intParam(url, "since", 0, 0, Number.MAX_SAFE_INTEGER);
	const limit = intParam(url, "limit", 500, 1, 5000);
	const sql = `SELECT char, t, kind, item, qty, money, place, name FROM ledger WHERE t >= ?1 ${char ? "AND char = ?3" : ""}
		ORDER BY t DESC LIMIT ?2`;
	const stmt = char ? env.DB.prepare(sql).bind(since, limit, char) : env.DB.prepare(sql).bind(since, limit);
	const { results } = await stmt.all();
	return json({ entries: results }, 200, PRIVATE);
}

// Today's rows written (uploads and the cron job) against the budget (the Worker var WRITE_BUDGET)
// and its soft limit (item info and names stop there, #145), and the database size (free plan:
// 500 MB per database).
export async function usage(env: Env, now: number): Promise<Response> {
	const budget = parseWriteBudget(env.WRITE_BUDGET);
	const res = await env.DB.prepare("SELECT rows_written, uploads FROM usage WHERE day = ?1")
		.bind(Math.floor(now / DAY))
		.all<{ rows_written: number; uploads: number }>();
	const row = res.results[0];
	return json(
		{
			day: Math.floor(now / DAY),
			rowsWritten: row?.rows_written ?? 0,
			uploads: row?.uploads ?? 0,
			budget,
			softBudget: softBudget(budget),
			dbBytes: (res.meta as { size_after?: number }).size_after ?? null,
		},
		200,
		PRIVATE,
	);
}

export async function listTokens(env: Env): Promise<Response> {
	const { results } = await env.DB.prepare(
		"SELECT id, prefix, name, scopes, created, created_by, last_used, revoked FROM tokens ORDER BY id DESC",
	).all<Record<string, string | number | null>>();
	return json(
		{
			tokens: results.map((t) => ({
				id: t.id,
				prefix: t.prefix,
				name: t.name,
				scopes: String(t.scopes).split(" "),
				created: t.created,
				createdBy: t.created_by,
				lastUsed: t.last_used,
				revoked: t.revoked,
			})),
		},
		200,
		PRIVATE,
	);
}

// Body { name, scopes: ["public", "private"] }. The token is in the response only, once.
export async function createToken(request: Request, env: Env, user: AccessUser, now: number): Promise<Response> {
	const body = parseJson(await readBody(request, 10_000)) as { name?: unknown; scopes?: unknown };
	if (typeof body !== "object" || body === null) throw new HttpError(400, "bad_shape", "body: expected an object");
	const name = body.name;
	if (typeof name !== "string" || name.trim().length === 0 || name.length > 64) {
		throw new HttpError(400, "bad_shape", "name: expected a string of 1 to 64 characters");
	}
	const scopes = body.scopes ?? ["public", "private"];
	if (
		!Array.isArray(scopes) ||
		scopes.length === 0 ||
		!scopes.every((s): s is Scope => SCOPES.includes(s as Scope)) ||
		new Set(scopes).size !== scopes.length
	) {
		throw new HttpError(400, "bad_shape", 'scopes: expected a non-empty list of "public" and/or "private"');
	}
	const active = await env.DB.prepare("SELECT count(*) AS n FROM tokens WHERE revoked IS NULL").first<{ n: number }>();
	if ((active?.n ?? 0) >= MAX_ACTIVE_TOKENS) {
		throw new HttpError(409, "too_many_tokens", `at most ${MAX_ACTIVE_TOKENS} active tokens; revoke one first`);
	}
	const token = newToken();
	const prefix = token.slice(0, 7);
	const sorted = SCOPES.filter((s) => scopes.includes(s)).join(" ");
	const row = await env.DB.prepare(
		"INSERT INTO tokens (hash, prefix, name, scopes, created, created_by) VALUES (?1, ?2, ?3, ?4, ?5, ?6) RETURNING id",
	)
		.bind(await hashToken(token), prefix, name.trim(), sorted, now, user.email)
		.first<{ id: number }>();
	return json({ id: row!.id, token, prefix, name: name.trim(), scopes: sorted.split(" "), created: now }, 201, PRIVATE);
}

export async function revokeToken(env: Env, id: number, now: number): Promise<Response> {
	const row = await env.DB.prepare("UPDATE tokens SET revoked = ?2 WHERE id = ?1 AND revoked IS NULL RETURNING id")
		.bind(id, now)
		.first<{ id: number }>();
	if (!row) throw new HttpError(404, "not_found", "no active token with this id");
	return json({ id, revoked: now }, 200, PRIVATE);
}
