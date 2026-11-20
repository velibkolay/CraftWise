// Private page /me/crafted (#266): the craft log the companion uploads, per recipe: crafts and estimated profit
// today, in the last 7 days and in total, the active crafting time and gold per active hour. Like Make > Crafted in
// the addon. Data: /api/me/crafted, /api/me/characters (private API), recipes from /data/recipes.json, product names
// from /api/browse?ids= (public API). A day without profit or time shows a dash, never a guess.
import { itemName, loadItemNames } from "./lib/itemnames";
import { type Browse, get } from "./lib/api";
import { mainHouse } from "./lib/housesel";
import { profitEl } from "./lib/craftview";
import { type Line, durationText, localDay, type LogRow, parseRows, SORT_KEYS, type SortKey, sortLines, summarize } from "./lib/craftedlog";
import { bottomTabs, clear, closeButton, errorBox, h, onSkinChange, s, slot, statusBar, topBar } from "./lib/dom";
import { qualityClass } from "./lib/format";
import { fullName, type Character } from "./lib/me";
import { RECIPES_URL, type RecipeData, spellOf } from "./lib/recipes";

const PAGE = 25;

interface State {
	char: string | null;
	line: number | null; // profession skill line
	q: string;
	sort: SortKey;
	desc: boolean;
	page: number;
}

function readState(): State {
	const p = new URLSearchParams(location.search);
	const sort = p.get("sort") as SortKey | null;
	const line = Number(p.get("prof"));
	return {
		char: p.get("c"),
		line: Number.isInteger(line) && line > 0 ? line : null,
		q: (p.get("q") ?? "").trim(),
		sort: sort && SORT_KEYS.includes(sort) ? sort : "pToday",
		desc: p.get("dir") !== "asc",
		page: Math.max(1, Number(p.get("p")) || 1),
	};
}

function writeState(): void {
	const p = new URLSearchParams();
	if (st.char) p.set("c", st.char);
	if (st.line !== null) p.set("prof", String(st.line));
	if (st.q) p.set("q", st.q);
	if (st.sort !== "pToday") p.set("sort", st.sort);
	if (!st.desc) p.set("dir", "asc");
	if (st.page > 1) p.set("p", String(st.page));
	const url = `/me/crafted${p.size ? `?${p}` : ""}`;
	if (url !== location.pathname + location.search) history.replaceState(null, "", url);
}

let st = readState();
let rows: LogRow[] = [];
let chars: Character[] = [];
let data: RecipeData | null = null;
let more = false;
const names = new Map<number, { name: string | null; quality: number | null }>();
const lineOf = new Map<number, number>(); // recipe -> skill line

const app = document.getElementById("app")!;
const subline = h("span", {}, "WoW: Forever");
const statusSlot = h("div", { class: "statusrow" });
const heading = h("h2", { class: "res-title", id: "res-title", tabindex: "-1" });
const charSel = h("select", { class: "winput", id: "f-char", "aria-label": "Character" });
const profSel = h("select", { class: "winput", id: "f-prof", "aria-label": "Profession" });
const nameInput = h("input", { class: "winput", id: "f-name", type: "search", autocomplete: "off", placeholder: "Recipe name", "aria-label": "Filter by recipe name" });
const tableWrap = h("div", { class: "tscroll" });
const pager = h("div", { class: "pager" });
const colHint = h("span", { class: "hint" });
const footnote = h("p", { class: "hint footnote" });

function shell(): void {
	const results = h(
		"div",
		{ class: "results" },
		h("form", { class: "filters", "aria-label": "Filters", onsubmit: (e: Event) => e.preventDefault() }, heading, h("span", { class: "grow" }), charSel, profSel, nameInput),
		h("div", { class: "inset" }, tableWrap),
	);
	const frame = h(
		"section",
		{ class: "frame", "aria-labelledby": "cd-title" },
		h("div", { class: "wtitle" }, h("h1", { id: "cd-title" }, "Crafted")),
		closeButton("/me", "Close and go to My Characters"),
		statusSlot,
		h("div", { class: "cols" }, results),
		h("div", { class: "footbar" }, pager, colHint),
	);
	clear(app, topBar(subline, "crafted"), h("main", { class: "shell" }, frame, bottomTabs("crafted"), footnote));
}

function wire(): void {
	charSel.addEventListener("change", () => {
		st.char = charSel.value || null;
		changed();
	});
	profSel.addEventListener("change", () => {
		st.line = profSel.value ? Number(profSel.value) : null;
		changed();
	});
	nameInput.addEventListener("input", () => {
		st.q = nameInput.value.trim();
		changed();
	});
}

function changed(): void {
	st.page = 1;
	writeState();
	renderTable();
}

// ---- Data -------------------------------------------------------------------------------------------

function metaOf(recipe: number): { name: string; profession: string | null } {
	const sp = data ? spellOf(data, recipe) : null;
	const out = sp?.output ?? null;
	const name = (out !== null ? names.get(out)?.name : null) ?? sp?.name ?? (out !== null ? itemName(out) : `Recipe ${recipe}`);
	return { name, profession: sp?.profession ?? null };
}

async function load(): Promise<void> {
	try {
		const [log, list] = await Promise.all([get<{ rows: unknown; more: boolean }>("/api/me/crafted"), get<{ characters: Character[] }>("/api/me/characters")]);
		rows = parseRows(log.rows);
		more = log.more === true;
		const withRows = new Set(rows.map((r) => r.char));
		chars = list.characters.filter((c) => withRows.has(c.key));
		data = await get<RecipeData>(RECIPES_URL);
		await loadItemNames(get);
		for (const r of rows) {
			const sp = spellOf(data, r.recipe);
			if (sp) lineOf.set(r.recipe, sp.skillLine);
		}
		const house = await mainHouse(chars.map((c) => c.realm)).catch(() => null);
		subline.textContent = "WoW: Forever, your crafting";
		clear(statusSlot, house ? statusBar(house) : h("span", {}), h("span", { class: "hint" }, "Estimated profit at craft time, not money received"));
		clear(footnote, "The craft log comes from the addon, uploaded by the companion app. The addon keeps 90 days; this page keeps every day it received.");
		renderFilters();
		renderTable();
		void loadNames();
	} catch {
		clear(heading, "Crafted");
		clear(tableWrap, errorBox("The craft log could not be loaded. Open this page through your Access login and reload."));
	}
}

// The products' names and qualities, 100 items a request; the table is drawn again after each.
async function loadNames(): Promise<void> {
	if (!data) return;
	const need = new Set<number>();
	for (const r of rows) {
		const out = spellOf(data, r.recipe)?.output;
		if (out && !names.has(out)) need.add(out);
	}
	const house = await mainHouse().catch(() => null);
	if (!house || !need.size) return;
	const ids = [...need];
	try {
		for (let i = 0; i < ids.length; i += 100) {
			const chunk = ids.slice(i, i + 100);
			const res = await get<Browse>(`/api/browse?house=${encodeURIComponent(house.key)}&ids=${chunk.join(",")}`);
			for (const id of chunk) names.set(id, { name: null, quality: null });
			for (const it of res.items) names.set(it.id, { name: it.name, quality: it.quality });
			renderTable();
		}
	} catch {
		// names stay as "Item <id>": nothing is guessed
	}
}

function renderFilters(): void {
	clear(charSel, h("option", { value: "" }, "All characters"), chars.map((c) => h("option", { value: c.key, selected: c.key === st.char }, fullName(c))));
	charSel.value = st.char ?? "";
	const lines = [...new Set(lineOf.values())];
	clear(
		profSel,
		h("option", { value: "" }, "All professions"),
		lines
			.map((l) => ({ l, name: data!.professions[String(l)] ?? `Profession ${l}` }))
			.sort((a, b) => a.name.localeCompare(b.name))
			.map((p) => h("option", { value: String(p.l), selected: p.l === st.line }, p.name)),
	);
	profSel.value = st.line === null ? "" : String(st.line);
}

// ---- Table ------------------------------------------------------------------------------------------

type Col = { key: SortKey; label: string; cls: string; firstDesc: boolean; tip?: string };
const COLUMNS: Col[] = [
	{ key: "name", label: "Recipe", cls: "c-name", firstDesc: false },
	{ key: "profession", label: "Profession", cls: "c-prof", firstDesc: false },
	{ key: "today", label: "Today", cls: "r", firstDesc: true, tip: "Crafts today" },
	{ key: "week", label: "7 days", cls: "r", firstDesc: true, tip: "Crafts today and the six days before" },
	{ key: "all", label: "Total", cls: "r", firstDesc: true },
	{ key: "pToday", label: "Profit today", cls: "r c-profit", firstDesc: true, tip: "Estimated profit at craft time, not money received" },
	{ key: "pWeek", label: "Profit 7 days", cls: "r c-profit", firstDesc: true, tip: "Estimated profit at craft time, not money received" },
	{ key: "pAll", label: "Profit total", cls: "r c-profit", firstDesc: true, tip: "Estimated profit at craft time, not money received" },
	{ key: "active", label: "Active time", cls: "r", firstDesc: true, tip: "Seconds spent crafting without a break; days before it was recorded have none" },
	{ key: "perHour", label: "Per active hour", cls: "r", firstDesc: true, tip: "Estimated profit per hour of active crafting, over the days that have both" },
];

function shown(): Line[] {
	if (!data) return [];
	const q = st.q.toLowerCase();
	return summarize(rows, localDay(new Date()), st.char, metaOf).filter((l) => (st.line === null || lineOf.get(l.recipe) === st.line) && (!q || l.name.toLowerCase().includes(q)));
}

function profitCell(p: { profit: number | null; partial: boolean }): HTMLElement {
	if (p.profit === null) return h("td", { class: "r" }, h("span", { class: "hint", title: "No profit was recorded for these crafts" }, "–"));
	return h(
		"td",
		{ class: "r c-profit", title: "Estimated profit at craft time, not money received" + (p.partial ? ". Some crafts had no price: the figure covers the priced ones only" : "") },
		profitEl(p.profit),
		p.partial ? h("span", { class: "hint" }, " *") : null,
	);
}

function countCell(n: number): HTMLElement {
	return n ? h("td", { class: "r num" }, n.toLocaleString("en-US")) : h("td", { class: "r" }, h("span", { class: "hint" }, "–"));
}

function lineEl(l: Line): HTMLElement {
	const out = data ? spellOf(data, l.recipe)?.output ?? null : null;
	const quality = qualityClass(out !== null ? (names.get(out)?.quality ?? null) : null);
	return h(
		"tr",
		{},
		h("td", { class: "c-name" }, out !== null ? h("a", { href: `/item/${out}`, class: `iname ${quality}` }, slot(l.name, quality), h("span", { class: "nm" }, l.name)) : h("span", { class: "iname" }, l.name)),
		h("td", { class: "c-prof" }, l.profession ?? ""),
		countCell(l.today.n),
		countCell(l.week.n),
		countCell(l.all.n),
		profitCell(l.today),
		profitCell(l.week),
		profitCell(l.all),
		l.active === null ? h("td", { class: "r" }, h("span", { class: "hint", title: "No time was recorded for these crafts" }, "–")) : h("td", { class: "r num" }, durationText(l.active)),
		l.perHour === null ? h("td", { class: "r" }, h("span", { class: "hint" }, "–")) : h("td", { class: "r c-profit" }, profitEl(l.perHour), h("span", { class: "hint" }, " /h")),
	);
}

function renderTable(): void {
	if (!data) return;
	const list = sortLines(shown(), st.sort, st.desc);
	const pages = Math.max(1, Math.ceil(list.length / PAGE));
	st.page = Math.min(st.page, pages);
	const page = list.slice((st.page - 1) * PAGE, st.page * PAGE);
	clear(heading, "Crafted ", h("span", { class: "hint count" }, `${list.length.toLocaleString("en-US")} ${list.length === 1 ? "recipe" : "recipes"}${more ? ", the newest days only" : ""}`));
	clear(colHint, "Crafts and estimated profit per recipe: today, the last 7 days (today and the six before) and in total. Profit is the estimate recorded when each craft was made (the profit view's cost basis, a vendor sale where the item is marked to sell), not money received. A * marks a figure that misses crafts without a price. Active time counts the gaps between crafts of at most 30 seconds; per active hour uses only days that have both a profit and a time. A dash means not recorded.");
	document.title = "Crafted - Velikopter Market";
	nameInput.value = st.q;
	const head = h(
		"tr",
		{},
		COLUMNS.map((c) => {
			const sorted = c.key === st.sort;
			const th = h("th", { class: c.cls, scope: "col", title: c.tip ?? null, "aria-sort": sorted ? (st.desc ? "descending" : "ascending") : null });
			const btn = h("button", { type: "button" }, c.label, sorted ? h("span", { class: `srt${st.desc ? "" : " asc"}`, "aria-hidden": "true" }) : null);
			btn.addEventListener("click", () => {
				st.desc = sorted ? !st.desc : c.firstDesc;
				st.sort = c.key;
				st.page = 1;
				writeState();
				renderTable();
				(tableWrap.querySelector("th[aria-sort] button") as HTMLButtonElement | null)?.focus();
			});
			th.append(btn);
			return th;
		}),
	);
	const empty = rows.length ? "No crafts match the filters." : "No craft log has been uploaded yet. Update the addon and run the companion app.";
	const body = h("tbody", {}, page.length ? page.map(lineEl) : h("tr", {}, h("td", { colspan: COLUMNS.length, class: "empty" }, empty)));
	clear(tableWrap, h("table", { class: "tbl list recipes crafts crafted", "aria-labelledby": "res-title" }, h("thead", {}, head), body));
	renderPager(pages);
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
	renderFilters();
	renderTable();
});

shell();
wire();
onSkinChange(() => {
	shell();
	renderFilters();
	renderTable();
});
void load();
