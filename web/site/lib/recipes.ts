// Crafting profit per recipe (#143). Pure: no DOM, no fetch; the Worker tests import it.
// The recipe data is web/public/data/recipes.json, written by tools/gen_site_recipes.lua from the addon's bundled
// data (CraftWise/Data/Recipes.lua, Sources.lua, Vendor.lua). Prices are the Horde AH's from /api/browse. A price
// that is missing stays missing: a craft with any reagent or the product unpriced has no profit (unknown).
import type { BrowseItem } from "./api";
import { AH_CUT } from "./format";

export const RECIPES_URL = "/data/recipes.json";

export interface RecipeData {
	v: number;
	about: string;
	sources: Record<string, string[]>;
	professions: Record<string, string>;
	teach: Record<string, [number, number]>; // recipe item -> [spell, required skill (0 = not known)]
	spells: Record<string, number[]>; // spell -> [skillLine, output item (0 = none), output qty, reagent, qty, ...]
	names: Record<string, string>; // names of the spells that make no item
	vendor: Record<string, number>; // vendor buy price per unit
	sell: Record<string, number>; // vendor sell price per unit (the client's ItemSparse, bundled)
}

export interface Spell {
	id: number;
	skillLine: number;
	profession: string | null;
	output: number | null; // null: makes no item (an enchant and the like)
	qty: number; // output quantity, the mean yield
	reagents: { item: number; qty: number }[];
	name: string | null; // only for spells that make no item
}

export function spellOf(data: RecipeData, id: number): Spell | null {
	const row = data.spells[String(id)];
	if (!row || row.length < 3) return null;
	const [skillLine, output, qty] = row as [number, number, number];
	const reagents: Spell["reagents"] = [];
	for (let i = 3; i + 1 < row.length; i += 2) reagents.push({ item: row[i]!, qty: row[i + 1]! });
	return {
		id,
		skillLine,
		profession: data.professions[String(skillLine)] ?? null,
		output: output > 0 ? output : null,
		qty: output > 0 ? qty : 0,
		reagents,
		name: data.names[String(id)] ?? null,
	};
}

export interface Teach {
	spellId: number;
	spell: Spell | null; // null when the spell isn't in Recipes.lua (its reagents aren't known)
	skill: number | null; // required skill to learn it, when the client gives one
}

// What a recipe item teaches, when Sources.lua knows the item.
export function teachOf(data: RecipeData, item: number): Teach | null {
	const t = data.teach[String(item)];
	if (!t) return null;
	return { spellId: t[0], spell: spellOf(data, t[0]), skill: t[1] > 0 ? t[1] : null };
}

// Spells that make the item, and the recipe item that teaches a spell (when one does).
export function makersOf(data: RecipeData, item: number): Spell[] {
	const out: Spell[] = [];
	for (const id of Object.keys(data.spells)) {
		if (data.spells[id]![1] === item) out.push(spellOf(data, Number(id))!);
	}
	return out.sort((a, b) => a.id - b.id);
}

export function recipeItemOf(data: RecipeData, spellId: number): { item: number; skill: number | null } | null {
	for (const [item, [spell, skill]] of Object.entries(data.teach)) {
		if (spell === spellId) return { item: Number(item), skill: skill > 0 ? skill : null };
	}
	return null;
}

// Every item whose price a recipe item's profit needs: the product and the reagents.
export function itemsNeeded(data: RecipeData, recipeItems: number[]): number[] {
	const ids = new Set<number>();
	for (const r of recipeItems) {
		const s = teachOf(data, r)?.spell;
		if (!s) continue;
		if (s.output) ids.add(s.output);
		for (const x of s.reagents) ids.add(x.item);
	}
	return [...ids];
}

// ---- Prices ------------------------------------------------------------------------------------

// One item's Horde AH price and vendor sell price, as /api/browse gives them.
export interface Quote {
	typical: number | null; // the 7-day typical price, when there is one
	lowest: number | null; // the lowest listing, while listed
	sellPrice: number | null; // what a vendor pays (0 = vendors don't buy it, null = not known)
	units?: number | null; // units listed now (with `lowest`)
	listings?: number | null; // listings now, when the scan counted them
}

export function quoteOf(item: BrowseItem): Quote {
	return {
		typical: item.typical.status === "ok" ? item.typical.price : null,
		lowest: item.current && item.current.listed ? item.current.min : null,
		sellPrice: item.sellPrice,
		units: item.current && item.current.listed ? item.current.qty : null,
		listings: item.current && item.current.listed ? item.current.listings : null,
	};
}

export type Basis = "typical" | "lowest" | "vendor";

export interface Priced {
	unit: number; // copper per unit
	basis: Basis;
	// With basis "lowest": what the listing behind the price holds now (null = not known).
	units?: number | null;
	listings?: number | null;
}

// What one unit costs on the auction house: the typical price, else the lowest listing.
export function ahPrice(q: Quote | undefined): Priced | null {
	if (!q) return null;
	if (q.typical !== null) return { unit: q.typical, basis: "typical" };
	if (q.lowest !== null) return { unit: q.lowest, basis: "lowest", units: q.units ?? null, listings: q.listings ?? null };
	return null;
}

// A thin market (#143 review): a price from the lowest listing (no typical price yet) that rests on one or two
// listings or fewer than 5 units. Only a marker; the maths stays the same.
export const THIN_LISTINGS = 2;
export const THIN_UNITS = 5;

export function isThin(p: Priced | null): boolean {
	if (!p || p.basis !== "lowest") return false;
	return (p.listings != null && p.listings <= THIN_LISTINGS) || (p.units != null && p.units < THIN_UNITS);
}

// A reagent: the cheaper of the auction house and a vendor (Vendor.lua's buy price).
export function reagentPrice(q: Quote | undefined, vendorBuy: number | undefined): Priced | null {
	const ah = ahPrice(q);
	const vendor: Priced | null = vendorBuy !== undefined && vendorBuy > 0 ? { unit: vendorBuy, basis: "vendor" } : null;
	if (ah && vendor) return vendor.unit < ah.unit ? vendor : ah;
	return ah ?? vendor;
}

// What a vendor pays for one unit of the product: the site's sell price, else the bundled one; null when vendors
// don't buy it or it isn't known.
export function vendorSell(q: Quote | undefined, bundledSell: number | undefined): number | null {
	const v = q?.sellPrice ?? bundledSell ?? null;
	return v !== null && v > 0 ? v : null;
}

// The product: one unit on the auction house after the 5% cut, or what a vendor pays when that is more (as
// format.ts sellChoice and the addon's ns.GetSellValue). Without a Horde AH price there is no value (#143 review):
// a vendor price alone would show a loss for every item that just isn't listed; craft() keeps it as a floor.
export function productValue(q: Quote | undefined, bundledSell: number | undefined): Priced | null {
	const ah = ahPrice(q);
	if (!ah) return null;
	const net = Math.floor(ah.unit * (1 - AH_CUT));
	const vendor = vendorSell(q, bundledSell);
	if (vendor !== null && vendor > net) return { unit: vendor, basis: "vendor" };
	return { ...ah, unit: net };
}

// ---- One craft ---------------------------------------------------------------------------------

export interface ReagentLine {
	item: number;
	qty: number;
	price: Priced | null;
	total: number | null;
}

export interface Craft {
	spell: Spell;
	reagents: ReagentLine[];
	cost: number | null; // all reagents of one craft; null when one has no price
	value: Priced | null; // one unit of the product
	revenue: number | null; // value x output quantity, rounded down
	profit: number | null; // revenue - cost; null when either is unknown or the spell makes no item
	missing: number[]; // items without any price (reagents, then the product)
	noAhProduct: boolean; // the product has no Horde AH price (its profit is unknown even with a vendor price)
	vendorFloor: number | null; // then: what a vendor pays for one unit, when vendors buy it
	worst: number | null; // then: vendor floor x output quantity - reagent cost (the profit at worst)
	thin: boolean; // the product's price rests on a thin market (isThin)
	vendor: VendorCheck;
}

// The vendor check (#185): the product sold to a vendor, whatever the auction house pays.
export interface VendorCheck {
	sale: number | null; // vendor sell price x output quantity, rounded down; null when vendors don't buy it or it isn't known
	profit: number | null; // sale - reagent cost (each reagent where cheaper); null when either is unknown. Needs no AH price for the product.
	loopCost: number | null; // reagents all bought from vendors; null when one has no vendor buy price
	loop: boolean; // every reagent has a vendor buy price and sale - loopCost > 0: no auction house supply involved
}

export function vendorCheck(data: RecipeData, spell: Spell, quotes: Map<number, Quote>, cost: number | null): VendorCheck {
	let sale: number | null = null;
	if (spell.output) {
		const unit = vendorSell(quotes.get(spell.output), data.sell[String(spell.output)]);
		if (unit !== null) sale = Math.floor(unit * spell.qty);
	}
	let loopCost: number | null = spell.reagents.length ? 0 : null;
	for (const r of spell.reagents) {
		const buy = data.vendor[String(r.item)];
		if (loopCost === null || buy === undefined || buy <= 0) loopCost = null;
		else loopCost += buy * r.qty;
	}
	return { sale, profit: sale !== null && cost !== null ? sale - cost : null, loopCost, loop: sale !== null && loopCost !== null && sale - loopCost > 0 };
}

export function craft(data: RecipeData, spell: Spell, quotes: Map<number, Quote>): Craft {
	const missing: number[] = [];
	let cost: number | null = 0;
	const reagents = spell.reagents.map((r) => {
		const price = reagentPrice(quotes.get(r.item), data.vendor[String(r.item)]);
		if (!price) {
			missing.push(r.item);
			cost = null;
			return { item: r.item, qty: r.qty, price, total: null };
		}
		const total = price.unit * r.qty;
		if (cost !== null) cost += total;
		return { item: r.item, qty: r.qty, price, total };
	});
	let value: Priced | null = null;
	let revenue: number | null = null;
	let noAhProduct = false;
	let vendorFloor: number | null = null;
	let worst: number | null = null;
	if (spell.output) {
		const q = quotes.get(spell.output);
		value = productValue(q, data.sell[String(spell.output)]);
		if (value) revenue = Math.floor(value.unit * spell.qty);
		else {
			missing.push(spell.output);
			noAhProduct = true;
			vendorFloor = vendorSell(q, data.sell[String(spell.output)]);
			if (vendorFloor !== null && cost !== null) worst = Math.floor(vendorFloor * spell.qty) - cost;
		}
	}
	const profit = cost !== null && revenue !== null ? revenue - cost : null;
	return { spell, reagents, cost, value, revenue, profit, missing, noAhProduct, vendorFloor, worst, thin: isThin(value), vendor: vendorCheck(data, spell, quotes, cost) };
}

// How many crafts earn back the recipe's price; only when a craft makes a profit and the recipe has a price.
export function paysBack(recipePrice: number | null, profit: number | null): number | null {
	if (recipePrice === null || profit === null || profit <= 0) return null;
	return Math.max(1, Math.ceil(recipePrice / profit));
}

// A recipe item in the list: what it teaches, the craft with today's prices, the recipe's own price and the
// crafts it takes to pay for itself. `status` says why a profit is missing.
export interface RecipeRow {
	teach: Teach | null;
	craft: Craft | null;
	recipePrice: Priced | null; // what the recipe costs on the auction house
	payback: number | null;
	status: "ok" | "not_in_data" | "no_reagents" | "no_item" | "no_price" | "no_ah_price";
}

export function recipeRow(data: RecipeData, recipeItem: number, recipeQuote: Quote | undefined, quotes: Map<number, Quote>): RecipeRow {
	const teach = teachOf(data, recipeItem);
	const recipePrice = ahPrice(recipeQuote);
	if (!teach) return { teach, craft: null, recipePrice, payback: null, status: "not_in_data" };
	if (!teach.spell) return { teach, craft: null, recipePrice, payback: null, status: "no_reagents" };
	const c = craft(data, teach.spell, quotes);
	const reagentMissing = c.missing.some((id) => id !== teach.spell!.output);
	const status = !teach.spell.output ? "no_item" : c.profit !== null ? "ok" : !reagentMissing && c.noAhProduct ? "no_ah_price" : "no_price";
	return { teach, craft: c, recipePrice, payback: paysBack(recipePrice?.unit ?? null, c.profit), status };
}

// Words for a price's basis, as the breakdowns show them; `short` for table cells.
export function basisText(b: Basis, short = false): string {
	if (short) return b === "typical" ? "AH market" : b === "lowest" ? "AH lowest" : "vendor";
	return b === "typical" ? "AH market price" : b === "lowest" ? "AH lowest now" : "vendor";
}

// What a lowest-listing price rests on: "3 units in 1 listing", "40 units"; null for other prices.
export function depthText(p: Priced | null): string | null {
	if (!p || p.basis !== "lowest" || (p.units == null && p.listings == null)) return null;
	const units = p.units != null ? `${p.units.toLocaleString("en-US")} ${p.units === 1 ? "unit" : "units"}` : null;
	const listings = p.listings != null ? `${p.listings.toLocaleString("en-US")} ${p.listings === 1 ? "listing" : "listings"}` : null;
	return units && listings ? `${units} in ${listings}` : (units ?? listings);
}
