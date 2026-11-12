// The Waylaid Crates page (#129): data shaping (web/site/lib/crates.ts), the guide's Favor table and the
// route /me/crates. All data here is invented.
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { crateParts, guideFavor } from "../site/lib/crateFavorGuide";
import { type AhPrice, crateGroups, crateIds, crateList, favorBalance, favorIds, favorText, matchesQuery, merchants, reprice, standingMet, wareNotes, wareValue } from "../site/lib/crates";
import { PAGE_HEADERS } from "../src/pages";
import { access, accessJwt, accessKey, type AccessKey, call, clearData, serveAccessKeys } from "./helpers";

const SNAP_T = 1_800_000_000;

// An invented snapshot: three crates and one Favor merchant.
const data = {
	t: SNAP_T,
	crates: {
		list: [
			{
				id: 900001,
				name: "Waylaid Crate: Apprentice Herbs",
				tier: "Apprentice",
				crate: 500,
				crateFrom: "current lowest · Horde AH",
				options: [
					{ n: 20, name: "Example Leaf", id: 910001, cost: 400, how: "current lowest · Horde AH", best: true },
					{ n: 10, name: "Example Root", id: 910002, cost: 900, how: "typical · Horde AH" },
				],
				fillCost: 400,
				missing: "reward not seen",
			},
			{
				id: 900002,
				name: "Waylaid Crate: Journeyman Fabrics",
				tier: "Journeyman",
				held: 2,
				crate: 3000,
				crateFrom: "current lowest · Horde AH",
				options: [
					{ n: 2, name: "Example Hide", id: 910003, cost: 600, how: "crafted", best: true },
					{ n: 20, name: "Example Bolt", id: 910004, cost: 2000, how: "current lowest · Horde AH" },
				],
				fillCost: 600,
				reward: 25,
				rewardFrom: "seen",
				observed: 3,
				total: 3600,
				perFavor: 144,
				fillPerFavor: 24,
			},
			{
				id: 900003,
				name: "Waylaid Crate: Earthly Artisan Herbs",
				tier: "Earthly",
				options: [{ n: 5, name: "Unknown Bloom" }],
				missing: "no price for any bundle, reward not seen, no crate price",
			},
		],
		best: 900002,
		bestHeld: 900002,
	},
	favor: {
		id: 3402,
		name: "Merchant's Favor",
		balance: 40,
		vendors: [
			{
				npc: 990001,
				name: "Example Trader",
				zone: "Example Vale",
				faction: "Example Supply Company",
				factionID: 9001,
				standing: "Neutral",
				standingNow: "Friendly",
				rep: { value: 4500, min: 3000, max: 9000 },
				full: true,
				t: SNAP_T - 3600,
				items: [
					{ id: 920001, name: "Pattern: Example Belt", favor: 30, unusable: true },
					{ id: 920002, name: "Example Tonic", favor: 10, s: 5, p: 100 },
					{ id: 920003, name: "Example Charm", favor: 60, req: "Honored", n: 1 },
					{ id: 920004, name: "Example Token", favor: 20, other: "1 Example Mark", known: true },
				],
			},
		],
	},
};

const price = (t: number, min: number | null, listed = true, typical: number | null = null): AhPrice => ({ t, min, listed, typical });

describe("guide Favor per crate", () => {
	it("reads rank and kind from the name, not the first word", () => {
		expect(crateParts("Waylaid Crate: Earthly Expert Herbs")).toEqual({ rank: "Expert", kind: "Herbs" });
		expect(crateParts("Waylaid Crate: Apprentice Ingots")).toEqual({ rank: "Apprentice", kind: "Ingots" });
		expect(crateParts("Something Else")).toEqual({ rank: null, kind: null });
	});

	it("has the published values, the rank rule and nothing for Artisan", () => {
		expect(guideFavor("Waylaid Crate: Apprentice Ore")).toEqual({ favor: 5, basis: "listed" });
		expect(guideFavor("Waylaid Crate: Apprentice Parts")).toEqual({ favor: 10, basis: "listed" });
		expect(guideFavor("Waylaid Crate: Journeyman Fabrics")).toEqual({ favor: 20, basis: "listed" });
		expect(guideFavor("Waylaid Crate: Expert Textiles")).toEqual({ favor: 15, basis: "listed" });
		expect(guideFavor("Waylaid Crate: Flowering Expert Herbs")).toEqual({ favor: 15, basis: "rule" });
		expect(guideFavor("Waylaid Crate: Expert Parts")).toEqual({ favor: 30, basis: "rule" });
		expect(guideFavor("Waylaid Crate: Artisan Ore")).toBeNull();
		expect(guideFavor("Waylaid Crate: Earthly Artisan Herbs")).toBeNull();
	});
});

describe("repricing", () => {
	it("takes a newer listed AH price over an AH-based snapshot price, either way", () => {
		expect(reprice(400, "current lowest · Horde AH", SNAP_T, price(SNAP_T + 60, 25), 20)).toEqual({ copper: 500, source: "ah", label: "Horde AH now", t: SNAP_T + 60 });
		expect(reprice(400, "typical · Horde AH", SNAP_T, price(SNAP_T + 60, 10), 20)?.copper).toBe(200);
	});

	it("keeps the snapshot price when the AH price is older, missing or not listed", () => {
		expect(reprice(400, "x · Horde AH", SNAP_T, price(SNAP_T - 60, 10), 20)?.source).toBe("snapshot");
		expect(reprice(400, "x · Horde AH", SNAP_T, undefined, 20)?.source).toBe("snapshot");
		expect(reprice(400, "x · Horde AH", SNAP_T, price(SNAP_T + 60, 10, false), 20)?.source).toBe("snapshot");
	});

	it("keeps a crafted or vendor cost unless the newer AH price is cheaper", () => {
		expect(reprice(600, "crafted", SNAP_T, price(SNAP_T + 60, 400), 2)?.source).toBe("snapshot");
		expect(reprice(600, "crafted", SNAP_T, price(SNAP_T + 60, 200), 2)).toMatchObject({ copper: 400, source: "ah" });
		expect(reprice(50, "vendor", SNAP_T, price(SNAP_T + 60, 100))?.source).toBe("snapshot");
	});

	it("uses any AH price where the snapshot has none", () => {
		expect(reprice(null, null, SNAP_T, price(SNAP_T - 99, 7), 3)).toMatchObject({ copper: 21, source: "ah" });
		expect(reprice(null, null, SNAP_T, undefined)).toBeNull();
	});
});

describe("crate list", () => {
	it("lists the IDs to price", () => {
		expect(crateIds(data).sort()).toEqual([900001, 900002, 900003, 910001, 910002, 910003, 910004]);
		expect(favorIds(data).sort()).toEqual([920001, 920002, 920003, 920004]);
		expect(crateIds(null)).toEqual([]);
	});

	it("uses measured Favor first, the guide where nothing was seen, and nothing where neither exists", () => {
		const { list } = crateList(data, SNAP_T, new Map());
		const by = new Map(list.map((c) => [c.id, c]));
		expect(by.get(900002)!.favor).toEqual({ amount: 25, from: "seen", observed: 3 }); // guide says 20: measured wins
		expect(by.get(900001)!.favor).toEqual({ amount: 5, from: "guide", observed: null });
		expect(by.get(900003)!.favor).toBeNull();
		expect(favorText(by.get(900002)!.favor)).toBe("25 Favor (measured, n=3)");
		expect(favorText(by.get(900001)!.favor)).toBe("5 Favor (guide, beta)");
		expect(favorText({ amount: 15, from: "guide rule", observed: null })).toBe("15 Favor (guide rule, beta)");
		expect(favorText({ amount: 7, from: "tooltip", observed: null })).toBe("7 Favor (tooltip)");
		expect(favorText(null)).toBe("Favor not known yet");
	});

	it("works out cost per Favor from the snapshot prices and ranks like Crates.lua", () => {
		const r = crateList(data, SNAP_T, new Map());
		expect(r.list.map((c) => c.id)).toEqual([900002, 900001, 900003]);
		const [a, b, c] = r.list;
		expect(a).toMatchObject({ total: 3600, perFavor: 144, fillPerFavor: 24, held: 2, rank: "Journeyman", kind: "Fabrics" });
		expect(a!.fill?.name).toBe("Example Hide");
		expect(a!.fill?.crafted).toBe(true);
		expect(b).toMatchObject({ total: 900, perFavor: 180, fillPerFavor: 80 });
		expect(c).toMatchObject({ fill: null, total: null, perFavor: null, fillPerFavor: null, rank: "Artisan", tier: "Earthly" });
		expect(r.best).toBe(900002);
		expect(r.bestHeld).toBe(900002);
	});

	it("re-prices with newer AH prices and ranks again", () => {
		const prices = new Map<number, AhPrice>([
			[900002, price(SNAP_T + 600, 9000)], // the crate got dearer
			[910001, price(SNAP_T + 600, 10)], // the leaf got cheaper: 20 x 10
			[900001, price(SNAP_T + 600, 300)],
		]);
		const r = crateList(data, SNAP_T, prices);
		const herbs = r.list.find((c) => c.id === 900001)!;
		expect(herbs.fill?.cost).toMatchObject({ copper: 200, source: "ah" });
		expect(herbs.total).toBe(500);
		expect(herbs.perFavor).toBe(100);
		expect(r.list[0]!.id).toBe(900001);
		expect(r.best).toBe(900001);
		expect(r.bestHeld).toBe(900002); // the only crate carried
	});

	it("groups by rank and kind and searches crates and goods", () => {
		const { list } = crateList(data, SNAP_T, new Map());
		expect(crateGroups(list)).toEqual([
			{ rank: "Apprentice", kinds: [{ kind: "Herbs", n: 1 }], n: 1 },
			{ rank: "Journeyman", kinds: [{ kind: "Fabrics", n: 1 }], n: 1 },
			{ rank: "Artisan", kinds: [{ kind: "Herbs", n: 1 }], n: 1 },
		]);
		expect(list.filter((c) => matchesQuery(c, "bolt")).map((c) => c.id)).toEqual([900002]);
		expect(list.filter((c) => matchesQuery(c, "herbs")).length).toBe(2);
	});
});

describe("Favor merchants", () => {
	it("reads the balance", () => {
		expect(favorBalance(data)).toEqual({ name: "Merchant's Favor", balance: 40, max: null, earned: null });
		expect(favorBalance({})).toBeNull();
	});

	it("compares the requirement with the standing now", () => {
		expect(standingMet("Honored", "Friendly")).toBe(false);
		expect(standingMet("Friendly", "Friendly")).toBe(true);
		expect(standingMet("Requires Example Guild - Honored", "Friendly")).toBeNull();
		expect(standingMet(null, "Friendly")).toBeNull();
	});

	it("values a ware at the AH after the cut, else the typical, else unknown", () => {
		expect(wareValue(price(SNAP_T, 1000), 1)).toEqual({ copper: 950, basis: "current", t: SNAP_T });
		expect(wareValue(price(SNAP_T, 1000, false, 800), 2)).toEqual({ copper: 1520, basis: "typical", t: null });
		expect(wareValue(price(SNAP_T, null, false), 1)).toBeNull();
		expect(wareValue(undefined, 1)).toBeNull();
	});

	it("ranks wares by AH value per Favor, unknown ones last", () => {
		const prices = new Map<number, AhPrice>([
			[920001, price(SNAP_T, 2000)], // 1900 / 30 = 63.3
			[920002, price(SNAP_T, 100)], // 5 x 95 = 475, minus 100 copper = 375 / 10 = 37.5
			[920003, price(SNAP_T, 12000)], // 11400 / 60 = 190
		]);
		const [m] = merchants(data, prices);
		expect(m).toMatchObject({ name: "Example Trader", standingNow: "Friendly", rep: { value: 4500, min: 3000, max: 9000 }, full: true });
		expect(m!.wares.map((w) => w.id)).toEqual([920003, 920001, 920002, 920004]);
		const [charm, belt, tonic, token] = m!.wares;
		expect(charm!.perFavor).toBe(190);
		expect(charm!.reqMet).toBe(false);
		expect(belt!.perFavor).toBeCloseTo(63.33, 2);
		expect(tonic!.perFavor).toBe(37.5);
		expect(token!.value).toBeNull();
		expect(wareNotes(tonic!)).toEqual(["stack of 5"]);
		expect(wareNotes(token!)).toEqual(["also 1 Example Mark", "already known"]);
		expect(wareNotes(belt!)).toEqual(["unusable for you"]);
		expect(wareNotes(charm!)).toEqual(["1 in stock"]);
	});
});

describe("route /me/crates", () => {
	let key: AccessKey;
	beforeAll(async () => {
		key = await accessKey("k1");
	});
	beforeEach(async () => {
		await clearData();
		serveAccessKeys([key]);
	});
	afterEach(() => {
		vi.restoreAllMocks();
	});

	it("serves the crates page only with Access, with the page headers", async () => {
		expect((await call("GET", "/me/crates")).status).toBe(403);
		const jwt = await accessJwt(key);
		for (const path of ["/me/crates", "/me/crates/", "/me/crates/index.html"]) {
			const res = await call("GET", path, { headers: access(jwt) });
			expect(res.status).toBe(200);
			expect(res.headers.get("cache-control")).toBe("private, no-store");
			for (const [k, v] of Object.entries(PAGE_HEADERS)) expect(res.headers.get(k)).toBe(v);
			expect(await res.text()).toContain('<script type="module" src="/assets/crates.js"></script>');
		}
		for (const path of ["/me/nothing-here", "/me/crates/more", "/me/Crates", "/me/crates.js"]) {
			const res = await call("GET", path, { headers: access(jwt) });
			expect(res.status).toBe(404);
			expect(res.headers.get("cache-control")).toBe("private, no-store");
		}
	});
});
