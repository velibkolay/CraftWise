// The crafts view's logic (web/site/lib/crafts.ts, #185). Data and prices are invented.
import { describe, expect, it } from "vitest";
import { type CraftFilter, craftSpells, keep, knownSpells, professionList, scopeOf, sortCrafts, toRow } from "../site/lib/crafts";
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
const all: CraftFilter = { line: null, vendorOnly: false, loopsOnly: false, known: null, q: "" };
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
