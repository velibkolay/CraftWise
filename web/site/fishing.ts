// Private fishing page /me/fishing (#128): where this character fishes for the most gold. Zones and spots
// from the fishing document (snapshot.fishing with fishingZones), valued again with the Horde AH's prices
// of now where the document carries the item lists. Behind Cloudflare Access like /me.
import { type Browse, get, type House, pickHouse } from "./lib/api";
import { bottomTabs, clear, closeButton, errorBox, h, moneyEl, nowSeconds, onSkinChange, slot, topBar } from "./lib/dom";
import * as F from "./lib/fishing";
import { age, qualityClass } from "./lib/format";
import * as M from "./lib/me";
import { bar, barHead, kv, n, pane, sideTabs, well } from "./lib/mepage";

interface Item {
	name: string | null;
	quality: number | null;
}

const st = {
	readOnly: false,
	chars: [] as M.Character[],
	key: null as string | null,
	docs: null as M.CharacterDocs | null,
	house: null as House | null,
	quotes: new Map<number, F.AhQuote>(),
	pricesT: null as number | null,
	pricesFailed: false,
	items: new Map<number, Item>(),
	sort: "hour" as F.SortBy,
	sel: null as string | null,
};

const app = document.getElementById("app")!;

// ---- URL ---------------------------------------------------------------------------------------------

function readUrl(): void {
	const p = new URLSearchParams(location.search);
	st.key = p.get("c");
	st.sort = p.get("by") === "catch" ? "catch" : "hour";
}

function writeUrl(push: boolean): void {
	const p = new URLSearchParams();
	if (st.key) p.set("c", st.key);
	if (st.sort !== "hour") p.set("by", st.sort);
	const url = `/me/fishing${p.size ? `?${p}` : ""}`;
	if (url !== location.pathname + location.search) (push ? history.pushState : history.replaceState).call(history, null, "", url);
}

function charHref(key: string): string {
	return `/me/fishing?${new URLSearchParams({ c: key })}`;
}

function pickChar(e: Event, key: string): void {
	const me = e as MouseEvent;
	if (me.ctrlKey || me.metaKey || me.shiftKey || me.button === 1) return;
	e.preventDefault();
	if (key === st.key) return;
	st.key = key;
	st.sel = null;
	writeUrl(true);
	void loadChar();
}

// ---- Small pieces --------------------------------------------------------------------------------------

function itemName(id: number): string {
	return st.items.get(id)?.name ?? `Item ${id}`;
}

function quality(id: number): string {
	return qualityClass(st.items.get(id)?.quality ?? null);
}

function rangeEl(low: number | null, high: number | null): HTMLElement {
	if (low === null) return moneyEl(null);
	if (high === null || high === low) return moneyEl(low);
	return h("span", { class: "range" }, moneyEl(low), h("span", { "aria-hidden": "true" }, " – "), h("span", { class: "sr" }, " to "), moneyEl(high));
}

// The value now, with the snapshot's figure under it when today's prices changed it.
function valueCell(now: number | null, high: number | null, snap: number | null, revalued: boolean): HTMLElement {
	// The snapshot's figure only as a tooltip here; the detail pane says it in words.
	const changed = revalued && snap !== null && now !== null && snap !== now;
	return h("td", { class: "r", title: changed ? `At the snapshot: ${moneyText(snap)}` : null }, rangeEl(now, high));
}

function hourCell(r: { perHour: number | null; timed: number | null; timedTooFew: boolean }, snap: number | null, revalued: boolean): HTMLElement {
	if (r.perHour !== null) return valueCell(r.perHour, null, snap, revalued);
	if (r.timedTooFew) return h("td", { class: "r" }, h("span", { class: "hint" }, r.timed !== null ? `${r.timed} timed, too few` : "too few timed"));
	return h("td", { class: "r" }, h("span", { class: "hint" }, "not timed"));
}

function sampleText(r: F.Row): string {
	const what = r.source === "ref" ? (r.n === 1 ? "loot recorded" : "loots recorded") : r.n === 1 ? "catch" : "catches";
	return `${n(r.n)} ${what}`;
}

function smallFlag(small: boolean): HTMLElement | null {
	return small ? h("span", { class: "flag" }, "small sample") : null;
}

function sourceEl(r: F.Row): HTMLElement {
	return h("span", { class: `src ${r.source}` }, r.source === "ref" ? "Reference" : "Your catches");
}

// ---- Tables --------------------------------------------------------------------------------------------

function pickRow(key: string): void {
	st.sel = key;
	render();
	document.querySelector<HTMLElement>(`[data-key="${CSS.escape(key)}"] .rowpick`)?.focus();
	if (matchMedia("(max-width: 760px)").matches) document.getElementById("detail")?.scrollIntoView({ block: "start" });
}

function rowPick(key: string, ...label: (Node | string | null)[]): HTMLElement {
	return h("button", { type: "button", class: "rowpick", "aria-pressed": String(st.sel === key), onclick: () => pickRow(key) }, ...label);
}

function otherEl(r: F.ZoneRow): HTMLElement {
	const o = r.other;
	if (!o) return h("span", { class: "hint" }, "–");
	return h("span", { class: "other" }, h("span", { class: "hint" }, o.source === "ref" ? "Reference " : "Yours "), rangeEl(o.perCatch, o.perCatchHigh), o.source === "own" ? h("span", { class: "hint" }, ` (n = ${n(o.n)})`) : null);
}

function zoneTable(rows: F.ZoneRow[]): HTMLElement {
	return well(
		h(
			"table",
			{ class: "tbl wide fish" },
			h(
				"thead",
				{},
				h(
					"tr",
					{},
					h("th", {}, "Zone"),
					h("th", { class: "wide-only" }, "Source"),
					h("th", { class: "r wide-only" }, "Sample"),
					h("th", { class: "r" }, "Per Catch"),
					h("th", { class: "r wide-only" }, "Compared"),
					h("th", { class: "r" }, "Per Hour"),
				),
			),
			h(
				"tbody",
				{},
				rows.length
					? rows.map((r) =>
							h(
								"tr",
								{ class: st.sel === r.key ? "sel" : null, "data-key": r.key },
								h(
									"td",
									{ class: "namecell" },
									rowPick(r.key, r.zone || "Unknown zone"),
									smallFlag(r.small),
									h("span", { class: "phone-only hint sub2" }, r.source === "ref" ? "Reference, " : "Your catches, ", sampleText(r)),
									r.other ? h("span", { class: "phone-only sub2" }, otherEl(r)) : null,
									r.compare?.outside ? h("span", { class: "flag diff" }, `${r.compare.outside} ${r.compare.outside === 1 ? "item differs" : "items differ"} from the reference`) : null,
								),
								h("td", { class: "wide-only" }, sourceEl(r)),
								h("td", { class: "r num wide-only" }, sampleText(r)),
								valueCell(r.perCatch, r.perCatchHigh, r.snap.perCatch, r.revalued),
								h("td", { class: "r wide-only" }, otherEl(r)),
								hourCell(r, r.snap.perHour, r.revalued),
							),
						)
					: h("tr", {}, h("td", { class: "empty", colspan: 6 }, "No zones in this fishing log.")),
			),
		),
	);
}

function spotTable(rows: F.Row[], first: string, empty: string): HTMLElement {
	return well(
		h(
			"table",
			{ class: "tbl wide fish" },
			h("thead", {}, h("tr", {}, h("th", {}, first), h("th", { class: "r wide-only" }, "Catches"), h("th", { class: "r" }, "Per Catch"), h("th", { class: "r" }, "Per Hour"))),
			h(
				"tbody",
				{},
				rows.length
					? rows.map((r) => {
							const where = r.kind === "water" ? F.waterLabel(r.water, null) : [r.zone, r.sub].filter(Boolean).join(", ");
							const water = r.kind === "spot" ? F.waterLabel(r.water, r.pool) : null;
							return h(
								"tr",
								{ class: st.sel === r.key ? "sel" : null, "data-key": r.key },
								h(
									"td",
									{ class: "namecell" },
									rowPick(r.key, where || "Unknown place"),
									smallFlag(r.small),
									water ? h("span", { class: "hint sub2" }, water) : null,
									h("span", { class: "phone-only hint sub2" }, sampleText(r)),
								),
								h("td", { class: "r num wide-only" }, n(r.n)),
								valueCell(r.perCatch, r.perCatchHigh, r.snap.perCatch, r.revalued),
								hourCell(r, r.snap.perHour, r.revalued),
							);
						})
					: h("tr", {}, h("td", { class: "empty", colspan: 4 }, empty)),
			),
		),
	);
}

function poolTable(pools: F.PoolRow[]): HTMLElement {
	return well(
		h(
			"table",
			{ class: "tbl wide fish" },
			h(
				"thead",
				{},
				h("tr", {}, h("th", {}, "Pool"), h("th", { class: "r wide-only" }, "Visits"), h("th", { class: "r" }, "Catches per Visit"), h("th", { class: "r" }, "Per Visit"), h("th", { class: "r wide-only" }, "Seen, Not Fished")),
			),
			h(
				"tbody",
				{},
				pools.map((p) =>
					h(
						"tr",
						{ class: st.sel === p.key ? "sel" : null, "data-key": p.key },
						h(
							"td",
							{ class: "namecell" },
							rowPick(p.key, p.name),
							smallFlag(p.small),
							h("span", { class: "hint sub2" }, [p.catches !== null ? `${n(p.catches)} catches` : null, p.going ? `${p.going} visit${p.going === 1 ? "" : "s"} going on` : null].filter(Boolean).join(", ")),
							h("span", { class: "phone-only hint sub2" }, `${n(p.visits)} visits${p.notFished ? `, ${p.notFished} seen, not fished` : ""}`),
						),
						h("td", { class: "r num wide-only" }, n(p.visits)),
						h("td", { class: "r num" }, p.avg !== null ? `${p.min}–${p.max}, avg ${p.avg}` : "–"),
						h("td", { class: "r" }, moneyEl(p.perVisit)),
						h("td", { class: "r num wide-only" }, n(p.notFished)),
					),
				),
			),
		),
	);
}

// ---- Detail: what the selected row's catches are made of ----------------------------------------------------

function pctText(x: number | null): string {
	if (x === null) return "–";
	const p = x * 100;
	return p === 0 ? "0%" : p < 0.1 ? "<0.1%" : `${p.toFixed(p >= 10 ? 0 : 1)}%`;
}

function diffText(d: number | null): string {
	if (d === null) return "–";
	const p = d * 100;
	if (Math.abs(p) < 0.05) return "0.0";
	return `${p > 0 ? "+" : "−"}${Math.abs(p).toFixed(1)}`;
}

// Own shares with their 95% interval against the reference's share, item by item.
function compareTable(c: F.Compare, ownMin: number): HTMLElement[] {
	const own = c.own;
	const ref = c.ref;
	const head = [
		kv("Your catches", own ? h("span", {}, rangeEl(own.perCatch, own.perCatchHigh), " per catch") : h("span", { class: "hint" }, "none"), own ? `n = ${n(own.n)} catches${own.n < ownMin ? `: a small sample, fewer than ${ownMin}` : ""}.` : null),
		kv("Reference", ref ? h("span", {}, rangeEl(ref.perCatch, ref.perCatchHigh), " per catch") : h("span", { class: "hint" }, "not in the reference"), ref ? `n = ${n(ref.n)} recorded loots.` : null),
	];
	const rows = c.lines.map((l) => {
		const name = itemName(l.id);
		const q = quality(l.id);
		return h(
			"tr",
			{ class: l.outside ? "outside" : null },
			h("td", { class: "itemcell" }, h("a", { class: "iname", href: `/item/${l.id}` }, slot(name, q), h("span", { class: `nm ${q}` }, name))),
			h(
				"td",
				{ class: "r num" },
				l.share !== null ? pctText(l.share) : "–",
				l.hits !== null && l.n !== null ? h("span", { class: "hint sub2" }, `${n(l.hits)} of ${n(l.n)}, ${pctText(l.lo)}–${pctText(l.hi)}`) : null,
			),
			h("td", { class: "r num" }, pctText(l.refShare)),
			h("td", { class: "r num" }, l.outside ? h("span", { class: "flag diff" }, diffText(l.diff)) : diffText(l.diff), l.outside ? h("span", { class: "sr" }, " outside your interval") : null),
			h("td", { class: "r wide-only" }, rangeEl(l.ownPerCatch, null), h("span", { class: "hint sub2" }, "ref ", rangeEl(l.refPerCatch, l.refPerCatchHigh))),
		);
	});
	return [
		h("div", {}, ...head.flat()),
		well(
			h(
				"table",
				{ class: "tbl wide fish cmp" },
				h(
					"thead",
					{},
					h("tr", {}, h("th", {}, "Item"), h("th", { class: "r" }, "Yours"), h("th", { class: "r" }, "Reference"), h("th", { class: "r" }, "Diff, pts"), h("th", { class: "r wide-only" }, "Per Catch Now")),
				),
				h("tbody", {}, rows.length ? rows : h("tr", {}, h("td", { class: "empty", colspan: 5 }, "Nothing to compare."))),
			),
		),
	];
}

function zoneDetail(r: F.ZoneRow, page: F.FishingPage): HTMLElement {
	const parts: (HTMLElement | null)[] = [barHead("Catch"), h("p", { class: "lbl dtitle", id: "detail" }, r.zone || "Unknown zone")];
	if (r.revalued && r.snap.perCatch !== null && r.snap.perCatch !== r.perCatch) parts.push(h("p", { class: "hint note" }, `At the snapshot (the addon's prices then): ${moneyText(r.snap.perCatch)} per catch from ${r.source === "ref" ? "the reference" : "your catches"}.`));
	const c = r.compare;
	if (c) parts.push(...compareTable(c, page.ownMin));
	else if (r.lines) {
		parts.push(h("div", {}, ...kv(r.source === "ref" ? "Reference" : "Your catches", h("span", {}, rangeEl(r.perCatch, r.perCatchHigh), " per catch"), sampleText(r) + ".")));
		parts.push(itemsTable(r.lines, r));
	} else parts.push(h("p", { class: "hint pad" }, "This upload has no item list, so the values are the ones in the snapshot. Update CraftWise and the companion to see them with today's prices."));
	parts.push(
		h(
			"div",
			{},
			...kv(
				"Value per hour",
				r.perHour !== null ? moneyEl(r.perHour) : h("span", { class: "hint" }, r.timedTooFew ? "too few timed catches" : "not timed"),
				r.timed !== null && r.minutes !== null ? `${n(r.timed)} timed catches in ${r.minutes.toLocaleString("en-US")} min${r.perHour === null ? `; it takes ${page.ownMin}` : ""}.` : null,
			),
		),
	);
	for (const w of r.waters) {
		parts.push(h("h3", { class: "auchead" }, h("span", { class: "lbl" }, F.waterLabel(w.water, w.name ?? (w.obj !== null && w.water === "pool" ? `object ${w.obj}` : null))), h("span", { class: "hint" }, `n = ${n(w.n)}${w.small ? ", small sample" : ""}`)));
		parts.push(...compareTable(w.compare, page.ownMin));
	}
	if (r.watersMore) parts.push(h("p", { class: "hint note" }, `${r.watersMore} more water types are in /craftwise fishing.`));
	parts.push(
		h(
			"p",
			{ class: "hint note" },
			`Yours = share of your catches that brought the item, with its 95% interval (Wilson). Reference = how often the reference recorded it per fishing loot. A difference is marked when the reference's share lies outside your interval. Below ${page.ownMin} own catches the sample is small: the interval is wide and the reference ranks the zone.`,
		),
	);
	return pane("p-detail", "fishing", ...parts);
}

function itemsTable(lines: F.ValuedLine[], row: { perCountUnits: boolean; n: number | null }): HTMLElement {
	return well(
		h(
			"table",
			{ class: "tbl wide fish items" },
			h("thead", {}, h("tr", {}, h("th", {}, "Item"), h("th", { class: "r" }, "Each"), h("th", { class: "r" }, "Per Catch"))),
			h(
				"tbody",
				{},
				lines.length
					? lines.map((l) => {
							const name = itemName(l.id);
							const q = quality(l.id);
							return h(
								"tr",
								{},
								h("td", { class: "itemcell" }, h("a", { class: "iname", href: `/item/${l.id}` }, slot(name, q), h("span", { class: `nm ${q}` }, name)), h("span", { class: "hint sub2" }, F.unitsText(l, row))),
								h("td", { class: "r" }, rangeEl(l.now?.copper ?? null, l.now?.high ?? null), h("span", { class: "hint sub2" }, F.sourceText(l.now))),
								h("td", { class: "r" }, rangeEl(l.perCatch, l.perCatchHigh)),
							);
						})
					: h("tr", {}, h("td", { class: "empty", colspan: 3 }, "Nothing was caught.")),
			),
		),
	);
}

function detailPane(page: F.FishingPage): HTMLElement {
	const rows: (F.Row | F.PoolRow)[] = [...page.zones, ...page.spots, ...page.waters, ...page.pools];
	const r = rows.find((x) => x.key === st.sel) ?? null;
	if (!r) return pane("p-detail", "fishing", barHead("Catch"), h("p", { class: "hint pad" }, "Pick a row to see what its catches are made of."));
	if ("kind" in r && r.kind === "zone") return zoneDetail(r as F.ZoneRow, page);
	const isPool = !("kind" in r);
	const title = isPool ? r.name : r.kind === "water" ? F.waterLabel(r.water, null) : r.kind === "spot" ? [r.zone, r.sub].filter(Boolean).join(", ") : r.zone;
	const row = isPool ? { perCountUnits: true, n: r.catches } : r;
	const lines = r.lines;
	const head = isPool
		? [kv("Catches from this pool", n(r.catches)), kv("Value per catch", moneyEl(r.perCatch)), kv("Value per visit", moneyEl(r.perVisit), r.avg !== null ? `${r.avg} catches per ended visit on average x the value per catch.` : null)]
		: [
				kv("Source", r.source === "ref" ? "Local reference" : r.kind === "zone" ? "Your catches" : "Your catches here", sampleText(r) + (r.small ? `: a small sample, fewer than ${page.ownMin}.` : ".")),
				kv("Value per catch", rangeEl(r.perCatch, r.perCatchHigh), r.revalued && r.snap.perCatch !== null && r.snap.perCatch !== r.perCatch ? `At the snapshot: ${moneyText(r.snap.perCatch)}.` : null),
				kv(
					"Value per hour",
					r.perHour !== null ? moneyEl(r.perHour) : h("span", { class: "hint" }, r.timedTooFew ? "too few timed catches" : "not timed"),
					r.timed !== null && r.minutes !== null ? `${n(r.timed)} timed catches in ${r.minutes.toLocaleString("en-US")} min${r.perHour === null ? `; it takes ${page.ownMin}` : ""}.` : null,
				),
			];
	return pane(
		"p-detail",
		"fishing",
		barHead("Catch"),
		h("p", { class: "lbl dtitle", id: "detail" }, title || "Unknown"),
		h("div", {}, ...head.flat()),
		lines
			? itemsTable(lines, row)
			: h("p", { class: "hint pad" }, "This upload has no item list, so the values are the ones in the snapshot. Update CraftWise and the companion to see them with today's prices."),
	);
}

function moneyText(copper: number): string {
	return moneyEl(copper).querySelector(".sr")?.textContent ?? String(copper);
}

// ---- Page --------------------------------------------------------------------------------------------------

let redraw: (() => void) | null = null;
onSkinChange(() => redraw?.());

function shell(title: string, medal: Node, parts: Node[]): void {
	redraw = () => shell(title, medal, parts);
	const back = st.key ? `/me?${new URLSearchParams({ c: st.key })}` : "/me";
	const frame = h(
		"section",
		{ class: "frame me", "aria-labelledby": "me-title" },
		h("div", { class: "medal", "aria-hidden": "true" }, medal),
		h("div", { class: "wtitle" }, h("h1", { id: "me-title" }, title)),
		closeButton(back, "Close and go to My Characters"),
		...parts,
	);
	clear(
		app,
		topBar(st.readOnly ? "Private: read-only access" : "Private: signed in with Cloudflare Access", "fishing"),
		h("main", { class: "shell me-shell" }, frame, bottomTabs("fishing")),
	);
}

function sortButtons(): HTMLElement {
	const btn = (by: F.SortBy, label: string) =>
		h(
			"button",
			{
				type: "button",
				class: "wtab up",
				"aria-pressed": String(st.sort === by),
				onclick: () => {
					st.sort = by;
					writeUrl(false);
					render();
				},
			},
			label,
		);
	return h("div", { class: "periods", role: "group", "aria-label": "Rank by" }, btn("hour", "Per Hour"), btn("catch", "Per Catch"));
}

function pricesLine(now: number, page: F.FishingPage): string {
	if (!page.itemLists) return "Values as in the snapshot: this upload has no item lists yet.";
	if (st.pricesFailed) return "Today's prices could not be read: values as in the snapshot.";
	const house = st.house?.label ?? "Horde AH";
	const scanned = st.house?.lastScan != null ? `, scanned ${age(now - st.house.lastScan)}` : "";
	return `Values with today's ${house} prices${scanned}, after the 5% cut.`;
}

function render(): void {
	const now = nowSeconds();
	const c = st.chars.find((x) => x.key === st.key) ?? null;
	if (!c) {
		shell("Where to Fish", h("span", { class: "medal-letter" }, "?"), [h("p", { class: "notice" }, "No characters uploaded yet. Create an upload token on My Characters and put it into the companion app.")]);
		redraw = render;
		return;
	}
	document.title = `Fishing, ${M.fullName(c)}: Velikopter Market`;
	const docs = st.docs;
	const page = F.fishingPage(docs?.fishing ?? null, docs?.snapshot ?? null, st.quotes);
	const v = M.charView(docs?.snapshot ?? null);
	const who = [v.level ?? c.level ? `Level ${v.level ?? c.level}` : null, v.race ?? c.race, v.cls ?? c.class].filter(Boolean).join(" ");
	const skill = page?.skill ?? null;
	const ff = page?.findFish;
	const times = [c.fishingT !== null ? `Fishing log ${age(now - c.fishingT)}.` : "No fishing log yet.", page ? pricesLine(now, page) : null].filter(Boolean).join(" ");
	const head = [
		sideTabs(st.chars, st.key, charHref, pickChar),
		h(
			"div",
			{ class: "mehead" },
			h("p", { class: "lbl who" }, who),
			skill ? bar("skill", skill.skill, skill.max, `Fishing ${skill.skill} / ${skill.max}`, `Fishing skill ${skill.skill} of ${skill.max}`) : h("span", { class: "hint" }, "Fishing skill not in this snapshot."),
			h("span", { class: "hint times" }, times),
		),
	];
	if (!page) {
		shell(`Where to Fish: ${M.fullName(c)}`, medal(c), [...head, h("p", { class: "notice" }, "No fishing log uploaded for this character yet.")]);
		redraw = render;
		return;
	}
	const zones = F.sortRows(page.zones, st.sort);
	const spots = F.sortRows(page.spots, st.sort);
	const pools = F.sortPools(page.pools);
	if (!st.sel || ![...page.zones, ...page.spots, ...page.waters, ...page.pools].some((r) => r.key === st.sel)) st.sel = zones[0]?.key ?? spots[0]?.key ?? null;
	const more = (count: number | null, what: string) => (count ? ` ${count} more ${what} are in /craftwise fishing.` : "");
	const stats = h(
		"div",
		{ class: "stats" },
		h("p", {}, h("span", { class: "lbl" }, "Catches"), ` ${n(page.catches)}${page.days !== null ? ` in ${page.days} days` : ""}`),
		page.containersOpened !== null ? h("p", {}, h("span", { class: "lbl" }, "Containers opened"), ` ${n(page.containersOpened)}`) : null,
		ff && ff.known !== null ? h("p", {}, h("span", { class: "lbl" }, "Find Fish"), ff.known ? ` known, tracking ${ff.tracking === null ? "unknown" : ff.tracking ? "on" : "off"}` : " not known") : null,
	);
	const body = h(
		"div",
		{ class: "fishbody" },
		h("div", { class: "lctl" }, h("span", { class: "lbl rankby" }, "Rank by"), sortButtons()),
		h(
			"div",
			{ class: "merow" },
			pane(
				"p-zones",
				"fishing",
				barHead("Where to Fish"),
				stats,
				zoneTable(zones),
				h(
					"p",
					{ class: "hint note" },
					`Your catches count for a zone from ${page.ownMin} on; below that the local reference ranks it where it has the zone, and the other source is shown as Compared. Reference rows are what players recorded on the reference site, not this character's catches. `,
					"The data has no fishing skill a zone needs, so no zone is marked as out of reach.",
					more(page.moreZones, "zones"),
					more(page.compareMore, "zones with own catches"),
				),
			),
		),
		h(
			"div",
			{ class: "merow" },
			detailPane(page),
			h(
				"div",
				{ class: "mecol" },
				pane("p-spots", "fishing", barHead("Your Spots"), spotTable(spots, "Spot", "No catches in this period."), h("p", { class: "hint note" }, `Zone, subzone and water, from your own catches of the last ${page.days ?? 90} days.${more(page.moreSpots, "spots")}`)),
				pane(
					"p-waters",
					"fishing",
					barHead("Open Water and Pools"),
					page.waters.length ? spotTable(page.waters, "Water", "") : h("p", { class: "hint pad" }, "Not in this upload yet: update CraftWise and the companion."),
					page.pools.length ? poolTable(pools) : h("p", { class: "hint pad" }, "No pool visits yet."),
					h(
						"p",
						{ class: "hint note" },
						"A visit is the catches from one pool until it vanished or you left it (the game doesn't tell the two apart). Per visit = catches per visit x value per catch now.",
						more(page.morePools, "pools"),
					),
				),
			),
		),
		h(
			"p",
			{ class: "hint note foot" },
			`Small sample = fewer than ${page.ownMin} catches; they rank after the others. Value per hour = your timed catches per hour x the value per catch, shown from ${page.ownMin} timed catches on (a session's first catch is untimed; catches more than ${page.sessionGap ?? 5} min apart start a new session). `,
			"Each item: the Horde AH's typical price (else its lowest listing) after the cut, or the vendor price when that is more; containers by their contents and items without a price today as in the snapshot.",
		),
	);
	shell(`Where to Fish: ${M.fullName(c)}`, medal(c), [...head, body]);
	redraw = render;
}

function medal(c: M.Character): HTMLElement {
	return h("span", { class: `medal-letter cls-${M.classKey(c.class)}` }, (c.name ?? c.key).charAt(0));
}

function loading(text: string): void {
	shell("Where to Fish", h("span", { class: "medal-letter" }, "?"), [h("p", { class: "notice", "aria-busy": "true" }, text)]);
}

// Today's Horde AH prices and the item names, 100 items per request.
async function loadPrices(): Promise<void> {
	const key = st.key;
	const { ids, names } = F.fishingItems(st.docs?.fishing ?? null, st.docs?.snapshot ?? null);
	for (const [id, name] of names) if (!st.items.has(id)) st.items.set(id, { name, quality: null });
	st.quotes = new Map();
	st.pricesFailed = false;
	if (!st.house || !ids.length) return;
	try {
		for (let i = 0; i < ids.length; i += 100) {
			const b = await get<Browse>(`/api/browse?house=${encodeURIComponent(st.house.key)}&ids=${ids.slice(i, i + 100).join(",")}`);
			if (key !== st.key) return;
			for (const [id, q] of F.quotesOf(b.items)) st.quotes.set(id, q);
			for (const it of b.items) st.items.set(it.id, { name: it.name ?? st.items.get(it.id)?.name ?? null, quality: it.quality });
		}
	} catch {
		st.quotes = new Map();
		st.pricesFailed = true;
	}
}

async function loadChar(): Promise<void> {
	const key = st.key;
	if (!key) return render();
	loading("Loading the fishing log");
	try {
		const docs = await get<M.CharacterDocs>(`/api/me/characters/${encodeURIComponent(key)}`);
		if (key !== st.key) return;
		st.docs = docs;
		await loadPrices();
		if (key !== st.key) return;
	} catch (err) {
		shell("Where to Fish", h("span", { class: "medal-letter" }, "?"), [errorBox(`The fishing log could not be loaded: ${(err as Error).message}.`)]);
		return;
	}
	render();
}

function latestChar(): string | null {
	let best: M.Character | null = null;
	for (const c of st.chars) if (!best || (c.fishingT ?? 0) > (best.fishingT ?? 0)) best = c;
	return best?.key ?? null;
}

async function main(): Promise<void> {
	readUrl();
	loading("Loading your characters");
	try {
		const [me, chars] = await Promise.all([get<{ email: string | null }>("/api/me"), get<{ characters: M.Character[] }>("/api/me/characters")]);
		st.readOnly = me.email === null;
		st.chars = chars.characters;
	} catch (err) {
		shell("Where to Fish", h("span", { class: "medal-letter" }, "?"), [errorBox(`Your private data could not be loaded: ${(err as Error).message}. Reload the page to sign in again.`)]);
		return;
	}
	try {
		st.house = pickHouse((await get<{ houses: House[] }>("/api/houses")).houses);
	} catch {
		st.pricesFailed = true;
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
	else render();
});

void main();
