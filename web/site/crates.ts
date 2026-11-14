// Private page /me/crates (#129): Waylaid crates by cost per Merchant's Favor, and what to buy with Favor.
// From the character's snapshot (`crates`, `favor`, private API) with current Horde AH prices (public API).
import { type Browse, get, type House, pickHouse } from "./lib/api";
import { GUIDE_SOURCES } from "./lib/crateFavorGuide";
import * as C from "./lib/crates";
import { bottomTabs, clear, closeButton, errorBox, h, moneyEl, nowSeconds, onSkinChange, s, slot, statusBar, topBar } from "./lib/dom";
import { favouriteLabel, isFromAddon, syncAddonWatch, toggleFavourite } from "./lib/favs";
import { age, qualityClass } from "./lib/format";
import * as M from "./lib/me";

interface Item {
	name: string | null;
	quality: number | null;
}

const st = {
	chars: [] as M.Character[],
	key: null as string | null,
	snapshot: null as M.Doc | null,
	house: null as House | null,
	prices: new Map<number, C.AhPrice>(),
	items: new Map<number, Item>(),
	pricesFailed: false,
	crates: null as C.CrateList | null,
	merchants: [] as C.Merchant[],
	balance: null as C.Balance | null,
	rank: null as string | null,
	kind: null as string | null,
	heldOnly: false,
	pricedOnly: false,
	q: "",
	sel: null as number | null,
	open: new Set<string>(),
};

const app = document.getElementById("app")!;

// ---- URL -------------------------------------------------------------------------------------------

function readUrl(): void {
	const p = new URLSearchParams(location.search);
	st.key = p.get("c");
}

function writeUrl(push: boolean): void {
	const p = new URLSearchParams();
	if (st.key && st.chars.length > 1) p.set("c", st.key);
	const url = `/me/crates${p.size ? `?${p}` : ""}`;
	if (url !== location.pathname + location.search) (push ? history.pushState : history.replaceState).call(history, null, "", url);
}

// ---- Small pieces ----------------------------------------------------------------------------------

function n(v: number | null): string {
	return v === null ? "–" : v.toLocaleString("en-US");
}

function itemName(id: number | null, fallback: string): string {
	return (id !== null ? st.items.get(id)?.name : null) ?? fallback;
}

function quality(id: number | null): string {
	return qualityClass(id !== null ? (st.items.get(id)?.quality ?? null) : null);
}

function money(v: number | null): HTMLElement {
	return moneyEl(v === null ? null : Math.round(v));
}

// Where a price comes from and how old it is: "Horde AH, 2 h ago" or "snapshot (crafted), 5 h ago".
function priceSource(p: C.Priced | null, now: number): string {
	if (!p) return "no price";
	const when = p.t !== null ? `, ${age(now - p.t)}` : "";
	return p.source === "ah" ? `Horde AH now${when}` : `snapshot: ${p.label}${when}`;
}

function pricedCell(p: C.Priced | null, now: number): HTMLElement {
	return h("td", { class: "r wide-only", title: priceSource(p, now) }, money(p?.copper ?? null), p && p.source === "snapshot" ? h("span", { class: "cr-src hint", "aria-hidden": "true" }, "s") : null);
}

function favorCell(f: C.Favor | null): HTMLElement {
	if (!f) return h("td", { class: "r hint wide-only" }, "not known yet");
	const how = f.from === "seen" ? `measured${f.observed !== null ? ` n=${f.observed}` : ""}` : f.from;
	return h("td", { class: `r num wide-only${f.from.startsWith("guide") ? " cr-guide" : ""}`, title: C.favorText(f) }, String(f.amount), " ", h("span", { class: "hint cr-how" }, how));
}

function crateIcon(): SVGElement {
	return s(
		"svg",
		{ width: 40, height: 40, viewBox: "0 0 40 40", class: "cr-icon", "aria-hidden": "true" },
		s("path", { d: "M7 15 L20 9 L33 15 L33 29 L20 35 L7 29 Z M7 15 L20 21 L33 15 M20 21 V35", class: "under" }),
		s("path", { d: "M7 15 L20 21 L20 35 L7 29 Z", class: "face" }),
		s("path", { d: "M7 15 L20 9 L33 15 L33 29 L20 35 L7 29 Z M7 15 L20 21 L33 15 M20 21 V35 M12 18 L12 29 M27 24 L33 21", class: "over" }),
	);
}

// ---- Crates ------------------------------------------------------------------------------------------

function shownCrates(): C.Crate[] {
	return (st.crates?.list ?? []).filter(
		(c) =>
			(!st.rank || (c.rank ?? "Other") === st.rank) &&
			(!st.kind || (c.kind ?? "Other") === st.kind) &&
			(!st.heldOnly || c.held > 0) &&
			(!st.pricedOnly || c.fill !== null) &&
			C.matchesQuery(c, st.q),
	);
}

function pick(rank: string | null, kind: string | null, held = false): void {
	st.rank = rank;
	st.kind = kind;
	st.heldOnly = held;
	if (rank) st.open.add(rank);
	renderCrates();
}

function tree(): HTMLElement {
	const list = st.crates?.list ?? [];
	const entry = (label: string, count: number, current: boolean, onclick: () => void, cls = "entry") =>
		h("a", { href: "#crates", class: cls, "aria-current": current ? "page" : null, onclick: (e: Event) => (e.preventDefault(), onclick()) }, h("span", {}, label), h("span", { class: "n num" }, String(count)));
	const held = list.filter((c) => c.held > 0).length;
	return h(
		"nav",
		{ class: "tree", "aria-label": "Crate ranks" },
		entry("All crates", list.length, !st.rank && !st.heldOnly, () => pick(null, null), "entry cr-all"),
		held ? entry("Crates you carry", held, st.heldOnly, () => pick(null, null, true), "entry cr-all") : null,
		C.crateGroups(list).map((g) => {
			const open = st.open.has(g.rank) || st.rank === g.rank;
			const id = `rank-${g.rank.toLowerCase()}`;
			const plate = h(
				"button",
				{
					type: "button",
					class: "plate",
					"aria-expanded": String(open),
					"aria-controls": id,
					onclick: () => {
						if (st.open.has(g.rank)) st.open.delete(g.rank);
						else st.open.add(g.rank);
						renderCrates();
					},
				},
				h("span", {}, g.rank, " ", h("span", { class: "hint num" }, String(g.n))),
				h("span", { class: `pm${open ? "" : " plus"}`, "aria-hidden": "true" }),
			);
			return h(
				"div",
				{ class: "cat" },
				plate,
				h(
					"div",
					{ class: "entries", id, hidden: !open },
					entry(`All ${g.rank}`, g.n, st.rank === g.rank && !st.kind, () => pick(g.rank, null)),
					g.kinds.map((k) => entry(k.kind, k.n, st.rank === g.rank && st.kind === k.kind, () => pick(g.rank, k.kind))),
				),
			);
		}),
	);
}

function crateRow(c: C.Crate, now: number): HTMLElement {
	const name = itemName(c.id, c.name);
	const q = quality(c.id);
	const tags = [
		c.id === st.crates?.best ? h("span", { class: "cr-tag" }, "best to buy") : null,
		c.id === st.crates?.bestHeld ? h("span", { class: "cr-tag" }, "best you carry") : null,
		c.held > 0 ? h("span", { class: "cr-tag held" }, `you carry ${c.held}`) : null,
	];
	const fill = c.fill;
	const tr = h(
		"tr",
		{ "data-id": c.id, class: [c.id === st.sel ? "sel" : "", c.id === st.crates?.best || c.id === st.crates?.bestHeld ? "cr-best" : ""].join(" ").trim() || null },
		h(
			"td",
			{ class: "c-name" },
			h("a", { href: `/item/${c.id}`, class: `iname ${q}`, onclick: (e: Event) => selectCrate(e, c.id) }, slot(c.kind ?? name.replace(/^Waylaid Crate: /, ""), q), h("span", { class: "nm" }, name.replace(/^Waylaid Crate: /, ""))),
			tags.some(Boolean) ? h("span", { class: "cr-tags" }, tags) : null,
			h("span", { class: "phone-only hint sub2" }, fill ? `${fill.n ?? "?"} ${itemName(fill.id, fill.name)}` : "no bundle price", ", ", C.favorText(c.favor)),
		),
		h("td", { class: "wide-only" }, fill ? [`${fill.n ?? "?"} ${itemName(fill.id, fill.name)}`, fill.crafted ? h("span", { class: "hint" }, " crafted") : null] : h("span", { class: "hint" }, c.bundles.length ? "no price" : "list not read")),
		fill ? pricedCell(fill.cost, now) : h("td", { class: "r wide-only" }, money(null)),
		pricedCell(c.crate, now),
		h("td", { class: "r wide-only" }, money(c.total)),
		favorCell(c.favor),
		h("td", { class: "r" }, c.perFavor !== null ? money(c.perFavor) : h("span", { class: "hint" }, "–")),
		h("td", { class: "r" }, c.fillPerFavor !== null ? money(c.fillPerFavor) : h("span", { class: "hint" }, "–")),
	);
	tr.addEventListener("click", (e) => {
		if ((e.target as HTMLElement).closest("a")) return;
		setSel(c.id);
	});
	return tr;
}

function selectCrate(e: Event, id: number): void {
	const me = e as MouseEvent;
	if (me.ctrlKey || me.metaKey || me.shiftKey || me.button === 1) return;
	if (st.sel === id) return; // a second click opens the item page
	e.preventDefault();
	setSel(id);
}

function setSel(id: number): void {
	st.sel = id;
	for (const tr of document.querySelectorAll<HTMLElement>(".cr-table tbody tr")) tr.classList.toggle("sel", tr.dataset.id === String(id));
	renderDetail();
}

function crateTable(list: C.Crate[], now: number): HTMLElement {
	const th = (label: string, cls = "", spoken?: string) => h("th", { class: cls || null, title: spoken ?? null }, label);
	return h(
		"table",
		{ class: "tbl cr-table", "aria-labelledby": "cr-res" },
		h(
			"thead",
			{},
			h(
				"tr",
				{},
				th("Crate", "c-name"),
				th("Cheapest Bundle", "wide-only"),
				th("Bundle Cost", "r wide-only"),
				th("Crate Price", "r wide-only"),
				th("Total", "r wide-only"),
				th("Favor", "r wide-only"),
				th("Per Favor", "r", "Crate and cheapest bundle per Favor point"),
				th("Fill per Favor", "r", "Cheapest bundle per Favor point, for a crate you already have"),
			),
		),
		h("tbody", {}, list.length ? list.map((c) => crateRow(c, now)) : h("tr", {}, h("td", { class: "empty", colspan: 8 }, (st.crates?.list.length ?? 0) ? "No crates match." : "No Waylaid crate in this snapshot yet."))),
	);
}

const detailBox = h("div", { class: "cr-detail" });
const footLeft = h("span", { class: "hint" });
const favBtn = h("button", { type: "button", class: "wbtn dark", disabled: true }, "Add Bundle to Favourites");
const histBtn = h("a", { class: "wbtn", "aria-disabled": "true" }, "Price History");

function renderDetail(): void {
	const now = nowSeconds();
	const c = st.crates?.list.find((x) => x.id === st.sel) ?? null;
	const fill = c?.fill ?? null;
	favBtn.disabled = !fill?.id || isFromAddon(fill.id);
	favBtn.textContent = fill?.id ? favouriteLabel(fill.id, "Bundle") : "Add Bundle to Favourites";
	if (fill?.id) {
		histBtn.setAttribute("href", `/item/${fill.id}`);
		histBtn.removeAttribute("aria-disabled");
		histBtn.setAttribute("aria-label", `Price history of ${itemName(fill.id, fill.name)}`);
	} else {
		histBtn.removeAttribute("href");
		histBtn.setAttribute("aria-disabled", "true");
	}
	if (!c) {
		clear(detailBox);
		return;
	}
	const row = (label: string, value: Node | string) => h("p", { class: "row" }, h("span", { class: "lbl" }, label), typeof value === "string" ? h("span", {}, value) : value);
	const priceLine = (p: C.Priced | null) => h("span", {}, money(p?.copper ?? null), h("span", { class: "hint sub2" }, priceSource(p, now)));
	clear(
		detailBox,
		h(
			"div",
			{ class: "pane cr-tipcol" },
			h("span", { class: "tiptab" }, "CraftWise"),
			h(
				"div",
				{ class: "tip" },
				h("p", { class: `tip-title ${quality(c.id)}` }, itemName(c.id, c.name)),
				c.bundles.length ? h("p", { class: "cr-use" }, "Fill the crate with any bundle from the following list:") : h("p", { class: "hint" }, "The fill list was not read from the tooltip yet."),
				c.bundles.map((b) =>
					h(
						"p",
						{ class: `row cr-bundle${b.best ? " best" : ""}` },
						h("span", {}, `${b.n ?? "?"} `, b.id !== null ? h("a", { href: `/item/${b.id}`, class: quality(b.id) }, itemName(b.id, b.name)) : h("span", {}, b.name), b.best ? h("span", { class: "hint" }, " cheapest") : null, b.crafted ? h("span", { class: "hint" }, " crafted") : null),
						priceLine(b.cost),
					),
				),
				h("p", { class: "addon" }, "Worked out"),
				row("Crate", priceLine(c.crate)),
				row("Cheapest bundle", money(c.fill?.cost?.copper ?? null)),
				row("Total", money(c.total)),
				row("Favor per crate", c.favor ? C.favorText(c.favor) : "not known yet (not measured, no guide value)"),
				row("Cost per Favor", c.perFavor !== null ? money(c.perFavor) : "–"),
				row("Fill only per Favor", c.fillPerFavor !== null ? money(c.fillPerFavor) : "–"),
				c.held > 0 ? row("You carry", String(c.held)) : null,
			),
		),
		h(
			"section",
			{ class: "pane cr-how-pane", "aria-labelledby": "cr-how-h" },
			h("h3", { class: "bar-head", id: "cr-how-h" }, "How this is worked out"),
			h(
				"p",
				{ class: "cr-text" },
				"Bundles come from each crate's tooltip as the addon read it. Prices are the Horde AH's current lowest where the site has a newer scan than the snapshot; otherwise the snapshot's own price (marked s), which may be a crafted cost from your recipes or a vendor price. Favor is what the tooltip states or what you gained when a crate left your bags (measured). Where neither was seen, the value published by guides from the beta is shown and labelled as such; it is not measured. The 15% chance of double Favor is not counted.",
			),
			guideNote(),
		),
	);
}

function guideNote(): HTMLElement {
	return h(
		"p",
		{ class: "hint note" },
		"Guide values (beta data, not confirmed by Blizzard): ",
		GUIDE_SOURCES.map((src, i) => [i ? ", " : "", h("a", { href: src.url, rel: "noopener noreferrer", target: "_blank", class: "cr-link" }, src.label), ` (updated ${src.updated})`]),
		". Expert herbs, curiosities and parts only follow the guides' rule (raw materials 15, crafted goods 30); Artisan crates are in no guide.",
	);
}

const crateBox = h("div", { class: "results", id: "crates" });
const sideBox = h("div", { class: "side" });
const treeToggle = h("button", { type: "button", class: "wbtn dark cat-toggle", "aria-expanded": "false", "aria-controls": "cr-well" }, "Crate Ranks");
const searchInput = h("input", { class: "winput", type: "search", placeholder: "Search crates or goods", autocomplete: "off", "aria-label": "Search crates or goods" });
treeToggle.addEventListener("click", () => {
	const open = treeToggle.getAttribute("aria-expanded") !== "true";
	treeToggle.setAttribute("aria-expanded", String(open));
	app.classList.toggle("tree-open", open);
});
searchInput.addEventListener("input", () => {
	st.q = searchInput.value;
	renderCrates();
});
favBtn.addEventListener("click", () => {
	const fill = st.crates?.list.find((x) => x.id === st.sel)?.fill;
	if (!fill?.id) return;
	toggleFavourite(fill.id);
	renderDetail();
});

function renderCrates(): void {
	const now = nowSeconds();
	const list = shownCrates();
	if (st.sel === null || !list.some((c) => c.id === st.sel)) st.sel = st.crates?.best ?? list[0]?.id ?? null;
	const title = st.heldOnly ? "Crates You Carry" : st.rank ? (st.kind ? `${st.rank} ${st.kind}` : `${st.rank} Crates`) : "All Crates";
	const pricedBox = h("input", { type: "checkbox", class: "wcheck", id: "cr-priced", checked: st.pricedOnly });
	pricedBox.addEventListener("change", () => {
		st.pricedOnly = pricedBox.checked;
		renderCrates();
	});
	const spend = st.merchants.reduce((sum, m) => sum + m.wares.length, 0);
	clear(
		sideBox,
		treeToggle,
		h("div", { class: "searchrow", role: "search" }, h("label", { class: "search" }, s("svg", { width: 15, height: 15, viewBox: "0 0 16 16", "aria-hidden": "true", class: "mag" }, s("circle", { cx: 6.5, cy: 6.5, r: 4.6 }), s("path", { d: "M10 10 L14 14" })), searchInput)),
		h(
			"div",
			{ class: "inset well", id: "cr-well" },
			tree(),
			st.merchants.length
				? h(
						"div",
						{ class: "cr-spendat" },
						h("p", { class: "lbl" }, "Spend Favor at"),
						st.merchants.map((m) => h("p", {}, h("a", { href: `#m-${m.npc ?? m.name}` }, [m.name, m.zone].filter(Boolean).join(", ")))),
						h("p", { class: "hint" }, `${st.merchants.map((m) => m.faction).filter(Boolean).join(", ")}${st.merchants.some((m) => m.faction) ? ", " : ""}${spend} items for Favor`),
					)
				: null,
		),
	);
	const snapAge = st.crates?.snapT != null ? age(now - st.crates.snapT) : null;
	const scanAge = st.house?.lastScan != null ? age(now - st.house.lastScan) : null;
	clear(
		crateBox,
		h(
			"div",
			{ class: "filters" },
			h("h2", { class: "res-title", id: "cr-res" }, title, " ", h("span", { class: "hint count" }, `${list.length}, cheapest Favor first`)),
			h("span", { class: "grow" }),
			h("label", { class: "cr-check", for: "cr-priced" }, pricedBox, h("span", {}, "Only crates with a bundle price")),
		),
		h("div", { class: "inset" }, h("div", { class: "tscroll" }, crateTable(list, now))),
		h(
			"p",
			{ class: "hint note" },
			st.pricesFailed
				? "Current AH prices could not be read: every price is the snapshot's."
				: `Prices: the Horde AH's current lowest (last scan ${scanAge ?? "unknown"}) where it is newer than the snapshot (${snapAge ?? "time unknown"}); s = the snapshot's price (hover a price for its source). Favor: measured or tooltip from your turn-ins; guide = published beta values, not measured.`,
		),
		detailBox,
	);
	const ids = (st.crates?.list ?? []).map((c) => c.id).sort((a, b) => a - b);
	footLeft.textContent = ids.length ? `Crates ${ids[0]} to ${ids[ids.length - 1]}.` : "";
	renderDetail();
}

// ---- Spend your Favor --------------------------------------------------------------------------------

const spendBox = h("section", { class: "cr-spend", "aria-labelledby": "sp-title", id: "spend" });

function repBar(m: C.Merchant): HTMLElement | null {
	if (!m.rep) return null;
	const part = m.rep.value - m.rep.min;
	const whole = m.rep.max - m.rep.min;
	const text = `${m.standingNow ?? "Standing"} ${n(part)} / ${n(whole)}`;
	const el = h("div", { class: "sbar cr-rep", role: "img", "aria-label": `${m.faction ?? "Reputation"}: ${text}` }, h("i", {}), h("b", {}, text));
	(el.firstChild as HTMLElement).style.width = `${(M.share(part, whole) * 100).toFixed(1)}%`;
	return el;
}

function wareRow(w: C.Ware, m: C.Merchant, now: number): HTMLElement {
	const name = itemName(w.id, w.name);
	const q = quality(w.id);
	const notes = C.wareNotes(w);
	const bal = st.balance?.balance ?? null;
	const short = bal !== null && w.favor > bal ? w.favor - bal : 0;
	const req = w.req
		? w.reqMet === false
			? h("span", { class: "cr-short" }, w.req, h("span", { class: "hint" }, ` (you: ${m.standingNow})`))
			: h("span", {}, w.req, w.reqMet ? h("span", { class: "hint" }, " (met)") : null)
		: h("span", { class: "hint" }, "–");
	const value = w.value
		? h("span", { title: w.value.basis === "current" ? `Horde AH lowest${w.value.t !== null ? `, ${age(now - w.value.t)}` : ""}, after the 5% cut` : "7-day typical at the Horde AH (not listed now), after the 5% cut" }, money(w.value.copper), w.value.basis === "typical" ? h("span", { class: "cr-src hint", "aria-hidden": "true" }, "t") : null)
		: h("span", { class: "hint" }, "unknown");
	return h(
		"tr",
		{ class: w.unusable || w.known ? "cr-dim" : null },
		h(
			"td",
			{ class: "c-name" },
			w.id !== null ? h("a", { href: `/item/${w.id}`, class: `iname ${q}` }, slot(name, q), h("span", { class: "nm" }, name)) : h("span", { class: `iname ${q}` }, slot(name, q), h("span", { class: "nm" }, name)),
			notes.length ? h("span", { class: "hint sub2" }, notes.join(", ")) : null,
			h("span", { class: "phone-only hint sub2" }, `${w.favor} Favor${w.req ? `, needs ${w.req}` : ""}`),
		),
		h("td", { class: "r num wide-only" }, String(w.favor), w.copper ? [" + ", money(w.copper)] : null, short ? h("span", { class: "hint sub2" }, `${short} short`) : null),
		h("td", { class: "r wide-only" }, value),
		h("td", { class: "r" }, w.perFavor !== null ? money(w.perFavor) : h("span", { class: "hint" }, "unknown")),
		h("td", { class: "wide-only" }, req),
	);
}

function renderSpend(): void {
	const now = nowSeconds();
	const b = st.balance;
	clear(
		spendBox,
		h("h2", { class: "res-title", id: "sp-title" }, "Spend Your Favor", b?.balance != null ? h("span", { class: "hint count" }, ` you have ${n(b.balance)}${b.max !== null ? ` of ${n(b.max)}` : ""}`) : null),
		st.merchants.length
			? st.merchants.map((m) =>
					h(
						"div",
						{ class: "cr-merchant", id: `m-${m.npc ?? m.name}` },
						h(
							"div",
							{ class: "cr-mhead" },
							h("h3", { class: "lbl" }, [m.name, m.zone].filter(Boolean).join(", ")),
							m.faction ? h("span", { class: "hint" }, m.faction) : null,
							h("span", { class: "grow" }),
							repBar(m),
						),
						h(
							"div",
							{ class: "inset" },
							h(
								"div",
								{ class: "tscroll" },
								h(
									"table",
									{ class: "tbl cr-wares" },
									h("thead", {}, h("tr", {}, h("th", { class: "c-name" }, "Item"), h("th", { class: "r wide-only" }, "Favor"), h("th", { class: "r wide-only" }, "AH Value"), h("th", { class: "r" }, "Value per Favor"), h("th", { class: "wide-only" }, "Needs"))),
									h("tbody", {}, m.wares.length ? m.wares.map((w) => wareRow(w, m, now)) : h("tr", {}, h("td", { class: "empty", colspan: 5 }, "No items for Favor recorded."))),
								),
							),
						),
						h(
							"p",
							{ class: "hint note" },
							`List recorded ${m.t !== null ? age(now - m.t) : "at an unknown time"}${m.standing ? ` at ${m.standing}` : ""}.`,
							m.full ? "" : " The merchant window's filter was not \"All\": the list may miss items.",
						),
					),
				)
			: h("p", { class: "notice" }, "No Favor merchant recorded yet. Open a merchant that sells for Merchant's Favor (e.g. Pawani in The Barrens) with the addon on."),
		h("p", { class: "hint note" }, "AH value: the Horde AH's current lowest price after the 5% cut (t = the 7-day typical, for items not listed now), for the whole purchase, minus any copper the merchant asks on top, per Favor point. Items without an AH price are unknown; many Favor items cannot be sold."),
	);
}

// ---- Page --------------------------------------------------------------------------------------------

let redraw: (() => void) | null = null;
onSkinChange(() => redraw?.());

function charPicker(): HTMLElement | null {
	if (st.chars.length < 2) return null;
	const sel = h("select", { class: "winput", id: "cr-char", "aria-label": "Character" }, st.chars.map((c) => h("option", { value: c.key, selected: c.key === st.key }, M.fullName(c))));
	sel.addEventListener("change", () => {
		st.key = sel.value;
		writeUrl(true);
		void loadChar();
	});
	return sel;
}

function shell(parts: Node[]): void {
	const b = st.balance;
	const frame = h(
		"section",
		{ class: "frame cr", "aria-labelledby": "cr-title" },
		h("div", { class: "medal", "aria-hidden": "true" }, h("span", { class: "medal-letter cr-medal" }, crateIcon())),
		h("div", { class: "wtitle" }, h("h1", { id: "cr-title" }, "Waylaid Crates")),
		closeButton("/", "Close and go to the auction house"),
		h(
			"div",
			{ class: "statusrow" },
			statusBar(st.house),
			h("span", { class: "grow" }),
			charPicker(),
			b
				? h(
						"p",
						{ class: "inset cr-balance" },
						h("span", { class: "lbl" }, b.name),
						h("span", { class: "num" }, b.balance !== null ? n(b.balance) : "–"),
						b.max !== null ? h("span", { class: "hint" }, `of ${n(b.max)}`) : null,
					)
				: null,
		),
		...parts,
	);
	const who = st.chars.find((c) => c.key === st.key);
	clear(
		app,
		topBar(who ? `Private: ${M.fullName(who)}` : "Private: signed in with Cloudflare Access", "crates"),
		h("main", { class: "shell" }, frame, bottomTabs("crates")),
	);
}

function render(): void {
	redraw = render;
	if (!st.snapshot) {
		shell([h("p", { class: "notice" }, st.chars.length ? "No snapshot uploaded for this character yet." : "No characters uploaded yet. Create an upload token on My Characters and put it into the companion app.")]);
		return;
	}
	renderCrates();
	renderSpend();
	shell([
		h("div", { class: "cols" }, sideBox, crateBox),
		h("div", { class: "footbar" }, footLeft, h("span", { class: "grow" }), favBtn, histBtn),
		spendBox,
	]);
}

function loading(text: string): void {
	redraw = () => loading(text);
	shell([h("p", { class: "notice", "aria-busy": "true" }, text)]);
}

function failed(text: string): void {
	redraw = () => failed(text);
	shell([errorBox(text)]);
}

function shape(): void {
	const data = st.snapshot?.data ?? null;
	const snapT = typeof (data as { t?: unknown } | null)?.t === "number" ? (data as { t: number }).t : (st.snapshot?.t ?? null);
	st.crates = C.crateList(data, snapT, st.prices);
	st.merchants = C.merchants(data, st.prices);
	st.balance = C.favorBalance(data);
}

// Current Horde AH prices, names and qualities of the crates, bundles and Favor wares (100 IDs per request).
async function loadPrices(): Promise<void> {
	const data = st.snapshot?.data ?? null;
	if (!st.house) {
		st.pricesFailed = true;
		return;
	}
	const ids = [...new Set([...C.crateIds(data), ...C.favorIds(data)])].filter((id) => !st.prices.has(id) && !st.items.has(id));
	for (let i = 0; i < ids.length; i += 100) {
		const chunk = ids.slice(i, i + 100);
		try {
			const b = await get<Browse>(`/api/browse?house=${encodeURIComponent(st.house.key)}&ids=${chunk.join(",")}`);
			for (const it of b.items) {
				st.items.set(it.id, { name: it.name, quality: it.quality });
				if (it.current) st.prices.set(it.id, { t: it.current.t, min: it.current.min, listed: it.current.listed, typical: it.typical.status === "ok" ? it.typical.price : null });
			}
		} catch {
			st.pricesFailed = true;
			return;
		}
	}
}

async function loadChar(): Promise<void> {
	const key = st.key;
	if (!key) return render();
	loading("Loading the character's crates");
	try {
		const docs = await get<M.CharacterDocs>(`/api/me/characters/${encodeURIComponent(key)}`);
		if (key !== st.key) return;
		st.snapshot = docs.snapshot;
	} catch (err) {
		failed(`The character could not be loaded: ${(err as Error).message}.`);
		return;
	}
	await loadPrices();
	if (key !== st.key) return;
	shape();
	st.sel = null;
	render();
}

function latestChar(): string | null {
	let best: M.Character | null = null;
	for (const c of st.chars) if (!best || (c.snapshotT ?? 0) > (best.snapshotT ?? 0)) best = c;
	return best?.key ?? null;
}

async function main(): Promise<void> {
	readUrl();
	loading("Loading your crates");
	void syncAddonWatch().then((changed) => changed && st.crates && renderDetail());
	try {
		st.chars = (await get<{ characters: M.Character[] }>("/api/me/characters")).characters;
	} catch (err) {
		failed(`Your private data could not be loaded: ${(err as Error).message}. Reload the page to sign in again.`);
		return;
	}
	try {
		st.house = pickHouse((await get<{ houses: House[] }>("/api/houses")).houses);
	} catch {
		st.house = null;
	}
	if (!st.chars.some((c) => c.key === st.key)) st.key = latestChar();
	writeUrl(false);
	await loadChar();
}

window.addEventListener("popstate", () => {
	const before = st.key;
	readUrl();
	if (!st.chars.some((c) => c.key === st.key)) st.key = latestChar();
	if (st.key !== before) void loadChar();
});

void main();
