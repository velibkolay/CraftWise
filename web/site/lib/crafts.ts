// The crafts view (#185): every recipe that makes an item, with today's prices and the vendor check. Pure: no
// DOM, no fetch; the Worker tests import it. The maths is recipes.ts (craft, vendorCheck).
import { craft, type Craft, type Quote, type RecipeData, recipeItemOf, type Spell, spellOf } from "./recipes";

export type CraftSort = "name" | "profession" | "cost" | "ah" | "vendor" | "profit" | "vprofit" | "pct" | "vpct";
export const CRAFT_SORTS: CraftSort[] = ["name", "profession", "cost", "ah", "vendor", "profit", "vprofit", "pct", "vpct"];

export interface CraftRow {
	spell: Spell;
	craft: Craft;
	ready: boolean; // every price the craft needs has been fetched (until then the AH columns say so)
	name: string | null; // the product's name, once known
	recipeItem: number | null;
	// The sortable numbers; null = unknown.
	cost: number | null;
	ah: number | null; // the sale: the product at the Horde AH after the cut, or a vendor when that pays more (as the list)
	vendor: number | null;
	profit: number | null;
	vprofit: number | null;
	pct: number | null; // profit / reagents cost (1.5 = +150 %)
	vpct: number | null;
	loop: boolean;
}

// The return per copper spent on reagents: profit / cost. Null when either is unknown or the cost is 0.
export function pctOf(profit: number | null, cost: number | null): number | null {
	if (profit === null || cost === null || cost <= 0) return null;
	return profit / cost;
}

// "+150 %", "−25 %", "0 %"; whole numbers from 10 % up, one decimal below, thousands separated.
export function formatPct(p: number): string {
	const pc = p * 100;
	const abs = Math.abs(pc);
	const n = abs >= 10 ? Math.round(abs) : Math.round(abs * 10) / 10;
	if (n === 0) return "0 %";
	return `${pc < 0 ? "−" : "+"}${n.toLocaleString("en-US", { maximumFractionDigits: 1 })} %`;
}

// Every spell that makes an item, ascending by ID. Enchants and the like make none: nothing to sell.
export function craftSpells(data: RecipeData): Spell[] {
	const out: Spell[] = [];
	for (const id of Object.keys(data.spells)) {
		const s = spellOf(data, Number(id))!;
		if (s.output) out.push(s);
	}
	return out.sort((a, b) => a.id - b.id);
}

// The product first, then the reagents.
export function itemsOfSpell(s: Spell): number[] {
	return [s.output!, ...s.reagents.map((r) => r.item)];
}

// The professions that have a craft, by skill line, for the profession filter.
export function professionList(data: RecipeData, spells: Spell[]): { line: number; name: string }[] {
	const lines = new Set(spells.map((s) => s.skillLine));
	return [...lines].map((line) => ({ line, name: data.professions[String(line)] ?? `Profession ${line}` })).sort((a, b) => a.name.localeCompare(b.name));
}

export interface CraftFilter {
	line: number | null; // skill line, null = all
	vendorOnly: boolean; // "Profit when sold to a vendor": vendor profit > 0
	loopsOnly: boolean;
	known: Set<number> | null; // "My crafts": spell IDs known by the characters; null = off
	q: string; // part of the product's name (needs the names)
}

// The spells a filter keeps before any AH price is known (what must be priced): profession, loops, my crafts.
export function scopeOf(data: RecipeData, spells: Spell[], f: CraftFilter): Spell[] {
	const none = new Map<number, Quote>();
	return spells.filter((s) => {
		if (f.line !== null && s.skillLine !== f.line) return false;
		if (f.known && !f.known.has(s.id)) return false;
		if (f.loopsOnly && !craft(data, s, none).vendor.loop) return false;
		return true;
	});
}

export function toRow(data: RecipeData, s: Spell, quotes: Map<number, Quote>, fetched: Set<number>, names: Map<number, string | null>): CraftRow {
	const c = craft(data, s, quotes);
	return {
		spell: s,
		craft: c,
		ready: itemsOfSpell(s).every((id) => fetched.has(id)),
		name: names.get(s.output!) ?? null,
		recipeItem: recipeItemOf(data, s.id)?.item ?? null,
		cost: c.cost,
		ah: c.revenue,
		vendor: c.vendor.sale,
		profit: c.profit,
		vprofit: c.vendor.profit,
		pct: pctOf(c.profit, c.cost),
		vpct: pctOf(c.vendor.profit, c.cost),
		loop: c.vendor.loop,
	};
}

export function keep(r: CraftRow, f: CraftFilter): boolean {
	if (f.vendorOnly && !(r.vprofit !== null && r.vprofit > 0)) return false;
	if (f.q && !(r.name ?? "").toLowerCase().includes(f.q.toLowerCase())) return false;
	return true;
}

export function sortCrafts(list: CraftRow[], key: CraftSort, desc: boolean): CraftRow[] {
	const dir = desc ? -1 : 1;
	const byName = (a: CraftRow, b: CraftRow) => (a.name ?? `~${a.spell.id}`).localeCompare(b.name ?? `~${b.spell.id}`) || a.spell.id - b.spell.id;
	return [...list].sort((a, b) => {
		if (key === "name") return dir * byName(a, b);
		if (key === "profession") return dir * (a.spell.profession ?? "").localeCompare(b.spell.profession ?? "") || byName(a, b);
		const va = a[key];
		const vb = b[key];
		if (va === null && vb === null) return byName(a, b);
		if (va === null) return 1; // unknown: always last
		if (vb === null) return -1;
		if (key === "pct" || key === "vpct") {
			// Ties: the bigger absolute profit of that column first (in the sort's direction), then the name.
			const pk = key === "pct" ? "profit" : "vprofit";
			return dir * (va - vb) || dir * (Math.abs(a[pk]!) - Math.abs(b[pk]!)) || byName(a, b);
		}
		return dir * (va - vb) || byName(a, b);
	});
}

// "My crafts": the spell IDs a character snapshot (docs/snapshot.md, `professions[].known`, "id,id,...") lists.
// A profession whose window was never opened has none (`cached = false`): nothing is assumed for it.
export function knownSpells(snapshotData: unknown): Set<number> {
	const out = new Set<number>();
	const d = snapshotData as { professions?: unknown } | null;
	if (!d || !Array.isArray(d.professions)) return out;
	for (const p of d.professions) {
		const known = (p as { known?: unknown } | null)?.known;
		if (typeof known !== "string") continue;
		for (const part of known.split(",")) {
			const n = Number(part);
			if (Number.isInteger(n) && n > 0) out.add(n);
		}
	}
	return out;
}
