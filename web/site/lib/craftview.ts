// The crafting breakdowns (#143) the list page (under a recipe row) and the item page ("Craft It", "Teaches") share.
// The numbers come from recipes.ts; this only draws them.
import { h, moneyEl, skinMoney } from "./dom";
import { qualityClass } from "./format";
import { basisText, type Craft, type Priced, type RecipeRow, type Spell } from "./recipes";

export type CraftNames = Map<number, { name: string | null; quality: number | null }>;

// Profit money: a loss is marked with a minus sign and the loss colour, and read out as "loss".
export function profitEl(copper: number): HTMLElement {
	if (copper >= 0) return h("span", { class: "profit" }, moneyEl(copper));
	return h("span", { class: "profit loss" }, h("span", { "aria-hidden": "true" }, "−"), h("span", { class: "sr" }, "loss of "), moneyEl(-copper));
}

export function craftsText(n: number): string {
	return `${n.toLocaleString("en-US")} ${n === 1 ? "craft" : "crafts"}`;
}

function itemLink(id: number, names: CraftNames): HTMLElement {
	const n = names.get(id);
	return h("a", { href: `/item/${id}`, class: `ilink ${qualityClass(n?.quality ?? null)}` }, n?.name ?? `Item ${id}`);
}

function priceNote(p: Priced | null, product = false): string {
	if (!p) return "no price";
	if (p.basis === "vendor") return product ? "a vendor pays" : "vendor";
	return product ? `${basisText(p.basis)}, after the 5% cut` : basisText(p.basis, true);
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
function reagentTable(c: Craft, names: CraftNames, label: string): HTMLElement {
	return h(
		"table",
		{ class: "tbl bd", "aria-label": label },
		h("thead", {}, h("tr", {}, h("th", { scope: "col" }, "Reagent"), h("th", { scope: "col", class: "r" }, "Each"), h("th", { scope: "col", class: "r" }, "Cost"))),
		h(
			"tbody",
			{},
			c.reagents.map((r) =>
				h(
					"tr",
					{},
					h("td", {}, h("span", { class: "qty" }, `${qtyText(r.qty)} ×`), " ", itemLink(r.item, names)),
					h("td", { class: "r" }, moneyEl(r.price?.unit ?? null), h("span", { class: "hint basis" }, priceNote(r.price))),
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
function sums(c: Craft, extra: HTMLElement[]): HTMLElement {
	const s = c.spell;
	const rows: (HTMLElement | null)[] = [line("Reagents", moneyEl(c.cost, "unknown"))];
	if (s.output) {
		rows.push(
			line(
				s.qty !== 1 ? `Product, ${qtyText(s.qty)} × ${c.value ? skinMoney(c.value.unit).short : "?"}` : "Product",
				moneyEl(c.revenue, "unknown"),
				priceNote(c.value, true),
			),
		);
		rows.push(line("Profit per craft", c.profit === null ? h("span", { class: "hint" }, "unknown") : profitEl(c.profit)));
	}
	return h("div", { class: "bd-sums" }, rows, extra);
}

function missingNote(c: Craft, names: CraftNames): HTMLElement | null {
	if (!c.missing.length) return null;
	const list: (Node | string)[] = [];
	c.missing.forEach((id, i) => list.push(i ? ", " : "", itemLink(id, names)));
	return h("p", { class: "hint bd-note" }, "No price yet for ", ...list, ", so the profit is unknown.");
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
export function craftItBreakdown(c: Craft, recipe: { item: number; skill: number | null } | null, names: CraftNames): HTMLElement[] {
	const s = c.spell;
	const head = recipe
		? [h("span", { class: "lbl" }, `${professionText(s, recipe.skill)}: `), itemLink(recipe.item, names)]
		: [h("span", { class: "lbl" }, s.profession ?? `Profession ${s.skillLine}`), h("span", { class: "hint" }, " · no recipe item in the data (trainer or not known)")];
	return [
		h("p", { class: "bd-head" }, ...head, s.qty !== 1 ? h("span", { class: "hint" }, ` · makes ${qtyText(s.qty)} per craft`) : null),
		reagentTable(c, names, `Reagents to craft ${names.get(s.output ?? 0)?.name ?? "it"}`),
		sums(c, []),
		missingNote(c, names) ?? h("span", { hidden: true }),
	];
}
