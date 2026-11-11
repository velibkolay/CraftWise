// Private page /me (#98): characters, ledger, auctions, fishing, upload tokens and usage, from the
// private API behind Cloudflare Access. Desktop shows every pane; a phone shows one section at a time.
import { type Browse, get, type House, pickHouse } from "./lib/api";
import { bottomTabs, clear, closeButton, currentSkin, errorBox, h, moneyEl, nowSeconds, onSkinChange, s, slot, topBar } from "./lib/dom";
import { age, qualityClass } from "./lib/format";
import * as M from "./lib/me";

type Section = "overview" | "ledger" | "auctions" | "fishing" | "tokens";
const SECTIONS: [Section, string][] = [
	["overview", "Overview"],
	["ledger", "Ledger"],
	["auctions", "Auctions"],
	["fishing", "Fishing"],
	["tokens", "Tokens"],
];
const PERIODS: [M.Period, string][] = [
	["today", "Today"],
	["reset", "Since Reset"],
	["all", "All"],
];
const LEDGER_LIMIT = 5000;
const MINI_ROWS = 5;

interface Item {
	name: string | null;
	quality: number | null;
}

const st = {
	email: null as string | null,
	readOnly: false,
	chars: [] as M.Character[],
	key: null as string | null,
	docs: null as M.CharacterDocs | null,
	view: null as M.CharView | null,
	entries: [] as M.LedgerEntry[],
	period: "today" as M.Period,
	kind: "",
	tokens: [] as M.Token[],
	usage: null as M.Usage | null,
	house: null as House | null,
	houseLabels: new Map<string, string>(),
	items: new Map<number, Item>(),
	section: "overview" as Section,
};
const reveal = new M.TokenReveal();

const app = document.getElementById("app")!;
const ledgerBox = h("div", { class: "pane-body" });
const miniBox = h("div", { class: "pane-body" });
const auctionBox = h("div", { class: "pane-body" });
const tokenBox = h("div", { class: "pane-body" });
let body: HTMLElement | null = null;

// ---- Requests ------------------------------------------------------------------------------------

// POST and DELETE: same-origin fetch, so the browser sends this site's Origin header, which the
// Worker requires on changes (web/docs/api.md "Private API").
async function send<T>(method: "POST" | "DELETE", path: string, payload?: unknown): Promise<T> {
	const res = await fetch(path, {
		method,
		credentials: "same-origin",
		headers: payload === undefined ? { accept: "application/json" } : { accept: "application/json", "content-type": "application/json" },
		body: payload === undefined ? undefined : JSON.stringify(payload),
	});
	const data = (await res.json().catch(() => ({}))) as T & { message?: string };
	if (!res.ok) throw new Error(data.message ?? `request failed (${res.status})`);
	return data;
}

function readUrl(): void {
	const p = new URLSearchParams(location.search);
	st.key = p.get("c");
	const sec = p.get("s") as Section | null;
	st.section = sec && SECTIONS.some(([k]) => k === sec) ? sec : "overview";
}

function writeUrl(push: boolean): void {
	const p = new URLSearchParams();
	if (st.key) p.set("c", st.key);
	if (st.section !== "overview") p.set("s", st.section);
	const url = `/me${p.size ? `?${p}` : ""}`;
	if (url !== location.pathname + location.search) (push ? history.pushState : history.replaceState).call(history, null, "", url);
}

// ---- Small pieces ---------------------------------------------------------------------------------

function signOf(v: number): 1 | -1 | 0 {
	return v > 0 ? 1 : v < 0 ? -1 : 0;
}

// Money with a + or - in front (green in, red out; the Velikopter skin writes a real minus); the sign is spoken
// as "plus" / "minus".
function signed(copper: number | null, sign: 1 | -1 | 0): HTMLElement {
	if (copper === null) return moneyEl(null);
	return h(
		"span",
		{ class: "signed" },
		sign ? h("span", { class: sign > 0 ? "sg-in" : "sg-out", "aria-hidden": "true" }, sign > 0 ? "+" : currentSkin() === "velikopter" ? "\u2212" : "-") : null,
		sign ? h("span", { class: "sr" }, sign > 0 ? "plus" : "minus") : null,
		moneyEl(Math.abs(copper)),
	);
}

function kv(label: string, value: Node | string, hint?: string | null): HTMLElement[] {
	const out = [h("p", { class: "kv" }, h("span", {}, label), typeof value === "string" ? h("span", {}, value) : value)];
	if (hint) out.push(h("p", { class: "hint kv-hint" }, hint));
	return out;
}

function barHead(text: string): HTMLElement {
	return h("h2", { class: "bar-head" }, text);
}

function pane(cls: string, sec: string, ...children: (Node | null)[]): HTMLElement {
	return h("section", { class: `pane me-pane ${cls}`, "data-sec": sec }, ...children);
}

function well(...children: Node[]): HTMLElement {
	return h("div", { class: "inset tscroll" }, ...children);
}

function bar(cls: string, part: number, whole: number, text: string, label: string): HTMLElement {
	const el = h("div", { class: `sbar ${cls}`, role: "img", "aria-label": label }, h("i", {}), h("b", {}, text));
	(el.firstChild as HTMLElement).style.width = `${(M.share(part, whole) * 100).toFixed(1)}%`;
	return el;
}

function n(v: number | null): string {
	return v === null ? "–" : v.toLocaleString("en-US");
}

function itemName(id: number | null, fallback: string | null): string {
	return (id !== null ? st.items.get(id)?.name : null) ?? fallback ?? (id !== null ? `Item ${id}` : "Unknown item");
}

function quality(id: number | null): string {
	return qualityClass(id !== null ? (st.items.get(id)?.quality ?? null) : null);
}

function itemLink(id: number | null, name: string): HTMLElement {
	const q = quality(id);
	const inner = [slot(name, q), h("span", { class: `nm ${q}` }, name)];
	return id !== null ? h("a", { class: "iname", href: `/item/${id}` }, inner) : h("span", { class: "iname" }, inner);
}

function placeLabel(place: string | null): string {
	if (!place) return "";
	return st.houseLabels.get(place) ?? place;
}

// ---- Character -------------------------------------------------------------------------------------

function professions(v: M.CharView): HTMLElement {
	if (!v.professions.length) return h("p", { class: "hint pad" }, "No professions in this snapshot.");
	return h(
		"div",
		{ class: "profs" },
		v.professions.map((p) =>
			h(
				"div",
				{},
				h("p", { class: "prof-line" }, h("span", { class: "lbl" }, p.name), p.kind ? h("span", { class: "hint" }, p.kind) : null),
				bar("skill", p.skill, p.max, `${p.skill} / ${p.max}`, `${p.name} ${p.skill} of ${p.max}`),
			),
		),
	);
}

function holdings(v: M.CharView, now: number): HTMLElement[] {
	const ho = v.holdings;
	if (!ho) return [h("p", { class: "hint pad" }, "No holdings in this snapshot.")];
	const kinds = (k: number) => `${k.toLocaleString("en-US")} item ${k === 1 ? "kind" : "kinds"}`;
	const out = [
		h(
			"div",
			{},
			ho.bags !== null ? kv("Bags", kinds(ho.bags)) : null,
			ho.bank ? kv("Bank", `${kinds(ho.bank.kinds)}${ho.bank.t !== null ? `, ${age(now - ho.bank.t)}` : ""}`) : null,
			ho.mail ? kv("Mailbox", `${ho.mail.mails} ${ho.mail.mails === 1 ? "mail" : "mails"}${ho.mail.t !== null ? `, ${age(now - ho.mail.t)}` : ""}`) : null,
		),
	];
	if (ho.notCounted.length) out.push(h("p", { class: "hint kv-hint" }, `Not counted: ${ho.notCounted.join(", ")}.`));
	return out;
}

function charKvs(v: M.CharView, withRealm: boolean): HTMLElement {
	return h(
		"div",
		{},
		v.money !== null ? kv("Gold carried", moneyEl(v.money)) : null,
		v.location ? kv("Location", v.location) : null,
		v.guild ? kv("Guild", v.guild) : null,
		withRealm && v.realm ? kv("Realm", [v.realm, v.faction].filter(Boolean).join(", ")) : null,
	);
}

function characterPane(v: M.CharView, now: number): HTMLElement {
	return pane(
		"p-char",
		"desk",
		barHead("Character"),
		charKvs(v, true),
		barHead("Professions"),
		professions(v),
		barHead("Holdings"),
		...holdings(v, now),
	);
}

// ---- Ledger ------------------------------------------------------------------------------------------

function totalsGrid(t: M.Totals | null, cols: 2 | 4): HTMLElement {
	const cell = (label: string, el: HTMLElement) => h("div", { class: "tot" }, h("p", { class: "lbl" }, label), h("p", {}, el));
	if (!t) return h("p", { class: "inset hint pad" }, "No reset time in this snapshot.");
	return h(
		"div",
		{ class: `inset totals c${cols}` },
		cell("Spent", signed(t.spent, t.spent ? -1 : 0)),
		cell("Received", signed(Math.abs(t.received), signOf(t.received))),
		cell("Net from trades", signed(Math.abs(t.net), signOf(t.net))),
		cell("Other money", t.other === null ? moneyEl(null) : signed(Math.abs(t.other), signOf(t.other))),
	);
}

function entryMoney(e: M.LedgerEntry): HTMLElement {
	return signed(e.money, e.money ? M.entrySign(e.kind) : 0);
}

function ledgerRows(list: M.LedgerEntry[], now: number): HTMLElement[] {
	return list.map((e) => {
		const kind = M.kindLabel(e.kind);
		const place = placeLabel(e.place);
		const when = M.clockLabel(e.t, now);
		return h(
			"tr",
			{},
			h("td", { class: "num wide-only" }, when),
			h("td", { class: "wide-only kindcell" }, kind, place ? h("span", { class: "hint sub2" }, place) : null),
			h(
				"td",
				{ class: "itemcell" },
				itemLink(e.item, itemName(e.item, e.name)),
				h("span", { class: "phone-only hint sub2" }, `${e.qty !== null ? `x${e.qty}, ` : ""}${when}, ${kind}${place ? `, ${place}` : ""}`),
			),
			h("td", { class: "r num wide-only" }, n(e.qty)),
			h("td", { class: "r" }, entryMoney(e)),
		);
	});
}

function renderLedger(): void {
	const v = st.view;
	const now = nowSeconds();
	const ledger = v?.ledger ?? { today: null, reset: null };
	const since = M.periodSince(st.period, now, ledger);
	const t = M.periodTotals(st.entries, st.period, now, ledger, st.kind);
	const list = since === null ? [] : M.filterEntries(st.entries, since, st.kind);

	const periods = h(
		"div",
		{ class: "periods", role: "group", "aria-label": "Period" },
		PERIODS.map(([p, label]) =>
			h(
				"button",
				{
					type: "button",
					class: "wtab up",
					"aria-pressed": String(st.period === p),
					disabled: p === "reset" && !ledger.reset,
					onclick: () => {
						st.period = p;
						renderLedger();
					},
				},
				label,
			),
		),
	);
	const kindSel = h("select", { class: "winput", id: "f-kind", "aria-label": "Kind" }, h("option", { value: "" }, "All kinds"), M.kindsPresent(st.entries).map((k) => h("option", { value: k, selected: st.kind === k }, M.kindLabel(k))));
	kindSel.addEventListener("change", () => {
		st.kind = kindSel.value;
		renderLedger();
	});
	const sinceText =
		since === null ? "" : st.period === "today" ? `Since midnight, ${M.dateLabel(since)}.` : st.period === "reset" ? `Since ${M.clockLabel(since, now)}, the last ledger reset.` : `Every entry uploaded${st.entries.length >= LEDGER_LIMIT ? `, the latest ${LEDGER_LIMIT.toLocaleString("en-US")}` : ""}.`;
	const notes: string[] = [];
	if (t?.uncounted) notes.push(`${t.uncounted} entries of a kind the totals don't count.`);
	if (t && t.other === null && !st.kind && st.period !== "all") notes.push("Other money comes from today's snapshot; this snapshot is of another day.");

	clear(
		ledgerBox,
		h("div", { class: "lctl" }, periods, h("span", { class: "grow" }), h("span", { class: "kindf" }, h("label", { class: "field", for: "f-kind" }, h("span", { class: "lbl" }, "Kind")), kindSel)),
		h("p", { class: "hint since" }, sinceText),
		totalsGrid(t, 4),
		well(
			h(
				"table",
				{ class: "tbl ledger" },
				h(
					"thead",
					{},
					h("tr", {}, h("th", { class: "wide-only" }, "Time"), h("th", { class: "wide-only" }, "Kind"), h("th", {}, "Item"), h("th", { class: "r wide-only" }, "Qty"), h("th", { class: "r" }, "Money")),
				),
				h("tbody", {}, list.length ? ledgerRows(list, now) : h("tr", {}, h("td", { class: "empty", colspan: 5 }, "No entries in this period."))),
			),
		),
		h("p", { class: "hint note" }, "Other money is the change no logged trade explains: loot, quests, repairs, fees. AH sales count when their mail is taken.", ...notes.map((x) => ` ${x}`)),
	);
	renderMini();
}

// Phone overview: today's totals and the latest entries, with a way to the whole ledger.
function renderMini(): void {
	const now = nowSeconds();
	const ledger = st.view?.ledger ?? { today: null, reset: null };
	const today = M.periodTotals(st.entries, "today", now, ledger);
	const list = M.filterEntries(st.entries, M.localDayStart(now)).slice(0, MINI_ROWS);
	clear(
		miniBox,
		barHead("Ledger Today"),
		totalsGrid(today, 2),
		well(
			h(
				"table",
				{ class: "tbl mini" },
				h("thead", {}, h("tr", {}, h("th", {}, "Latest"), h("th", { class: "r" }, "Money"))),
				h(
					"tbody",
					{},
					list.length
						? list.map((e) =>
								h(
									"tr",
									{},
									h("td", { class: "itemcell" }, itemLink(e.item, itemName(e.item, e.name)), h("span", { class: "hint sub2" }, `${e.qty !== null ? `x${e.qty}, ` : ""}${M.clockLabel(e.t, now)}, ${M.kindLabel(e.kind)}`)),
									h("td", { class: "r" }, entryMoney(e)),
								),
							)
						: h("tr", {}, h("td", { class: "empty", colspan: 2 }, "No trades today.")),
				),
			),
		),
		h("button", { type: "button", class: "wbtn dark wide", onclick: () => setSection("ledger", true) }, "Whole Ledger"),
	);
}

// ---- Auctions ------------------------------------------------------------------------------------

function auctionKvs(a: M.AuctionView, counts: boolean): HTMLElement {
	const groups = M.auctionGroups(a, nowSeconds());
	const count = (k: string) => groups.find((g) => g.key === k)?.rows.length ?? 0;
	const listedHint = a.listedTotal !== null ? [a.listedNote ? `After the ${a.listedNote}` : null, a.listedLeftOut.length ? `Left out: ${a.listedLeftOut.join(", ")}` : null].filter(Boolean).join(". ") : null;
	return h(
		"div",
		{},
		kv("On its way by mail", moneyEl(a.expectedTotal), a.expectedMissing ? `${a.expectedMissing} ${a.expectedMissing === 1 ? "sale" : "sales"} without an expected payout left out.` : null),
		a.listedTotal !== null ? kv("If all listed sell", moneyEl(a.listedTotal), listedHint ? `${listedHint}.` : null) : count("active") ? kv("If all listed sell", moneyEl(null), "Not in this snapshot yet.") : null,
		counts ? kv("Listed, sold, returning", `${count("active")}, ${count("sold")}, ${count("returning")}`) : null,
	);
}

function renderAuctions(): void {
	const a = st.view?.auctions ?? null;
	const now = nowSeconds();
	if (!a) {
		clear(auctionBox, barHead("Auctions"), h("p", { class: "hint pad" }, "No auction data in this snapshot."));
		return;
	}
	const groups = M.auctionGroups(a, now).filter((g) => g.rows.length);
	clear(
		auctionBox,
		barHead("Auctions"),
		auctionKvs(a, false),
		h(
			"div",
			{ class: "aucs" },
			groups.length
				? groups.map((g) =>
						h(
							"div",
							{ class: "aucgroup" },
							h("h3", { class: "auchead" }, h("span", { class: "lbl" }, g.title), h("span", { class: "hint" }, String(g.rows.length))),
							h(
								"ul",
								{ class: "auclist" },
								g.rows.map((r) => {
									const name = itemName(r.item, r.name);
									const q = quality(r.item);
									return h(
										"li",
										{},
										slot(name, q),
										h(
											"div",
											{ class: "aucname" },
											h("p", {}, r.item !== null ? h("a", { class: `nm ${q}`, href: `/item/${r.item}` }, name) : h("span", { class: `nm ${q}` }, name), r.units !== null ? h("span", { class: "hint" }, ` x${r.units}`) : null),
											h("p", { class: "hint sub2" }, r.note),
										),
										r.money !== null ? h("span", { class: "aucm" }, h("span", { class: "sr" }, `${r.moneyLabel} `), moneyEl(r.money)) : null,
									);
								}),
							),
						),
					)
				: h("p", { class: "hint pad" }, "No auctions tracked."),
		),
		a.ownedListAt !== null ? h("p", { class: "hint note" }, `Your auctions list at the AH was last read ${age(now - a.ownedListAt)}.`) : null,
	);
}

// ---- Fishing ------------------------------------------------------------------------------------

function fishingPane(f: M.FishingView | null): HTMLElement {
	if (!f) return pane("p-fish", "fishing", barHead("Fishing"), h("p", { class: "hint pad" }, "No fishing log uploaded for this character."));
	const stat = (label: string, value: string | null) => (value === null ? null : h("p", {}, h("span", { class: "lbl" }, label), ` ${value}`));
	const perCatch = (z: { perCatch: number | null; perCatchHigh?: number | null }) =>
		z.perCatchHigh != null && z.perCatch !== null ? h("span", { class: "range" }, moneyEl(z.perCatch), h("span", { "aria-hidden": "true" }, " – "), h("span", { class: "sr" }, " to "), moneyEl(z.perCatchHigh)) : moneyEl(z.perCatch);
	const perHour = (v: number | null) => (v === null ? h("span", { class: "hint" }, "not timed") : moneyEl(v));
	const more: string[] = [];
	if (f.moreSpots) more.push(`${f.moreSpots} more spots`);
	if (f.moreZones) more.push(`${f.moreZones} more zones`);
	return pane(
		"p-fish",
		"fishing",
		barHead(f.days !== null ? `Fishing, Last ${f.days} Days` : "Fishing"),
		h("div", { class: "stats" }, stat("Catches", n(f.catches)), stat("Containers opened", f.containersOpened === null ? null : n(f.containersOpened)), stat("Find Fish", f.findFish)),
		f.spots.length
			? well(
					h(
						"table",
						{ class: "tbl wide" },
						h("thead", {}, h("tr", {}, h("th", {}, "Best Spots"), h("th", {}, "Water"), h("th", { class: "r" }, "Catches"), h("th", { class: "r" }, "Per Catch"), h("th", { class: "r" }, "Per Hour"))),
						h(
							"tbody",
							{},
							f.spots.map((sp) =>
								h(
									"tr",
									{},
									h("td", {}, sp.zone, sp.sub ? h("span", { class: "hint" }, ` ${sp.sub}`) : null),
									h("td", {}, sp.water),
									h("td", { class: "r num" }, n(sp.n)),
									h("td", { class: "r" }, moneyEl(sp.perCatch)),
									h("td", { class: "r" }, perHour(sp.perHour)),
								),
							),
						),
					),
				)
			: h("p", { class: "hint pad" }, "No catches in this period."),
		f.zones.length
			? well(
					h(
						"table",
						{ class: "tbl wide" },
						h("thead", {}, h("tr", {}, h("th", {}, "Zones by Value per Catch"), h("th", {}, "Source"), h("th", { class: "r" }, "Catches"), h("th", { class: "r" }, "Per Catch"), h("th", { class: "r" }, "Per Hour"))),
						h(
							"tbody",
							{},
							f.zones.map((z) =>
								h(
									"tr",
									{},
									h("td", {}, z.zone, z.unpriced ? h("span", { class: "hint" }, ` ${z.unpriced} unpriced`) : null),
									h("td", {}, z.source),
									h("td", { class: "r num" }, n(z.n)),
									h("td", { class: "r" }, perCatch(z)),
									h("td", { class: "r" }, perHour(z.perHour)),
								),
							),
						),
					),
				)
			: null,
		f.pools.length
			? well(
					h(
						"table",
						{ class: "tbl wide" },
						h("thead", {}, h("tr", {}, h("th", {}, "Pools"), h("th", { class: "r" }, "Visits"), h("th", {}, "Catches per Visit"), h("th", { class: "r" }, "Seen, not fished"))),
						h(
							"tbody",
							{},
							f.pools.map((p) => h("tr", {}, h("td", {}, p.name), h("td", { class: "r num" }, n(p.visits)), h("td", {}, p.perVisit ?? "–"), h("td", { class: "r num" }, n(p.seen)))),
						),
					),
				)
			: null,
		h(
			"p",
			{ class: "hint note" },
			"Small catch counts are small samples. Per hour counts only catches that follow another within the session gap.",
			f.zones.some((z) => z.source === "Reference") ? " Reference rows come from the local fishing reference addon." : "",
			more.length ? ` Not shown: ${more.join(", ")} (see /craftwise fishing).` : "",
		),
	);
}

// ---- Tokens -----------------------------------------------------------------------------------------

function fili(pos: string): SVGElement {
	return s(
		"svg",
		{ class: `fili ${pos}`, viewBox: "0 0 30 30", "aria-hidden": "true" },
		s("path", { d: "M2 28 V9 Q2 2 9 2 H28" }),
		pos.startsWith("t") ? s("path", { d: "M6 20 C6 11 9 7 14 6 C10 9 9 12 10 15 C11 12 13 11 15 12" }) : null,
	);
}

function renderTokens(message = "", focus: "" | "popup" | "new" = ""): void {
	const now = nowSeconds();
	const shown = reveal.current;
	const nameInput = h("input", { class: "winput", id: "tok-name", name: "name", maxlength: 64, autocomplete: "off", placeholder: "Companion PC", value: "" });
	const createBtn = h("button", { type: "submit", class: "wbtn", id: "tok-new", disabled: st.readOnly }, "New Token");
	const status = h("p", { class: "hint note", role: "status" }, message);
	const form = h(
		"form",
		{ class: "tokform" },
		h("label", { class: "field", for: "tok-name" }, h("span", { class: "lbl" }, "Name")),
		nameInput,
		createBtn,
	);
	form.addEventListener("submit", async (e) => {
		e.preventDefault();
		const name = nameInput.value.trim() || "Companion PC";
		createBtn.disabled = true;
		try {
			const created = await send<M.CreatedToken>("POST", "/api/me/tokens", { name });
			reveal.show(created);
			st.tokens = (await get<{ tokens: M.Token[] }>("/api/me/tokens")).tokens;
			renderTokens("", "popup");
		} catch (err) {
			createBtn.disabled = false;
			status.textContent = `Not created: ${(err as Error).message}.`;
		}
	});

	const rows = M.sortTokens(st.tokens).map((t) => {
		const action = h("td", { class: "r act" });
		const revokeBtn = h("button", { type: "button", class: "wbtn dark small", disabled: st.readOnly, "aria-label": `Revoke ${t.name}` }, "Revoke");
		// The confirm step is a row of its own under the token (no browser dialog).
		const confirmRevoke = () => {
			const row = revokeBtn.closest("tr")!;
			row.parentElement?.querySelector(".confirmrow")?.remove();
			const keep = h("button", { type: "button", class: "wbtn dark small" }, "Keep");
			const yes = h("button", { type: "button", class: "wbtn small" }, "Revoke");
			const confirm = h(
				"tr",
				{ class: "confirmrow" },
				h("td", { colspan: 4 }, h("span", { class: "confirm" }, h("span", { class: "lbl" }, `Revoke "${t.name}"? The companion using it can no longer upload.`), h("span", { class: "btns" }, yes, keep))),
			);
			row.after(confirm);
			keep.addEventListener("click", () => {
				confirm.remove();
				revokeBtn.focus();
			});
			yes.addEventListener("click", async () => {
				yes.disabled = true;
				keep.disabled = true;
				try {
					await send("DELETE", `/api/me/tokens/${t.id}`);
					st.tokens = (await get<{ tokens: M.Token[] }>("/api/me/tokens")).tokens;
					renderTokens(`Revoked "${t.name}".`, "new");
				} catch (err) {
					renderTokens(`Not revoked: ${(err as Error).message}.`);
				}
			});
			keep.focus();
		};
		revokeBtn.addEventListener("click", confirmRevoke);
		if (t.revoked === null) action.append(revokeBtn);
		const dim = t.revoked !== null ? "hint" : "";
		const used = t.revoked !== null ? `Revoked ${M.dateLabel(t.revoked)}` : t.lastUsed !== null ? age(now - t.lastUsed) : "never used";
		return h(
			"tr",
			{},
			h(
				"td",
				{ class: `tname ${dim}` },
				t.name,
				t.scopes.length === 2 ? null : h("span", { class: "hint sub2" }, M.scopesText(t.scopes)),
				h("span", { class: "hint sub2 phone-only" }, `${t.prefix}…, ${used}`),
			),
			h("td", { class: `narrow wide-only ${dim}` }, `${t.prefix}…`),
			h("td", { class: `wide-only ${dim}` }, used),
			action,
		);
	});

	let popup: HTMLElement | null = null;
	if (shown) {
		const out = h("input", { class: "winput tokout", readonly: true, value: shown.token, "aria-label": "New token", spellcheck: "false" });
		const copyBtn = h("button", { type: "button", class: "wbtn" }, "Copy");
		const copyNote = h("p", { class: "hint", role: "status" });
		copyBtn.addEventListener("click", async () => {
			try {
				await navigator.clipboard.writeText(shown.token);
				copyBtn.textContent = "Copied";
				copyNote.textContent = "The token is on the clipboard.";
			} catch {
				out.select();
				copyNote.textContent = "Copying was blocked: the token is selected, press Ctrl+C.";
			}
		});
		const doneBtn = h("button", { type: "button", class: "wbtn" }, "Done");
		doneBtn.addEventListener("click", () => {
			reveal.dismiss();
			renderTokens("", "new");
		});
		out.addEventListener("focus", () => out.select());
		popup = h(
			"div",
			{ class: "popup", role: "dialog", "aria-labelledby": "tok-h" },
			fili("tl"),
			fili("tr"),
			fili("bl"),
			fili("br"),
			h("p", { id: "tok-h" }, `Token "${shown.name}" created. Copy it into the companion now: it is shown only this once.`),
			out,
			h("div", { class: "popbtns" }, copyBtn, doneBtn),
			copyNote,
		);
	}

	clear(
		tokenBox,
		barHead("Upload Tokens"),
		well(
			h(
				"table",
				{ class: "tbl tokens" },
				h("thead", {}, h("tr", {}, h("th", {}, "Name"), h("th", { class: "wide-only" }, "Starts"), h("th", { class: "wide-only" }, "Last Used"), h("th", {}, h("span", { class: "sr" }, "Action")))),
				h("tbody", {}, rows.length ? rows : h("tr", {}, h("td", { class: "empty", colspan: 4 }, "No tokens yet. Create one for the companion app."))),
			),
		),
		form,
		st.readOnly ? h("p", { class: "hint note" }, "Read-only access: sign in with your e-mail to create or revoke tokens.") : null,
		status,
		popup,
	);
	if (focus === "popup") popup?.querySelector<HTMLInputElement>(".tokout")?.focus();
	else if (focus === "new") document.getElementById("tok-new")?.focus();
}

// ---- Usage, characters ----------------------------------------------------------------------------

function usagePane(): HTMLElement {
	const u = st.usage;
	if (!u) return pane("p-usage", "tokens", barHead("Usage Today"), h("p", { class: "hint pad" }, "Usage could not be read."));
	return pane(
		"p-usage",
		"tokens",
		barHead("Usage Today"),
		h(
			"div",
			{ class: "meter" },
			h("p", { class: "prof-line" }, h("span", { class: "lbl" }, "Rows written"), h("span", { class: "hint" }, `uploads stop at ${u.budget.toLocaleString("en-US")}`)),
			bar("", u.rowsWritten, u.budget, `${n(u.rowsWritten)} / ${n(u.budget)}`, `${n(u.rowsWritten)} of ${n(u.budget)} rows written today`),
		),
		u.dbBytes !== null
			? h(
					"div",
					{ class: "meter" },
					h("p", { class: "prof-line" }, h("span", { class: "lbl" }, "Database size"), h("span", { class: "hint" }, `thin out old rows past ${M.megabytes(M.DB_THIN_AT)}`)),
					bar("", u.dbBytes, M.DB_LIMIT, `${M.megabytes(u.dbBytes)} / ${M.megabytes(M.DB_LIMIT)}`, `${M.megabytes(u.dbBytes)} of ${M.megabytes(M.DB_LIMIT)}`),
				)
			: null,
		h("div", {}, kv("Uploads today", n(u.uploads))),
		h("p", { class: "hint note" }, "The day is counted in UTC and starts again at 00:00 UTC."),
	);
}

function charactersPane(now: number): HTMLElement {
	const ago = (t: number | null) => (t === null ? h("span", { class: "hint" }, "none yet") : age(now - t));
	return pane(
		"p-chars",
		"overview",
		barHead("Characters"),
		well(
			h(
				"table",
				{ class: "tbl wide" },
				h("thead", {}, h("tr", {}, h("th", {}, "Name"), h("th", {}, "Race and Class"), h("th", { class: "r" }, "Level"), h("th", {}, "Snapshot"), h("th", {}, "Auctions"), h("th", {}, "Fishing"))),
				h(
					"tbody",
					{},
					st.chars.map((c) =>
						h(
							"tr",
							{ class: c.key === st.key ? "sel" : null },
							h("td", {}, h("a", { href: charHref(c.key), "aria-current": c.key === st.key ? "page" : null, onclick: (e: Event) => pickChar(e, c.key) }, M.fullName(c))),
							h("td", {}, [c.race, c.class].filter(Boolean).join(" ")),
							h("td", { class: "r num" }, n(c.level)),
							h("td", {}, ago(c.snapshotT)),
							h("td", {}, ago(c.auctionsT)),
							h("td", {}, ago(c.fishingT)),
						),
					),
				),
			),
		),
	);
}

// Without a choice in the URL: the character with the newest snapshot.
function latestChar(): string | null {
	let best: M.Character | null = null;
	for (const c of st.chars) if (!best || (c.snapshotT ?? 0) > (best.snapshotT ?? 0)) best = c;
	return best?.key ?? null;
}

function charHref(key: string): string {
	return `/me?${new URLSearchParams({ c: key })}`;
}

function pickChar(e: Event, key: string): void {
	const me = e as MouseEvent;
	if (me.ctrlKey || me.metaKey || me.shiftKey || me.button === 1) return;
	e.preventDefault();
	if (key === st.key) return;
	st.key = key;
	writeUrl(true);
	void loadChar();
}

function setSection(sec: Section, push: boolean): void {
	st.section = sec;
	body?.setAttribute("data-s", sec);
	for (const b of document.querySelectorAll<HTMLButtonElement>(".sectabs button")) b.setAttribute("aria-pressed", String(b.dataset.tab === sec));
	writeUrl(push);
	if (push) document.querySelector<HTMLElement>(".sectabs")?.scrollIntoView({ block: "nearest" });
}

// ---- Page --------------------------------------------------------------------------------------------

// What the page shows now, drawn again when the skin changes: the shell as it is, or render() once loaded.
let redraw: (() => void) | null = null;
onSkinChange(() => redraw?.());

function shell(title: string, medal: Node, parts: Node[]): void {
	redraw = () => shell(title, medal, parts);
	const frame = h(
		"section",
		{ class: "frame me", "aria-labelledby": "me-title" },
		h("div", { class: "medal", "aria-hidden": "true" }, medal),
		h("div", { class: "wtitle" }, h("h1", { id: "me-title" }, title)),
		closeButton("/", "Close and go to the auction house"),
		...parts,
	);
	clear(
		app,
		topBar(st.readOnly ? "Private: read-only access" : "Private: signed in with Cloudflare Access", "me"),
		h("main", { class: "shell me-shell" }, frame, bottomTabs("me")),
	);
}

function header(c: M.Character, v: M.CharView, now: number): HTMLElement[] {
	const who = [v.level ?? c.level ? `Level ${v.level ?? c.level}` : null, v.race ?? c.race, v.cls ?? c.class].filter(Boolean).join(" ");
	const times = [c.snapshotT !== null ? `Snapshot ${age(now - c.snapshotT)}.` : "No snapshot yet.", c.fishingT !== null ? `Fishing log ${age(now - c.fishingT)}.` : null].filter(Boolean).join(" ");
	const xp = v.xp;
	const xpText = xp ? `XP ${n(xp.xp)} / ${n(xp.max)}${xp.rested ? `, rested ${n(xp.rested)}` : ""}` : "";
	return [
		h(
			"nav",
			{ class: "sidetabs", "aria-label": "Characters" },
			st.chars.map((ch) =>
				h(
					"a",
					{
						href: charHref(ch.key),
						class: `stab cls-${M.classKey(ch.class)}`,
						"aria-current": ch.key === st.key ? "page" : null,
						"aria-label": `${M.fullName(ch)}, ${[ch.level !== null ? `level ${ch.level}` : null, ch.class].filter(Boolean).join(" ")}`,
						title: M.fullName(ch),
						onclick: (e: Event) => pickChar(e, ch.key),
					},
					(ch.name ?? ch.key).charAt(0),
					ch.level !== null ? h("span", { class: "lv", "aria-hidden": "true" }, String(ch.level)) : null,
				),
			),
		),
		h(
			"div",
			{ class: "mehead" },
			h("p", { class: "lbl who" }, who),
			xp ? bar("xp", xp.xp, xp.max, xpText, `Experience ${xpText.slice(3)}`) : null,
			h("span", { class: "hint times" }, times),
		),
	];
}

function sectionTabs(): HTMLElement {
	return h(
		"div",
		{ class: "sectabs", role: "group", "aria-label": "Sections" },
		SECTIONS.map(([k, label]) => h("button", { type: "button", class: "wtab up", "data-tab": k, "aria-pressed": String(st.section === k), onclick: () => setSection(k, true) }, label)),
	);
}

function render(): void {
	const now = nowSeconds();
	const c = st.chars.find((x) => x.key === st.key) ?? null;
	if (!c) {
		renderTokens();
		body = h(
			"div",
			{ class: "mebody", "data-s": "tokens" },
			h("p", { class: "notice" }, "No characters uploaded yet. Create an upload token below and put it into the companion app; your characters appear after its first upload."),
			h("div", { class: "merow" }, pane("p-tokens", "tokens", tokenBox), usagePane()),
		);
		shell("My Characters", h("span", { class: "medal-letter" }, "?"), [body]);
		redraw = render;
		return;
	}
	const v = st.view ?? M.charView(null);
	document.title = `${M.fullName(c)}: Velikopter Market`;
	renderLedger();
	renderAuctions();
	renderTokens();
	const phoneOverview = pane(
		"p-over",
		"overview",
		barHead("Character"),
		charKvs(v, false),
		v.auctions ? barHead("Auctions") : null,
		v.auctions ? auctionKvs(v.auctions, true) : null,
		miniBox,
		barHead("Professions"),
		professions(v),
		barHead("Holdings"),
		...holdings(v, now),
	);
	body = h(
		"div",
		{ class: "mebody", "data-s": st.section },
		sectionTabs(),
		h("div", { class: "merow r1" }, characterPane(v, now), phoneOverview, pane("p-ledger", "ledger", barHead("Ledger"), ledgerBox), pane("p-auc", "auctions", auctionBox)),
		h("div", { class: "merow r2" }, fishingPane(M.fishingView(st.docs?.fishing ?? null, st.docs?.snapshot ?? null)), pane("p-tokens", "tokens", tokenBox)),
		h("div", { class: "merow r3" }, charactersPane(now), usagePane()),
	);
	shell(M.fullName(c), h("span", { class: `medal-letter cls-${M.classKey(c.class)}` }, (c.name ?? c.key).charAt(0)), [...header(c, v, now), body]);
	redraw = render;
}

function loading(text: string): void {
	shell("My Characters", h("span", { class: "medal-letter" }, "?"), [h("p", { class: "notice", "aria-busy": "true" }, text)]);
}

// House labels for the ledger's AH entries: the snapshot's own market houses, then the public list.
function addHouseLabels(snapshot: M.Doc | null): void {
	const houses = (snapshot?.data as { market?: { houses?: Record<string, { label?: unknown }> } } | null)?.market?.houses;
	for (const [key, hse] of Object.entries(houses ?? {})) if (typeof hse?.label === "string") st.houseLabels.set(key, hse.label);
}

// Item names and qualities for the ledger and auction rows, from the public item info.
async function loadItems(): Promise<void> {
	if (!st.house) return;
	const ids = new Set<number>();
	for (const e of st.entries) if (e.item !== null) ids.add(e.item);
	if (st.view?.auctions) for (const g of M.auctionGroups(st.view.auctions, nowSeconds())) for (const r of g.rows) if (r.item !== null) ids.add(r.item);
	const todo = [...ids].filter((id) => !st.items.has(id)).slice(0, 500);
	if (!todo.length) return;
	const key = st.key;
	for (let i = 0; i < todo.length; i += 100) {
		const chunk = todo.slice(i, i + 100);
		try {
			const b = await get<Browse>(`/api/browse?house=${encodeURIComponent(st.house.key)}&ids=${chunk.join(",")}`);
			for (const it of b.items) st.items.set(it.id, { name: it.name, quality: it.quality });
		} catch {
			return; // names and colours stay as recorded
		}
	}
	if (key === st.key) {
		renderLedger();
		renderAuctions();
	}
}

async function loadChar(): Promise<void> {
	const key = st.key;
	if (!key) return render();
	loading("Loading the character");
	try {
		const [docs, ledger] = await Promise.all([
			get<M.CharacterDocs>(`/api/me/characters/${encodeURIComponent(key)}`),
			get<unknown>(`/api/me/ledger?${new URLSearchParams({ char: key, limit: String(LEDGER_LIMIT) })}`),
		]);
		if (key !== st.key) return;
		st.docs = docs;
		st.view = M.charView(docs.snapshot);
		st.entries = M.parseLedger(ledger);
		st.kind = "";
		if (st.period === "reset" && !st.view.ledger.reset) st.period = "today";
		addHouseLabels(docs.snapshot);
	} catch (err) {
		shell("My Characters", h("span", { class: "medal-letter" }, "?"), [errorBox(`The character could not be loaded: ${(err as Error).message}.`)]);
		return;
	}
	render();
	void loadItems();
}

async function main(): Promise<void> {
	readUrl();
	loading("Loading your characters");
	try {
		const [me, chars, tokens, usage] = await Promise.all([
			get<{ email: string | null }>("/api/me"),
			get<{ characters: M.Character[] }>("/api/me/characters"),
			get<{ tokens: M.Token[] }>("/api/me/tokens"),
			get<M.Usage>("/api/me/usage").catch(() => null),
		]);
		st.email = me.email;
		st.readOnly = me.email === null;
		st.chars = chars.characters;
		st.tokens = tokens.tokens;
		st.usage = usage;
	} catch (err) {
		shell("My Characters", h("span", { class: "medal-letter" }, "?"), [errorBox(`Your private data could not be loaded: ${(err as Error).message}. Reload the page to sign in again.`)]);
		return;
	}
	try {
		const houses = (await get<{ houses: House[] }>("/api/houses")).houses;
		st.house = pickHouse(houses);
		for (const hs of houses) st.houseLabels.set(hs.key, hs.label);
	} catch {
		// labels fall back to the house keys
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
	else setSection(st.section, false);
});

void main();
