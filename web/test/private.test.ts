import { env } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
	access,
	accessJwt,
	accessKey,
	bearer,
	call,
	clearData,
	makeToken,
	now,
	ORIGIN,
	serveAccessKeys,
	type AccessKey,
} from "./helpers";
import { PAGE_HEADERS } from "../src/pages";

const CHAR = "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner";

let key: AccessKey;
let other: AccessKey;
beforeAll(async () => {
	key = await accessKey("k1");
	other = await accessKey("k2");
});
beforeEach(async () => {
	await clearData();
	serveAccessKeys([key]);
});
afterEach(() => {
	vi.restoreAllMocks();
});

function snapshot(t: number, level = 20) {
	return {
		v: 1,
		t,
		char: { name: "Velikopter", surname: "Tanner", realm: "CAMWOW EU4 Realm 8 PvP", faction: "Horde", race: "Orc", class: "Hunter", level },
		location: { zone: "Orgrimmar" },
	};
}

async function privateUpload(token: string, body: unknown) {
	return call("POST", "/api/private/upload", { body, headers: bearer(token) });
}

describe("Cloudflare Access check", () => {
	it("refuses /api/me and /me without a valid Access token", async () => {
		expect((await call("GET", "/api/me")).status).toBe(403);
		expect((await call("GET", "/me")).status).toBe(403);
		expect((await call("GET", "/api/me", { headers: access("a.b.c") })).status).toBe(403);
		// signed by a key Access doesn't list
		expect((await call("GET", "/api/me", { headers: access(await accessJwt(other)) })).status).toBe(403);
		const t = now();
		expect((await call("GET", "/api/me", { headers: access(await accessJwt(key, { aud: ["other-app"] })) })).status).toBe(403);
		expect((await call("GET", "/api/me", { headers: access(await accessJwt(key, { iss: "https://evil.cloudflareaccess.com" })) })).status).toBe(403);
		expect((await call("GET", "/api/me", { headers: access(await accessJwt(key, { exp: t - 3600 })) })).status).toBe(403);
		expect((await call("GET", "/api/me", { headers: access(await accessJwt(key, { nbf: t + 3600 })) })).status).toBe(403);
		// tampered payload
		const [h, , s] = (await accessJwt(key)).split(".");
		const forged = btoa(JSON.stringify({ iss: "https://velikopter.cloudflareaccess.com", aud: "test-aud", sub: "x", exp: t + 60 }))
			.replace(/=+$/, "");
		expect((await call("GET", "/api/me", { headers: access(`${h}.${forged}.${s}`) })).status).toBe(403);
	});

	it("accepts a valid token, refetching the keys once when Access rotated them", async () => {
		const res = await call("GET", "/api/me", { headers: access(await accessJwt(key)) });
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ email: "veli@example.com" });
		// Access adds k2; the cached key list doesn't have it yet
		const calls = serveAccessKeys([key, other], false);
		expect((await call("GET", "/api/me", { headers: access(await accessJwt(key)) })).status).toBe(200);
		expect(calls.n).toBe(0); // k1 from the cache
		expect((await call("GET", "/api/me", { headers: access(await accessJwt(other)) })).status).toBe(200);
		expect(calls.n).toBe(1); // refetched for k2
		expect((await call("GET", "/api/me", { headers: access(await accessJwt(other)) })).status).toBe(200);
		expect(calls.n).toBe(1);
	});

	it("serves the private page only with Access, with the page's security headers", async () => {
		const jwt = await accessJwt(key);
		for (const path of ["/me", "/me/", "/me/index.html"]) {
			const res = await call("GET", path, { headers: access(jwt) });
			expect(res.status).toBe(200);
			expect(res.headers.get("cache-control")).toBe("private, no-store");
			for (const [k, v] of Object.entries(PAGE_HEADERS)) expect(res.headers.get(k)).toBe(v);
			expect(await res.text()).toContain('<script type="module" src="/assets/me.js"></script>');
		}
		// The fishing page (#128), behind the same check.
		for (const path of ["/me/fishing", "/me/fishing/"]) {
			const fishing = await call("GET", path, { headers: access(jwt) });
			expect(fishing.status).toBe(200);
			expect(fishing.headers.get("cache-control")).toBe("private, no-store");
			for (const [k, v] of Object.entries(PAGE_HEADERS)) expect(fishing.headers.get(k)).toBe(v);
			expect(await fishing.text()).toContain('<script type="module" src="/assets/fishing.js"></script>');
		}
		expect((await call("GET", "/me/fishing")).status).toBe(403);
		expect((await call("GET", "/me/fishing.html", { headers: access(jwt) })).status).toBe(404);
		const missing = await call("GET", "/me/other", { headers: access(jwt) });
		expect(missing.status).toBe(404);
		expect(missing.headers.get("cache-control")).toBe("private, no-store");
		expect((await call("POST", "/me", { headers: access(jwt, { origin: ORIGIN }) })).status).toBe(405);
		expect((await call("GET", "/me/index.html")).status).toBe(403);
	});

	it("fails closed when ACCESS_AUD is not set", async () => {
		const { default: worker } = await import("../src/index");
		const { createExecutionContext } = await import("cloudflare:test");
		const res = await worker.fetch(
			new Request<unknown, IncomingRequestCfProperties>(`${ORIGIN}/api/me`, { headers: access(await accessJwt(key)) }),
			{ ...env, ACCESS_AUD: "" },
			createExecutionContext(),
		);
		expect(res.status).toBe(503);
	});
});

describe("upload tokens on the private page", () => {
	it("creates, lists and revokes tokens; the token itself is shown once", async () => {
		const jwt = await accessJwt(key);
		const headers = access(jwt, { origin: ORIGIN });
		let res = await call("POST", "/api/me/tokens", { body: { name: "Companion PC", scopes: ["public"] }, headers });
		expect(res.status).toBe(201);
		const created = await res.json<{ id: number; token: string; prefix: string; scopes: string[] }>();
		expect(created.token).toMatch(/^cw_[A-Za-z0-9_-]{43}$/);
		expect(created.scopes).toEqual(["public"]);
		const stored = await env.DB.prepare("SELECT hash, created_by FROM tokens").first<{ hash: string; created_by: string }>();
		expect(stored!.hash).not.toContain(created.token);
		expect(stored!.created_by).toBe("veli@example.com");

		res = await call("GET", "/api/me/tokens", { headers: access(jwt) });
		const list = await res.json<{ tokens: Record<string, unknown>[] }>();
		expect(list.tokens).toHaveLength(1);
		expect(JSON.stringify(list)).not.toContain(created.token);
		expect(list.tokens[0]).toMatchObject({ prefix: created.prefix, name: "Companion PC", scopes: ["public"], revoked: null });

		// the token uploads public data but not private data
		expect((await call("POST", "/api/upload", { body: { v: 1, houses: {} }, headers: bearer(created.token) })).status).toBe(200);
		expect((await privateUpload(created.token, { v: 1, snapshots: { [CHAR]: { t: now(), data: snapshot(now()) } } })).status).toBe(403);

		res = await call("DELETE", `/api/me/tokens/${created.id}`, { headers });
		expect(res.status).toBe(200);
		expect((await call("POST", "/api/upload", { body: { v: 1, houses: {} }, headers: bearer(created.token) })).status).toBe(401);
		expect((await call("DELETE", `/api/me/tokens/${created.id}`, { headers })).status).toBe(404);
	});

	it("refuses cross-site changes and bad token requests", async () => {
		const jwt = await accessJwt(key);
		expect((await call("POST", "/api/me/tokens", { body: { name: "x" }, headers: access(jwt) })).status).toBe(403);
		expect((await call("POST", "/api/me/tokens", { body: { name: "x" }, headers: access(jwt, { origin: "https://evil.example" }) })).status).toBe(403);
		const headers = access(jwt, { origin: ORIGIN });
		expect((await call("POST", "/api/me/tokens", { body: { name: "" }, headers })).status).toBe(400);
		expect((await call("POST", "/api/me/tokens", { body: { name: "x", scopes: ["admin"] }, headers })).status).toBe(400);
		const ok = await call("POST", "/api/me/tokens", { body: { name: "both" }, headers });
		expect((await ok.json<{ scopes: string[] }>()).scopes).toEqual(["public", "private"]);
	});

	it("lets an Access service token read but not change anything", async () => {
		const jwt = await accessJwt(key, { email: undefined, sub: "", common_name: "abc.access" });
		const headers = access(jwt, { origin: ORIGIN });
		const me = await call("GET", "/api/me", { headers });
		expect(me.status).toBe(200);
		expect(await me.json()).toEqual({ email: null });
		expect((await call("GET", "/api/me/tokens", { headers })).status).toBe(200);
		const post = await call("POST", "/api/me/tokens", { body: { name: "x" }, headers });
		expect(post.status).toBe(403);
		expect((await post.json<{ error: string }>()).error).toBe("read_only");
		expect((await call("DELETE", "/api/me/tokens/1", { headers })).status).toBe(403);
	});
});

describe("private upload and read", () => {
	it("stores the latest documents per character, the ledger once, and serves them behind Access", async () => {
		const token = await makeToken("private");
		const t = now();
		const ledger = [
			{ t: t - 50, c: CHAR, k: "ahbuy", i: 2589, q: 20, m: 2000, w: "CAMWOW EU4 Realm 8 PvP|H", n: "Linen Cloth" },
			{ t: t - 40, c: CHAR, k: "vsell", i: 4306, q: 1, m: 150, w: "Innkeeper Gryshka" },
			{ t: t - 40, c: CHAR, k: "vsell", i: 4306, q: 1, m: 150, w: "Innkeeper Gryshka" },
		];
		const body = {
			v: 1,
			snapshots: { [CHAR]: { t, data: snapshot(t) } },
			auctions: { [CHAR]: { t, data: { active: [], sold: [{ item: 2589, q: 20 }] } } },
			fishing: { [CHAR]: { t: t - 10, data: { days: 90, catches: 12 } } },
			ledger,
		};
		let res = await privateUpload(token, body);
		expect(res.status).toBe(200);
		expect((await res.json<{ received: unknown }>()).received).toEqual({ snapshots: 1, auctions: 1, fishing: 1, ledger: 3, watch: 0 });
		res = await privateUpload(token, body); // again: nothing new
		expect((await res.json<{ rowsWritten: number }>()).rowsWritten).toBe(1);
		// an older snapshot never replaces a newer one
		await privateUpload(token, { v: 1, snapshots: { [CHAR]: { t: t - 100, data: snapshot(t - 100, 10) } } });

		const jwt = await accessJwt(key);
		const chars = await (await call("GET", "/api/me/characters", { headers: access(jwt) })).json<{ characters: Record<string, unknown>[] }>();
		expect(chars.characters).toEqual([
			{
				key: CHAR,
				realm: "CAMWOW EU4 Realm 8 PvP",
				name: "Velikopter",
				surname: "Tanner",
				faction: "Horde",
				race: "Orc",
				class: "Hunter",
				level: 20,
				snapshotT: t,
				auctionsT: t,
				fishingT: t - 10,
			},
		]);
		res = await call("GET", `/api/me/characters/${encodeURIComponent(CHAR)}`, { headers: access(jwt) });
		const doc = await res.json<{ snapshot: { t: number; data: { char: { level: number } } }; fishing: { data: unknown } }>();
		expect(doc.snapshot.t).toBe(t);
		expect(doc.snapshot.data.char.level).toBe(20);
		expect(doc.fishing.data).toEqual({ days: 90, catches: 12 });
		expect((await call("GET", "/api/me/characters/nobody-here", { headers: access(jwt) })).status).toBe(404);

		const entries = await (await call("GET", `/api/me/ledger?char=${encodeURIComponent(CHAR)}`, { headers: access(jwt) })).json<{ entries: Record<string, unknown>[] }>();
		expect(entries.entries).toHaveLength(3); // the two identical vendor sales are both kept
		expect(entries.entries[2]).toMatchObject({ kind: "ahbuy", item: 2589, qty: 20, money: 2000, name: "Linen Cloth" });

		const usage = await (await call("GET", "/api/me/usage", { headers: access(jwt) })).json<{ uploads: number; rowsWritten: number; dbBytes: number }>();
		expect(usage.uploads).toBe(3);
		expect(usage.dbBytes).toBeGreaterThan(0);
		expect(usage.rowsWritten).toBeGreaterThan(0);
	});

	it("validates private uploads", async () => {
		const token = await makeToken("private");
		const t = now();
		let res = await privateUpload(token, { v: 1 });
		expect(res.status).toBe(400);
		res = await privateUpload(token, { v: 1, snapshots: { "no dash": { t, data: {} } } });
		expect(await res.json()).toMatchObject({ error: "bad_shape" });
		res = await privateUpload(token, { v: 1, ledger: [{ t, c: CHAR, k: "AH BUY" }] });
		expect(await res.json()).toEqual({ error: "bad_shape", message: "ledger[0].k: expected lower-case letters" });
		expect((await makeToken("public").then((p) => privateUpload(p, { v: 1, snapshots: {} }))).status).toBe(403);
	});
});
