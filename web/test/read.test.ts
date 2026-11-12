import { env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { BOOTY, call, clearData, HORDE, houses, makeToken, now, upload } from "./helpers";

const DAY = 86400;
const t0 = now();
const today = Math.floor(t0 / DAY);

// Linen Cloth: 5 days of CraftWise history at the Horde AH, current min well above typical.
// Peacebloom: 3 days, current min below typical. Purple Lotus: outside the scope (no typical).
// Silverleaf: 2 days only (too little history).
beforeAll(async () => {
	await clearData();
	const token = await makeToken("public");
	const day = (d: number, typ: number) => ({ day: today - d, lo: typ - 5, typ, hi: typ + 20, qtyMax: 100, listMax: 5, n: 2 });
	const res = await upload(token, {
		v: 1,
		houses: houses(),
		scans: [
			{ house: HORDE, t: t0 - 7200, kind: "search", items: 3, source: "ui" },
			{ house: HORDE, t: t0, kind: "full", items: 3, lastOnly: 1, source: "auctionator" },
			{ house: BOOTY, t: t0 - 3600, kind: "full", items: 1, lastOnly: 0, source: "ui" },
		],
		items: {
			"2589": { n: "Linen Cloth", q: 1, i: 132889, c: 7, s: 5, p: 13 },
			"2447": { n: "Peacebloom", q: 1, i: 133939, c: 7, s: 9 },
			"8831": { n: "Purple Lotus", q: 1 },
			"765": { n: "Silverleaf", q: 1 },
		},
		classNames: { "7": "Trade Goods" },
		subclassNames: { "7": { "5": "Cloth", "9": "Herb" } },
		prices: [
			{
				item: "2589",
				house: HORDE,
				last: { t: t0, min: 150, qty: 300, listings: 4 },
				raw: [{ t: t0, total: 300, listings: 4, tiers: [150, 20, 160, 280] }],
				days: [day(4, 100), day(3, 102), day(2, 98), day(1, 100), day(0, 104)],
			},
			{ item: "2589", house: BOOTY, last: { t: t0 - 3600, min: 120, qty: 20, listings: 2 } },
			{
				item: "2447",
				house: HORDE,
				last: { t: t0, min: 30, qty: 50, listings: 3 },
				days: [day(2, 60), day(1, 61), day(0, 59)],
			},
			{ item: "8831", house: HORDE, last: { t: t0, min: 900, qty: 2, listings: 1 } },
			{ item: "765", house: HORDE, last: { t: t0, min: 10, qty: 2, listings: 1 }, days: [day(1, 50), day(0, 50)] },
		],
	});
	expect(res.status).toBe(200);
});

describe("public read API", () => {
	it("lists houses, faction house first, with last scan times", async () => {
		const res = await call("GET", "/api/houses");
		expect(res.headers.get("cache-control")).toBe("public, max-age=60");
		const { houses: list } = await res.json<{ houses: Record<string, unknown>[] }>();
		expect(list.map((h) => h.key)).toEqual([HORDE, BOOTY]);
		expect(list[0]).toMatchObject({ label: "Horde AH", faction: "Horde", lastScan: t0, lastFullScan: t0, lastFullScanItems: 4 });
		expect(list[1]).toMatchObject({ label: "Booty Bay", kind: "neutral", faction: null, lastFullScan: t0 - 3600 });
	});

	it("lists recent scans, newest first, optionally per house", async () => {
		let body = await (await call("GET", "/api/scans?limit=2")).json<{ scans: Record<string, unknown>[] }>();
		expect(body.scans).toEqual([
			{ house: HORDE, label: "Horde AH", t: t0, kind: "full", items: 3, lastOnly: 1, source: "auctionator" },
			{ house: BOOTY, label: "Booty Bay", t: t0 - 3600, kind: "full", items: 1, lastOnly: 0, source: "ui" },
		]);
		body = await (await call("GET", `/api/scans?house=${encodeURIComponent(BOOTY)}`)).json();
		expect(body.scans).toHaveLength(1);
	});

	it("searches by word prefix and by item ID", async () => {
		let body = await (await call("GET", "/api/items?q=lot")).json<{ items: { id: number; name: string; prices: unknown[] }[] }>();
		expect(body.items.map((i) => i.name)).toEqual(["Purple Lotus"]);
		body = await (await call("GET", "/api/items?q=LINEN%20cl")).json();
		expect(body.items).toHaveLength(1);
		expect(body.items[0]!.prices).toEqual([
			{ house: HORDE, label: "Horde AH", suffix: 0, t: t0, min: 150, qty: 300, listings: 4, off: null, listed: true },
			{ house: BOOTY, label: "Booty Bay", suffix: 0, t: t0 - 3600, min: 120, qty: 20, listings: 2, off: null, listed: true },
		]);
		body = await (await call("GET", "/api/items?q=2447")).json();
		expect(body.items.map((i) => i.name)).toEqual(["Peacebloom"]);
		// #120: the client's names and the sell price with every item (null when not uploaded)
		const names = await (await call("GET", "/api/items?q=lotus")).json<{ items: Record<string, unknown>[] }>();
		expect(names.items[0]).toMatchObject({ class: null, className: null, subclassName: null, sellPrice: null });
		const herb = await (await call("GET", "/api/items?q=peace")).json<{ items: Record<string, unknown>[] }>();
		expect(herb.items[0]).toMatchObject({ class: 7, subclass: 9, className: "Trade Goods", subclassName: "Herb", sellPrice: null });
		body = await (await call("GET", "/api/items?q=zzz")).json();
		expect(body.items).toEqual([]);
		expect((await call("GET", "/api/items?q=a")).status).toBe(400);
	});

	it("gives item detail per house: current, depth, typical, history", async () => {
		const res = await call("GET", "/api/items/2589");
		expect(res.status).toBe(200);
		const body = await res.json<{ item: Record<string, unknown>; markets: Record<string, unknown>[] }>();
		expect(body.item).toEqual({
			id: 2589,
			name: "Linen Cloth",
			quality: 1,
			icon: 132889,
			class: 7,
			subclass: 5,
			className: "Trade Goods",
			subclassName: "Cloth",
			sellPrice: 13,
		});
		const lotus = await (await call("GET", "/api/items/8831")).json<{ item: Record<string, unknown> }>();
		expect(lotus.item).toMatchObject({ class: null, className: null, subclassName: null, sellPrice: null });
		expect(body.markets).toHaveLength(2);
		const horde = body.markets[0]!;
		expect(horde).toMatchObject({
			house: HORDE,
			suffix: 0,
			current: { t: t0, min: 150, qty: 300, listings: 4, listed: true },
			depth: { t: t0, total: 300, tiers: [{ price: 150, qty: 20 }, { price: 160, qty: 280 }] },
			typical: { status: "ok", price: 100, days: 5 },
		});
		expect((horde.days as unknown[]).length).toBe(5);
		expect((horde.days as Record<string, unknown>[])[0]).toEqual({
			day: today - 4,
			src: "craftwise",
			lo: 95,
			typ: 100,
			hi: 120,
			qtyMax: 100,
			listMax: 5,
			n: 2,
			gone: null,
		});
		expect(horde.raw).toEqual([{ t: t0, total: 300, listings: 4, m: null, tiers: [{ price: 150, qty: 20 }, { price: 160, qty: 280 }] }]);
		const booty = body.markets[1]!;
		expect(booty).toMatchObject({ house: BOOTY, depth: null, typical: { status: "too_little_history", days: 0 } });
		expect((booty.days as Record<string, unknown>[])[0]).toMatchObject({ src: "last", lo: 120, typ: null });
	});

	it("answers 404 for an item without data and for unknown endpoints", async () => {
		expect((await call("GET", "/api/items/999999")).status).toBe(404);
		expect((await call("GET", "/api/nope")).status).toBe(404);
		expect((await call("POST", "/api/houses")).status).toBe(405);
	});

	it("lists top movers per house against the typical price, and caches them", async () => {
		const res = await call("GET", `/api/movers?house=${encodeURIComponent(HORDE)}`);
		expect(res.status).toBe(200);
		const body = await res.json<{ up: Record<string, unknown>[]; down: Record<string, unknown>[]; computedAt: number }>();
		expect(body.up).toEqual([
			{ item: 2589, suffix: 0, name: "Linen Cloth", quality: 1, icon: 132889, t: t0, min: 150, qty: 300, listings: 4, typical: 100, typicalDays: 5, change: 0.5 },
		]);
		expect(body.down.map((m) => [m.name, m.typical, m.change])).toEqual([["Peacebloom", 60, -0.5]]);
		const cached = await env.DB.prepare("SELECT count(*) AS n FROM cache").first<{ n: number }>();
		expect(cached!.n).toBe(1);
		const again = await (await call("GET", `/api/movers?house=${encodeURIComponent(HORDE)}`)).json<{ computedAt: number }>();
		expect(again.computedAt).toBe(body.computedAt);
		expect((await call("GET", "/api/movers?house=nope")).status).toBe(404);
		expect((await call("GET", "/api/movers")).status).toBe(400);
	});

	it("serves the static list page", async () => {
		const res = await call("GET", "/");
		expect(res.status).toBe(200);
		expect(await res.text()).toContain('src="/assets/list.js"');
	});
});

describe("random-suffix variants in the read API (#118)", () => {
	it("merges packed variants with the rows stored before them", async () => {
		const horde = (await env.DB.prepare("SELECT id FROM houses WHERE key = ?1").bind(HORDE).first<{ id: number }>())!.id;
		// rows written before migration 0002: one older and one newer than the packed variant
		await env.DB.batch([
			env.DB.prepare("INSERT INTO prices (house, item, suffix, t, min, qty) VALUES (?1, 15210, 1017, ?2, 4000, 1)").bind(horde, t0 - 7200),
			env.DB.prepare("INSERT INTO prices (house, item, suffix, t, min, qty) VALUES (?1, 15210, 1018, ?2, 3000, 1)").bind(horde, t0),
			env.DB.prepare("INSERT INTO daily (house, item, suffix, day, src, lo, hi, qty_max) VALUES (?1, 15210, 1017, ?2, 0, 4000, 4000, 1)").bind(horde, today),
		]);
		const token = await makeToken("public");
		const res = await upload(token, {
			v: 1,
			houses: houses(),
			items: { "15210": { n: "Burnished Leggings", q: 2 } },
			prices: [
				{ item: "15210:1017", house: HORDE, last: { t: t0, min: 5000, qty: 2 } },
				{ item: "15210:1018", house: HORDE, last: { t: t0 - 3600, min: 3500, qty: 1 } },
				{ item: "15210:1019", house: HORDE, last: { t: t0, min: 6000, qty: 1 } },
			],
		});
		expect(res.status).toBe(200);

		const detail = await (await call("GET", "/api/items/15210")).json<{ markets: Record<string, any>[] }>();
		expect(detail.markets.map((m) => [m.suffix, m.current.t, m.current.min, m.current.listed])).toEqual([
			[1017, t0, 5000, true],
			[1018, t0, 3000, true],
			[1019, t0, 6000, true],
		]);
		const m1017 = detail.markets[0]!;
		expect(m1017).toMatchObject({ house: HORDE, depth: null, typical: { status: "too_little_history" } });
		expect(m1017.days).toEqual([{ day: today, src: "last", lo: 4000, typ: null, hi: 5000, qtyMax: 2, listMax: null, n: null, gone: null }]);
		expect(detail.markets[2]!.days).toEqual([{ day: today, src: "last", lo: 6000, typ: null, hi: 6000, qtyMax: 1, listMax: null, n: null, gone: null }]);

		const found = await (await call("GET", "/api/items?q=burnished")).json<{ items: { prices: Record<string, unknown>[] }[] }>();
		expect(found.items[0]!.prices.map((p) => [p.house, p.suffix, p.min])).toEqual([
			[HORDE, 1017, 5000],
			[HORDE, 1018, 3000],
			[HORDE, 1019, 6000],
		]);
	});
});
