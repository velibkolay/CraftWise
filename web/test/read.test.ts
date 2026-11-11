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
			"2589": { n: "Linen Cloth", q: 1, i: 132889, c: 7, s: 5 },
			"2447": { n: "Peacebloom", q: 1, i: 133939, c: 7, s: 9 },
			"8831": { n: "Purple Lotus", q: 1 },
			"765": { n: "Silverleaf", q: 1 },
		},
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
		body = await (await call("GET", "/api/items?q=zzz")).json();
		expect(body.items).toEqual([]);
		expect((await call("GET", "/api/items?q=a")).status).toBe(400);
	});

	it("gives item detail per house: current, depth, typical, history", async () => {
		const res = await call("GET", "/api/items/2589");
		expect(res.status).toBe(200);
		const body = await res.json<{ item: Record<string, unknown>; markets: Record<string, unknown>[] }>();
		expect(body.item).toEqual({ id: 2589, name: "Linen Cloth", quality: 1, icon: 132889, class: 7, subclass: 5 });
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

	it("serves the static placeholder page", async () => {
		const res = await call("GET", "/");
		expect(res.status).toBe(200);
		expect(await res.text()).toContain("CraftWise prices");
	});
});
