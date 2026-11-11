// Item list (/): category tree, search, filters, sortable table, favourites (#97).
import { type Browse, type BrowseItem, type Categories, get, type House, mainHouse } from "./lib/api";
import { bottomTabs, clear, closeButton, errorBox, h, moneyEl, onSkinChange, pctText, rotor, s, slot, statusBar, topBar, type View } from "./lib/dom";
import { favourites, isFavourite, toggleFavourite } from "./lib/favs";
import { changeClass, changes, className, pctSpoken, qualityClass, qualityName, sparkPath, sparkValues, subclassName } from "./lib/format";

const PAGE = 25;
// Classes listed first in the tree (the materials the site is about), the rest by ID.
const CLASS_ORDER = [7, 0, 9, 1, 15, 5];

type SortKey = "name" | "market" | "lowest" | "c24" | "c7" | "listed";
interface Row {
	item: BrowseItem;
	market: number | null;
	lowest: number | null;
	c24: number | null;
	c7: number | null;
	listed: number | null;
	quality: string;
}

interface State {
	view: View;
	cat: string | null; // "7.9", "7", "none"
	q: string;
	page: number;
	sort: SortKey;
	desc: boolean;
	rarity: string; // "" = all, else quality ID
	minListed: number;
	sel: number | null;
}

function readState(): State {
	const p = new URLSearchParams(location.search);
	const view = p.get("view");
	const sort = p.get("sort") as SortKey | null;
	return {
		view: view === "favourites" || view === "crates" ? view : "browse",
		cat: p.get("c"),
		q: (p.get("q") ?? "").trim(),
		page: Math.max(1, Number(p.get("p")) || 1),
		sort: sort && ["name", "market", "lowest", "c24", "c7", "listed"].includes(sort) ? sort : "market",
		desc: p.get("dir") !== "asc",
		rarity: p.get("r") ?? "",
		minListed: Math.max(0, Number(p.get("min")) || 0),
		sel: null,
	};
}

function writeState(st: State, push = true): void {
	const p = new URLSearchParams();
	if (st.view !== "browse") p.set("view", st.view);
	if (st.view === "browse" && st.q) p.set("q", st.q);
	else if (st.view === "browse" && st.cat) p.set("c", st.cat);
	if (st.sort !== "market") p.set("sort", st.sort);
	if (!st.desc) p.set("dir", "asc");
	if (st.rarity) p.set("r", st.rarity);
	if (st.minListed) p.set("min", String(st.minListed));
	if (st.page > 1) p.set("p", String(st.page));
	const url = `/${p.size ? `?${p}` : ""}`;
	if (url !== location.pathname + location.search) (push ? history.pushState : history.replaceState).call(history, null, "", url);
}

let st = readState();
let house: House | null = null;
let cats: Categories | null = null;
let data: Browse | null = null;
let rows: Row[] = [];
let loadSeq = 0;

// ---- Shell ------------------------------------------------------------------------------------

const app = document.getElementById("app")!;
const subline = h("span", {}, "WoW: Forever");
const statusSlot = h("div", { class: "statusrow" });
const searchInput = h("input", { class: "winput", type: "search", name: "q", placeholder: "Search", autocomplete: "off", "aria-label": "Search items by name" });
const tree = h("nav", { class: "tree", "aria-label": "Categories" });
const treeToggle = h("button", { type: "button", class: "wbtn dark cat-toggle", "aria-expanded": "false", "aria-controls": "tree-well" }, "Categories");
const heading = h("h2", { class: "res-title", id: "res-title", tabindex: "-1" });
const raritySel = h("select", { class: "winput", id: "f-rarity" });
const minInput = h("input", { class: "winput num-in", id: "f-min", type: "number", min: "0", step: "1", inputmode: "numeric" });
const tableWrap = h("div", { class: "tscroll" });
const pager = h("div", { class: "pager" });
const favBtn = h("button", { type: "button", class: "wbtn dark", disabled: true }, "Add to Favourites");
const histBtn = h("a", { class: "wbtn", "aria-disabled": "true" }, "Price History");
const footnote = h("p", { class: "hint footnote" });

function shell(): void {
	const side = h(
		"div",
		{ class: "side" },
		h(
			"form",
			{ class: "searchrow", role: "search", onsubmit: onSearch },
			h(
				"label",
				{ class: "search" },
				s("svg", { width: 15, height: 15, viewBox: "0 0 16 16", "aria-hidden": "true", class: "mag" }, s("circle", { cx: 6.5, cy: 6.5, r: 4.6 }), s("path", { d: "M10 10 L14 14" })),
				searchInput,
			),
			h("button", { type: "submit", class: "wbtn dark gold" }, "Search ", h("span", { class: "tri", "aria-hidden": "true" })),
		),
		treeToggle,
		h("div", { class: "inset well", id: "tree-well" }, tree),
	);
	const results = h(
		"div",
		{ class: "results" },
		h(
			"form",
			{ class: "filters", "aria-label": "Filters", onsubmit: (e: Event) => e.preventDefault() },
			heading,
			h("span", { class: "grow" }),
			h("label", { class: "field", for: "f-rarity" }, h("span", { class: "lbl" }, "Rarity")),
			raritySel,
			h("label", { class: "field", for: "f-min" }, h("span", { class: "lbl" }, "Listed at least")),
			minInput,
		),
		h("div", { class: "inset" }, tableWrap),
	);
	const frame = h(
		"section",
		{ class: "frame", "aria-labelledby": "ah-title" },
		h("div", { class: "medal", "aria-hidden": "true" }, h("span", { class: "medal-rotor" }, rotor(52))),
		h("div", { class: "wtitle" }, h("h1", { id: "ah-title" }, "Auction House")),
		closeButton("/", "Close and go to the start of the list"),
		statusSlot,
		h("div", { class: "cols" }, side, results),
		h(
			"div",
			{ class: "footbar" },
			pager,
			h("span", { class: "hint" }, "Market Price is the typical price of the last 7 days. Listed is units on the auction house."),
			h("span", { class: "grow" }),
			favBtn,
			histBtn,
		),
	);
	clear(app, topBar(subline, st.view), h("main", { class: "shell" }, frame, bottomTabs(st.view), footnote));
}

// Listeners of the shell's lasting controls, added once (shell() runs again when the skin changes).
function wire(): void {
	treeToggle.addEventListener("click", () => {
		const open = treeToggle.getAttribute("aria-expanded") !== "true";
		treeToggle.setAttribute("aria-expanded", String(open));
		app.classList.toggle("tree-open", open);
	});
	raritySel.addEventListener("change", () => {
		st.rarity = raritySel.value;
		st.page = 1;
		writeState(st, false);
		renderTable();
	});
	minInput.addEventListener("input", () => {
		st.minListed = Math.max(0, Math.floor(Number(minInput.value) || 0));
		st.page = 1;
		writeState(st, false);
		renderTable();
	});
	favBtn.addEventListener("click", () => {
		if (st.sel === null) return;
		toggleFavourite(st.sel);
		if (st.view === "favourites") void load();
		else renderTable();
	});
}

function onSearch(e: Event): void {
	e.preventDefault();
	const q = searchInput.value.trim();
	st = { ...st, view: "browse", q, page: 1, sel: null };
	writeState(st);
	void load();
}

// ---- Category tree ------------------------------------------------------------------------------

function catKey(c: number | null, sub: number | null): string {
	return c === null ? "none" : `${c}.${sub}`;
}

function groupedCats(): { cls: number | null; total: number; subs: { sub: number | null; items: number }[] }[] {
	const groups = new Map<number | null, { cls: number | null; total: number; subs: { sub: number | null; items: number }[] }>();
	for (const c of cats?.categories ?? []) {
		let g = groups.get(c.class);
		if (!g) groups.set(c.class, (g = { cls: c.class, total: 0, subs: [] }));
		g.total += c.items;
		g.subs.push({ sub: c.subclass, items: c.items });
	}
	const rank = (c: number | null) => (c === null ? 1000 : CLASS_ORDER.includes(c) ? CLASS_ORDER.indexOf(c) : 100 + c);
	return [...groups.values()].sort((a, b) => rank(a.cls) - rank(b.cls));
}

function defaultCat(): string | null {
	const g = groupedCats()[0];
	if (!g) return null;
	const sub = [...g.subs].sort((a, b) => b.items - a.items)[0]!;
	return catKey(g.cls, sub.sub);
}

const openClasses = new Set<string>();

function renderTree(): void {
	const groups = groupedCats();
	if (!groups.length) {
		clear(tree, h("p", { class: "hint pad" }, "No categories yet."));
		return;
	}
	const activeClass = st.view === "browse" && !st.q && st.cat ? st.cat.split(".")[0]! : null;
	if (activeClass) openClasses.add(activeClass);
	clear(
		tree,
		groups.map((g) => {
			const key = g.cls === null ? "none" : String(g.cls);
			const open = openClasses.has(key);
			const listId = `cat-${key}`;
			const plate = h(
				"button",
				{ type: "button", class: "plate", "aria-expanded": String(open), "aria-controls": listId },
				h("span", {}, className(g.cls)),
				h("span", { class: `pm${open ? "" : " plus"}`, "aria-hidden": "true" }),
			);
			plate.addEventListener("click", () => {
				if (openClasses.has(key)) openClasses.delete(key);
				else openClasses.add(key);
				renderTree();
			});
			const entries =
				g.cls === null
					? [entry("none", "Items without info", g.total)]
					: g.subs.map((sub) => entry(catKey(g.cls, sub.sub), subclassName(g.cls, sub.sub), sub.items));
			return h("div", { class: "cat" }, plate, h("div", { class: "entries", id: listId, hidden: !open }, entries));
		}),
	);
}

function entry(key: string, label: string, n: number): HTMLElement {
	const current = st.view === "browse" && !st.q && st.cat === key;
	const a = h("a", { href: `/?c=${key}`, class: "entry", "aria-current": current ? "page" : null }, h("span", {}, label), h("span", { class: "n num" }, n));
	a.addEventListener("click", (e) => {
		if ((e as MouseEvent).ctrlKey || (e as MouseEvent).metaKey || (e as MouseEvent).shiftKey) return;
		e.preventDefault();
		st = { ...st, view: "browse", q: "", cat: key, page: 1, sel: null };
		searchInput.value = "";
		app.classList.remove("tree-open");
		treeToggle.setAttribute("aria-expanded", "false");
		writeState(st);
		void load();
	});
	return a;
}

// ---- Data ---------------------------------------------------------------------------------------

function toRow(item: BrowseItem, today: number): Row {
	const ch = changes(item.days, today);
	const cur = item.current;
	return {
		item,
		market: item.typical.status === "ok" ? item.typical.price : null,
		lowest: cur && cur.listed ? cur.min : null,
		c24: ch.c24,
		c7: ch.c7,
		listed: cur && cur.listed ? cur.qty : cur ? 0 : null,
		quality: qualityClass(item.quality),
	};
}

function sortRows(list: Row[]): Row[] {
	const k = st.sort;
	const dir = st.desc ? -1 : 1;
	return [...list].sort((a, b) => {
		if (k === "name") return dir * (a.item.name ?? "").localeCompare(b.item.name ?? "");
		const va = a[k];
		const vb = b[k];
		if (va === null && vb === null) return (a.item.name ?? "").localeCompare(b.item.name ?? "");
		if (va === null) return 1; // no value: always last
		if (vb === null) return -1;
		return dir * (va - vb) || (a.item.name ?? "").localeCompare(b.item.name ?? "");
	});
}

function filtered(): Row[] {
	return rows.filter((r) => (st.rarity === "" || String(r.item.quality) === st.rarity) && (st.minListed === 0 || (r.listed ?? 0) >= st.minListed));
}

async function load(): Promise<void> {
	const seq = ++loadSeq;
	searchInput.value = st.q;
	minInput.value = st.minListed ? String(st.minListed) : "";
	syncTabs();
	try {
		if (!house) {
			house = await mainHouse();
			if (!house) throw new Error("no house");
			subline.textContent = `WoW: Forever, ${house.label}`;
			clear(statusSlot, statusBar(house), h("span", { class: "hint" }, "Prices are marked stale after 24 h"));
			clear(footnote, `Prices come from CraftWise scans of the ${house.label} on ${house.realm}. Item icons are placeholders.`);
		}
		if (!cats) {
			cats = await get<Categories>(`/api/categories?house=${encodeURIComponent(house.key)}`);
		}
		if (st.view === "browse" && !st.q && !st.cat) {
			st.cat = defaultCat();
			writeState(st, false);
		}
		renderTree();
		if (st.view === "crates") return renderMessage("Waylaid Crates", "Prices of Waylaid Crates and what they hold get their own list here soon.");
		let query: string | null = null;
		if (st.view === "favourites") {
			const ids = favourites();
			if (!ids.length) return renderMessage("Favourites", "No favourites yet. Select an item and press Add to Favourites, or use the star on its page.");
			query = `ids=${ids.join(",")}`;
		} else if (st.q) query = `q=${encodeURIComponent(st.q)}`;
		else if (st.cat === "none") query = "class=none";
		else if (st.cat) {
			const [c, sub] = st.cat.split(".");
			query = `class=${c}${sub !== undefined && sub !== "null" ? `&subclass=${sub}` : ""}`;
		}
		if (!query) return renderMessage("Auction House", "No prices recorded for this auction house yet.");
		setBusy(true);
		const res = await get<Browse>(`/api/browse?house=${encodeURIComponent(house.key)}&${query}`);
		if (seq !== loadSeq) return;
		data = res;
		rows = res.items.map((i) => toRow(i, res.today));
		renderRarity();
		renderTable();
	} catch (e) {
		if (seq !== loadSeq) return;
		const msg = e instanceof Error && e.message === "no house" ? "No auction house has been scanned yet." : "The prices could not be loaded. Check your connection and reload the page.";
		renderMessage("Auction House", msg, true);
	} finally {
		if (seq === loadSeq) setBusy(false);
	}
}

// Keeps the tab bars in step with the view (browse, favourites, crates).
function syncTabs(): void {
	for (const a of app.querySelectorAll<HTMLAnchorElement>("a[data-view]")) {
		if (a.dataset.view === st.view) a.setAttribute("aria-current", "page");
		else a.removeAttribute("aria-current");
	}
}

function setBusy(on: boolean): void {
	tableWrap.setAttribute("aria-busy", String(on));
}

function title(): string {
	if (st.view === "favourites") return "Favourites";
	if (st.q) return `Search: ${st.q}`;
	if (st.cat === "none") return "Items without info";
	if (st.cat) {
		const [c, sub] = st.cat.split(".").map((v) => (v === "null" ? null : Number(v)));
		return sub === undefined ? className(c ?? null) : subclassName(c ?? null, sub);
	}
	return "Auction House";
}

function renderMessage(head: string, text: string, isError = false): void {
	rows = [];
	data = null; // the message stays when the table is drawn again (skin change, filters)
	clear(heading, head);
	clear(tableWrap, isError ? errorBox(text) : h("p", { class: "notice" }, text));
	clear(pager);
	setSelection(null);
}

function renderRarity(): void {
	const present = [...new Set(rows.map((r) => r.item.quality).filter((q): q is number => q !== null))].sort((a, b) => a - b);
	if (st.rarity && !present.includes(Number(st.rarity))) present.push(Number(st.rarity));
	clear(
		raritySel,
		h("option", { value: "" }, "All"),
		present.map((q) => h("option", { value: String(q), selected: String(q) === st.rarity }, qualityName(q) ?? `Quality ${q}`)),
	);
	raritySel.value = st.rarity;
}

const COLUMNS: { key: SortKey | null; label: string; cls: string; firstDesc: boolean }[] = [
	{ key: "name", label: "Name", cls: "c-name", firstDesc: false },
	{ key: "market", label: "Market Price", cls: "r", firstDesc: true },
	{ key: "lowest", label: "Lowest", cls: "r", firstDesc: true },
	{ key: "c24", label: "24h", cls: "r", firstDesc: true },
	{ key: "c7", label: "7d", cls: "r", firstDesc: true },
	{ key: null, label: "Last 7 Days", cls: "c-spark", firstDesc: false },
	{ key: "listed", label: "Listed", cls: "r", firstDesc: true },
];

function renderTable(): void {
	if (!data) return;
	const list = sortRows(filtered());
	const pages = Math.max(1, Math.ceil(list.length / PAGE));
	st.page = Math.min(st.page, pages);
	const shown = list.slice((st.page - 1) * PAGE, st.page * PAGE);
	const count = list.length === rows.length ? `${rows.length} items` : `${list.length} of ${rows.length} items`;
	clear(heading, title(), " ", h("span", { class: "hint count" }, count + (data.more ? ", first 500 shown" : "")));
	document.title = `${title()} - Velikopter Market`;

	const favs = new Set(favourites());
	const head = h(
		"tr",
		{},
		COLUMNS.map((c) => {
			const sorted = c.key === st.sort;
			const th = h("th", { class: c.cls, scope: "col", "aria-sort": sorted ? (st.desc ? "descending" : "ascending") : null });
			if (!c.key) return append2(th, c.label);
			const label = c.key === "market" ? [h("span", {}, "Market"), h("span", { class: "wide-only" }, " Price")] : c.label;
			const btn = h("button", { type: "button" }, label, sorted ? h("span", { class: `srt${st.desc ? "" : " asc"}`, "aria-hidden": "true" }) : null);
			btn.addEventListener("click", () => {
				st.desc = sorted ? !st.desc : c.firstDesc;
				st.sort = c.key!;
				st.page = 1;
				writeState(st, false);
				renderTable();
				(tableWrap.querySelector(`th[aria-sort] button`) as HTMLButtonElement | null)?.focus();
			});
			return append2(th, btn);
		}),
	);
	const body = h(
		"tbody",
		{},
		shown.length
			? shown.map((r) => rowEl(r, favs.has(r.item.id), data!.today))
			: h("tr", {}, h("td", { colspan: COLUMNS.length, class: "empty" }, rows.length ? "No items match the filters." : "No items here yet.")),
	);
	clear(tableWrap, h("table", { class: "tbl list", "aria-labelledby": "res-title" }, h("thead", {}, head), body));
	if (st.sel !== null && !shown.some((r) => r.item.id === st.sel)) setSelection(null);
	else setSelection(st.sel);
	renderPager(pages);
}

function append2(el: HTMLElement, ...c: (Node | string)[]): HTMLElement {
	el.append(...c);
	return el;
}

function rowEl(r: Row, fav: boolean, today: number): HTMLElement {
	const it = r.item;
	const name = it.name ?? `Item ${it.id}`;
	const spark = sparkPath(sparkValues(it.days, today), 96, 20, 2);
	const cur = it.current;
	const tr = h(
		"tr",
		{ "data-id": it.id },
		h(
			"td",
			{ class: "c-name" },
			h(
				"a",
				{ href: `/item/${it.id}`, class: `iname ${r.quality}` },
				slot(name, r.quality),
				h("span", { class: "nm" }, name),
				fav ? h("span", { class: "star", role: "img", "aria-label": "Favourite" }) : null,
			),
		),
		h("td", { class: "r" }, moneyEl(r.market)),
		h("td", { class: "r" }, cur && !cur.listed ? h("span", { class: "hint" }, "not listed") : moneyEl(r.lowest)),
		changeCell(r.c24, "24 hours"),
		changeCell(r.c7, "7 days"),
		h(
			"td",
			{ class: "c-spark" },
			spark
				? s("svg", { width: 96, height: 20, viewBox: "0 0 96 20", "aria-hidden": "true", class: "spark" }, s("path", { d: spark, class: "under" }), s("path", { d: spark, class: "over" }))
				: null,
		),
		h(
			"td",
			{ class: "r num" },
			r.listed === null ? "–" : r.listed.toLocaleString("en-US"),
			cur && cur.listed && cur.listings !== null ? h("span", { class: "hint" }, ` in ${cur.listings.toLocaleString("en-US")}`) : null,
		),
	);
	tr.addEventListener("click", (e) => {
		if ((e.target as Element).closest("a")) return;
		setSelection(it.id);
	});
	tr.addEventListener("focusin", () => setSelection(it.id));
	return tr;
}

function changeCell(v: number | null, span: string): HTMLElement {
	return h("td", { class: "r num" }, h("span", { class: changeClass(v), "aria-hidden": "true" }, pctText(v)), h("span", { class: "sr" }, `${span}: ${pctSpoken(v)}`));
}

function setSelection(id: number | null): void {
	st.sel = id;
	for (const tr of tableWrap.querySelectorAll("tbody tr")) {
		tr.classList.toggle("sel", id !== null && (tr as HTMLElement).dataset.id === String(id));
	}
	const row = rows.find((r) => r.item.id === id);
	favBtn.disabled = !row;
	favBtn.textContent = row && isFavourite(row.item.id) ? "Remove from Favourites" : "Add to Favourites";
	if (row) {
		histBtn.setAttribute("href", `/item/${row.item.id}`);
		histBtn.removeAttribute("aria-disabled");
		histBtn.setAttribute("aria-label", `Price history of ${row.item.name ?? `item ${row.item.id}`}`);
	} else {
		histBtn.removeAttribute("href");
		histBtn.setAttribute("aria-disabled", "true");
		histBtn.removeAttribute("aria-label");
	}
}

function renderPager(pages: number): void {
	const go = (p: number) => {
		st.page = p;
		writeState(st, false);
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
	void load();
});

shell();
wire();
onSkinChange(() => {
	shell();
	syncTabs();
	renderTable();
});
void load();
