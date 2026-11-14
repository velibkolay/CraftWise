// Item list (/): category tree, search, filters, sortable table, favourites (#97), crafting profit of recipe
// items (#143).
import { type Browse, type BrowseItem, type Categories, get, type House, mainHouse } from "./lib/api";
import { bottomTabs, clear, closeButton, errorBox, h, moneyEl, onSkinChange, pctText, rotor, s, skinMoney, slot, statusBar, topBar, type View } from "./lib/dom";
import { favouriteLabel, favourites, isFromAddon, syncAddonWatch, toggleFavourite } from "./lib/favs";
import { changeClass, changes, className, pctSpoken, qualityClass, qualityName, sellChoice, sparkPath, sparkValues, subclassName } from "./lib/format";
import { type CraftNames, craftBreakdown, craftsText, profitEl, thinTag } from "./lib/craftview";
import { itemsNeeded, type Quote, quoteOf, RECIPES_URL, type RecipeData, type RecipeRow, recipeRow } from "./lib/recipes";

const PAGE = 25;
// Classes listed first in the tree (the materials the site is about), the rest by ID.
const CLASS_ORDER = [7, 0, 9, 1, 15, 5];

type SortKey = "name" | "market" | "lowest" | "vendor" | "profit" | "payback" | "c24" | "c7" | "listed";
const SORT_KEYS: SortKey[] = ["name", "market", "lowest", "vendor", "profit", "payback", "c24", "c7", "listed"];
interface Row {
	item: BrowseItem;
	market: number | null;
	lowest: number | null;
	vendor: number | null; // vendor sell price (#120); 0 = vendors don't buy it
	toVendor: boolean; // a vendor pays more than the auction house after the cut
	c24: number | null;
	c7: number | null;
	listed: number | null;
	quality: string;
	recipe: RecipeRow | null; // recipe items (#143): the craft with today's prices, once they are loaded
	profit: number | null;
	payback: number | null;
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
	vendorOnly: boolean; // "Better sold to a vendor" (#120)
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
		sort: sort && SORT_KEYS.includes(sort) ? sort : "market",
		desc: p.get("dir") !== "asc",
		rarity: p.get("r") ?? "",
		minListed: Math.max(0, Number(p.get("min")) || 0),
		vendorOnly: p.get("vendor") === "1",
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
	if (st.vendorOnly) p.set("vendor", "1");
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

// Crafting profit (#143): the recipe data (public/data/recipes.json) and the prices and names of products and
// reagents, fetched once per page view and kept while the visitor moves between categories.
let recipeData: RecipeData | null = null;
let recipeFetch: Promise<RecipeData> | null = null;
const quotes = new Map<number, Quote>();
const itemNames: CraftNames = new Map();
let pricing: "idle" | "loading" | "failed" = "idle";
const openRows = new Set<number>(); // rows whose breakdown is open

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
const vendorBox = h("input", { type: "checkbox", id: "f-vendor" }) as HTMLInputElement;
const tableWrap = h("div", { class: "tscroll" });
const pager = h("div", { class: "pager" });
const favBtn = h("button", { type: "button", class: "wbtn dark", disabled: true }, "Add to Favourites");
const histBtn = h("a", { class: "wbtn", "aria-disabled": "true" }, "Price History");
const footnote = h("p", { class: "hint footnote" });
const colHint = h("span", { class: "hint" });

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
			h("label", { class: "field vcheck", for: "f-vendor" }, vendorBox, h("span", { class: "lbl" }, "Better sold to a vendor")),
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
			colHint,
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
	vendorBox.addEventListener("change", () => {
		st.vendorOnly = vendorBox.checked;
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

interface CatGroup {
	cls: number | null;
	name: string; // the client's name (#120), else the enum identifier
	total: number;
	subs: { sub: number | null; name: string; items: number }[];
}

function groupedCats(): CatGroup[] {
	const groups = new Map<number | null, CatGroup>();
	for (const c of cats?.categories ?? []) {
		let g = groups.get(c.class);
		if (!g) groups.set(c.class, (g = { cls: c.class, name: className(c.class, c.className), total: 0, subs: [] }));
		g.total += c.items;
		g.subs.push({ sub: c.subclass, name: subclassName(c.class, c.subclass, c.subclassName), items: c.items });
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
				h("span", {}, g.name),
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
					: g.subs.map((sub) => entry(catKey(g.cls, sub.sub), sub.name, sub.items));
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
	const market = item.typical.status === "ok" ? item.typical.price : null;
	const lowest = cur && cur.listed ? cur.min : null;
	return {
		item,
		market,
		lowest,
		vendor: item.sellPrice,
		toVendor: sellChoice(market, lowest, item.sellPrice).best === "vendor",
		c24: ch.c24,
		c7: ch.c7,
		listed: cur && cur.listed ? cur.qty : cur ? 0 : null,
		quality: qualityClass(item.quality),
		recipe: null,
		profit: null,
		payback: null,
	};
}

// A list with recipe items gets the Profit and Pays back columns.
function isRecipeItem(item: BrowseItem): boolean {
	return item.class === 9 || (recipeData !== null && recipeData.teach[String(item.id)] !== undefined);
}

function recipeMode(): boolean {
	return rows.some((r) => isRecipeItem(r.item));
}

function remember(items: BrowseItem[]): void {
	for (const it of items) {
		quotes.set(it.id, quoteOf(it));
		if (it.name !== null || !itemNames.has(it.id)) itemNames.set(it.id, { name: it.name, quality: it.quality });
	}
}

// The recipe data, then the Horde AH prices of every product and reagent the listed recipes need that this page
// view hasn't fetched yet: 100 items per /api/browse request, three requests at a time.
async function loadRecipes(seq: number): Promise<void> {
	if (!recipeMode()) return;
	pricing = "loading";
	try {
		recipeFetch ??= get<RecipeData>(RECIPES_URL);
		recipeData = await recipeFetch;
		const need = itemsNeeded(
			recipeData,
			rows.map((r) => r.item.id),
		).filter((id) => !quotes.has(id));
		const chunks: number[][] = [];
		for (let i = 0; i < need.length; i += 100) chunks.push(need.slice(i, i + 100));
		const houseKey = encodeURIComponent(house!.key);
		const worker = async () => {
			for (let c = chunks.shift(); c; c = chunks.shift()) remember((await get<Browse>(`/api/browse?house=${houseKey}&ids=${c.join(",")}`)).items);
		};
		await Promise.all([worker(), worker(), worker()]);
		if (seq !== loadSeq) return;
		pricing = "idle";
	} catch {
		recipeFetch = null;
		if (seq !== loadSeq) return;
		// Without the AH prices a craft would be priced from vendor prices alone: show no profit at all instead.
		pricing = "failed";
		for (const r of rows) r.recipe = r.profit = r.payback = null;
		return renderTable();
	}
	priceRecipes();
	renderTable();
}

function priceRecipes(): void {
	if (!recipeData) return;
	for (const r of rows) {
		if (!isRecipeItem(r.item)) continue;
		r.recipe = recipeRow(recipeData, r.item.id, quoteOf(r.item), quotes);
		r.profit = r.recipe.craft?.profit ?? null;
		r.payback = r.recipe.payback;
	}
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
	return rows.filter(
		(r) => (st.rarity === "" || String(r.item.quality) === st.rarity) && (st.minListed === 0 || (r.listed ?? 0) >= st.minListed) && (!st.vendorOnly || r.toVendor),
	);
}

async function load(): Promise<void> {
	if (st.view === "crates") return location.replace("/me/crates"); // the crates page moved there (#129)
	const seq = ++loadSeq;
	searchInput.value = st.q;
	minInput.value = st.minListed ? String(st.minListed) : "";
	vendorBox.checked = st.vendorOnly;
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
		remember(res.items);
		openRows.clear();
		if (recipeMode()) {
			if (recipeData && res.items.every((i) => !isRecipeItem(i) || itemsNeeded(recipeData!, [i.id]).every((id) => quotes.has(id)))) {
				priceRecipes();
				pricing = "idle";
			} else pricing = "loading";
		}
		renderRarity();
		renderTable();
		if (pricing === "loading") void loadRecipes(seq);
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
		const g = groupedCats().find((x) => x.cls === (c ?? null));
		if (sub === undefined) return g?.name ?? className(c ?? null);
		return g?.subs.find((x) => x.sub === sub)?.name ?? subclassName(c ?? null, sub);
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
	{ key: "vendor", label: "Vendor", cls: "r", firstDesc: true },
	{ key: "c24", label: "24h", cls: "r", firstDesc: true },
	{ key: "c7", label: "7d", cls: "r c-7d", firstDesc: true },
	{ key: null, label: "Last 7 Days", cls: "c-spark", firstDesc: false },
	{ key: "listed", label: "Listed", cls: "r", firstDesc: true },
];

// Recipe lists (#143): Profit and Pays back right after the name (in view on a phone too); no sparkline.
const RECIPE_COLUMNS: typeof COLUMNS = [
	COLUMNS[0]!,
	{ key: "profit", label: "Profit", cls: "r c-profit", firstDesc: true },
	{ key: "payback", label: "Pays back", cls: "r c-payback", firstDesc: false },
	...COLUMNS.slice(1).filter((c) => c.cls !== "c-spark"),
];

function columns(): typeof COLUMNS {
	return recipeMode() ? RECIPE_COLUMNS : COLUMNS;
}

function renderTable(): void {
	if (!data) return;
	const cols = columns();
	const recipes = cols === RECIPE_COLUMNS;
	const list = sortRows(filtered());
	const pages = Math.max(1, Math.ceil(list.length / PAGE));
	st.page = Math.min(st.page, pages);
	const shown = list.slice((st.page - 1) * PAGE, st.page * PAGE);
	const count = list.length === rows.length ? `${rows.length} items` : `${list.length} of ${rows.length} items`;
	const priceNote = recipes && pricing === "loading" ? ", pricing the recipes" : recipes && pricing === "failed" ? ", the recipe prices could not be loaded" : "";
	clear(heading, title(), " ", h("span", { class: "hint count" }, count + (data.more ? ", first 500 shown" : "") + priceNote));
	clear(colHint, recipes ? "Profit is one craft's product at the Horde AH after the 5% cut (or a vendor, if it pays more) minus its reagents, each where it is cheaper: AH or vendor. Pays back: crafts until the recipe's AH price is earned back. Press a profit for the breakdown." : "Market Price is the typical price of the last 7 days. Vendor is what a vendor pays for one. Listed is units on the auction house.");
	document.title = `${title()} - Velikopter Market`;

	const favs = new Set(favourites());
	const head = h(
		"tr",
		{},
		cols.map((c) => {
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
			? shown.map((r) => [rowEl(r, favs.has(r.item.id), data!.today, recipes), recipes && openRows.has(r.item.id) ? detailRow(r, cols.length) : null])
			: h("tr", {}, h("td", { colspan: cols.length, class: "empty" }, rows.length ? "No items match the filters." : "No items here yet.")),
	);
	clear(tableWrap, h("table", { class: recipes ? "tbl list recipes" : "tbl list", "aria-labelledby": "res-title" }, h("thead", {}, head), body));
	if (st.sel !== null && !shown.some((r) => r.item.id === st.sel)) setSelection(null);
	else setSelection(st.sel);
	renderPager(pages);
}

function append2(el: HTMLElement, ...c: (Node | string)[]): HTMLElement {
	el.append(...c);
	return el;
}

function rowEl(r: Row, fav: boolean, today: number, recipes: boolean): HTMLElement {
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
				fav ? h("span", { class: "star", role: "img", "aria-label": isFromAddon(it.id) ? "Watched in the addon" : "Favourite", title: isFromAddon(it.id) ? "Watched in the addon" : undefined }) : null,
			),
		),
		recipes ? profitCell(r) : null,
		recipes ? h("td", { class: "r num c-payback" }, r.payback !== null ? craftsText(r.payback) : h("span", { class: "hint" }, "–")) : null,
		h("td", { class: "r" }, moneyEl(r.market)),
		h("td", { class: "r" }, cur && !cur.listed ? h("span", { class: "hint" }, "not listed") : moneyEl(r.lowest)),
		vendorCell(r),
		changeCell(r.c24, "24 hours"),
		changeCell(r.c7, "7 days", " c-7d"),
		recipes
			? null
			: h(
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
		if ((e.target as Element).closest("a, button")) return;
		setSelection(it.id);
	});
	tr.addEventListener("focusin", () => setSelection(it.id));
	return tr;
}

// The vendor sell price (#120): "no sale" when vendors don't buy it, "–" when not known yet; marked when a
// vendor pays more than the auction house after the cut.
function vendorCell(r: Row): HTMLElement {
	if (r.vendor === null) return h("td", { class: "r" }, moneyEl(null));
	if (r.vendor === 0) return h("td", { class: "r" }, h("span", { class: "hint" }, "no sale"));
	return h("td", { class: "r", title: r.toVendor ? "A vendor pays more than the auction house after the cut" : null }, moneyEl(r.vendor), r.toVendor ? h("span", { class: "hint" }, " best") : null);
}

// Profit per craft (#143): money, a loss marked; a button that opens the breakdown under the row. Unknown says why.
function profitCell(r: Row): HTMLElement {
	if (!isRecipeItem(r.item)) return h("td", { class: "r c-profit" });
	const rec = r.recipe;
	if (!rec) return h("td", { class: "r c-profit" }, h("span", { class: "hint" }, pricing === "failed" ? "–" : "…"));
	if (rec.status === "not_in_data" || rec.status === "no_reagents") {
		return h("td", { class: "r c-profit", title: "The bundled recipe data doesn't know what this recipe makes or its reagents" }, h("span", { class: "hint" }, "no data"));
	}
	const open = openRows.has(r.item.id);
	const c = rec.craft!;
	const label =
		rec.status === "no_item"
			? h("span", { class: "hint" }, "no item")
			: rec.status === "no_ah_price"
				? h("span", { class: "hint" }, "no AH price")
				: r.profit === null
					? h("span", { class: "hint" }, "unknown")
					: [profitEl(r.profit), c.thin ? thinTag(c.value) : null];
	let tip: string;
	if (rec.status === "no_item") tip = "It makes no item (an enchant or the like): no product to value";
	else if (rec.status === "no_ah_price")
		tip =
			c.vendorFloor !== null && c.worst !== null
				? `The product has no Horde AH price. A vendor pays ${skinMoney(c.vendorFloor).short}: at worst ${c.worst < 0 ? `a loss of ${skinMoney(-c.worst).short}` : `${skinMoney(c.worst).short} profit`}`
				: "The product has no Horde AH price";
	else if (r.profit === null) tip = "Unknown: a reagent or the product has no price";
	else tip = `Product ${skinMoney(c.revenue!).short} - reagents ${skinMoney(c.cost!).short}${c.thin ? ". Thin market: the product's price rests on few units or listings" : ""}`;
	const btn = h(
		"button",
		{ type: "button", class: "pbtn", "aria-expanded": String(open), "aria-controls": `bd-${r.item.id}`, title: tip },
		h("span", { class: `chev${open ? " open" : ""}`, "aria-hidden": "true" }),
		label,
		h("span", { class: "sr" }, ", breakdown"),
	);
	btn.addEventListener("click", () => {
		if (openRows.has(r.item.id)) openRows.delete(r.item.id);
		else openRows.add(r.item.id);
		setSelection(r.item.id);
		renderTable();
		tableWrap.querySelector<HTMLButtonElement>(`tr[data-id="${r.item.id}"] .pbtn`)?.focus();
	});
	return h("td", { class: "r c-profit" }, btn);
}

function detailRow(r: Row, span: number): HTMLElement | null {
	if (!r.recipe?.craft) return null;
	return h("tr", { class: "detail" }, h("td", { colspan: span }, h("div", { class: "breakdown", id: `bd-${r.item.id}` }, craftBreakdown(r.recipe, itemNames, r.item.name))));
}

function changeCell(v: number | null, span: string, cls = ""): HTMLElement {
	return h("td", { class: `r num${cls}` }, h("span", { class: changeClass(v), "aria-hidden": "true" }, pctText(v)), h("span", { class: "sr" }, `${span}: ${pctSpoken(v)}`));
}

function setSelection(id: number | null): void {
	st.sel = id;
	for (const tr of tableWrap.querySelectorAll("tbody tr")) {
		tr.classList.toggle("sel", id !== null && (tr as HTMLElement).dataset.id === String(id));
	}
	const row = rows.find((r) => r.item.id === id);
	favBtn.disabled = !row;
	favBtn.textContent = row ? favouriteLabel(row.item.id) : "Add to Favourites";
	favBtn.disabled = !row || isFromAddon(row.item.id);
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
// The addon's watch list (#165), when the private API answers: redraw once it changes the favourites.
void syncAddonWatch().then((changed) => {
	if (!changed) return;
	if (st.view === "favourites") void load();
	else renderTable();
});
