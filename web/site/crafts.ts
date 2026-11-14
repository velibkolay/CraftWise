// Crafts (/crafts, #185): every craft with today's Horde AH prices and the vendor check, to find crafts that
// pay when the product goes to a vendor and vendor loops. Prices and names come from /api/browse (as the list
// page); the recipes from /data/recipes.json. A price that is missing stays missing.
import { type Browse, type BrowseItem, get, type House, mainHouse } from "./lib/api";
import { CRAFT_SORTS, type CraftFilter, type CraftRow, type CraftSort, craftSpells, itemsOfSpell, keep, knownSpells, professionList, scopeOf, sortCrafts, toRow } from "./lib/crafts";
import { type CraftNames, craftItBreakdown, loopTag, profitEl } from "./lib/craftview";
import { bottomTabs, clear, closeButton, errorBox, h, moneyEl, onSkinChange, s, skinMoney, slot, statusBar, topBar } from "./lib/dom";
import { qualityClass } from "./lib/format";
import { type Quote, quoteOf, RECIPES_URL, type RecipeData, type Spell } from "./lib/recipes";

const PAGE = 25;

interface State {
	line: number | null; // profession skill line
	q: string;
	vendorOnly: boolean;
	loopsOnly: boolean;
	mine: boolean;
	sort: CraftSort;
	desc: boolean;
	page: number;
}

function readState(): State {
	const p = new URLSearchParams(location.search);
	const sort = p.get("sort") as CraftSort | null;
	const line = Number(p.get("prof"));
	return {
		line: Number.isInteger(line) && line > 0 ? line : null,
		q: (p.get("q") ?? "").trim(),
		vendorOnly: p.get("vendor") === "1",
		loopsOnly: p.get("loops") === "1",
		mine: p.get("mine") === "1",
		sort: sort && CRAFT_SORTS.includes(sort) ? sort : "vprofit",
		desc: p.get("dir") !== "asc",
		page: Math.max(1, Number(p.get("p")) || 1),
	};
}

function writeState(push = false): void {
	const p = new URLSearchParams();
	if (st.line !== null) p.set("prof", String(st.line));
	if (st.q) p.set("q", st.q);
	if (st.vendorOnly) p.set("vendor", "1");
	if (st.loopsOnly) p.set("loops", "1");
	if (st.mine) p.set("mine", "1");
	if (st.sort !== "vprofit") p.set("sort", st.sort);
	if (!st.desc) p.set("dir", "asc");
	if (st.page > 1) p.set("p", String(st.page));
	const url = `/crafts${p.size ? `?${p}` : ""}`;
	if (url !== location.pathname + location.search) (push ? history.pushState : history.replaceState).call(history, null, "", url);
}

let st = readState();
let house: House | null = null;
let data: RecipeData | null = null;
let spells: Spell[] = [];
let known: Set<number> | null = null; // "My crafts": spell IDs known by the characters, when the private API answered
const quotes = new Map<number, Quote>();
const fetched = new Set<number>();
const itemNames: CraftNames = new Map();
const nameOnly = new Map<number, string | null>();
let loadSeq = 0;
let loading = false;
let failed = false;
const openRows = new Set<number>(); // spells whose breakdown is open
let selected: number | null = null;

// ---- Shell ------------------------------------------------------------------------------------

const app = document.getElementById("app")!;
const subline = h("span", {}, "WoW: Forever");
const statusSlot = h("div", { class: "statusrow" });
const heading = h("h2", { class: "res-title", id: "res-title", tabindex: "-1" });
const profSel = h("select", { class: "winput", id: "f-prof" });
const nameInput = h("input", { class: "winput", id: "f-name", type: "search", autocomplete: "off", placeholder: "Product name", "aria-label": "Filter by product name" });
const vendorBox = h("input", { type: "checkbox", id: "f-vendor" }) as HTMLInputElement;
const loopBox = h("input", { type: "checkbox", id: "f-loops" }) as HTMLInputElement;
const mineBox = h("input", { type: "checkbox", id: "f-mine" }) as HTMLInputElement;
const mineLabel = h("label", { class: "field vcheck", for: "f-mine", hidden: true }, mineBox, h("span", { class: "lbl" }, "My crafts"));
const tableWrap = h("div", { class: "tscroll" });
const pager = h("div", { class: "pager" });
const colHint = h("span", { class: "hint" });
const footnote = h("p", { class: "hint footnote" });

function shell(): void {
	const results = h(
		"div",
		{ class: "results" },
		h(
			"form",
			{ class: "filters", "aria-label": "Filters", onsubmit: (e: Event) => e.preventDefault() },
			heading,
			h("span", { class: "grow" }),
			h("label", { class: "field", for: "f-prof" }, h("span", { class: "lbl" }, "Profession")),
			profSel,
			nameInput,
			h("label", { class: "field vcheck", for: "f-vendor" }, vendorBox, h("span", { class: "lbl" }, "Profit when sold to a vendor")),
			h("label", { class: "field vcheck", for: "f-loops" }, loopBox, h("span", { class: "lbl" }, "Loops only")),
			mineLabel,
		),
		h("div", { class: "inset" }, tableWrap),
	);
	const frame = h(
		"section",
		{ class: "frame", "aria-labelledby": "cr-title" },
		h("div", { class: "wtitle" }, h("h1", { id: "cr-title" }, "Crafts")),
		closeButton("/", "Close and go to the item list"),
		statusSlot,
		h("div", { class: "cols" }, results),
		h("div", { class: "footbar" }, pager, colHint),
	);
	clear(app, topBar(subline, "crafts"), h("main", { class: "shell" }, frame, bottomTabs("crafts"), footnote));
}

function wire(): void {
	profSel.addEventListener("change", () => {
		st.line = profSel.value ? Number(profSel.value) : null;
		changed();
	});
	nameInput.addEventListener("input", () => {
		st.q = nameInput.value.trim();
		st.page = 1;
		writeState();
		renderTable();
	});
	vendorBox.addEventListener("change", () => {
		st.vendorOnly = vendorBox.checked;
		changed(false);
	});
	loopBox.addEventListener("change", () => {
		st.loopsOnly = loopBox.checked;
		changed();
	});
	mineBox.addEventListener("change", () => {
		st.mine = mineBox.checked;
		changed();
	});
}

// A filter changed: back to page 1, and price what the new scope needs.
function changed(price = true): void {
	st.page = 1;
	writeState();
	if (price) void priceScope();
	renderTable();
}

// ---- Data ---------------------------------------------------------------------------------------

function filter(): CraftFilter {
	return { line: st.line, vendorOnly: st.vendorOnly, loopsOnly: st.loopsOnly, known: st.mine && known ? known : null, q: st.q };
}

function remember(items: BrowseItem[]): void {
	for (const it of items) {
		fetched.add(it.id);
		quotes.set(it.id, quoteOf(it));
		itemNames.set(it.id, { name: it.name, quality: it.quality });
		nameOnly.set(it.id, it.name);
	}
}

// Prices and names of what the scope's crafts need (products first), 100 items a request, three at a time; the
// table is drawn again after each request.
async function priceScope(): Promise<void> {
	if (!data || !house) return;
	const seq = ++loadSeq;
	const need: number[] = [];
	const seen = new Set<number>();
	const scope = scopeOf(data, spells, filter());
	for (const sp of scope) if (!fetched.has(sp.output!) && !seen.has(sp.output!)) (seen.add(sp.output!), need.push(sp.output!));
	for (const sp of scope) for (const id of itemsOfSpell(sp)) if (!fetched.has(id) && !seen.has(id)) (seen.add(id), need.push(id));
	if (!need.length) {
		loading = false;
		return renderTable();
	}
	loading = true;
	failed = false;
	const chunks: number[][] = [];
	for (let i = 0; i < need.length; i += 100) chunks.push(need.slice(i, i + 100));
	const houseKey = encodeURIComponent(house.key);
	const worker = async () => {
		for (let c = chunks.shift(); c; c = chunks.shift()) {
			const res = await get<Browse>(`/api/browse?house=${houseKey}&ids=${c.join(",")}`);
			for (const id of c) fetched.add(id); // an ID the API doesn't know stays unpriced: nothing is guessed
			remember(res.items);
			if (seq === loadSeq) renderTable();
		}
	};
	try {
		await Promise.all([worker(), worker(), worker()]);
	} catch {
		if (seq === loadSeq) failed = true;
	}
	if (seq === loadSeq) {
		loading = false;
		renderTable();
	}
}

// "My crafts": the recipes the characters know, from the uploaded snapshots (private API). Anyone without the
// Access login (a redirect or an error) just doesn't get the filter. Never throws.
async function loadKnown(): Promise<void> {
	try {
		const opts: RequestInit = { headers: { accept: "application/json" }, credentials: "same-origin", redirect: "manual", signal: AbortSignal.timeout(6000) };
		const list = await fetch("/api/me/characters", opts);
		if (!list.ok) return;
		const keys = ((await list.json()) as { characters?: { key?: unknown }[] }).characters?.flatMap((c) => (typeof c.key === "string" ? [c.key] : [])) ?? [];
		const all = new Set<number>();
		for (const key of keys) {
			const res = await fetch(`/api/me/characters/${encodeURIComponent(key)}`, opts);
			if (!res.ok) continue;
			const snap = ((await res.json()) as { snapshot?: { data?: unknown } | null }).snapshot;
			for (const id of knownSpells(snap?.data)) all.add(id);
		}
		if (!all.size) return; // no snapshot lists learned recipes yet: no filter, nothing guessed
		known = all;
		mineLabel.hidden = false;
		if (st.mine) {
			void priceScope();
			renderTable();
		}
	} catch {
		// no private API for this visitor
	}
}

async function load(): Promise<void> {
	try {
		house = await mainHouse();
		if (!house) throw new Error("no house");
		subline.textContent = `WoW: Forever, ${house.label}`;
		clear(statusSlot, statusBar(house), h("span", { class: "hint" }, "Prices are marked stale after 24 h"));
		clear(footnote, `Prices come from CraftWise scans of the ${house.label} on ${house.realm}. Item icons are placeholders.`);
		data = await get<RecipeData>(RECIPES_URL);
		spells = craftSpells(data);
		renderProfessions();
		void loadKnown();
		await priceScope();
	} catch (e) {
		const msg = e instanceof Error && e.message === "no house" ? "No auction house has been scanned yet." : "The crafts could not be loaded. Check your connection and reload the page.";
		clear(heading, "Crafts");
		clear(tableWrap, errorBox(msg));
	}
}

function renderProfessions(): void {
	clear(
		profSel,
		h("option", { value: "" }, "All"),
		professionList(data!, spells).map((p) => h("option", { value: String(p.line), selected: p.line === st.line }, p.name)),
	);
	profSel.value = st.line === null ? "" : String(st.line);
}

// ---- Table --------------------------------------------------------------------------------------

type Col = { key: CraftSort | null; label: string; cls: string; firstDesc: boolean };
const COLUMNS: Col[] = [
	{ key: "name", label: "Product", cls: "c-name", firstDesc: false },
	{ key: "profession", label: "Profession", cls: "c-prof", firstDesc: false },
	{ key: "cost", label: "Reagents", cls: "r", firstDesc: false },
	{ key: "ah", label: "AH sale", cls: "r", firstDesc: true },
	{ key: "vendor", label: "Vendor sale", cls: "r", firstDesc: true },
	{ key: "profit", label: "Profit", cls: "r c-profit", firstDesc: true },
	{ key: "vprofit", label: "Vendor profit", cls: "r c-profit", firstDesc: true },
];

function rowsNow(): CraftRow[] {
	if (!data) return [];
	const f = filter();
	return scopeOf(data, spells, f)
		.map((sp) => toRow(data!, sp, quotes, fetched, nameOnly))
		.filter((r) => keep(r, f));
}

function renderTable(): void {
	if (!data) return;
	const list = sortCrafts(rowsNow(), st.sort, st.desc);
	const pages = Math.max(1, Math.ceil(list.length / PAGE));
	st.page = Math.min(st.page, pages);
	const shown = list.slice((st.page - 1) * PAGE, st.page * PAGE);
	const note = failed ? ", some prices could not be loaded" : loading ? ", pricing the crafts" : "";
	clear(heading, "Crafts ", h("span", { class: "hint count" }, `${list.length.toLocaleString("en-US")} ${list.length === 1 ? "craft" : "crafts"}${note}`));
	clear(colHint, "AH sale: one craft's product at the Horde AH after the 5% cut (or a vendor, if it pays more). Vendor sale: what a vendor pays for the product. Reagents: each where it is cheaper, AH or vendor. A loop buys every reagent from a vendor and sells the product to one for more. Press a profit for the breakdown.");
	document.title = "Crafts - Velikopter Market";
	vendorBox.checked = st.vendorOnly;
	loopBox.checked = st.loopsOnly;
	mineBox.checked = st.mine;
	nameInput.value = st.q;
	const head = h(
		"tr",
		{},
		COLUMNS.map((c) => {
			const sorted = c.key === st.sort;
			const th = h("th", { class: c.cls, scope: "col", "aria-sort": sorted ? (st.desc ? "descending" : "ascending") : null });
			const btn = h("button", { type: "button" }, c.label, sorted ? h("span", { class: `srt${st.desc ? "" : " asc"}`, "aria-hidden": "true" }) : null);
			btn.addEventListener("click", () => {
				st.desc = sorted ? !st.desc : c.firstDesc;
				st.sort = c.key!;
				st.page = 1;
				writeState();
				renderTable();
				(tableWrap.querySelector("th[aria-sort] button") as HTMLButtonElement | null)?.focus();
			});
			th.append(btn);
			return th;
		}),
	);
	const empty = loading ? "Pricing the crafts…" : "No crafts match the filters.";
	const body = h(
		"tbody",
		{},
		shown.length ? shown.map((r) => [rowEl(r), openRows.has(r.spell.id) ? detailRow(r) : null]) : h("tr", {}, h("td", { colspan: COLUMNS.length, class: "empty" }, empty)),
	);
	clear(tableWrap, h("table", { class: "tbl list recipes crafts", "aria-labelledby": "res-title" }, h("thead", {}, head), body));
	renderPager(pages);
}

// AH figures are unknown ("…") until the craft's prices have been fetched.
function cell(r: CraftRow, v: number | null): HTMLElement {
	if (v === null && !r.ready) return h("td", { class: "r" }, h("span", { class: "hint" }, "…"));
	return h("td", { class: "r" }, moneyEl(v));
}

function profitButton(r: CraftRow, value: number | null, tip: string): HTMLElement {
	const open = openRows.has(r.spell.id);
	const label = value === null ? h("span", { class: "hint" }, r.ready ? "unknown" : "…") : profitEl(value);
	const btn = h(
		"button",
		{ type: "button", class: "pbtn", "aria-expanded": String(open), "aria-controls": `bd-${r.spell.id}`, title: tip },
		h("span", { class: `chev${open ? " open" : ""}`, "aria-hidden": "true" }),
		label,
		h("span", { class: "sr" }, ", breakdown"),
	);
	btn.addEventListener("click", () => {
		if (openRows.has(r.spell.id)) openRows.delete(r.spell.id);
		else openRows.add(r.spell.id);
		selected = r.spell.id;
		renderTable();
		tableWrap.querySelector<HTMLButtonElement>(`tr[data-id="${r.spell.id}"] .pbtn`)?.focus();
	});
	return h("td", { class: "r c-profit" }, btn);
}

function rowEl(r: CraftRow): HTMLElement {
	const out = r.spell.output!;
	const name = r.name ?? `Item ${out}`;
	const quality = qualityClass(itemNames.get(out)?.quality ?? null);
	const v = r.craft.vendor;
	return h(
		"tr",
		{ "data-id": r.spell.id, class: selected === r.spell.id ? "sel" : null },
		h(
			"td",
			{ class: "c-name" },
			h("a", { href: `/item/${out}`, class: `iname ${quality}` }, slot(name, quality), h("span", { class: "nm" }, name)),
			r.spell.qty !== 1 ? h("span", { class: "hint" }, ` × ${Number.isInteger(r.spell.qty) ? r.spell.qty : r.spell.qty.toFixed(2)}`) : null,
			r.loop ? " " : null,
			r.loop ? loopTag() : null,
		),
		h("td", { class: "c-prof" }, r.spell.profession ?? `Profession ${r.spell.skillLine}`),
		cell(r, r.cost),
		cell(r, r.ah),
		h("td", { class: "r" }, moneyEl(r.vendor), r.vendor === null ? null : h("span", { class: "sr" }, ", vendor price")),
		profitButton(r, r.profit, r.profit === null ? "Unknown: a reagent or the product has no Horde AH price" : `Product ${skinMoney(r.craft.revenue!).short} - reagents ${skinMoney(r.cost!).short}`),
		profitButton(
			r,
			r.vprofit,
			r.vprofit === null ? (v.sale === null ? "Vendors don't buy it, or the price isn't known" : "Unknown: a reagent has no price") : `Vendor sale ${skinMoney(v.sale!).short} - reagents ${skinMoney(r.cost!).short}`,
		),
	);
}

function detailRow(r: CraftRow): HTMLElement {
	return h(
		"tr",
		{ class: "detail" },
		h("td", { colspan: COLUMNS.length }, h("div", { class: "breakdown", id: `bd-${r.spell.id}` }, craftItBreakdown(r.craft, r.recipeItem !== null ? { item: r.recipeItem, skill: data!.teach[String(r.recipeItem)]?.[1] || null } : null, itemNames, data!.vendor))),
	);
}

function renderPager(pages: number): void {
	const go = (p: number) => {
		st.page = p;
		writeState();
		renderTable();
		heading.focus();
	};
	const arrow = (dir: "prev" | "next", disabled: boolean) =>
		h(
			"button",
			{ type: "button", class: "wbtn dark sq", "aria-label": dir === "prev" ? "Previous page" : "Next page", disabled, onclick: () => go(st.page + (dir === "prev" ? -1 : 1)) },
			s("svg", { width: 8, height: 10, viewBox: "0 0 8 10", "aria-hidden": "true" }, s("path", { d: dir === "prev" ? "M7 1 L2 5 L7 9 Z" : "M1 1 L6 5 L1 9 Z", class: "arrow" })),
		);
	clear(pager, arrow("prev", st.page <= 1), h("span", { class: "winput pageno", "aria-live": "polite" }, `Page ${st.page} of ${pages}`), arrow("next", st.page >= pages));
}

window.addEventListener("popstate", () => {
	st = readState();
	profSel.value = st.line === null ? "" : String(st.line);
	void priceScope();
	renderTable();
});

shell();
wire();
onSkinChange(() => {
	shell();
	renderTable();
});
void load();
