import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { MAX_PUBLIC_BYTES, UPLOADS_PER_MINUTE, WRITE_BUDGET } from "../src/limits";
import { BOOTY, bearer, call, clearData, HORDE, houses, makeToken, now, upload } from "./helpers";

const DAY = 86400;

function payload(t: number) {
	const today = Math.floor(t / DAY);
	return {
		v: 1,
		houses: houses(),
		scans: [
			{ house: HORDE, t, kind: "full", items: 1, lastOnly: 2, source: "auctionator" },
			{ house: BOOTY, t: t - 600, kind: "search", items: 1, source: "ui" },
		],
		items: {
			"2589": { n: "Linen Cloth", q: 1, i: 132889, c: 7, s: 5 },
			"2447": { n: "Peacebloom", q: 1, i: 133939, c: 7, s: 9 },
			"8831": { n: "Purple Lotus" },
		},
		prices: [
			{
				item: "2589",
				house: HORDE,
				last: { t, min: 95, qty: 400, listings: 6 },
				raw: [
					{ t: t - 3600, total: 380, listings: 5, tiers: [100, 20, 110, 200] },
					{ t, total: 400, listings: 6, m: 120, tiers: [95, 10, 100, 40, 120, 150] },
				],
				days: [
					{ day: today - 2, lo: 90, typ: 100, hi: 140, qtyMax: 500, listMax: 7, n: 4 },
					{ day: today - 1, lo: 92, typ: 104, hi: 150, qtyMax: 450, listMax: 6, n: 3, gone: 20 },
					{ day: today, lo: 95, typ: 110, hi: 120, qtyMax: 400, listMax: 6, n: 2 },
				],
			},
			{ item: "2447", house: HORDE, last: { t, min: 40, qty: 12, listings: 3 } },
			{ item: "8831", house: HORDE, last: { t: t - 7200, min: 900, qty: 2, listings: 1, off: t } },
			{ item: "15210:1017", house: BOOTY, last: { t: t - 600, min: 25000, qty: 1 } },
		],
	};
}

async function one<T>(sql: string, ...args: unknown[]): Promise<T | null> {
	return env.DB.prepare(sql).bind(...args).first<T>();
}

let token: string;
beforeEach(async () => {
	await clearData();
	token = await makeToken();
});

describe("POST /api/upload: auth and limits", () => {
	it("refuses a missing, malformed, unknown or revoked token", async () => {
		const body = payload(now());
		expect((await call("POST", "/api/upload", { body })).status).toBe(401);
		expect((await call("POST", "/api/upload", { body, headers: bearer("nope") })).status).toBe(401);
		const unknown = "cw_" + "A".repeat(43);
		const res = await call("POST", "/api/upload", { body, headers: bearer(unknown) });
		expect(res.status).toBe(401);
		expect(await res.json()).toMatchObject({ error: "unauthorized" });
		await env.DB.exec("UPDATE tokens SET revoked = 1");
		expect((await upload(token, body)).status).toBe(401);
	});

	it("refuses a token without the public scope", async () => {
		const priv = await makeToken("private");
		expect((await upload(priv, payload(now()))).status).toBe(403);
	});

	it("needs POST and JSON", async () => {
		expect((await call("GET", "/api/upload", { headers: bearer(token) })).status).toBe(405);
		const res = await call("POST", "/api/upload", { raw: "{}", headers: { ...bearer(token), "content-type": "text/plain" } });
		expect(res.status).toBe(415);
		expect((await call("POST", "/api/upload", { raw: "{nope", headers: bearer(token) })).status).toBe(400);
	});

	it("refuses bodies over the size limit", async () => {
		const res = await call("POST", "/api/upload", { raw: " ".repeat(MAX_PUBLIC_BYTES + 1), headers: bearer(token) });
		expect(res.status).toBe(413);
	});

	it("names the bad field", async () => {
		const body = payload(now());
		(body.prices[0]!.last as { min: unknown }).min = -5;
		const res = await upload(token, body);
		expect(res.status).toBe(400);
		expect(await res.json()).toEqual({ error: "bad_shape", message: "prices[0].last.min: expected a non-negative integer" });
	});

	it("rate-limits per token and minute", async () => {
		const body = { v: 1, houses: houses() };
		await env.DB.prepare("UPDATE tokens SET rl_window = ?1, rl_count = ?2").bind(Math.floor(now() / 60), UPLOADS_PER_MINUTE).run();
		const res = await upload(token, body);
		expect(res.status).toBe(429);
		expect(res.headers.get("retry-after")).toBeTruthy();
	});

	it("stops uploads when the daily write budget is used up", async () => {
		await env.DB.prepare("INSERT INTO usage (day, rows_written) VALUES (?1, ?2)").bind(Math.floor(now() / DAY), WRITE_BUDGET).run();
		const res = await upload(token, payload(now()));
		expect(res.status).toBe(429);
		expect(await res.json()).toMatchObject({ error: "write_budget" });
	});
});

describe("POST /api/upload: storage", () => {
	it("stores houses, items, prices, points, days and scans", async () => {
		const t = now();
		const res = await upload(token, payload(t));
		expect(res.status).toBe(200);
		const out = await res.json<{ received: Record<string, number>; rowsWritten: number }>();
		expect(out.received).toEqual({ houses: 2, scans: 2, items: 3, prices: 4, points: 2, days: 3 });
		expect(out.rowsWritten).toBeGreaterThan(0);

		const h = await one<{ id: number; last_scan: number; last_full_scan: number; last_full_scan_items: number }>(
			"SELECT * FROM houses WHERE key = ?1",
			HORDE,
		);
		expect(h).toMatchObject({ last_scan: t, last_full_scan: t, last_full_scan_items: 3 });
		const booty = await one<{ last_full_scan: number | null; faction: string | null }>("SELECT * FROM houses WHERE key = ?1", BOOTY);
		expect(booty).toMatchObject({ last_full_scan: null, faction: null });

		expect(await one("SELECT name, quality, icon, class, subclass FROM items WHERE id = 2589")).toEqual({
			name: "Linen Cloth",
			quality: 1,
			icon: 132889,
			class: 7,
			subclass: 5,
		});
		expect(await one("SELECT name, quality FROM items WHERE id = 8831")).toEqual({ name: "Purple Lotus", quality: null });
		const words = await env.DB.prepare("SELECT word FROM item_words WHERE item = 8831 ORDER BY word").all();
		expect(words.results).toEqual([{ word: "lotus" }, { word: "purple" }]);

		const p = await one<Record<string, unknown>>("SELECT * FROM prices WHERE house = ?1 AND item = 2589", h!.id);
		expect(p).toMatchObject({ t, min: 95, qty: 400, listings: 6, off: null, depth_t: t, depth_total: 400 });
		expect(JSON.parse(p!.depth as string)).toEqual([95, 10, 100, 40, 120, 150]);
		const gear = await one<Record<string, unknown>>("SELECT * FROM prices WHERE item = 15210");
		expect(gear).toMatchObject({ suffix: 1017, min: 25000, qty: 1, listings: null, depth: null });
		expect(await one("SELECT off FROM prices WHERE item = 8831")).toEqual({ off: t });

		const points = await env.DB.prepare("SELECT t, total, m, tiers FROM points WHERE item = 2589 ORDER BY t").all();
		expect(points.results).toEqual([
			{ t: t - 3600, total: 380, m: null, tiers: "[100,20,110,200]" },
			{ t, total: 400, m: 120, tiers: "[95,10,100,40,120,150]" },
		]);
		const today = Math.floor(t / DAY);
		const days = await env.DB.prepare("SELECT day, src, typ, n, gone FROM daily WHERE item = 2589 ORDER BY day").all();
		expect(days.results).toEqual([
			{ day: today - 2, src: 1, typ: 100, n: 4, gone: null },
			{ day: today - 1, src: 1, typ: 104, n: 3, gone: 20 },
			{ day: today, src: 1, typ: 110, n: 2, gone: null },
		]);
		// An item outside the scope gets a daily row from its `last`: no typical, no counts.
		expect(await one("SELECT src, lo, typ, hi, qty_max, list_max, n FROM daily WHERE item = 2447")).toEqual({
			src: 0,
			lo: 40,
			typ: null,
			hi: 40,
			qty_max: 12,
			list_max: 3,
			n: null,
		});
		const scans = await env.DB.prepare("SELECT kind, items, last_only, source FROM scans ORDER BY t").all();
		expect(scans.results).toEqual([
			{ kind: "search", items: 1, last_only: null, source: "ui" },
			{ kind: "full", items: 1, last_only: 2, source: "auctionator" },
		]);
		const usage = await one<{ rows_written: number; uploads: number }>("SELECT * FROM usage");
		expect(usage).toMatchObject({ rows_written: out.rowsWritten, uploads: 1 });
	});

	it("is idempotent: the same body again writes only the token's rate-limit row", async () => {
		const body = payload(now());
		await upload(token, body);
		const before = await env.DB.prepare("SELECT (SELECT count(*) FROM prices) p, (SELECT count(*) FROM points) r, (SELECT count(*) FROM daily) d").first();
		const res = await upload(token, body);
		expect(res.status).toBe(200);
		expect((await res.json<{ rowsWritten: number }>()).rowsWritten).toBe(1);
		const after = await env.DB.prepare("SELECT (SELECT count(*) FROM prices) p, (SELECT count(*) FROM points) r, (SELECT count(*) FROM daily) d").first();
		expect(after).toEqual(before);
	});

	it("keeps the newer observation and merges the day of an item outside the scope", async () => {
		const t = now();
		const base = { v: 1, houses: houses() };
		await upload(token, { ...base, prices: [{ item: "2447", house: HORDE, last: { t: t - 100, min: 40, qty: 12, listings: 3 } }] });
		// older observation: ignored for the current price, merged into its day
		await upload(token, { ...base, prices: [{ item: "2447", house: HORDE, last: { t: t - 200, min: 30, qty: 20, listings: 2 } }] });
		expect(await one("SELECT t, min, qty FROM prices WHERE item = 2447")).toEqual({ t: t - 100, min: 40, qty: 12 });
		const day = await one<{ lo: number; hi: number; qty_max: number; list_max: number }>("SELECT * FROM daily WHERE item = 2447");
		if (Math.floor((t - 200) / DAY) === Math.floor((t - 100) / DAY)) {
			expect(day).toMatchObject({ lo: 30, hi: 40, qty_max: 20, list_max: 3 });
		}
		// newer observation wins
		await upload(token, { ...base, prices: [{ item: "2447", house: HORDE, last: { t, min: 45, qty: 8 } }] });
		expect(await one("SELECT t, min, qty, listings FROM prices WHERE item = 2447")).toEqual({ t, min: 45, qty: 8, listings: null });
		// same time, now marked not listed by a later full scan
		await upload(token, { ...base, prices: [{ item: "2447", house: HORDE, last: { t, min: 45, qty: 8, off: t + 5 } }] });
		expect(await one("SELECT off FROM prices WHERE item = 2447")).toEqual({ off: t + 5 });
	});

	it("lets CraftWise's aggregate replace a day built from `last`, never the other way round", async () => {
		const t = now();
		const today = Math.floor(t / DAY);
		const base = { v: 1, houses: houses() };
		await upload(token, { ...base, prices: [{ item: "2589", house: HORDE, last: { t, min: 50, qty: 5, listings: 1 } }] });
		expect(await one("SELECT src FROM daily WHERE item = 2589")).toEqual({ src: 0 });
		const days = [{ day: today, lo: 50, typ: 60, hi: 70, qtyMax: 5, listMax: 1, n: 1 }];
		await upload(token, { ...base, prices: [{ item: "2589", house: HORDE, days }] });
		expect(await one("SELECT src, typ, n FROM daily WHERE item = 2589")).toEqual({ src: 1, typ: 60, n: 1 });
		await upload(token, { ...base, prices: [{ item: "2589", house: HORDE, last: { t: t + 1, min: 20, qty: 5 } }] });
		expect(await one("SELECT src, lo, typ FROM daily WHERE item = 2589")).toEqual({ src: 1, lo: 50, typ: 60 });
		// an aggregate over fewer points never replaces one over more
		await upload(token, { ...base, prices: [{ item: "2589", house: HORDE, days: [{ ...days[0], typ: 99, n: 3 }] }] });
		await upload(token, { ...base, prices: [{ item: "2589", house: HORDE, days: [{ ...days[0], typ: 1, n: 2 }] }] });
		expect(await one("SELECT typ, n FROM daily WHERE item = 2589")).toEqual({ typ: 99, n: 3 });
	});

	it("updates item info only when it changed and keeps fields the upload doesn't have", async () => {
		const base = { v: 1, houses: houses() };
		await upload(token, { ...base, items: { "8831": { n: "Purple Lotus", q: 1, i: 134200 } } });
		let res = await upload(token, { ...base, items: { "8831": { n: "Purple Lotus" } } });
		expect((await res.json<{ itemsChanged: number }>()).itemsChanged).toBe(0);
		res = await upload(token, { ...base, items: { "8831": { n: "Black Lotus" } } });
		expect((await res.json<{ itemsChanged: number }>()).itemsChanged).toBe(1);
		expect(await one("SELECT name, quality, icon FROM items WHERE id = 8831")).toEqual({ name: "Black Lotus", quality: 1, icon: 134200 });
		const words = await env.DB.prepare("SELECT word FROM item_words WHERE item = 8831 ORDER BY word").all();
		expect(words.results).toEqual([{ word: "black" }, { word: "lotus" }]);
	});
});
