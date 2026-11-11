// Data shaping for the private page /me (#98). No DOM here: the Worker tests import it.
// Every field comes from the private API (web/docs/api.md) as the addon wrote it (docs/snapshot.md);
// a field the upload lacks stays missing (null), it is never filled in.
import { money } from "./format";

// ---- Reading untyped JSON --------------------------------------------------------------------

type J = unknown;
const obj = (v: J): Record<string, J> | null => (v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, J>) : null);
const arr = (v: J): J[] => (Array.isArray(v) ? v : []);
const num = (v: J): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);
const str = (v: J): string | null => (typeof v === "string" ? v : null);
const bool = (v: J): boolean | null => (typeof v === "boolean" ? v : null);

// ---- API shapes ----------------------------------------------------------------------------------

export interface Character {
	key: string;
	realm: string | null;
	name: string | null;
	surname: string | null;
	faction: string | null;
	race: string | null;
	class: string | null;
	level: number | null;
	snapshotT: number | null;
	auctionsT: number | null;
	fishingT: number | null;
}

export interface Doc {
	t: number;
	data: unknown;
}

export interface CharacterDocs {
	key: string;
	snapshot: Doc | null;
	auctions: Doc | null;
	fishing: Doc | null;
}

export interface LedgerEntry {
	char: string;
	t: number;
	kind: string;
	item: number | null;
	qty: number | null;
	money: number | null;
	place: string | null;
	name: string | null;
}

export interface Usage {
	day: number;
	rowsWritten: number;
	uploads: number;
	budget: number;
	dbBytes: number | null;
}

export interface Token {
	id: number;
	prefix: string;
	name: string;
	scopes: string[];
	created: number;
	createdBy: string | null;
	lastUsed: number | null;
	revoked: number | null;
}

export interface CreatedToken {
	id: number;
	token: string;
	prefix: string;
	name: string;
	scopes: string[];
	created: number;
}

export function fullName(c: Pick<Character, "name" | "surname" | "key">): string {
	const n = [c.name, c.surname].filter(Boolean).join(" ");
	return n || c.key;
}

// "Hunter" -> "hunter": picks the tab colour (site.css .cls-*). Unknown classes keep the default.
export function classKey(cls: string | null): string {
	return (cls ?? "").toLowerCase().replace(/[^a-z]/g, "");
}

// ---- Snapshot (docs/snapshot.md) -------------------------------------------------------------

export interface Profession {
	name: string;
	kind: string | null;
	skill: number;
	max: number;
}

export interface LedgerSum {
	since: number;
	spent: number | null;
	received: number | null;
	net: number | null;
	other: number | null;
}

export interface CharView {
	t: number | null;
	level: number | null;
	race: string | null;
	cls: string | null;
	realm: string | null;
	faction: string | null;
	xp: { xp: number; max: number; rested: number | null } | null;
	money: number | null;
	location: string | null;
	guild: string | null; // only a name: false (no guild) and missing are both left out
	professions: Profession[];
	holdings: { bags: number | null; bank: { kinds: number; t: number | null } | null; mail: { mails: number; t: number | null } | null; notCounted: string[] } | null;
	ledger: { today: LedgerSum | null; reset: LedgerSum | null };
	auctions: AuctionView | null;
}

function ledgerSum(v: J): LedgerSum | null {
	const o = obj(v);
	const since = num(o?.since);
	if (!o || since === null) return null;
	return { since, spent: num(o.spent), received: num(o.received), net: num(o.net), other: num(o.other) };
}

export function charView(snapshot: Doc | null): CharView {
	const d = obj(snapshot?.data) ?? {};
	const c = obj(d.char) ?? {};
	const loc = obj(d.location);
	const xp = num(c.xp);
	const xpMax = num(c.xpMax);
	const zone = str(loc?.zone);
	const sub = str(loc?.subzone);
	const h = obj(d.holdings);
	const bank = obj(h?.bank);
	const mail = obj(h?.mail);
	const bags = obj(h?.bags);
	const led = obj(d.ledger);
	return {
		t: num(d.t) ?? snapshot?.t ?? null,
		level: num(c.level),
		race: str(c.race),
		cls: str(c.class),
		realm: str(c.realm),
		faction: str(c.faction),
		// xpMax 0 means the client reported no XP to the next level: no bar then.
		xp: xp !== null && xpMax !== null && xpMax > 0 ? { xp, max: xpMax, rested: num(c.rested) } : null,
		money: num(c.money),
		location: zone ? (sub ? `${zone}, ${sub}` : zone) : null,
		guild: str(c.guild),
		professions: arr(d.professions).flatMap((p) => {
			const o = obj(p);
			const name = str(o?.name);
			const skill = num(o?.skill);
			const max = num(o?.max);
			return o && name && skill !== null && max !== null ? [{ name, kind: str(o.kind), skill, max }] : [];
		}),
		holdings: h
			? {
					bags: bags ? Object.keys(bags).length : null,
					bank: bank ? { kinds: Object.keys(obj(bank.items) ?? {}).length, t: num(bank.t) } : null,
					mail: mail && num(mail.mails) !== null ? { mails: num(mail.mails)!, t: num(mail.t) } : null,
					notCounted: arr(h.notCounted).flatMap((s) => (typeof s === "string" ? [s] : [])),
				}
			: null,
		ledger: { today: ledgerSum(led?.today), reset: ledgerSum(led?.reset) },
		auctions: auctionView(d.auctions),
	};
}

// ---- Ledger (CraftWise/Ledger.lua) -----------------------------------------------------------

export type Period = "today" | "reset" | "all";

// Kinds as Ledger.lua records them; `dir` is the money's direction. A kind not listed here is
// shown as recorded and left out of the totals.
export const KINDS: Record<string, { label: string; dir: 1 | -1 }> = {
	ahbuy: { label: "AH buy", dir: -1 },
	ahsell: { label: "AH sale", dir: 1 },
	vbuy: { label: "Vendor buy", dir: -1 },
	vsell: { label: "Vendor sale", dir: 1 },
	buyback: { label: "Buyback", dir: -1 },
};

export function kindLabel(kind: string): string {
	return KINDS[kind]?.label ?? kind;
}

export function parseLedger(v: J): LedgerEntry[] {
	return arr(obj(v)?.entries).flatMap((e) => {
		const o = obj(e);
		const t = num(o?.t);
		const kind = str(o?.kind);
		const char = str(o?.char);
		if (!o || t === null || kind === null || char === null) return [];
		return [{ char, t, kind, item: num(o.item), qty: num(o.qty), money: num(o.money), place: str(o.place), name: str(o.name) }];
	});
}

// Start of the viewer's local day: the addon's "today" is the game client's local calendar day
// (Ledger.lua DayStart), and the page is read on the same machine's clock.
export function localDayStart(now: number): number {
	const d = new Date(now * 1000);
	d.setHours(0, 0, 0, 0);
	return Math.floor(d.getTime() / 1000);
}

// First second of a period; null when the period is not known (no snapshot with a reset time).
export function periodSince(period: Period, now: number, ledger: CharView["ledger"]): number | null {
	if (period === "today") return localDayStart(now);
	if (period === "reset") return ledger.reset?.since ?? null;
	return 0;
}

export interface Totals {
	spent: number;
	received: number;
	net: number;
	// Money change no logged trade explains, from the snapshot (it needs the start money, which the
	// entries don't carry). Null for "All", for a kind filter and when the snapshot is of another day.
	other: number | null;
	count: number;
	uncounted: number; // entries of a kind the totals don't know
}

// As Ledger.lua Totals(): spent = AH and vendor buys; received = vendor and AH sales minus buybacks.
export function totals(entries: LedgerEntry[], since: number, kind = ""): Totals {
	let spent = 0;
	let received = 0;
	let count = 0;
	let uncounted = 0;
	for (const e of entries) {
		if (e.t < since || (kind && e.kind !== kind)) continue;
		count++;
		const m = e.money ?? 0;
		if (e.kind === "ahbuy" || e.kind === "vbuy") spent += m;
		else if (e.kind === "vsell" || e.kind === "ahsell") received += m;
		else if (e.kind === "buyback") received -= m;
		else uncounted++;
	}
	return { spent, received, net: received - spent, other: null, count, uncounted };
}

export function periodTotals(entries: LedgerEntry[], period: Period, now: number, ledger: CharView["ledger"], kind = ""): Totals | null {
	const since = periodSince(period, now, ledger);
	if (since === null) return null;
	const t = totals(entries, since, kind);
	if (!kind) {
		const snap = period === "today" ? ledger.today : period === "reset" ? ledger.reset : null;
		if (snap && snap.since === since) t.other = snap.other;
	}
	return t;
}

export function filterEntries(entries: LedgerEntry[], since: number, kind = ""): LedgerEntry[] {
	return entries.filter((e) => e.t >= since && (!kind || e.kind === kind));
}

// The kinds present, in a fixed order (known kinds first, then the rest as recorded).
export function kindsPresent(entries: LedgerEntry[]): string[] {
	const seen = new Set(entries.map((e) => e.kind));
	const known = Object.keys(KINDS).filter((k) => seen.has(k));
	const other = [...seen].filter((k) => !(k in KINDS)).sort();
	return [...known, ...other];
}

// Signed amount of one entry: buys and buybacks are money out.
export function entrySign(kind: string): 1 | -1 | 0 {
	return KINDS[kind]?.dir ?? 0;
}

// ---- Auctions (snapshot.auctions, docs/snapshot.md) ------------------------------------------

export interface AuctionRow {
	item: number | null;
	name: string;
	units: number | null;
	note: string;
	money: number | null;
	moneyLabel: string; // what the amount is, for screen readers
}

export interface AuctionGroup {
	key: "sold" | "active" | "returning" | "uncertain";
	title: string;
	rows: AuctionRow[];
}

export interface AuctionView {
	expectedTotal: number | null;
	expectedMissing: number | null;
	listedTotal: number | null;
	listedCounted: number | null;
	listedNote: string | null;
	listedLeftOut: string[];
	ownedListAt: number | null;
	raw: Record<string, J>; // the four lists, shaped by auctionGroups against the page's clock
}

const GROUPS: [AuctionGroup["key"], string][] = [
	["sold", "Sold, awaiting mail"],
	["active", "Listed"],
	["returning", "Returning by mail"],
	["uncertain", "Sold or cancelled, uncertain"],
];

export function auctionView(v: J): AuctionView | null {
	const a = obj(v);
	if (!a) return null;
	const left: string[] = [];
	const nb = num(a.listedNoBuyout);
	const uc = num(a.listedUnknownCut);
	const up = num(a.listedUnpriced);
	if (nb) left.push(`${nb} without a buyout`);
	if (uc) left.push(`${uc} at a house with an unverified cut`);
	if (up) left.push(`${up} listed before tracking`);
	return {
		expectedTotal: num(a.expectedTotal),
		expectedMissing: num(a.expectedMissing),
		listedTotal: num(a.listedTotal),
		listedCounted: num(a.listedCounted),
		listedNote: str(a.listedNote),
		listedLeftOut: left,
		ownedListAt: num(a.ownedListAt),
		raw: a,
	};
}

export function timeLeft(seconds: number): string {
	if (seconds <= 0) return "time is up";
	if (seconds < 3600) return `${Math.max(1, Math.round(seconds / 60))} min left`;
	if (seconds < 48 * 3600) return `${Math.round(seconds / 3600)} h left`;
	return `${Math.round(seconds / 86400)} days left`;
}

function ago(seconds: number): string {
	const s = Math.max(0, seconds);
	if (s < 90) return "just now";
	if (s < 3600) return `${Math.round(s / 60)} min ago`;
	if (s < 48 * 3600) return `${Math.round(s / 3600)} h ago`;
	return `${Math.round(s / 86400)} days ago`;
}

// The four lists with one line of text per row and the amount it is about:
// sold = the expected payout (after the confirmed cut), listed = the buyout before the cut.
export function auctionGroups(view: AuctionView, now: number): AuctionGroup[] {
	return GROUPS.map(([key, title]) => ({
		key,
		title,
		rows: arr(view.raw[key]).flatMap((r) => {
			const o = obj(r);
			if (!o) return [];
			const units = num(o.q);
			const name = str(o.name) ?? (num(o.item) !== null ? `Item ${num(o.item)}` : "Unknown item");
			const row: AuctionRow = { item: num(o.item), name, units, note: "", money: null, moneyLabel: "" };
			const notes: string[] = [];
			if (key === "sold") {
				const at = num(o.soldAt);
				notes.push(at !== null ? `sold ${ago(now - at)}` : "sold");
				const exp = num(o.expected);
				if (exp !== null) {
					row.money = exp;
					row.moneyLabel = "expected";
				}
				const n = str(o.expectedNote);
				if (n) notes.push(exp !== null ? `after ${n}` : n);
				if (str(o.unitsSold)) notes.push(`units sold: ${str(o.unitsSold)}`);
			} else if (key === "active") {
				const unit = num(o.unitBuyout);
				const bid = num(o.unitBid);
				if (unit !== null) {
					notes.push(`buyout ${money(unit).short} each`);
					if (units !== null) {
						row.money = unit * units;
						row.moneyLabel = "buyout";
					}
				} else if (bid !== null) notes.push(`bid ${money(bid).short} each, no buyout`);
				const exp = num(o.expires);
				if (o.overdue === true) notes.push("time is up, outcome not seen yet");
				else if (exp !== null) notes.push(timeLeft(exp - now));
				else if (o.untracked === true) notes.push("listed before tracking");
			} else {
				notes.push(str(o.statusText) ?? str(o.status) ?? key);
				const at = num(o.at) ?? num(o.expires);
				if (key === "returning" && at !== null && at <= now) notes.push(ago(now - at));
			}
			const house = str(o.houseLabel);
			// The site is about the Horde AH (#96); other houses are named.
			if (house && house !== "Horde AH") notes.push(house);
			row.note = notes.join(", ");
			return [row];
		}),
	}));
}

// ---- Fishing (fishing document: snapshot.fishing with fishingZones) -------------------------

export interface Spot {
	zone: string;
	sub: string;
	water: string;
	n: number | null;
	perCatch: number | null;
	perHour: number | null;
}

export interface Zone {
	zone: string;
	source: string;
	n: number | null;
	perCatch: number | null;
	perCatchHigh: number | null;
	perHour: number | null;
	unpriced: number | null;
}

export interface Pool {
	name: string;
	visits: number | null;
	perVisit: string | null;
	seen: number | null;
}

export interface FishingView {
	days: number | null;
	catches: number | null;
	containersOpened: number | null;
	findFish: string | null;
	spots: Spot[];
	moreSpots: number | null;
	zones: Zone[];
	moreZones: number | null;
	reference: boolean | null;
	pools: Pool[];
}

export function waterText(water: string | null, pool: string | null): string {
	if (water === "open") return "Open water";
	if (water === "pool") return pool ? `Pool: ${pool}` : "Pool";
	return pool ? `Not known yet (${pool})` : "Not known yet";
}

export function fishingView(fishing: Doc | null, snapshot: Doc | null): FishingView | null {
	const f = obj(fishing?.data) ?? obj(obj(snapshot?.data)?.fishing);
	if (!f) return null;
	const z = obj(f.fishingZones) ?? obj(obj(snapshot?.data)?.fishingZones);
	const ff = obj(f.findFish);
	const known = bool(ff?.known);
	const tracking = bool(ff?.tracking);
	return {
		days: num(f.days),
		catches: num(f.catches),
		containersOpened: num(f.containersOpened),
		findFish: known === null ? null : known ? `known, tracking ${tracking === null ? "unknown" : tracking ? "on" : "off"}` : "not known",
		spots: arr(f.spots).flatMap((s) => {
			const o = obj(s);
			if (!o) return [];
			return [{ zone: str(o.zone) ?? "", sub: str(o.sub) ?? "", water: waterText(str(o.water), str(o.pool)), n: num(o.n), perCatch: num(o.perCatch), perHour: num(o.perHour) }];
		}),
		moreSpots: num(f.moreSpots),
		zones: arr(z?.zones).flatMap((s) => {
			const o = obj(s);
			if (!o) return [];
			const src = str(o.source);
			return [
				{
					zone: str(o.zone) ?? "",
					source: src === "own" ? "Your catches" : src === "ref" ? "Reference" : (src ?? ""),
					n: num(o.n),
					perCatch: num(o.perCatch),
					perCatchHigh: num(o.perCatchHigh),
					perHour: num(o.perHour),
					unpriced: num(o.unpriced),
				},
			];
		}),
		moreZones: num(z?.more),
		reference: bool(z?.reference),
		pools: arr(f.pools).flatMap((p) => {
			const o = obj(p);
			if (!o) return [];
			return [{ name: str(o.name) ?? (num(o.obj) !== null ? `Pool ${num(o.obj)}` : "Pool"), visits: num(o.visits), perVisit: str(o.perVisit), seen: num(o.seen) }];
		}),
	};
}

// ---- Usage, tokens ------------------------------------------------------------------------------

export const DB_LIMIT = 500 * 1024 * 1024; // D1 free plan, per database (web/docs/api.md "Budget")
export const DB_THIN_AT = 400 * 1024 * 1024;

export function megabytes(bytes: number): string {
	const mb = bytes / (1024 * 1024);
	return `${mb < 10 ? mb.toFixed(1) : Math.round(mb).toLocaleString("en-US")} MB`;
}

export function share(part: number, whole: number): number {
	return whole > 0 ? Math.min(1, Math.max(0, part / whole)) : 0;
}

// Active tokens first (newest first), then the revoked ones.
export function sortTokens(tokens: Token[]): Token[] {
	return [...tokens].sort((a, b) => Number(a.revoked !== null) - Number(b.revoked !== null) || b.id - a.id);
}

export function scopesText(scopes: string[]): string {
	const has = (s: string) => scopes.includes(s);
	if (has("public") && has("private")) return "prices and private data";
	if (has("public")) return "prices only";
	if (has("private")) return "private data only";
	return scopes.join(", ");
}

// The new token, held only until the viewer closes the popup. The token list never carries it
// (GET /api/me/tokens has no token field), so once dismissed it is gone from the page.
export class TokenReveal {
	private shown: { name: string; token: string } | null = null;

	show(created: CreatedToken): { name: string; token: string } {
		this.shown = { name: created.name, token: created.token };
		return this.shown;
	}

	get current(): { name: string; token: string } | null {
		return this.shown;
	}

	dismiss(): void {
		this.shown = null;
	}
}

// ---- Time labels in the viewer's local time --------------------------------------------------

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// "22:41" for today, else "Nov 10, 22:41".
export function clockLabel(t: number, now: number): string {
	const d = new Date(t * 1000);
	const hm = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
	return t >= localDayStart(now) && t < localDayStart(now) + 86400 ? hm : `${MONTHS[d.getMonth()]} ${d.getDate()}, ${hm}`;
}

export function dateLabel(t: number): string {
	const d = new Date(t * 1000);
	return `${MONTHS[d.getMonth()]} ${d.getDate()}`;
}

export { ago };
