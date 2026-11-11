// wow.velikopter.com Worker (#95): public price API, uploads from the companion app (#94), and the
// private API behind Cloudflare Access. Static pages come from ./public (Workers static assets);
// only /api/*, /me and /me/* reach this code first (wrangler.jsonc run_worker_first).
import { rowsWritten, usageStatement, verifyAccess } from "./auth";
import type { Env } from "./env";
import { errorResponse, HttpError, json } from "./http";
import * as L from "./limits";
import * as me from "./me";
import * as read from "./read";
import { assertJson, privateUpload, publicUpload } from "./upload";

function nowSeconds(): number {
	return Math.floor(Date.now() / 1000);
}

function methodNotAllowed(allow: string): never {
	throw new HttpError(405, "method_not_allowed", `use ${allow}`, { allow });
}

// Requests that change data on /api/me/* must come from this site (Access authenticates by cookie).
function assertSameOrigin(request: Request, url: URL): void {
	const origin = request.headers.get("origin");
	if (origin !== url.origin) throw new HttpError(403, "bad_origin", "cross-site request refused");
}

async function privateApi(request: Request, env: Env, url: URL, now: number): Promise<Response> {
	const user = await verifyAccess(request, env, now);
	const path = url.pathname.slice("/api/me".length);
	const method = request.method;
	// An Access service token (no e-mail, e.g. Claude's read access) may only read.
	if (user.email === null && method !== "GET" && method !== "HEAD") {
		throw new HttpError(403, "read_only", "service tokens can only read");
	}
	if (method !== "GET" && method !== "HEAD") assertSameOrigin(request, url);

	if (path === "" || path === "/") {
		if (method !== "GET") methodNotAllowed("GET");
		return json({ email: user.email }, 200, { "cache-control": "private, no-store" });
	}
	if (path === "/characters") {
		if (method !== "GET") methodNotAllowed("GET");
		return me.characters(env);
	}
	const char = /^\/characters\/([^/]+)$/.exec(path);
	if (char) {
		if (method !== "GET") methodNotAllowed("GET");
		return me.character(env, decodeURIComponent(char[1]!));
	}
	if (path === "/ledger") {
		if (method !== "GET") methodNotAllowed("GET");
		return me.ledger(env, url);
	}
	if (path === "/usage") {
		if (method !== "GET") methodNotAllowed("GET");
		return me.usage(env, now);
	}
	if (path === "/tokens") {
		if (method === "GET") return me.listTokens(env);
		if (method === "POST") {
			assertJson(request);
			return me.createToken(request, env, user, now);
		}
		methodNotAllowed("GET, POST");
	}
	const token = /^\/tokens\/([1-9][0-9]{0,9})$/.exec(path);
	if (token) {
		if (method !== "DELETE") methodNotAllowed("DELETE");
		return me.revokeToken(env, Number(token[1]), now);
	}
	throw new HttpError(404, "not_found", "no such endpoint");
}

async function route(request: Request, env: Env): Promise<Response> {
	const url = new URL(request.url);
	const path = url.pathname;
	const now = nowSeconds();

	// The private page itself: served only with a valid Access login.
	if (path === "/me" || path.startsWith("/me/")) {
		await verifyAccess(request, env, now);
		const res = await env.ASSETS.fetch(request);
		const out = new Response(res.body, res);
		out.headers.set("cache-control", "private, no-store");
		return out;
	}
	if (path === "/api/me" || path.startsWith("/api/me/")) return privateApi(request, env, url, now);

	if (path === "/api/upload" || path === "/api/private/upload") {
		if (request.method !== "POST") methodNotAllowed("POST");
		assertJson(request);
		return path === "/api/upload" ? publicUpload(request, env, now) : privateUpload(request, env, now);
	}

	if (request.method !== "GET" && request.method !== "HEAD") methodNotAllowed("GET");
	if (path === "/api/houses") return read.houses(env);
	if (path === "/api/scans") return read.scans(env, url);
	if (path === "/api/items") return read.search(env, url);
	const item = /^\/api\/items\/([1-9][0-9]{0,9})$/.exec(path);
	if (item) return read.itemDetail(env, url, Number(item[1]), now);
	if (path === "/api/movers") return read.movers(env, url, now);
	if (path.startsWith("/api/")) throw new HttpError(404, "not_found", "no such endpoint");
	return env.ASSETS.fetch(request);
}

// Daily retention: raw points (30 days), scan log, usage and cache rows.
export async function retention(env: Env, now: number): Promise<number> {
	const today = Math.floor(now / L.DAY);
	const db = env.DB;
	const results = await db.batch([
		db.prepare("DELETE FROM points WHERE t < ?1").bind(now - L.RAW_DAYS * L.DAY),
		db.prepare("DELETE FROM scans WHERE t < ?1").bind(now - L.SCANS_DAYS * L.DAY),
		db.prepare("DELETE FROM usage WHERE day < ?1").bind(today - L.USAGE_DAYS),
		db.prepare("DELETE FROM cache WHERE t < ?1").bind(now - L.CACHE_DAYS * L.DAY),
	]);
	const written = rowsWritten(results);
	await usageStatement(env, now, written, 0).run();
	return written;
}

export default {
	async fetch(request, env, _ctx): Promise<Response> {
		try {
			return await route(request, env);
		} catch (e) {
			if (e instanceof HttpError) return errorResponse(e);
			console.error("unhandled", e instanceof Error ? e.stack : e);
			return errorResponse(new HttpError(500, "internal", "internal error"));
		}
	},
	async scheduled(_controller, env, ctx): Promise<void> {
		ctx.waitUntil(retention(env, nowSeconds()));
	},
} satisfies ExportedHandler<Env>;
