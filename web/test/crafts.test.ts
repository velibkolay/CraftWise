// The crafts view's logic (web/site/lib/crafts.ts, #185). Data and prices are invented.
import { describe, expect, it } from "vitest";
import { type CraftFilter, craftSpells, formatPct, keep, knownSpells, paybackOf, snapshotLines, pctOf, professionList, recipeCostOf, scopeOf, sortCrafts, toRow } from "../site/lib/crafts";
import type { Quote, RecipeData } from "../site/lib/recipes";

const data: RecipeData = {
	v: 1,
	about: "",
	sources: {},
	professions: { "197": "Tailoring", "164": "Blacksmithing", "333": "Enchanting" },
	teach: { "100": [10, 125] },
	// 10: 2 x item 50 from 3 x 60 + 1 x 61 (a loop); 11: an enchant; 12: 1 x item 51 from 1 x 62 (an AH reagent)
	spells: { "10": [197, 50, 2, 60, 3, 61, 1], "11": [333, 0, 0, 60, 1], "12": [164, 51, 1, 62, 1] },
	names: {},
	vendor: { "60": 2, "61": 10 },
	sell: { "50": 20, "51": 100 },
};
const q = (typical: number | null): Quote => ({ typical, lowest: null, sellPrice: null });
const all: CraftFilter = { line: null, vendorOnly: false, loopsOnly: false, known: null, ownLines: null, q: "" };
const names = new Map<number, string | null>([
	[50, "Bolt"],
	[51, "Blade"],
]);

describe("crafts view", () => {
	const spells = craftSpells(data);
	const fetched = new Set([50, 51, 60, 61, 62]);
	const quotes = new Map<number, Quote>([
		[50, q(30)],
		[51, q(90)],
		[62, q(40)],
	]);
	const rows = spells.map((s) => toRow(data, s, quotes, fetched, names));

	it("lists the spells that make an item, not enchants", () => {
		expect(spells.map((s) => s.id)).toEqual([10, 12]);
		expect(professionList(data, spells)).toEqual([
			{ line: 164, name: "Blacksmithing" },
			{ line: 197, name: "Tailoring" },
		]);
	});

	it("keeps the AH and the vendor figures apart", () => {
		// Bolt: cost 3 x 2 + 10 = 16; AH 30 -> 28 after the cut, x2 = 56; vendor 2 x 20 = 40
		expect(rows[0]).toMatchObject({ cost: 16, ah: 56, vendor: 40, profit: 40, vprofit: 24, loop: true, recipeItem: 100, ready: true });
		expect(rows[1]).toMatchObject({ cost: 40, vendor: 100, vprofit: 60, loop: false, recipeItem: null });
	});

	it("filters by vendor profit, loops, profession and my crafts", () => {
		expect(rows.filter((r) => keep(r, { ...all, vendorOnly: true }))).toHaveLength(2);
		expect(scopeOf(data, spells, { ...all, loopsOnly: true }).map((s) => s.id)).toEqual([10]);
		expect(scopeOf(data, spells, { ...all, line: 164 }).map((s) => s.id)).toEqual([12]);
		expect(scopeOf(data, spells, { ...all, known: new Set([12]) }).map((s) => s.id)).toEqual([12]);
		expect(rows.filter((r) => keep(r, { ...all, q: "blad" })).map((r) => r.spell.id)).toEqual([12]);
		const loss = toRow(data, spells[1]!, new Map([[62, q(500)]]), fetched, names);
		expect(loss.vprofit).toBe(100 - 500);
		expect(keep(loss, { ...all, vendorOnly: true })).toBe(false);
	});

	it("marks a craft whose prices are not fetched yet as not ready, and never fills in a price", () => {
		const r = toRow(data, spells[1]!, new Map(), new Set([51]), names);
		expect(r.ready).toBe(false);
		expect(r.cost).toBeNull();
		expect(r.vprofit).toBeNull();
		expect(r.vendor).toBe(100);
	});

	it("sorts with unknowns last in both directions", () => {
		const unknown = toRow(data, spells[1]!, new Map(), fetched, names);
		const list = [unknown, rows[0]!];
		expect(sortCrafts(list, "vprofit", true).map((r) => r.spell.id)).toEqual([10, 12]);
		expect(sortCrafts(list, "vprofit", false).map((r) => r.spell.id)).toEqual([10, 12]);
		expect(sortCrafts(rows, "name", false).map((r) => r.name)).toEqual(["Blade", "Bolt"]);
	});
});

describe("known spells of a snapshot", () => {
	it("reads the known IDs of every profession and ignores what isn't there", () => {
		const d = { professions: [{ name: "Tailoring", known: "10,12, 99,x" }, { name: "Fishing", cached: false }, { name: "Cooking", known: "7" }] };
		expect([...knownSpells(d)].sort((a, b) => a - b)).toEqual([7, 10, 12, 99]);
		expect(knownSpells(null).size).toBe(0);
		expect(knownSpells({ professions: "no" }).size).toBe(0);
	});
});

describe("profit %", () => {
	it("is profit / cost, null when either is unknown or cost is 0", () => {
		// Veli's example: 10s cost, 15s profit = +150 %; 1g cost, 10s profit = +10 %.
		expect(pctOf(1500, 1000)).toBe(1.5);
		expect(pctOf(1000, 10000)).toBe(0.1);
		expect(pctOf(-500, 1000)).toBe(-0.5);
		expect(pctOf(null, 1000)).toBeNull();
		expect(pctOf(100, null)).toBeNull();
		expect(pctOf(100, 0)).toBeNull();
	});
	it("formats sensibly", () => {
		expect(formatPct(1.5)).toBe("+150 %");
		expect(formatPct(0.1)).toBe("+10 %");
		expect(formatPct(0.0734)).toBe("+7.3 %");
		expect(formatPct(-0.25)).toBe("−25 %");
		expect(formatPct(0)).toBe("0 %");
		expect(formatPct(0.0001)).toBe("0 %");
		expect(formatPct(123.4)).toBe("+12,340 %");
	});
	it("sorts by % with nulls last in both directions, ties by absolute profit then name", () => {
		const row = (name: string, id: number, cost: number | null, profit: number | null) =>
			({ spell: { id, profession: null }, name, cost, profit, vprofit: profit, pct: pctOf(profit, cost), vpct: pctOf(profit, cost) }) as never;
		const list = [row("B", 1, 1000, 1500), row("A", 2, 10000, 1000), row("N", 3, null, 500), row("C", 4, 2000, 3000), row("Z", 5, 100, 150)];
		const names = (d: boolean, k: "pct" | "vpct" = "pct") => sortCrafts(list, k, d).map((r) => r.name).join("");
		expect(names(true)).toBe("CBZAN"); // B, C, Z all 150 %; bigger profit first when descending, then A, null last
		expect(names(false)).toBe("AZBCN");
		expect(names(true, "vpct")).toBe("CBZAN");
	});
});

describe("recipe cost and payback (#263)", () => {
	// Spell 10 is taught by item 100; spell 12 has no recipe item.
	const spells = craftSpells(data);
	const fetched = new Set([50, 51, 60, 61, 62, 100]);
	const quotes = new Map<number, Quote>([
		[50, q(30)],
		[51, q(90)],
		[62, q(40)],
	]);
	const row = (id: number, qs = quotes, known: Set<number> | null = null, vendorBasis = false, fe = fetched) => toRow(data, spells.find((s) => s.id === id)!, qs, fe, names, known, vendorBasis);

	it("costs the vendor price of the recipe item when only a vendor sells it", () => {
		const d2 = { ...data, vendor: { ...data.vendor, "100": 700 } };
		expect(recipeCostOf(d2, 10, 100, quotes, null)).toEqual({ source: "vendor", unit: 700, basis: null });
	});

	it("takes the cheaper of the vendor and the AH, and says which", () => {
		const d2 = { ...data, vendor: { ...data.vendor, "100": 700 } };
		const cheaperAh = new Map(quotes).set(100, q(500));
		expect(recipeCostOf(d2, 10, 100, cheaperAh, null)).toEqual({ source: "ah", unit: 500, basis: "typical" });
		const dearerAh = new Map(quotes).set(100, q(900));
		expect(recipeCostOf(d2, 10, 100, dearerAh, null)?.source).toBe("vendor");
	});

	it("uses the lowest listing when there is no typical price", () => {
		const lowest = new Map(quotes).set(100, { typical: null, lowest: 450, sellPrice: null });
		expect(recipeCostOf(data, 10, 100, lowest, null)).toEqual({ source: "ah", unit: 450, basis: "lowest" });
	});

	it("is 0 and 'known' when a character knows the recipe, whatever it would cost", () => {
		const withAh = new Map(quotes).set(100, q(5000));
		expect(recipeCostOf(data, 10, 100, withAh, new Set([10]))).toEqual({ source: "known", unit: 0, basis: null });
		expect(row(10, withAh, new Set([10]))).toMatchObject({ recipe: 0, payback: 0, recipeReady: true });
	});

	it("is unknown without a first-hand figure: no recipe item, or no vendor and no AH price", () => {
		expect(recipeCostOf(data, 12, null, quotes, null)).toBeNull();
		expect(recipeCostOf(data, 10, 100, quotes, null)).toBeNull();
		expect(row(12)).toMatchObject({ recipeCost: null, recipe: null, payback: null });
		expect(row(10)).toMatchObject({ recipeCost: null, payback: null, recipeReady: true });
	});

	it("is not ready until the recipe item's price has been fetched", () => {
		expect(row(10, quotes, null, false, new Set([50, 60, 61])).recipeReady).toBe(false);
		expect(row(12, quotes, null, false, new Set([51, 62])).recipeReady).toBe(true); // no recipe item: nothing to fetch
	});

	it("pays back after ceil(cost / profit) crafts, never when there is no profit, unknown when either is", () => {
		expect(paybackOf(1000, 280)).toBe(4);
		expect(paybackOf(840, 280)).toBe(3);
		expect(paybackOf(5, 280)).toBe(1);
		expect(paybackOf(1000, 0)).toBe(Infinity);
		expect(paybackOf(1000, -5)).toBe(Infinity);
		expect(paybackOf(0, -5)).toBe(0);
		expect(paybackOf(1000, null)).toBeNull();
		expect(paybackOf(null, 280)).toBeNull();
	});

	it("follows the basis: vendor profit when 'Profit when sold to a vendor' is ticked, else the AH profit", () => {
		const qs = new Map(quotes).set(100, q(1000));
		// spell 10: 2 x item 50 at 30 = 2 x 28 after the cut = 56 - (3 x 2 + 10 = 16 reagents) = 40 AH profit; vendor 2 x 20 = 40 - 16 = 24
		const ah = row(10, qs);
		const vendor = row(10, qs, null, true);
		expect([ah.profit, ah.vprofit]).toEqual([40, 24]);
		expect(ah.payback).toBe(Math.ceil(1000 / 40));
		expect(vendor.payback).toBe(Math.ceil(1000 / 24));
	});

	it("says never for a recipe that costs something when the craft loses money", () => {
		const qs = new Map<number, Quote>([[50, { typical: 5, lowest: null, sellPrice: 0 }], [100, q(1000)]]); // 2 x 4 = 8 - 16 reagents: a loss (vendors don't buy it)
		expect(row(10, qs).payback).toBe(Infinity);
	});

	it("sorts by payback and recipe cost, unknowns last in both directions", () => {
		const d3: RecipeData = { ...data, teach: { "100": [10, 125], "101": [12, 0] } };
		const qs = new Map<number, Quote>([[50, q(30)], [51, q(90)], [62, q(40)], [100, q(1000)], [101, q(100)]]);
		const rows3 = craftSpells(d3).map((s) => toRow(d3, s, qs, new Set([50, 51, 60, 61, 62, 100, 101]), names));
		const order = (k: "payback" | "recipe", desc: boolean) => sortCrafts(rows3, k, desc).map((r) => r.spell.id);
		expect(order("recipe", false)).toEqual([12, 10]);
		expect(order("recipe", true)).toEqual([10, 12]);
		expect(order("payback", false)).toEqual([12, 10]); // spell 12: 100 / (85 - 40) = 3 crafts, spell 10: 1000 / 40 = 25
		expect(order("payback", true)).toEqual([10, 12]);
		const unknown = toRow(d3, craftSpells(d3)[1]!, new Map(), new Set([51, 62]), names);
		expect(sortCrafts([unknown, rows3[0]!], "payback", true).map((r) => r.spell.id)).toEqual([10, 12]);
	});
});

describe("known recipes, my professions, unlearned (#263)", () => {
	const spells = craftSpells(data);
	const fe = new Set([50, 51, 60, 61, 62, 100]);
	const mk = (id: number, known: Set<number> | null, cached: Set<number> | null) => toRow(data, spells.find((s) => s.id === id)!, new Map(), fe, names, known, false, cached);

	it("reads the skill lines of a snapshot and which of them list their recipes", () => {
		const snap = { professions: [{ line: 197, known: "10" }, { line: 164, cached: false }, { name: "x" }] };
		expect(snapshotLines(snap)).toEqual({ own: new Set([197, 164]), listed: new Set([197]) });
		expect(snapshotLines(null)).toEqual({ own: new Set(), listed: new Set() });
	});

	it("My professions keeps every recipe of the owned lines, learned or not", () => {
		expect(scopeOf(data, spells, { ...all, ownLines: new Set([197]) }).map((s) => s.id)).toEqual([10]);
	});

	it("marks a recipe learned, unlearned only where the profession's recipes are listed, else unknown", () => {
		const known = new Set([10]);
		expect(mk(10, known, new Set([197])).learned).toBe(true);
		expect(mk(12, known, new Set([164])).learned).toBe(false);
		expect(mk(12, known, new Set([197])).learned).toBeNull(); // 164's recipes are not listed: nothing is assumed
		expect(mk(12, null, null).learned).toBeNull();
	});
});
