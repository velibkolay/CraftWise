// Crafting profit per recipe (web/site/lib/recipes.ts, #143) and the recipe data it reads
// (public/data/recipes.json, tools/gen_site_recipes.lua). The prices in the maths tests are invented.
import { describe, expect, it } from "vitest";
import recipesJson from "../public/data/recipes.json?raw";
import type { BrowseItem } from "../site/lib/api";
import {
	ahPrice,
	basisText,
	craft,
	depthText,
	isThin,
	itemsNeeded,
	makersOf,
	paysBack,
	productValue,
	type Quote,
	quoteOf,
	reagentPrice,
	type RecipeData,
	recipeItemOf,
	recipeRow,
	spellOf,
	teachOf,
} from "../site/lib/recipes";

const real = JSON.parse(recipesJson) as RecipeData;

// A small data set: recipe item 100 teaches spell 10 (makes 2 x item 50 from 3 x 60 and 1 x 61; 61 sold by
// vendors for 10c); 101 teaches the enchant 11; 102 teaches 12, which isn't in the reagent data.
const data: RecipeData = {
	v: 1,
	about: "",
	sources: {},
	professions: { "197": "Tailoring", "333": "Enchanting" },
	teach: { "100": [10, 125], "101": [11, 0], "102": [12, 50] },
	spells: { "10": [197, 50, 2, 60, 3, 61, 1], "11": [333, 0, 0, 60, 1], "13": [197, 50, 1, 60, 2] },
	names: { "11": "Enchant Bracer - Minor Stamina" },
	vendor: { "61": 10 },
	sell: { "50": 7 },
};

const q = (typical: number | null, lowest: number | null, sellPrice: number | null = null): Quote => ({ typical, lowest, sellPrice });

describe("recipe data (recipes.json)", () => {
	it("is the generator's format with every source header", () => {
		expect(real.v).toBe(1);
		expect(Object.keys(real.sources).sort()).toEqual(["Recipes.lua", "Sources.lua", "Vendor.lua"]);
		expect(real.sources["Vendor.lua"]!.join(" ")).toContain("LGPL-2.1");
		expect(real.sources["Sources.lua"]!.join(" ")).toContain("GPL-3.0-or-later");
		expect(real.about).toContain("tools/gen_site_recipes.lua");
	});

	it("reads Sources.lua, Recipes.lua and Vendor.lua as the addon has them", () => {
		// Sources.lua: [2158] = { skill = 65, item = 2406 }; Recipes.lua: [2158] = Leatherworking, 7 Light
		// Leather + 2 Coarse Thread -> 1 x 2307; Vendor.lua: Coarse Thread 10c.
		const t = teachOf(real, 2406)!;
		expect(t.skill).toBe(65);
		expect(t.spell).toEqual({
			id: 2158,
			skillLine: 165,
			profession: "Leatherworking",
			output: 2307,
			qty: 1,
			reagents: [
				{ item: 2318, qty: 7 },
				{ item: 2320, qty: 2 },
			],
			name: null,
		});
		expect(real.vendor["2320"]).toBe(10);
		expect(spellOf(real, 818)).toMatchObject({ output: null, qty: 0, profession: "Cooking" });
	});

	it("names every profession a spell uses and points every recipe item at a known spell", () => {
		for (const row of Object.values(real.spells)) expect(real.professions[String(row[0])]).toBeTruthy();
		for (const [spell] of Object.values(real.teach)) expect(real.spells[String(spell)]).toBeTruthy();
	});
});

describe("spells and recipe items", () => {
	it("unpacks a spell", () => {
		expect(spellOf(data, 10)).toEqual({ id: 10, skillLine: 197, profession: "Tailoring", output: 50, qty: 2, reagents: [{ item: 60, qty: 3 }, { item: 61, qty: 1 }], name: null });
		expect(spellOf(data, 11)).toMatchObject({ output: null, qty: 0, name: "Enchant Bracer - Minor Stamina" });
		expect(spellOf(data, 99)).toBeNull();
	});

	it("knows what a recipe item teaches, the required skill only when given", () => {
		expect(teachOf(data, 100)).toMatchObject({ spellId: 10, skill: 125 });
		expect(teachOf(data, 101)!.skill).toBeNull();
		expect(teachOf(data, 102)).toEqual({ spellId: 12, spell: null, skill: 50 });
		expect(teachOf(data, 999)).toBeNull();
	});

	it("finds the spells that make an item and the recipe item of a spell", () => {
		expect(makersOf(data, 50).map((s) => s.id)).toEqual([10, 13]);
		expect(makersOf(data, 60)).toEqual([]);
		expect(recipeItemOf(data, 10)).toEqual({ item: 100, skill: 125 });
		expect(recipeItemOf(data, 13)).toBeNull();
	});

	it("lists the products and reagents to price", () => {
		expect(itemsNeeded(data, [100, 101, 102, 999]).sort()).toEqual([50, 60, 61]);
	});
});

describe("prices", () => {
	it("takes the typical price, else the lowest listing", () => {
		expect(ahPrice(q(100, 90))).toEqual({ unit: 100, basis: "typical" });
		expect(ahPrice(q(null, 90))).toEqual({ unit: 90, basis: "lowest", units: null, listings: null });
		expect(ahPrice({ ...q(null, 90), units: 3, listings: 1 })).toEqual({ unit: 90, basis: "lowest", units: 3, listings: 1 });
		expect(ahPrice(q(null, null))).toBeNull();
		expect(ahPrice(undefined)).toBeNull();
	});

	it("buys a reagent where it is cheaper: auction house or vendor", () => {
		expect(reagentPrice(q(15, 12), 10)).toEqual({ unit: 10, basis: "vendor" });
		expect(reagentPrice(q(8, 12), 10)).toEqual({ unit: 8, basis: "typical" });
		expect(reagentPrice(undefined, 10)).toEqual({ unit: 10, basis: "vendor" });
		expect(reagentPrice(q(null, 30), undefined)).toMatchObject({ unit: 30, basis: "lowest" });
		expect(reagentPrice(q(null, null), undefined)).toBeNull();
	});

	it("values the product after the 5% cut, or at the vendor when a vendor pays more", () => {
		expect(productValue(q(1000, 900, 20), undefined)).toEqual({ unit: 950, basis: "typical" });
		expect(productValue(q(null, 101, 0), undefined)).toMatchObject({ unit: 95, basis: "lowest" });
		expect(productValue(q(100, null, 96), undefined)).toEqual({ unit: 96, basis: "vendor" });
		// No site sell price yet: the bundled one, still only against an AH price.
		expect(productValue(q(100, null, null), 99)).toEqual({ unit: 99, basis: "vendor" });
		expect(productValue(q(100, null, 0), 99)).toEqual({ unit: 95, basis: "typical" });
	});

	it("gives the product no value without a Horde AH price, even when a vendor buys it", () => {
		expect(productValue(q(null, null, 500), undefined)).toBeNull();
		expect(productValue(q(null, null, null), 7)).toBeNull();
		expect(productValue(undefined, undefined)).toBeNull();
	});

	it("marks a lowest-listing price on one or two listings or under 5 units as thin", () => {
		const lo = (units: number | null, listings: number | null) => ({ unit: 10, basis: "lowest" as const, units, listings });
		expect(isThin(lo(4, null))).toBe(true);
		expect(isThin(lo(40, 2))).toBe(true);
		expect(isThin(lo(5, 3))).toBe(false);
		expect(isThin(lo(null, null))).toBe(false);
		expect(isThin({ unit: 10, basis: "typical" })).toBe(false);
		expect(isThin(null)).toBe(false);
		expect(depthText(lo(3, 1))).toBe("3 units in 1 listing");
		expect(depthText(lo(1, null))).toBe("1 unit");
		expect(depthText(lo(null, null))).toBeNull();
		expect(depthText({ unit: 10, basis: "typical" })).toBeNull();
	});

	it("reads a browse item", () => {
		const item = { typical: { status: "too_little_history", days: 1 }, current: { listed: true, min: 37, qty: 12, listings: null }, sellPrice: 15 } as unknown as BrowseItem;
		expect(quoteOf(item)).toEqual({ typical: null, lowest: 37, sellPrice: 15, units: 12, listings: null });
		const gone = { typical: { status: "ok", price: 40, days: 5 }, current: { listed: false, min: 37, qty: 3, listings: 1 }, sellPrice: null } as unknown as BrowseItem;
		expect(quoteOf(gone)).toEqual({ typical: 40, lowest: null, sellPrice: null, units: null, listings: null });
		expect(basisText("typical")).toBe("AH market price");
	});
});

describe("craft", () => {
	const spell = spellOf(data, 10)!;

	it("profit = product value x output quantity - reagent cost", () => {
		const quotes = new Map([
			[50, q(200, 180, 5)],
			[60, q(30, 25)],
			[61, q(null, 15)],
		]);
		const c = craft(data, spell, quotes);
		expect(c.reagents).toEqual([
			{ item: 60, qty: 3, price: { unit: 30, basis: "typical" }, total: 90 },
			{ item: 61, qty: 1, price: { unit: 10, basis: "vendor" }, total: 10 },
		]);
		expect(c.cost).toBe(100);
		expect(c.value).toEqual({ unit: 190, basis: "typical" });
		expect(c.revenue).toBe(380);
		expect(c.profit).toBe(280);
		expect(c.missing).toEqual([]);
		expect(c).toMatchObject({ noAhProduct: false, vendorFloor: null, worst: null, thin: false });
	});

	it("marks the profit thin when the product's lowest listing is thin", () => {
		const c = craft(data, spell, new Map([[50, { ...q(null, 200), units: 2, listings: 1 }], [60, q(30, null)]]));
		expect(c.profit).toBe(190 * 2 - 100);
		expect(c.thin).toBe(true);
		expect(c.value).toEqual({ unit: 190, basis: "lowest", units: 2, listings: 1 });
	});

	it("has no profit when the product has no AH price, the vendor price only as the worst case", () => {
		const c = craft(data, spell, new Map([[50, q(null, null, 30)], [60, q(30, null)]]));
		expect(c.profit).toBeNull();
		expect(c.missing).toEqual([50]);
		expect(c).toMatchObject({ noAhProduct: true, vendorFloor: 30, worst: 30 * 2 - 100 });
		const bundled = craft(data, spell, new Map([[60, q(30, null)]]));
		expect(bundled).toMatchObject({ noAhProduct: true, vendorFloor: 7, worst: 14 - 100 });
	});

	it("is negative when the reagents cost more", () => {
		const c = craft(data, spell, new Map([[50, q(20, null, 0)], [60, q(30, null)]]));
		expect(c.profit).toBe(19 * 2 - 100);
	});

	it("is unknown when a reagent or the product has no price, never guessed", () => {
		const noReagent = craft(data, spell, new Map([[50, q(200, null)]]));
		expect(noReagent.cost).toBeNull();
		expect(noReagent.profit).toBeNull();
		expect(noReagent.missing).toEqual([60]);
		const noProduct = craft(data, spell, new Map([[50, q(null, null, 0)], [60, q(30, null)]]));
		expect(noProduct.cost).toBe(100);
		expect(noProduct.profit).toBeNull();
		expect(noProduct.missing).toEqual([50]);
		expect(noProduct).toMatchObject({ noAhProduct: true, vendorFloor: null, worst: null });
	});

	it("has no profit for a spell that makes no item", () => {
		const c = craft(data, spellOf(data, 11)!, new Map([[60, q(30, null)]]));
		expect(c.cost).toBe(30);
		expect(c.value).toBeNull();
		expect(c.profit).toBeNull();
		expect(c.missing).toEqual([]);
	});
});

describe("pays back", () => {
	it("is the recipe price over the profit per craft, rounded up", () => {
		expect(paysBack(1000, 280)).toBe(4);
		expect(paysBack(840, 280)).toBe(3);
		expect(paysBack(5, 280)).toBe(1);
	});

	it("only when a craft makes a profit and the recipe has a price", () => {
		expect(paysBack(1000, 0)).toBeNull();
		expect(paysBack(1000, -5)).toBeNull();
		expect(paysBack(null, 280)).toBeNull();
		expect(paysBack(1000, null)).toBeNull();
	});
});

describe("recipe rows", () => {
	const quotes = new Map([
		[50, q(200, 180)],
		[60, q(30, 25)],
	]);

	it("prices a recipe item's craft and its pay back", () => {
		const r = recipeRow(data, 100, q(null, 1000), quotes);
		expect(r.status).toBe("ok");
		expect(r.craft!.profit).toBe(280);
		expect(r.recipePrice).toMatchObject({ unit: 1000, basis: "lowest" });
		expect(r.payback).toBe(4);
	});

	it("says why a profit is missing", () => {
		expect(recipeRow(data, 999, undefined, quotes)).toMatchObject({ status: "not_in_data", craft: null, payback: null });
		expect(recipeRow(data, 102, undefined, quotes).status).toBe("no_reagents");
		expect(recipeRow(data, 101, undefined, quotes).status).toBe("no_item");
		// The product has no AH price (a vendor price doesn't count); a reagent without a price.
		expect(recipeRow(data, 100, q(null, 1000), new Map([[50, q(null, null, 40)], [60, q(30, null)]]))).toMatchObject({ status: "no_ah_price", payback: null });
		expect(recipeRow(data, 100, q(null, 1000), new Map([[50, q(200, null)]]))).toMatchObject({ status: "no_price", payback: null });
	});

	it("has a profit but no pay back when the recipe has no price", () => {
		const r = recipeRow(data, 100, undefined, quotes);
		expect(r.craft!.profit).toBe(280);
		expect(r.payback).toBeNull();
	});
});
