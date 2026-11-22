// Connected realms as one auction house (#366): the upload of `connected`, the grouping at read time, the
// merge (newest `last`, days as Market.lua merges them) and what must not change (raw rows, the sync file).
import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { groupHouses, mergeGroupDays, mergeGroupPrices, type HouseRow } from "../src/groups";
import { body, bearer, call, clearData, makeToken, now, upload } from "./helpers";

const DAY = 86400;
const t0 = now();
const today = Math.floor(t0 / DAY);

const R4 = "CAMWOW EU4 Realm 4 PvP";
const R6 = "CAMWOW EU4 Realm 6 PvP";
const R8 = "CAMWOW EU4 Realm 8 PvP";
const horde = (r: string) => `${r}|H`;
const alliance = (r: string) => `${r}|A`;
const gadget = (r: string) => `${r}|N:Gadgetzan`;

function houseDefs(realms: string[], { alliances = false } = {}) {
	const out: Record<string, unknown> = {};
	for (const r of realms) {
		out[horde(r)] = { realm: r, kind: "faction", faction: "Horde", label: "Horde AH" };
		if (alliances) out[alliance(r)] = { realm: r, kind: "faction", faction: "Alliance", label: "Alliance AH" };
		out[gadget(r)] = { realm: r, kind: "neutral", label: "Gadgetzan" };
	}
	return out;
}

const day = (d: number, typ: number, n = 2) => ({ day: today - d, lo: typ - 5, typ, hi: typ + 20, qtyMax: 100, listMax: 5, n });

async function send(token: string, extra: Record<string, unknown> & { realms: string[]; alliances?: boolean }, short: Parameters<typeof body>[0]) {
	const { realms, alliances, ...rest } = extra;
	const b = body({ ...short, houses: houseDefs(realms, { alliances }) });
	return call("POST", "/api/upload", { body: { ...b, ...rest }, headers: bearer(token) });
}

interface HouseOut {
	key: string;
	realm: string;
	realms: string[];
	keys: string[];
	kind: string;
	faction: string | null;
	label: string;
	lastScan: number | null;
}
const getHouses = async () => ((await (await call("GET", "/api/houses")).json()) as { houses: HouseOut[] }).houses;

let token: string;
beforeEach(async () => {
	await clearData();
	token = await makeToken("public");
});

describe("upload: connected", () => {
	it("stores a pair once, with the earliest time, whichever side sent it", async () => {
		const res = await send(token, { realms: [R4], connected: { [R8]: { [R4]: t0 - 100 }, [R4]: { [R8]: t0 - 500 } } }, {});
		expect(res.status).toBe(200);
		const { results } = await env.DB.prepare("SELECT a, b, t FROM connected").all();
		expect(results).toEqual([{ a: R4, b: R8, t: t0 - 500 }]);
		// a later upload with a later time changes nothing; an earlier one lowers it
		await send(token, { realms: [R4], connected: { [R4]: { [R8]: t0 - 10 } } }, {});
		expect((await env.DB.prepare("SELECT t FROM connected").first<{ t: number }>())!.t).toBe(t0 - 500);
		await send(token, { realms: [R4], connected: { [R4]: { [R8]: t0 - 900 } } }, {});
		expect((await env.DB.prepare("SELECT t FROM connected").first<{ t: number }>())!.t).toBe(t0 - 900);
	});

	it("sending a stored pair again writes no row", async () => {
		await send(token, { realms: [R4], connected: { [R4]: { [R8]: t0 - 5 }, [R8]: { [R4]: t0 - 5 } } }, {});
		const first = await call("POST", "/api/upload", {
			body: { ...body({ houses: houseDefs([R4]) }), connected: { [R4]: { [R8]: t0 - 5 } } },
			headers: bearer(token),
		});
		const out = (await first.json()) as { rowsWritten: number };
		// the token's rate-limit row only
		expect(out.rowsWritten).toBe(1);
	});

	it.each([
		["a realm with |", { "A|B": { [R4]: t0 } }],
		["itself", { [R4]: { [R4]: t0 } }],
		["an empty name", { [R4]: { "": t0 } }],
		["a name over 64 characters", { [R4]: { ["x".repeat(65)]: t0 } }],
		["a time in the future", { [R4]: { [R8]: t0 + 10 * DAY } }],
		["a time before the game", { [R4]: { [R8]: 5 } }],
		["a pair that is not an object", { [R4]: "yes" }],
		["not an object", [R4, R8]],
	])("rejects %s", async (_name, connected) => {
		const res = await send(token, { realms: [R4], connected }, {});
		expect(res.status).toBe(400);
		expect((await env.DB.prepare("SELECT count(*) AS n FROM connected").first<{ n: number }>())!.n).toBe(0);
	});

	it("rejects more connected realms than the limit", async () => {
		const many = Object.fromEntries(Array.from({ length: 21 }, (_, i) => [`Realm ${i}`, t0]));
		expect((await send(token, { realms: [R4], connected: { [R4]: many } }, {})).status).toBe(400);
	});

	it("an upload without `connected` leaves the stored pairs alone", async () => {
		await send(token, { realms: [R4], connected: { [R4]: { [R8]: t0 - 5 } } }, {});
		expect((await send(token, { realms: [R4] }, {})).status).toBe(200);
		expect((await env.DB.prepare("SELECT count(*) AS n FROM connected").first<{ n: number }>())!.n).toBe(1);
	});
});

describe("grouping at read time", () => {
	// Realm 4 and Realm 8 proved; Realm 6 has houses but no proof.
	async function setup() {
		const bothFactions = { alliances: true };
		await send(token, { realms: [R4, R6, R8], ...bothFactions, connected: { [R4]: { [R8]: t0 - 5 }, [R8]: { [R4]: t0 - 5 } } }, {
			scans: [
				{ house: horde(R4), t: t0 - 100, kind: "full", items: 1, lastOnly: 0, source: "ui" },
				{ house: horde(R8), t: t0 - 50, kind: "full", items: 1, lastOnly: 0, source: "ui" },
			],
		});
	}

	it("shows one Horde house, one Alliance house and one Gadgetzan for every realm: the realm is not part of a house (#382)", async () => {
		await setup();
		const hs = await getHouses();
		const labelled = (kind: string, faction: string | null) => hs.filter((h) => h.kind === kind && h.faction === faction);
		const horde4 = hs.find((h) => h.keys.includes(horde(R4)))!;
		expect(horde4.keys).toEqual([horde(R4), horde(R6), horde(R8)]);
		expect(horde4.realms).toEqual([R4, R6, R8]);
		expect(horde4.label).toBe("Horde AH");
		expect(horde4.key).toBe(horde(R4));
		expect(horde4.lastScan).toBe(t0 - 50); // the newest scan of its members
		expect(labelled("faction", "Horde")).toHaveLength(1);
		expect(labelled("faction", "Alliance")).toHaveLength(1); // opposite factions never merged into the Horde one
		expect(labelled("neutral", null)).toHaveLength(1);
		const g = hs.find((h) => h.keys.includes(gadget(R8)))!;
		expect(g.keys).toEqual([gadget(R4), gadget(R6), gadget(R8)]);
		// a Horde house is never in a group with an Alliance one
		for (const h of hs) expect(new Set(h.keys.map((k) => k.split("|")[1]![0])).size).toBe(1);
	});

	it("an upload without a realm in the key is the same house, and its key stands for the group", async () => {
		await setup();
		const b = body({ houses: { H: { kind: "faction", faction: "Horde", label: "Horde AH" } }, scans: [{ house: "H", t: t0 - 10, kind: "full", items: 1, lastOnly: 0, source: "ui" }] });
		expect((await call("POST", "/api/upload", { body: b, headers: bearer(token) })).status).toBe(200);
		const hs = await getHouses();
		const h = hs.find((x) => x.keys.includes("H"))!;
		expect(h.key).toBe("H");
		expect(h.keys).toEqual(["H", horde(R4), horde(R6), horde(R8)].sort());
		expect(h.realms).toEqual([R4, R6, R8]); // the realm-less row has none
		expect(h.lastScan).toBe(t0 - 10);
		expect(hs.filter((x) => x.faction === "Horde")).toHaveLength(1);
		const bad = body({ houses: { H: { realm: "Some Realm", kind: "faction", faction: "Horde", label: "Horde AH" } } });
		expect((await call("POST", "/api/upload", { body: bad, headers: bearer(token) })).status).toBe(400);
	});

	it("deleting the pairs changes nothing, the stored rows were never touched", async () => {
		await setup();
		const before = JSON.stringify(await getHouses());
		await env.DB.prepare("DELETE FROM connected").run();
		expect(JSON.stringify(await getHouses())).toBe(before);
		expect((await env.DB.prepare("SELECT count(*) AS n FROM houses").first<{ n: number }>())!.n).toBe(9);
	});

	it("any member's key finds the group (scans, categories, browse, movers)", async () => {
		await setup();
		for (const key of [horde(R4), horde(R8)]) {
			const k = encodeURIComponent(key);
			expect(((await (await call("GET", `/api/scans?house=${k}`)).json()) as { scans: unknown[] }).scans).toHaveLength(2);
			expect((await call("GET", `/api/categories?house=${k}`)).status).toBe(200);
			expect((await call("GET", `/api/movers?house=${k}`)).status).toBe(200);
		}
		expect((await call("GET", `/api/categories?house=${encodeURIComponent("Nowhere|H")}`)).status).toBe(404);
	});
});

describe("read-time merge", () => {
	const ITEM = "2589";
	async function setup() {
		await send(token, { realms: [R4, R8], connected: { [R4]: { [R8]: t0 - 5 } } }, {
			items: { [ITEM]: { n: "Linen Cloth", q: 1, i: 1, c: 7, s: 5, p: 13 }, "2447": { n: "Peacebloom", q: 1, c: 7, s: 9 } },
			prices: [
				// R4 has the older price, R8 the newer one
				{ item: ITEM, house: horde(R4), last: { t: t0 - 3600, min: 100, qty: 10, listings: 2 }, days: [day(3, 90, 4), day(2, 95, 1)] },
				{ item: ITEM, house: horde(R8), last: { t: t0 - 60, min: 150, qty: 20, listings: 3 }, days: [day(2, 99, 3), day(1, 101, 2)] },
				// only R4 has this one, only R8 has the Gadgetzan row
				{ item: "2447", house: horde(R4), last: { t: t0 - 30, min: 30, qty: 5, listings: 1 } },
				{ item: ITEM, house: gadget(R4), last: { t: t0 - 10, min: 70, qty: 2, listings: 1 } },
				{ item: ITEM, house: gadget(R8), last: { t: t0 - 20, min: 60, qty: 2, listings: 1 } },
			],
		});
	}

	it("item detail: one market per group, newest `last` wins, days merge by n, nothing is shown twice", async () => {
		await setup();
		const res = (await (await call("GET", `/api/items/${ITEM}`)).json()) as {
			markets: { house: string; label: string; current: { min: number; t: number }; days: { day: number; typ: number; n: number }[] }[];
		};
		const horde = res.markets.filter((m) => m.label.includes("Horde AH"));
		expect(horde).toHaveLength(1);
		expect(horde[0]!.house).toBe(`${R4}|H`);
		expect(horde[0]!.label).toBe("Horde AH");
		expect(horde[0]!.current.min).toBe(150); // R8's, 60 s old, over R4's, 1 h old
		// day -2: R4 n=1, R8 n=3 -> R8; day -3 only R4; day -1 only R8
		expect(horde[0]!.days.filter((d) => d.typ !== null).map((d) => [today - d.day, d.typ, d.n])).toEqual([[3, 90, 4], [2, 99, 3], [1, 101, 2]]);
		const neutral = res.markets.filter((m) => m.label.includes("Gadgetzan"));
		expect(neutral).toHaveLength(1);
		expect(neutral[0]!.current.min).toBe(70); // R4's Gadgetzan is the newer one (10 s vs 20 s)
	});

	it("the raw rows stay per house key", async () => {
		await setup();
		const rows = (await env.DB.prepare("SELECT h.key, p.min FROM prices p JOIN houses h ON h.id = p.house WHERE p.item = 2589 AND h.key LIKE '%|H' ORDER BY h.key").all()).results;
		expect(rows).toEqual([{ key: horde(R4), min: 100 }, { key: horde(R8), min: 150 }]);
	});

	it("search shows one price per group", async () => {
		await setup();
		const res = (await (await call("GET", "/api/items?q=linen")).json()) as { items: { prices: { house: string; min: number }[] }[] };
		const prices = res.items[0]!.prices;
		expect(prices.filter((p) => p.house === horde(R4))).toEqual([expect.objectContaining({ min: 150 })]);
		expect(prices.some((p) => p.house === horde(R8))).toBe(false);
	});

	it("browse: the group's items with the newest price and the merged days; categories count an item once", async () => {
		await setup();
		const k = encodeURIComponent(horde(R8)); // a member's key works
		const cats = (await (await call("GET", `/api/categories?house=${k}`)).json()) as { house: string; categories: { class: number; items: number }[] };
		expect(cats.house).toBe(horde(R4));
		expect(cats.categories.filter((c) => c.class === 7).reduce((n, c) => n + c.items, 0)).toBe(2); // 2589 (both houses) and 2447 (R4 only)
		const res = (await (await call("GET", `/api/browse?house=${k}&class=7`)).json()) as {
			items: { id: number; current: { min: number } | null; days: { day: number; typ: number }[] }[];
		};
		const linen = res.items.find((i) => i.id === 2589)!;
		expect(linen.current!.min).toBe(150);
		expect(linen.days.map((d) => d.typ).filter((t) => t !== null)).toEqual([90, 99, 101]);
		expect(res.items.find((i) => i.id === 2447)!.current!.min).toBe(30); // an item only one realm has
	});

	it("movers: the typical price is made from the merged days", async () => {
		const lots = (n: number) => Array.from({ length: n }, (_, i) => day(i + 1, 100));
		await send(token, { realms: [R4, R8], connected: { [R4]: { [R8]: t0 - 5 } } }, {
			items: { [ITEM]: { n: "Linen Cloth", q: 1 } },
			// 1 day at each house: neither has the 2 days a typical price needs, together they have 2 (day 3 is out of the 3-day window)
			prices: [
				{ item: ITEM, house: horde(R4), last: { t: t0 - 60, min: 200, qty: 10, listings: 2 }, days: lots(1) },
				{ item: ITEM, house: horde(R8), last: { t: t0 - 90, min: 150, qty: 10, listings: 2 }, days: [day(2, 100), day(3, 100)] },
			],
		});
		const m = (await (await call("GET", `/api/movers?house=${encodeURIComponent(horde(R4))}`)).json()) as {
			up: { item: number; min: number; typical: number; typicalDays: number }[];
		};
		expect(m.up).toEqual([expect.objectContaining({ item: 2589, min: 200, typical: 100, typicalDays: 2 })]);
		// no pair is needed (#382): the same without the table
		await env.DB.prepare("DELETE FROM connected").run();
		await env.DB.prepare("DELETE FROM cache").run();
		const again = (await (await call("GET", `/api/movers?house=${encodeURIComponent(horde(R8))}`)).json()) as typeof m;
		expect(again.up).toEqual(m.up);
	});
});

describe("the sync download keeps house keys as uploaded", () => {
	it("sends both realms' keys, not a group", async () => {
		const sync = await makeToken("public private", "sync");
		await send(token, { realms: [R4, R8], connected: { [R4]: { [R8]: t0 - 5 } } }, {
			prices: [
				{ item: "2589", house: horde(R4), last: { t: t0 - 60, min: 100, qty: 1, listings: 1 } },
				{ item: "2589", house: horde(R8), last: { t: t0 - 30, min: 120, qty: 1, listings: 1 } },
			],
		});
		const res = await call("GET", "/api/sync/market?since=0", { headers: bearer(sync) });
		expect(res.status).toBe(200);
		const out = (await res.json()) as { houses: Record<string, unknown>; items: Record<string, Record<string, unknown>> };
		expect(Object.keys(out.houses).sort()).toEqual([gadget(R4), gadget(R8), horde(R4), horde(R8)].sort());
		expect(Object.keys(out.items["2589"]!).sort()).toEqual([horde(R4), horde(R8)].sort());
	});
});

describe("groupHouses (pure)", () => {
	let id = 0;
	const row = (key: string): HouseRow => {
		const [realm, slot] = (key.includes("|") ? key.split("|") : ["", key]) as [string, string];
		return {
			id: ++id,
			key,
			realm,
			kind: slot.startsWith("N:") ? "neutral" : "faction",
			faction: slot === "H" ? "Horde" : slot === "A" ? "Alliance" : null,
			label: slot === "H" ? "Horde AH" : slot === "A" ? "Alliance AH" : slot.slice(2),
			last_scan: null,
			last_full_scan: null,
			last_full_scan_items: null,
		};
	};

	it("joins by slot, whatever the realm: faction with the same faction, neutral with the same zone", () => {
		const rows = ["A|H", "A|A", "A|N:Gadgetzan", "B|H", "B|A", "B|N:BootyBay", "B|N:Gadgetzan", "C|H", "D|H", "H"].map(row);
		const groups = groupHouses(rows);
		const keysets = groups.map((g) => g.keys.join(" "));
		expect(keysets).toContain("A|H B|H C|H D|H H");
		expect(keysets).toContain("A|A B|A");
		expect(keysets).toContain("A|N:Gadgetzan B|N:Gadgetzan");
		expect(keysets).toContain("B|N:BootyBay");
		expect(groups).toHaveLength(4);
		expect(groups.find((g) => g.keys.includes("H"))!.house.key).toBe("H"); // the realm-less row stands for it
	});

	it("without a realm-less row the key that sorts first stands for the group; the label stays plain", () => {
		const g = groupHouses([row("Beta|H"), row("Alpha|H")])[0]!;
		expect(g.house.key).toBe("Alpha|H");
		expect(g.house.label).toBe("Horde AH");
		expect(g.realms).toEqual(["Alpha", "Beta"]);
	});
});

describe("merge cost", () => {
	// The free plan gives a Worker 10 ms of CPU per request. The merge is one pass over the rows of the
	// members, so a group of 3 houses of 5000 items each is the bound the browse and the movers meet.
	it("merging 3 houses of 5000 prices and 7 days each stays well under a request's budget", () => {
		const rep = new Map([[1, 1], [2, 1], [3, 1]]);
		const prices = [];
		const days = [];
		for (let h = 1; h <= 3; h++) {
			for (let i = 0; i < 5000; i++) {
				prices.push({ house: h, item: i, suffix: 0, t: 1000 + h, depth_t: null, depth_total: null });
				for (let d = 0; d < 7; d++) days.push({ house: h, item: i, suffix: 0, day: d, src: 1, lo: 1, hi: 2, qty_max: 3, list_max: 4, n: h });
			}
		}
		const start = performance.now();
		const p = mergeGroupPrices(prices, rep);
		const d = mergeGroupDays(days, rep);
		const ms = performance.now() - start;
		expect(p).toHaveLength(5000);
		expect(d).toHaveLength(35000);
		expect(p[0]!.t).toBe(1003);
		// generous: the point is that it is one linear pass, not a measurement of the runner
		expect(ms).toBeLessThan(1500);
	});
});

// keep the unused import checked by the compiler
void upload;
