import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { BOOTY, bearer, call, clearData, HORDE, makeToken, now, upload, type Short } from "./helpers";

const DAY = 86400;

let token: string;
beforeEach(async () => {
	await clearData();
	token = await makeToken();
});

async function get(path: string, tok = token): Promise<Response> {
	return call("GET", path, { headers: bearer(tok) });
}

interface Page {
	v: number;
	houses: Record<string, Record<string, unknown>>;
	scans?: Record<string, Record<string, unknown>[]>;
	names: Record<string, string>;
	itemInfo: Record<string, Record<string, unknown>>;
	classNames?: Record<string, string>;
	subclassNames?: Record<string, Record<string, string>>;
	items: Record<string, Record<string, { last?: Record<string, number>; raw?: { t: number; total: number; tiers: { price: number; qty: number }[] }[]; days?: Record<string, Record<string, number>> }>>;
	next: string | null;
	until: number;
}

async function page(path: string): Promise<Page> {
	const res = await get(path);
	expect(res.status).toBe(200);
	return (await res.json()) as Page;
}

// Walks every page; returns them.
async function all(since = 0, limit?: number): Promise<Page[]> {
	const pages: Page[] = [];
	let cursor: string | null = null;
	do {
		const q: string = `/api/sync/market?since=${since}${limit ? `&limit=${limit}` : ""}${cursor ? `&cursor=${cursor}` : ""}`;
		const p = await page(q);
		pages.push(p);
		cursor = p.next;
	} while (cursor && pages.length < 50);
	return pages;
}

function merged(pages: Page[]): Page["items"] {
	const out: Page["items"] = {};
	for (const p of pages) for (const [k, v] of Object.entries(p.items)) out[k] = { ...out[k], ...v };
	return out;
}

// Pretends every stored change happened `seconds` ago (the tests run within one second).
async function age(seconds: number): Promise<void> {
	await env.DB.batch([
		env.DB.prepare("UPDATE prices SET updated = updated - ?1").bind(seconds),
		env.DB.prepare("UPDATE variants SET updated = updated - ?1").bind(seconds),
	]);
}

const t = now();
const today = Math.floor(t / DAY);

function machineA(): Short {
	return {
		scans: [{ house: HORDE, t: t - 600, kind: "full", items: 1, lastOnly: 1, source: "auctionator" }],
		items: { "2589": { n: "Linen Cloth", q: 1, i: 132889, c: 7, s: 5, p: 13 }, "2447": { n: "Peacebloom", q: 1 } },
		classNames: { "7": "Trade Goods" },
		subclassNames: { "7": { "5": "Cloth" } },
		prices: [
			{
				item: "2589",
				house: HORDE,
				last: { t: t - 600, min: 95, qty: 400, listings: 6 },
				raw: [
					{ t: t - 7200, total: 380, listings: 5, tiers: [100, 20, 110, 200] },
					{ t: t - 600, total: 400, listings: 6, m: 120, tiers: [95, 10, 100, 40] },
				],
				days: [
					{ day: today - 1, lo: 92, typ: 104, hi: 150, qtyMax: 450, listMax: 6, n: 3, gone: 20 },
					{ day: today, lo: 95, typ: 110, hi: 120, qtyMax: 400, listMax: 6, n: 2 },
				],
			},
			{ item: "2447", house: HORDE, last: { t: t - 600, min: 40, qty: 12, listings: 3 } },
			{ item: "15210:1017", house: BOOTY, last: { t: t - 600, min: 25000, qty: 1 } },
		],
	};
}

describe("GET /api/sync/market: auth", () => {
	it("refuses no token, a malformed one, a revoked one and one without the public scope", async () => {
		expect((await call("GET", "/api/sync/market")).status).toBe(401);
		expect((await call("GET", "/api/sync/market", { headers: bearer("nope") })).status).toBe(401);
		const revoked = await makeToken("public", "old");
		await env.DB.prepare("UPDATE tokens SET revoked = ?1 WHERE name = 'old'").bind(now()).run();
		expect((await get("/api/sync/market", revoked)).status).toBe(401);
		const priv = await makeToken("private", "priv");
		const res = await get("/api/sync/market", priv);
		expect(res.status).toBe(403);
		expect(((await res.json()) as { error: string }).error).toBe("forbidden");
	});

	it("takes a public-only token, GET only", async () => {
		const pub = await makeToken("public", "pub");
		expect((await get("/api/sync/market", pub)).status).toBe(200);
		expect((await call("POST", "/api/sync/market", { body: {}, headers: bearer(pub) })).status).toBe(405);
	});

	it("refuses a bad since or cursor and keeps the response private", async () => {
		expect((await get("/api/sync/market?since=abc")).status).toBe(400);
		expect((await get("/api/sync/market?cursor=zzz")).status).toBe(400);
		const res = await get("/api/sync/market");
		expect(res.headers.get("cache-control")).toBe("private, no-store");
	});
});

describe("GET /api/sync/market: the merged market", () => {
	it("answers in the upload shape and the upload accepts it back", async () => {
		expect((await upload(token, machineA())).status).toBe(200);
		const [p] = await all();
		expect(p!.v).toBe(1);
		expect(p!.houses[HORDE]).toEqual({ realm: "CAMWOW EU4 Realm 8 PvP", kind: "faction", faction: "Horde", label: "Horde AH" });
		expect(p!.houses[BOOTY]!.faction).toBeUndefined();
		expect(p!.names["2589"]).toBe("Linen Cloth");
		expect(p!.itemInfo["2589"]).toMatchObject({ q: 1, i: 132889, c: 7, s: 5, p: 13 });
		expect(p!.classNames).toEqual({ "7": "Trade Goods" });
		expect(p!.subclassNames).toEqual({ "7": { "5": "Cloth" } });
		expect(p!.scans![HORDE]).toEqual([{ t: t - 600, kind: "full", items: 1, lastOnly: 1, source: "auctionator" }]);
		const e = p!.items["2589"]![HORDE]!;
		expect(e.last).toEqual({ t: t - 600, min: 95, qty: 400, listings: 6 });
		expect(e.raw).toEqual([
			{ t: t - 7200, total: 380, listings: 5, tiers: [{ price: 100, qty: 20 }, { price: 110, qty: 200 }] },
			{ t: t - 600, total: 400, listings: 6, m: 120, tiers: [{ price: 95, qty: 10 }, { price: 100, qty: 40 }] },
		]);
		expect(e.days![String(today)]).toEqual({ lo: 95, typ: 110, hi: 120, qtyMax: 400, listMax: 6, n: 2 });
		expect(e.days![String(today - 1)]!.gone).toBe(20);
		// last only outside the scope, and a variant under "<item>:<suffix>"
		expect(p!.items["2447"]![HORDE]).toEqual({ last: { t: t - 600, min: 40, qty: 12, listings: 3 } });
		expect(p!.items["15210:1017"]![BOOTY]).toEqual({ last: { t: t - 600, min: 25000, qty: 1 } });
		expect(p!.next).toBeNull();

		// the same document goes back through POST /api/upload (the companion's own path)
		const { next: _n, until: _u, ...doc } = p!;
		const again = await call("POST", "/api/upload", { body: doc, headers: bearer(token) });
		expect(again.status).toBe(200);
		expect(((await again.json()) as { rowsWritten: number }).rowsWritten).toBeLessThanOrEqual(2);
	});

	it("merges two machines: newest last, raw points and days of both", async () => {
		// machine A (the PC) scanned 10 minutes ago; machine B (the Mac) 2 minutes ago and has older history
		await upload(token, machineA());
		await upload(token, {
			prices: [
				{
					item: "2589",
					house: HORDE,
					last: { t: t - 120, min: 90, qty: 380, listings: 5 },
					raw: [
						{ t: t - 30 * 3600, total: 300, listings: 4, tiers: [105, 300] },
						{ t: t - 120, total: 380, listings: 5, tiers: [90, 30, 99, 100] },
					],
					days: [
						{ day: today - 5, lo: 80, typ: 88, hi: 99, qtyMax: 200, listMax: 3, n: 5 },
						{ day: today - 1, lo: 91, typ: 100, hi: 140, qtyMax: 300, listMax: 4, n: 1 },
					],
				},
			],
		});
		// a late upload of A's older scan does not turn the current price back
		await upload(token, { prices: [{ item: "2589", house: HORDE, last: { t: t - 5000, min: 120, qty: 1, listings: 1 } }] });
		const e = merged(await all())["2589"]![HORDE]!;
		expect(e.last).toEqual({ t: t - 120, min: 90, qty: 380, listings: 5 });
		expect(e.raw!.map((r) => r.t)).toEqual([t - 30 * 3600, t - 7200, t - 600, t - 120]);
		// every day either machine recorded; yesterday: A's n = 3 beats B's n = 1
		expect(Object.keys(e.days!).sort()).toEqual([today - 5, today - 1, today].map(String).sort());
		expect(e.days![String(today - 1)]).toMatchObject({ n: 3, typ: 104 });
	});

	it("same-day aggregates of two machines: the larger n wins, an equal n takes the later upload", async () => {
		const day = (n: number, typ: number) => ({ day: today - 3, lo: 1, typ, hi: 9, qtyMax: 5, listMax: 2, n });
		const send = (d: ReturnType<typeof day>) => upload(token, { prices: [{ item: "2589", house: HORDE, last: { t: t - 60, min: 5, qty: 1 }, days: [d] }] });
		const typOf = async () => merged(await all())["2589"]![HORDE]!.days![String(today - 3)]!.typ;
		await send(day(4, 100)); // machine A: 4 scans
		await send(day(2, 200)); // machine B: only 2 scans that day: A's day stays
		expect(await typOf()).toBe(100);
		await send(day(6, 300)); // B scanned more: B's day replaces it
		expect(await typOf()).toBe(300);
		await send(day(6, 400)); // equal n: the later upload
		expect(await typOf()).toBe(400);
	});

	it("only the last 48 h of raw points and 30 days of aggregates", async () => {
		await upload(token, {
			prices: [
				{
					item: "2589",
					house: HORDE,
					last: { t: t - 60, min: 5, qty: 1 },
					raw: [
						{ t: t - 49 * 3600, total: 1, tiers: [5, 1] },
						{ t: t - 47 * 3600, total: 1, tiers: [5, 1] },
					],
					days: [
						{ day: today - 40, lo: 1, typ: 2, hi: 3, qtyMax: 1, listMax: 1, n: 1 },
						{ day: today - 29, lo: 1, typ: 2, hi: 3, qtyMax: 1, listMax: 1, n: 1 },
					],
				},
			],
		});
		const e = merged(await all())["2589"]![HORDE]!;
		expect(e.raw!.map((r) => r.t)).toEqual([t - 47 * 3600]);
		expect(Object.keys(e.days!)).toEqual([String(today - 29)]);
	});

	it("an item outside the scope gets its last only, no src 0 days", async () => {
		await upload(token, { prices: [{ item: "2447", house: HORDE, last: { t: t - 60, min: 5, qty: 1 } }] });
		expect(merged(await all())["2447"]![HORDE]).toEqual({ last: { t: t - 60, min: 5, qty: 1 } });
	});

	it("merges variants from two machines per suffix, newest wins", async () => {
		const v = (suffix: number, tt: number, min: number) => ({ item: `15210:${suffix}`, house: BOOTY, last: { t: tt, min, qty: 1 } });
		await upload(token, { prices: [v(1017, t - 600, 100), v(1018, t - 600, 200)] });
		await upload(token, { prices: [v(1017, t - 100, 90), v(1019, t - 100, 300)] });
		const items = merged(await all());
		expect(items["15210:1017"]![BOOTY]!.last).toMatchObject({ t: t - 100, min: 90 });
		expect(items["15210:1018"]![BOOTY]!.last).toMatchObject({ min: 200 });
		expect(items["15210:1019"]![BOOTY]!.last).toMatchObject({ min: 300 });
	});

	it("keeps `off` as stored", async () => {
		await upload(token, { prices: [{ item: "8831", house: HORDE, last: { t: t - 7200, min: 900, qty: 2, listings: 1, off: t - 100 } }] });
		expect(merged(await all())["8831"]![HORDE]!.last).toEqual({ t: t - 7200, min: 900, qty: 2, listings: 1, off: t - 100 });
	});
});

describe("GET /api/sync/market: since and pages", () => {
	it("since returns only entries that changed, whole", async () => {
		await upload(token, machineA());
		await age(1000);
		const first = await page("/api/sync/market");
		expect(Object.keys(first.items).sort()).toEqual(["15210:1017", "2447", "2589"]);
		// nothing changed after `until`
		let p = await page(`/api/sync/market?since=${first.until}`);
		expect(p.items).toEqual({});
		// machine B sends one new raw point for 2589 without a newer `last`: the entry comes back whole
		await upload(token, { prices: [{ item: "2589", house: HORDE, last: { t: t - 5000, min: 120, qty: 1 }, raw: [{ t: t - 3000, total: 1, tiers: [120, 1] }] }] });
		p = await page(`/api/sync/market?since=${first.until}`);
		expect(Object.keys(p.items)).toEqual(["2589"]);
		expect(p.items["2589"]![HORDE]!.last!.t).toBe(t - 600);
		expect(p.items["2589"]![HORDE]!.raw!.map((r) => r.t)).toEqual([t - 7200, t - 3000, t - 600]);
		expect(p.names["2589"]).toBe("Linen Cloth");
		expect(p.names["2447"]).toBeUndefined();
	});

	it("a changed day aggregate or a newer last or an `off` marks the entry; a repeated upload does not", async () => {
		await upload(token, machineA());
		await age(1000);
		const since = (await page("/api/sync/market")).until;
		expect((await upload(token, machineA())).status).toBe(200);
		expect((await page(`/api/sync/market?since=${since}`)).items).toEqual({});
		await upload(token, { prices: [{ item: "2589", house: HORDE, last: { t: t - 600, min: 95, qty: 400 }, days: [{ day: today, lo: 95, typ: 111, hi: 120, qtyMax: 400, listMax: 6, n: 3 }] }] });
		await upload(token, { prices: [{ item: "2447", house: HORDE, last: { t: t - 600, min: 40, qty: 12, listings: 3, off: t - 10 } }] });
		await upload(token, { prices: [{ item: "15210:1017", house: BOOTY, last: { t: t - 5, min: 24000, qty: 2 } }] });
		const p = await page(`/api/sync/market?since=${since}`);
		expect(Object.keys(p.items).sort()).toEqual(["15210:1017", "2447", "2589"]);
		expect(p.items["2589"]![HORDE]!.days![String(today)]!.typ).toBe(111);
	});

	it("pages by limit and walks every entry once, in order, across price rows and variants", async () => {
		const prices: NonNullable<Short["prices"]> = [];
		for (let i = 1; i <= 7; i++) prices.push({ item: String(1000 + i), house: HORDE, last: { t: t - 100 * i, min: i, qty: 1 }, raw: [{ t: t - 100 * i, total: 1, tiers: [i, 1] }] });
		for (let i = 1; i <= 3; i++) prices.push({ item: `${20000 + i}:${i}`, house: BOOTY, last: { t: t - 100 * i, min: 50 + i, qty: 1 } });
		await upload(token, { prices });
		await age(100); // everything on the same index tuple order: by updated, house, item
		const pages = await all(0, 4);
		expect(pages.map((p) => p.next === null)).toEqual([false, false, true]);
		const keys = pages.flatMap((p) => Object.keys(p.items));
		expect(new Set(keys).size).toBe(10);
		expect(keys).toHaveLength(10);
		// houses on every page, class names and scans only on the first
		expect(pages.every((p) => Object.keys(p.houses).length === 2)).toBe(true);
		expect(pages[0]!.scans).toBeDefined();
		expect(pages[1]!.scans).toBeUndefined();
		expect(pages[1]!.classNames).toBeUndefined();
		// a page holds the names of its own items only
		expect(Object.keys(pages[1]!.names).every((id) => id in pages[1]!.items)).toBe(true);
	});

	it("a delta cursor keeps `since`: pages with a different since see other entries", async () => {
		await upload(token, { prices: [{ item: "1001", house: HORDE, last: { t: t - 100, min: 1, qty: 1 } }] });
		await age(500);
		await upload(token, { prices: [{ item: "1002", house: HORDE, last: { t: t - 50, min: 2, qty: 1 } }] });
		const recent = await all(now() - 100);
		expect(Object.keys(merged(recent))).toEqual(["1002"]);
		expect(Object.keys(merged(await all(0))).sort()).toEqual(["1001", "1002"]);
	});

	it("until lies a minute behind now", async () => {
		const p = await page("/api/sync/market");
		expect(now() - p.until).toBeGreaterThanOrEqual(59);
		expect(now() - p.until).toBeLessThanOrEqual(62);
	});

	it("writes at most the token's rate-limit row", async () => {
		await upload(token, machineA());
		const before = await env.DB.prepare("SELECT rows_written FROM usage").first<{ rows_written: number }>();
		for (let i = 0; i < 3; i++) await get("/api/sync/market");
		expect((await env.DB.prepare("SELECT rows_written FROM usage").first<{ rows_written: number }>())!.rows_written).toBe(before!.rows_written);
	});

	it("the migration's backfill gives rows stored before it an updated time, so a first download has them", async () => {
		await upload(token, { prices: [{ item: "2447", house: HORDE, last: { t: t - 600, min: 40, qty: 1 } }, { item: "15210:1017", house: BOOTY, last: { t: t - 300, min: 5, qty: 1 } }] });
		await env.DB.batch([env.DB.prepare("UPDATE prices SET updated = NULL"), env.DB.prepare("UPDATE variants SET updated = NULL")]);
		// the same statements as migrations/0005_sync.sql
		await env.DB.batch([
			env.DB.prepare("UPDATE prices SET updated = t"),
			env.DB.prepare("UPDATE variants SET updated = (SELECT max(CAST(value->>0 AS INTEGER)) FROM json_each(variants.data))"),
		]);
		expect(await env.DB.prepare("SELECT updated FROM prices").first()).toEqual({ updated: t - 600 });
		expect(await env.DB.prepare("SELECT updated FROM variants").first()).toEqual({ updated: t - 300 });
		expect(Object.keys(merged(await all())).sort()).toEqual(["15210:1017", "2447"]);
	});
});
