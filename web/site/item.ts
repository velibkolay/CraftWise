// Item page (/item/<id>): tooltip, cheapest listings, price history (#97); crafting profit (#143).
import { chart, type Point, type Series } from "./chart";
import { ApiError, type Browse, get, type House, type ItemDetail, type ItemInfo, type Market, mainHouse } from "./lib/api";
import { type CraftNames, craftBreakdown, craftItBreakdown } from "./lib/craftview";
import { craft, makersOf, type Quote, quoteOf, RECIPES_URL, type RecipeData, recipeItemOf, recipeRow, teachOf } from "./lib/recipes";
import { bottomTabs, clear, closeButton, currentSkin, errorBox, h, moneyEl, nowSeconds, onSkinChange, pctText, s, skinMoney, slot, statusBar, topBar } from "./lib/dom";
import { isFavourite, toggleFavourite } from "./lib/favs";
import {
	age,
	buyCost,
	changeClass,
	changes,
	className,
	DAY,
	dayLabel,
	pctSpoken,
	qualityClass,
	sellChoice,
	subclassName,
	timeLabel,
} from "./lib/format";

type Range = "48h" | "7d" | "30d";
const RANGES: { key: Range; label: string; days: number; hours: number }[] = [
	{ key: "48h", label: "48 Hours", days: 7, hours: 48 },
	{ key: "7d", label: "7 Days", days: 9, hours: 0 },
	{ key: "30d", label: "30 Days", days: 30, hours: 0 },
];

const app = document.getElementById("app")!;
const id = Number(/^\/item\/([1-9][0-9]{0,9})$/.exec(location.pathname)?.[1] ?? NaN);
let range: Range | null = null;
try {
	const saved = localStorage.getItem("cw-range");
	if (saved === "48h" || saved === "7d" || saved === "30d") range = saved;
} catch {
	// no storage: default range
}

function listHref(d: ItemDetail | null): string {
	const it = d?.item;
	if (!it || it.class === null) return "/";
	return `/?c=${it.class}.${it.subclass}`;
}

function frame(title: string, body: Node[], foot: Node[], back: string): HTMLElement {
	return h(
		"section",
		{ class: "frame", "aria-labelledby": "item-title" },
		h("div", { class: "medal", "aria-hidden": "true" }, h("span", { class: "medal-letter" }, title.charAt(0))),
		h("div", { class: "wtitle" }, h("h1", { id: "item-title" }, title)),
		closeButton(back, "Close and go back to the list"),
		...body,
		h("div", { class: "footbar" }, ...foot),
	);
}

function page(crumbs: Node | string, section: HTMLElement, house: House | null): void {
	clear(
		app,
		topBar(crumbs, "browse"),
		h(
			"main",
			{ class: "shell" },
			section,
			bottomTabs(null),
			house ? h("p", { class: "hint footnote" }, `Prices come from CraftWise scans of the ${house.label} on ${house.realm}. Item icons are placeholders.`) : null,
		),
	);
}

// What the page shows now, drawn again when the skin changes.
let redraw: (() => void) | null = null;
onSkinChange(() => redraw?.());

function fail(text: string, house: House | null = null): void {
	redraw = () => fail(text, house);
	document.title = "Item - Velikopter Market";
	page("WoW: Forever", frame("Item", [h("div", { class: "statusrow" }, h("a", { class: "wbtn", href: "/" }, "Back")), errorBox(text)], [], "/"), house);
}

async function main(): Promise<void> {
	if (!Number.isInteger(id)) return fail("No item chosen. Pick one from the list.");
	redraw = () => page("WoW: Forever", frame("Loading", [h("p", { class: "notice", "aria-busy": "true" }, "Loading prices")], [], "/"), null);
	redraw();
	let house: House | null = null;
	let detail: ItemDetail;
	try {
		[house, detail] = await Promise.all([mainHouse(), get<ItemDetail>(`/api/items/${id}?days=30&hours=48`)]);
	} catch (e) {
		if (e instanceof ApiError && e.status === 404) return fail(`No prices recorded for item ${id}.`);
		return fail("The prices could not be loaded. Check your connection and reload the page.");
	}
	render(detail, house);
	void loadCrafting(detail, house);
}

// ---- Crafting (#143) ------------------------------------------------------------------------------

interface Crafting {
	data: RecipeData;
	quotes: Map<number, Quote>;
	names: CraftNames;
	status: "loading" | "ok" | "failed";
}
let crafting: Crafting | null = null;

// This item's own quote: the main house's typical price and current listing, and its vendor sell price.
function ownQuote(m: Market | null, it: ItemInfo | null): Quote {
	return {
		typical: m?.typical.status === "ok" ? m.typical.price : null,
		lowest: m?.current && m.current.listed ? m.current.min : null,
		sellPrice: it?.sellPrice ?? null,
		units: m?.current && m.current.listed ? m.current.qty : null,
		listings: m?.current && m.current.listed ? m.current.listings : null,
	};
}

// The recipe data, then the Horde AH prices of the reagents, products and recipe items the blocks show.
async function loadCrafting(d: ItemDetail, house: House | null): Promise<void> {
	let data: RecipeData;
	try {
		data = await get<RecipeData>(RECIPES_URL);
	} catch {
		return; // without the recipe data the page simply has no crafting blocks
	}
	const makers = makersOf(data, d.id);
	const teach = teachOf(data, d.id);
	if (!makers.length && !teach?.spell) return;
	const m = d.markets.filter((x) => x.house === house?.key).sort((a, b) => a.suffix - b.suffix)[0] ?? null;
	const c: Crafting = { data, quotes: new Map([[d.id, ownQuote(m, d.item)]]), names: new Map([[d.id, { name: d.item?.name ?? null, quality: d.item?.quality ?? null }]]), status: "loading" };
	crafting = c;
	redraw?.();
	const ids = new Set<number>();
	for (const s of [...makers, ...(teach?.spell ? [teach.spell] : [])]) {
		if (s.output) ids.add(s.output);
		for (const r of s.reagents) ids.add(r.item);
		const rec = recipeItemOf(data, s.id);
		if (rec) ids.add(rec.item);
	}
	ids.delete(d.id);
	const list = [...ids];
	try {
		if (!house) throw new Error("no house");
		for (let i = 0; i < list.length; i += 100) {
			const b = await get<Browse>(`/api/browse?house=${encodeURIComponent(house.key)}&ids=${list.slice(i, i + 100).join(",")}`);
			for (const it of b.items) {
				c.quotes.set(it.id, quoteOf(it));
				c.names.set(it.id, { name: it.name, quality: it.quality });
			}
		}
		c.status = "ok";
	} catch {
		c.status = "failed";
	}
	redraw?.();
}

const CRAFT_NOTE =
	"Reagents at the Horde AH's market price (else its lowest listing) or from a vendor, whichever is cheaper; the product after the 5% cut, or what a vendor pays if that is more. No price, no profit: nothing is guessed.";

function craftBlocks(d: ItemDetail): HTMLElement[] {
	const c = crafting;
	if (!c) return [];
	const status = c.status === "loading" ? h("p", { class: "hint padx", "aria-busy": "true" }, "Pricing the reagents") : c.status === "failed" ? h("p", { class: "hint padx" }, "The reagent prices could not be loaded.") : null;
	const out: HTMLElement[] = [];
	const makers = makersOf(c.data, d.id);
	if (makers.length) {
		out.push(
			h(
				"div",
				{ class: "block" },
				h("h2", { class: "bar-head", id: "craft-title" }, "Craft It"),
				status ??
					h(
						"div",
						{ class: "inset", role: "group", "aria-labelledby": "craft-title" },
						makers.map((s) => h("div", { class: "craftbox" }, craftItBreakdown(craft(c.data, s, c.quotes), recipeItemOf(c.data, s.id), c.names))),
					),
				status ? null : h("p", { class: "hint padx" }, CRAFT_NOTE),
			),
		);
	}
	const teach = teachOf(c.data, d.id);
	if (teach?.spell) {
		const rec = recipeRow(c.data, d.id, c.quotes.get(d.id), c.quotes);
		out.push(
			h(
				"div",
				{ class: "block" },
				h("h2", { class: "bar-head", id: "teach-title" }, "Teaches"),
				status ?? h("div", { class: "inset", role: "group", "aria-labelledby": "teach-title" }, h("div", { class: "craftbox" }, craftBreakdown(rec, c.names, d.item?.name ?? null))),
				status ? null : h("p", { class: "hint padx" }, `${CRAFT_NOTE} Pays back: crafts until the recipe's AH price is earned back.`),
			),
		);
	}
	return out;
}

function render(d: ItemDetail, house: House | null): void {
	redraw = () => render(d, house);
	const it = d.item;
	const name = it?.name ?? `Item ${d.id}`;
	const q = qualityClass(it?.quality ?? null);
	const cls = it ? className(it.class, it.className) : null;
	const sub = it && it.class !== null ? subclassName(it.class, it.subclass, it.subclassName) : null;
	const mine = d.markets.filter((m) => m.house === house?.key).sort((a, b) => a.suffix - b.suffix);
	const m: Market | null = mine[0] ?? null;
	const others = d.markets.filter((x) => x.house !== house?.key && x.current && x.current.listed && x.current.min !== null);
	const back = listHref(d);
	document.title = `${name} - Velikopter Market`;

	const crumbs = h("span", {}, it && it.class !== null ? h("a", { href: back }, `${cls} / ${sub}`) : null, it && it.class !== null ? " / " : null, name);

	// ---- Detail pane --------------------------------------------------------------------------
	const favBtn = h("button", { type: "button", class: "favstar", "aria-pressed": String(isFavourite(d.id)), "aria-label": "Favourite" });
	const favFoot = h("button", { type: "button", class: "wbtn dark" });
	const syncFav = () => {
		const on = isFavourite(d.id);
		favBtn.setAttribute("aria-pressed", String(on));
		favFoot.textContent = on ? "Remove from Favourites" : "Add to Favourites";
	};
	const flip = () => {
		toggleFavourite(d.id);
		syncFav();
	};
	favBtn.addEventListener("click", flip);
	favFoot.addEventListener("click", flip);
	syncFav();

	const now = nowSeconds();
	const today = Math.floor(now / DAY);
	const cur = m?.current ?? null;
	const ch = m ? changes(m.days, today) : { c24: null, c7: null };
	const typ = m?.typical;
	const tipRows: (Node | null)[] = [
		h("p", { class: "row" }, h("span", { class: "lbl" }, "Market price, 7 days"), typ?.status === "ok" ? moneyEl(typ.price) : h("span", { class: "hint" }, typ ? `${typ.days} of 3 days` : "no data")),
		h("p", { class: "row" }, h("span", { class: "lbl" }, "Lowest now"), !cur ? h("span", { class: "hint" }, "no data") : cur.listed ? moneyEl(cur.min) : h("span", { class: "hint" }, "not listed")),
		h(
			"p",
			{ class: "row" },
			h("span", { class: "lbl" }, "Change"),
			h(
				"span",
				{},
				h("span", { class: changeClass(ch.c24), "aria-hidden": "true" }, pctText(ch.c24)),
				h("span", { "aria-hidden": "true" }, " 24 h "),
				h("span", { class: changeClass(ch.c7), "aria-hidden": "true" }, pctText(ch.c7)),
				h("span", { "aria-hidden": "true" }, " 7 d"),
				h("span", { class: "sr" }, `24 hours ${pctSpoken(ch.c24)}, 7 days ${pctSpoken(ch.c7)}`),
			),
		),
		cur && cur.listed && cur.qty !== null
			? h("p", { class: "row" }, h("span", { class: "lbl" }, "Listed"), h("span", {}, cur.listings !== null ? `${cur.qty.toLocaleString("en-US")} in ${cur.listings} auctions` : `${cur.qty.toLocaleString("en-US")} units`))
			: null,
		cur ? h("p", { class: "row" }, h("span", { class: "lbl" }, "Seen"), h("span", {}, `${age(now - cur.t)}, ${m!.label}`)) : null,
	];
	const tooltip = h(
		"div",
		{},
		h("span", { class: "tiptab" }, "Tooltip"),
		h(
			"div",
			{ class: "tip" },
			h("p", { class: `${q} tip-title` }, name),
			cls ? h("p", {}, sub && !sub.startsWith("Subclass") ? `${cls}, ${sub}` : cls) : null,
			h("p", { class: "hint" }, `Item ID ${d.id}`),
			sellPriceLine(it),
			h("p", { class: "addon" }, "CraftWise"),
			m ? tipRows.filter((n): n is Node => n !== null) : h("p", { class: "hint" }, `No prices at the ${house?.label ?? "auction house"} yet.`),
		),
	);

	const pane = h(
		"div",
		{ class: "pane" },
		fili("tl"),
		fili("tr"),
		fili("bl"),
		fili("br"),
		h("div", { class: "pane-head" }, slot(name, q, "ring"), h("div", { class: "grow" }, h("p", { class: `${q} pane-name` }, name), cls ? h("p", { class: "hint" }, cls) : null), favBtn),
		tooltip,
		sellBlock(m, it),
		...craftBlocks(d),
		listings(m),
	);

	// ---- Price history ------------------------------------------------------------------------
	const chartSlot = h("div", { class: "chart-slot" });
	const legend = h("p", { class: "sub" });
	const tabs = h("div", { class: "rtabs", role: "group", "aria-label": "Time range" });
	// Without a saved choice: 30 days once the history is longer than a week, else 7 days.
	if (!range) range = m && m.days.some((x) => x.day < today - 6) ? "30d" : "7d";
	const drawRange = () => {
		const r = RANGES.find((x) => x.key === range)!;
		clear(
			tabs,
			RANGES.map((x) =>
				h(
					"button",
					{
						type: "button",
						class: "wtab up",
						"aria-pressed": String(x.key === range),
						onclick: () => {
							range = x.key;
							try {
								localStorage.setItem("cw-range", range);
							} catch {
								// keep in memory only
							}
							drawRange();
						},
					},
					x.label,
				),
			),
		);
		const series = m ? (range === "48h" ? rawSeries(m, now) : daySeries(m, today, r.days === 9 ? 7 : r.days)) : null;
		if (!series || !series.points.length) {
			clear(chartSlot, h("p", { class: "empty-chart" }, range === "48h" ? "No detailed scans in the last 48 hours. Detailed scans cover the items CraftWise tracks; try 7 Days." : "No price history in this time range."));
			clear(legend);
			return;
		}
		clear(chartSlot, chart(series));
		clear(
			legend,
			// The Velikopter skin draws the line in ink, not red.
			(currentSkin() === "velikopter" ? "Line" : "Red line") +
				(range === "48h"
					? ": lowest price at each scan. Shaded band: the cheapest 8 price levels. Bars: units listed."
					: ": typical price of the day. Dashed line: lowest price, where no typical price is known. Shaded band: the day's low to high. Bars: most units listed."),
		);
	};
	drawRange();

	const parch = h(
		"div",
		{ class: "parchwrap" },
		tabs,
		h(
			"div",
			{ class: "parch" },
			h("div", { class: "parch-bg" }),
			h("div", { class: "parch-in" }, h("h2", {}, "Price History"), divider(), chartSlot, legend),
		),
	);

	const foot: Node[] = [favFoot];
	if (others.length) {
		const o = others[0]!;
		foot.push(h("span", { class: "hint" }, `Also seen at ${o.label}: lowest ${skinMoney(o.current!.min!).short}, ${age(now - o.current!.t)}.`));
	}
	foot.push(h("span", { class: "grow" }), h("a", { class: "wbtn", href: back }, sub && it?.class !== null ? `Back to ${sub}` : "Back to the list"));

	const section = frame(
		name,
		[
			h("div", { class: "statusrow" }, h("a", { class: "wbtn", href: back }, "Back"), statusBar(house), h("span", { class: "hint" }, "Prices are marked stale after 24 h")),
			h("div", { class: "cols item-cols" }, pane, parch),
		],
		foot,
		back,
	);
	page(crumbs, section, house);
	section.querySelector(".medal-letter")?.classList.add(q);
}

// The tooltip's "Sell Price" line, as the client shows it (#120); "No sell price" when vendors don't buy it.
function sellPriceLine(it: ItemInfo | null): HTMLElement | null {
	if (!it || it.sellPrice === null) return null;
	if (it.sellPrice === 0) return h("p", { class: "hint" }, "No sell price");
	return h("p", { class: "row" }, h("span", { class: "lbl" }, "Sell Price"), moneyEl(it.sellPrice));
}

// Auction House or Vendor (#120): one unit on the auction house after the 5% cut (the 7-day typical
// price, else the lowest listing) against what a vendor pays, the better one marked.
function sellBlock(m: Market | null, it: ItemInfo | null): HTMLElement | null {
	const typ = m?.typical.status === "ok" ? m.typical.price : null;
	const low = m?.current && m.current.listed ? m.current.min : null;
	const vendor = it?.sellPrice ?? null;
	const c = sellChoice(typ, low, vendor);
	if (c.ah === null && vendor === null) return null;
	const basis = c.ahBasis === "typical" ? "Auction house: market price after the 5% cut. " : c.ahBasis === "lowest" ? "Auction house: lowest listing after the 5% cut. " : "";
	let verdict: string;
	if (vendor === null) verdict = "The vendor price comes with the next upload of the CraftWise companion.";
	else if (c.best === "vendor") verdict = c.ah === null ? "No auction house price: sell it to a vendor." : `Better sold to a vendor: ${skinMoney(vendor - c.ah).short} more per unit.`;
	else if (c.best === "ah" && vendor === 0) verdict = "Vendors don't buy it: the auction house is the only way to sell it.";
	else if (c.best === "ah") verdict = `Better sold on the auction house: ${skinMoney(c.ah! - vendor).short} more per unit.`;
	else verdict = "Vendors don't buy it and the auction house has no price.";
	return h(
		"div",
		{ class: "block" },
		h("h2", { class: "bar-head", id: "sell-title" }, "Auction House or Vendor"),
		h(
			"div",
			{ class: "inset" },
			h(
				"table",
				{ class: "tbl", "aria-labelledby": "sell-title" },
				h("thead", {}, h("tr", {}, h("th", { scope: "col" }, "Sell to"), h("th", { scope: "col", class: "r" }, "Per unit"))),
				h(
					"tbody",
					{},
					h(
						"tr",
						{ class: c.best === "ah" ? "sel" : null },
						h("td", {}, "Auction House", c.best === "ah" ? h("span", { class: "sr" }, ", better") : null),
						h("td", { class: "r" }, moneyEl(c.ah)),
					),
					h(
						"tr",
						{ class: c.best === "vendor" ? "sel" : null },
						h("td", {}, "Vendor", c.best === "vendor" ? h("span", { class: "sr" }, ", better") : null),
						h("td", { class: "r" }, vendor === 0 ? h("span", { class: "hint" }, "doesn't buy it") : moneyEl(vendor, "not known yet")),
					),
				),
			),
		),
		h("p", { class: "hint padx" }, basis + verdict),
	);
}

function listings(m: Market | null): HTMLElement | null {
	const tiers = m?.depth?.tiers;
	if (!m || !tiers || !tiers.length) {
		return h(
			"div",
			{ class: "block" },
			h("h2", { class: "bar-head" }, "Cheapest Listings"),
			h("p", { class: "hint padx" }, "Price levels are recorded for the items CraftWise tracks in detail. This item only has its lowest price."),
		);
	}
	let run = 0;
	const buyN = 100;
	const cost = buyCost(tiers, buyN);
	return h(
		"div",
		{ class: "block" },
		h("h2", { class: "bar-head", id: "lst-title" }, "Cheapest Listings"),
		h(
			"div",
			{ class: "inset" },
			h(
				"table",
				{ class: "tbl", "aria-labelledby": "lst-title" },
				h("thead", {}, h("tr", {}, h("th", { scope: "col" }, "Buyout Price"), h("th", { scope: "col", class: "r" }, "Available"), h("th", { scope: "col", class: "r" }, "Running Total"))),
				h(
					"tbody",
					{},
					tiers.map((t, i) => {
						run += t.qty;
						return h("tr", { class: i === 0 ? "sel" : null }, h("td", {}, moneyEl(t.price)), h("td", { class: "r num" }, t.qty.toLocaleString("en-US")), h("td", { class: "r num" }, h("span", { class: "hint" }, run.toLocaleString("en-US"))));
					}),
				),
			),
		),
		h(
			"p",
			{ class: "hint padx" },
			`From the scan ${age(nowSeconds() - m.depth!.t)}`,
			cost !== null ? `. Buying ${buyN} costs about ${skinMoney(cost).short} each.` : ".",
		),
	);
}

function daySeries(m: Market, today: number, n: number): Series {
	const from = (today - n + 1) * DAY + DAY / 2;
	const points: Point[] = m.days
		.filter((d) => d.day > today - n)
		.map((d) => ({ x: d.day * DAY + DAY / 2, lo: d.lo, typ: d.typ, hi: d.hi, qty: d.qtyMax, title: dayLabel(d.day, true) }));
	return {
		points,
		from,
		to: today * DAY + DAY / 2,
		gapAfter: DAY,
		xLabels: (x) => dayLabel(Math.floor(x / DAY)),
		tipRows: [
			["Low", "lo"],
			["Typical", "typ"],
			["High", "hi"],
		],
		qtyLabel: "Listed",
		summary: `Daily low, typical and high price over ${n} days, ${points.length} days with scans.`,
	};
}

function rawSeries(m: Market, now: number): Series {
	const points: Point[] = m.raw
		.filter((r) => r.tiers && r.tiers.length)
		// The solid line is the lowest price; the band runs up to the dearest of the cheapest levels.
		.map((r) => ({ x: r.t, lo: r.tiers![0]!.price, typ: r.tiers![0]!.price, hi: r.tiers![r.tiers!.length - 1]!.price, qty: r.total, title: timeLabel(r.t) }));
	return {
		points,
		from: now - 48 * 3600,
		to: now,
		gapAfter: 12 * 3600,
		xLabels: (x) => timeLabel(x).replace(" UTC", ""),
		tipRows: [
			["Lowest", "typ"],
			["Top tier", "hi"],
		],
		qtyLabel: "Listed",
		summary: `Lowest price at each detailed scan in the last 48 hours, ${points.length} scans.`,
	};
}

function fili(pos: string): SVGElement {
	return s(
		"svg",
		{ class: `fili ${pos}`, viewBox: "0 0 30 30", "aria-hidden": "true" },
		s("path", { d: "M2 28 V9 Q2 2 9 2 H28" }),
		pos.startsWith("t") ? s("path", { d: "M6 20 C6 11 9 7 14 6 C10 9 9 12 10 15 C11 12 13 11 15 12" }) : null,
	);
}

function divider(): HTMLElement {
	return h(
		"div",
		{ class: "divider", "aria-hidden": "true" },
		s("svg", { width: 34, height: 16, viewBox: "0 0 34 16" }, s("path", { d: "M33 9.5 C24 9.5 16 12 10 9.5 C4 7 6 1.5 11 2.6 C15 3.6 14 8.6 10.4 7.4" })),
		h("span", {}),
	);
}

void main();
