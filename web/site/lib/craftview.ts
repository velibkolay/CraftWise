// The crafting breakdowns (#143) the list page (under a recipe row) and the item page ("Craft It", "Teaches") share.
// The numbers come from recipes.ts; this only draws them.
import { h, moneyEl, skinMoney } from "./dom";
import { qualityClass } from "./format";
import { basisText, type Craft, depthText, type Priced, type RecipeRow, type Spell } from "./recipes";

export type CraftNames = Map<number, { name: string | null; quality: number | null }>;

// Profit money: a loss is marked with a minus sign and the loss colour, and read out as "loss".
export function profitEl(copper: number): HTMLElement {
	if (copper >= 0) return h("span", { class: "profit" }, moneyEl(copper));
	return h("span", { class: "profit loss" }, h("span", { "aria-hidden": "true" }, "−"), h("span", { class: "sr" }, "loss of "), moneyEl(-copper));
}

// The thin-market marker (#143 review): the product's price is its lowest listing, on few units or listings.
export function thinTag(p: Priced | null): HTMLElement {
	const depth = depthText(p);
	return h(
		"span",
		{ class: "thin", title: `Thin market: priced from the lowest listing${depth ? ` (${depth})` : ""}, no typical price yet` },
		h("span", { "aria-hidden": "true" }, "thin"),
		h("span", { class: "sr" }, ", thin market"),
	);
}

export function craftsText(n: number): string {
	return `${n.toLocaleString("en-US")} ${n === 1 ? "craft" : "crafts"}`;
}

function itemLink(id: number, names: CraftNames): HTMLElement {
	const n = names.get(id);
	return h("a", { href: `/item/${id}`, class: `ilink ${qualityClass(n?.quality ?? null)}` }, n?.name ?? `Item ${id}`);
}

// Where a price comes from; a lowest listing also says what it holds ("AH lowest, 3 units in 1 listing").
function priceNote(p: Priced | null, product = false): string {
	if (!p) return "no price";
	if (p.basis === "vendor") return product ? "a vendor pays" : "vendor";
	const depth = depthText(p);
	const base = product ? `${basisText(p.basis)}, after the 5% cut` : basisText(p.basis, true);
	return depth ? `${base}, ${depth}` : base;
}

function qtyText(n: number): string {
	return Number.isInteger(n) ? n.toLocaleString("en-US") : n.toFixed(2);
}

// What the spell is: the product (a link) and how many one craft makes, or the spell's name when it makes no item.
export function makesEl(spell: Spell, names: CraftNames): (Node | string)[] {
	if (!spell.output) return [spell.name ?? `Spell ${spell.id}`, h("span", { class: "hint" }, " (makes no item)")];
	return [itemLink(spell.output, names), spell.qty !== 1 ? h("span", { class: "hint" }, ` × ${qtyText(spell.qty)} per craft`) : ""];
}

export function professionText(spell: Spell, skill: number | null): string {
	const prof = spell.profession ?? `Profession ${spell.skillLine}`;
	return skill !== null ? `${prof}, requires ${skill}` : prof;
}

// Reagents, one line each: quantity and name, the unit price and where it is cheaper, and the line's cost.
// With `vendorBuy` (the crafts view, #185) a column says what a vendor sells each reagent for, so both prices show.
function reagentTable(c: Craft, names: CraftNames, label: string, vendorBuy?: Record<string, number>): HTMLElement {
	return h(
		"table",
		{ class: "tbl bd", "aria-label": label },
		h(
			"thead",
			{},
			h("tr", {}, h("th", { scope: "col" }, "Reagent"), h("th", { scope: "col", class: "r" }, "Each"), vendorBuy ? h("th", { scope: "col", class: "r" }, "Vendor sells") : null, h("th", { scope: "col", class: "r" }, "Cost")),
		),
		h(
			"tbody",
			{},
			c.reagents.map((r) =>
				h(
					"tr",
					{},
					h("td", {}, h("span", { class: "qty" }, `${qtyText(r.qty)} ×`), " ", itemLink(r.item, names)),
					h("td", { class: "r" }, moneyEl(r.price?.unit ?? null), h("span", { class: "hint basis" }, priceNote(r.price))),
					vendorBuy ? h("td", { class: "r" }, vendorBuy[String(r.item)] ? moneyEl(vendorBuy[String(r.item)]!) : h("span", { class: "hint" }, "not sold")) : null,
					h("td", { class: "r" }, moneyEl(r.total)),
				),
			),
		),
	);
}

// One line of the sums: label, amount, and a note on where the amount comes from (grid columns, so amounts align).
function line(label: string, value: Node | string, note: string | null = null): HTMLElement {
	return h("p", { class: "row" }, h("span", { class: "lbl" }, label), h("span", { class: "val" }, value), h("span", { class: "hint basis" }, note ?? ""));
}

// The sums under the reagents: reagent cost, the product's value, profit per craft; `extra` lines follow.
function sums(c: Craft, extra: HTMLElement[], vendor = false): HTMLElement {
	const s = c.spell;
	const rows: (HTMLElement | null)[] = [line("Reagents", moneyEl(c.cost, "unknown"))];
	if (s.output && c.noAhProduct) {
		// No Horde AH price: no value and no profit; a vendor price only says how bad it can get.
		let floor: string | null = null;
		if (c.vendorFloor !== null) {
			floor = `a vendor pays ${skinMoney(c.vendorFloor).short}${s.qty !== 1 ? " each" : ""}`;
			if (c.worst !== null) floor += c.worst < 0 ? `: at worst a loss of ${skinMoney(-c.worst).short}` : `: at least ${skinMoney(c.worst).short} profit`;
		}
		rows.push(line("Product", h("span", { class: "hint" }, "no AH price"), floor ?? "vendors don't buy it"));
		rows.push(line("Profit per craft", h("span", { class: "hint" }, "unknown")));
	} else if (s.output) {
		rows.push(
			line(
				s.qty !== 1 ? `Product, ${qtyText(s.qty)} × ${c.value ? skinMoney(c.value.unit).short : "?"}` : "Product",
				moneyEl(c.revenue, "unknown"),
				priceNote(c.value, true),
			),
		);
		const profit = c.profit === null ? h("span", { class: "hint" }, "unknown") : h("span", {}, profitEl(c.profit), c.thin ? " " : null, c.thin ? thinTag(c.value) : null);
		rows.push(line("Profit per craft", profit));
	}
	if (vendor && s.output) rows.push(...vendorLines(c));
	return h("div", { class: "bd-sums" }, rows, extra);
}

// The vendor check (#185): the product sold to a vendor, the profit that gives, and whether it is a loop.
function vendorLines(c: Craft): HTMLElement[] {
	const v = c.vendor;
	const lines = [
		line("Sold to a vendor", v.sale === null ? h("span", { class: "hint" }, "no vendor price") : moneyEl(v.sale), v.sale === null ? "vendors don't buy it, or the price isn't known" : c.spell.qty !== 1 ? "vendor price × quantity" : null),
		line("Vendor profit", v.profit === null ? h("span", { class: "hint" }, "unknown") : profitEl(v.profit), v.profit === null ? null : "vendor sale - reagents"),
	];
	if (v.loop) lines.push(line("Loop", h("span", {}, loopTag(), " ", profitEl(v.sale! - v.loopCost!)), `at vendor prices only: reagents ${skinMoney(v.loopCost!).short}`));
	else if (v.loopCost === null) lines.push(line("Loop", h("span", { class: "hint" }, "no"), "a reagent isn't sold by a vendor"));
	else lines.push(line("Loop", h("span", { class: "hint" }, "no"), "vendor sale isn't above the cost at vendor prices"));
	return lines;
}

// The loop marker (#185): every reagent from a vendor, and the vendor pays more than they cost.
export function loopTag(): HTMLElement {
	return h("span", { class: "loop", title: "Loop: every reagent is sold by a vendor and a vendor pays more for the product than they cost" }, h("span", { "aria-hidden": "true" }, "loop"), h("span", { class: "sr" }, ", vendor loop"));
}

function missingNote(c: Craft, names: CraftNames): HTMLElement | null {
	const reagents = c.missing.filter((id) => !(c.noAhProduct && id === c.spell.output));
	const notes: (Node | string)[] = [];
	if (reagents.length) {
		notes.push("No price yet for ");
		reagents.forEach((id, i) => notes.push(i ? ", " : "", itemLink(id, names)));
		notes.push(", so the profit is unknown.");
	}
	if (c.noAhProduct && c.spell.output) {
		notes.push(reagents.length ? " " : "", itemLink(c.spell.output, names), " has no Horde AH price, so the profit is unknown; a vendor price alone is not counted.");
	}
	if (c.thin) notes.push(`Thin market: the product's price is its lowest listing (${depthText(c.value) ?? "few units"}), with no typical price yet.`);
	return notes.length ? h("p", { class: "hint bd-note" }, ...notes) : null;
}

// A recipe item's breakdown: what it teaches, the reagents, the sums, the recipe's price and its pay back.
export function craftBreakdown(rec: RecipeRow, names: CraftNames, title: string | null): HTMLElement[] {
	const c = rec.craft!;
	const s = c.spell;
	const extra: HTMLElement[] = [];
	if (s.output) {
		extra.push(
			line("Recipe", moneyEl(rec.recipePrice?.unit ?? null, "no AH price"), rec.recipePrice ? basisText(rec.recipePrice.basis) : null),
			line("Pays back after", rec.payback !== null ? craftsText(rec.payback) : h("span", { class: "hint" }, c.profit !== null && c.profit <= 0 ? "never (no profit)" : "unknown")),
		);
	}
	return [
		h("p", { class: "bd-head" }, h("span", { class: "lbl" }, "Teaches "), ...makesEl(s, names), h("span", { class: "hint" }, ` · ${professionText(s, rec.teach?.skill ?? null)}`)),
		reagentTable(c, names, `Reagents of ${title ?? "the recipe"}`),
		sums(c, extra),
		missingNote(c, names) ?? h("span", { hidden: true }),
	];
}

// "Craft It" on the item page: one craft of the item, with the recipe item that teaches it when there is one.
export function craftItBreakdown(c: Craft, recipe: { item: number; skill: number | null } | null, names: CraftNames, vendorBuy?: Record<string, number>): HTMLElement[] {
	const s = c.spell;
	const head = recipe
		? [h("span", { class: "lbl" }, `${professionText(s, recipe.skill)}: `), itemLink(recipe.item, names)]
		: [h("span", { class: "lbl" }, s.profession ?? `Profession ${s.skillLine}`), h("span", { class: "hint" }, " · no recipe item in the data (trainer or not known)")];
	return [
		h("p", { class: "bd-head" }, ...head, s.qty !== 1 ? h("span", { class: "hint" }, ` · makes ${qtyText(s.qty)} per craft`) : null),
		reagentTable(c, names, `Reagents to craft ${names.get(s.output ?? 0)?.name ?? "it"}`, vendorBuy),
		sums(c, [], vendorBuy !== undefined),
		missingNote(c, names) ?? h("span", { hidden: true }),
	];
}
