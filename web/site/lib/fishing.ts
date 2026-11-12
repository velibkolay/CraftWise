// Data shaping for the private fishing page /me/fishing (#128). No DOM here: the Worker tests import it.
// Everything comes from the character's fishing document (snapshot.fishing with fishingZones, docs/snapshot.md)
// and the public prices of the Horde AH (/api/browse). Catches are values as the addon recorded them; only the
// unit values are looked up again, the way the addon's ns.GetSellValue picks them. Nothing is extrapolated:
// value per hour needs enough timed catches, small samples are marked.
import type { BrowseItem } from "./api";
import type { Doc } from "./me";

type J = unknown;
const obj = (v: J): Record<string, J> | null => (v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, J>) : null);
const arr = (v: J): J[] => (Array.isArray(v) ? v : []);
const num = (v: J): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);
const str = (v: J): string | null => (typeof v === "string" ? v : null);
const bool = (v: J): boolean | null => (typeof v === "boolean" ? v : null);

// The cut the addon takes at the own faction house (CraftWise/Prices.lua ns.AH_CUT, confirmed for faction
// houses). The site's prices are the Horde AH's.
export const AH_CUT = 0.05;
// The addon's own "large enough" number (FishingZones.lua Z.OWN_MIN), used when the document doesn't say.
export const OWN_MIN_DEFAULT = 50;

// ---- Item lists (docs/snapshot.md "Item lists") --------------------------------------------------

export interface ItemLine {
	id: number;
	units: number; // a count caught, or units per catch
	unitsHigh: number;
	value: number | null; // unit value used in the snapshot (copper)
	valueHigh: number | null;
	contents: boolean; // valued by its contents: kept as it is
	vendor: number | null; // vendor sell price when the client knew it (0: vendors don't buy it)
}

const NUM = "([0-9]+(?:\\.[0-9]+)?(?:e[-+]?[0-9]+)?)";
const RANGE = new RegExp(`^${NUM}(?:-${NUM})?$`);

function range(text: string | undefined): [number, number] | null {
	const m = text ? RANGE.exec(text) : null;
	if (!m) return null;
	const a = Number(m[1]);
	const b = m[2] !== undefined ? Number(m[2]) : a;
	return Number.isFinite(a) && Number.isFinite(b) ? [a, b] : null;
}

interface Tail {
	value: number | null;
	valueHigh: number | null;
	contents: boolean;
	vendor: number | null;
}

// "<value>[-<high>]|? [c|v<vendor>]" from the fields at `i`; null when broken.
function tail(f: string[], i: number): Tail | null {
	const v = f[i];
	if (v === undefined) return null;
	const value = v === "?" ? null : range(v);
	if (v !== "?" && !value) return null;
	const t = f[i + 1] ?? "";
	return { value: value?.[0] ?? null, valueHigh: value?.[1] ?? null, contents: t === "c", vendor: /^v[0-9]+$/.test(t) ? Number(t.slice(1)) : null };
}

function entries(text: J): string[][] | null {
	const s = str(text);
	if (s === null) return null;
	return s
		.split(";")
		.map((p) => p.trim().split(/\s+/))
		.filter((f) => f.length >= 3 && Number.isInteger(Number(f[0])) && Number(f[0]) > 0);
}

// Item lists: "<itemID> <units>[-<high>] <value>[-<high>]|? [c|v<vendor>]; ...". Null when the list is missing
// (an older addon or companion): then nothing can be valued again. Broken entries are left out.
export function parseItems(text: J): ItemLine[] | null {
	const list = entries(text);
	if (!list) return null;
	return list.flatMap((f) => {
		const units = range(f[1]);
		const t = tail(f, 2);
		return units && t ? [{ id: Number(f[0]), units: units[0], unitsHigh: units[1], ...t }] : [];
	});
}

export interface ShareLine extends Tail {
	id: number;
	hits: number; // own catches that brought the item
	units: number; // how many of it
}

// Share lists (own catch composition): "<itemID> <hits> <units> <value>[-<high>]|? [c|v<vendor>]; ...".
export function parseShares(text: J): ShareLine[] | null {
	const list = entries(text);
	if (!list) return null;
	return list.flatMap((f) => {
		const hits = Number(f[1]);
		const units = Number(f[2]);
		const t = tail(f, 3);
		return Number.isInteger(hits) && hits >= 0 && Number.isFinite(units) && units >= 0 && t ? [{ id: Number(f[0]), hits, units, ...t }] : [];
	});
}

export interface RefLine extends Tail {
	id: number;
	count: number; // how often the reference recorded it
	outof: number | null; // out of this many loots; null: out of the record's total
	stack: [number, number];
}

// Reference lists: "<itemID> <count>[/<outof>] <stack>[-<high>] <value>[-<high>]|? [c|v<vendor>]; ...".
export function parseRef(text: J): RefLine[] | null {
	const list = entries(text);
	if (!list) return null;
	return list.flatMap((f) => {
		const m = /^([0-9]+)(?:\/([0-9]+))?$/.exec(f[1] ?? "");
		const stack = range(f[2]);
		const t = tail(f, 3);
		return m && stack && t ? [{ id: Number(f[0]), count: Number(m[1]), outof: m[2] !== undefined ? Number(m[2]) : null, stack, ...t }] : [];
	});
}

// 95% Wilson score interval of k successes in n trials.
export function wilson(k: number, n: number, z = 1.96): [number, number] {
	if (n <= 0) return [0, 1];
	const p = k / n;
	const z2 = z * z;
	const den = 1 + z2 / n;
	const mid = (p + z2 / (2 * n)) / den;
	const half = (z * Math.sqrt((p * (1 - p)) / n + z2 / (4 * n * n))) / den;
	return [Math.max(0, mid - half), Math.min(1, mid + half)];
}

// ---- Unit values now ----------------------------------------------------------------------------

export interface AhQuote {
	copper: number; // before the cut
	basis: "typical" | "current"; // current: the lowest listed price, too little history for a typical one
}

// As Market.lua M.Quote with the "typical" basis: the typical price, else the current lowest while listed.
export function ahQuote(item: Pick<BrowseItem, "typical" | "current"> | undefined): AhQuote | null {
	if (!item) return null;
	if (item.typical.status === "ok") return { copper: item.typical.price, basis: "typical" };
	if (item.current?.listed && item.current.min !== null && item.current.min > 0) return { copper: item.current.min, basis: "current" };
	return null;
}

export type UnitSource = "ah" | "vendor" | "contents" | "snapshot";

export interface UnitNow {
	copper: number;
	high: number;
	source: UnitSource;
	basis: AhQuote["basis"] | null;
}

// One unit, the way ns.GetSellValue picks: the Horde AH after the cut, unless the vendor pays more.
// Containers keep their contents value. Without a Horde AH price now: the value the snapshot used.
export function unitNow(line: ItemLine, quote: AhQuote | null): UnitNow | null {
	if (line.contents) {
		return line.value === null ? null : { copper: line.value, high: line.valueHigh ?? line.value, source: "contents", basis: null };
	}
	if (quote) {
		const net = Math.floor(quote.copper * (1 - AH_CUT));
		if (line.vendor !== null && line.vendor > net) return { copper: line.vendor, high: line.vendor, source: "vendor", basis: null };
		if (net > 0) return { copper: net, high: net, source: "ah", basis: quote.basis };
	}
	if (line.value !== null) return { copper: line.value, high: line.valueHigh ?? line.value, source: "snapshot", basis: null };
	if (line.vendor !== null && line.vendor > 0) return { copper: line.vendor, high: line.vendor, source: "vendor", basis: null };
	return null;
}

export function sourceText(u: UnitNow | null): string {
	if (!u) return "no price";
	if (u.source === "ah") return u.basis === "typical" ? "Horde AH typical, after cut" : "Horde AH lowest, after cut";
	if (u.source === "vendor") return "vendor";
	if (u.source === "contents") return "contents, as in the snapshot";
	return "as in the snapshot";
}

export interface ValuedLine extends ItemLine {
	now: UnitNow | null;
	perCatch: number | null; // this item's share of the value per catch, now (low end)
	perCatchHigh: number | null;
}

export interface Valued {
	lines: ValuedLine[];
	perCatch: number;
	perCatchHigh: number;
	unpriced: number; // items without any price, left out
}

// Value per catch now. `divisor` = catches when the units are counts (spots, waters, pools), 1 when they
// are units per catch (zones). Lines sorted by their share, most first.
export function valueLines(lines: ItemLine[], quotes: Map<number, AhQuote>, divisor: number): Valued {
	let low = 0;
	let high = 0;
	let unpriced = 0;
	const d = divisor > 0 ? divisor : 1;
	const out: ValuedLine[] = lines.map((l) => {
		const now = unitNow(l, quotes.get(l.id) ?? null);
		if (!now) {
			unpriced++;
			return { ...l, now, perCatch: null, perCatchHigh: null };
		}
		const a = (l.units * now.copper) / d;
		const b = (l.unitsHigh * now.high) / d;
		low += a;
		high += b;
		return { ...l, now, perCatch: Math.round(a), perCatchHigh: Math.round(b) };
	});
	out.sort((x, y) => (y.perCatch ?? -1) - (x.perCatch ?? -1) || y.units - x.units || x.id - y.id);
	return { lines: out, perCatch: Math.round(low), perCatchHigh: Math.round(high), unpriced };
}

// ---- Rows ------------------------------------------------------------------------------------------

export type RowKind = "zone" | "spot" | "water";

export interface Row {
	key: string;
	kind: RowKind;
	zone: string;
	sub: string;
	water: string | null; // "open" | "pool" | "?"
	pool: string | null;
	source: "own" | "ref";
	n: number | null; // catches (own) or recorded fishing loots (reference)
	small: boolean; // fewer than ownMin catches or loots
	perCountUnits: boolean; // the lines' units are counts (divide by n)
	snap: { perCatch: number | null; perCatchHigh: number | null; perHour: number | null };
	perCatch: number | null;
	perCatchHigh: number | null;
	perHour: number | null; // null without enough timed catches
	timed: number | null;
	minutes: number | null;
	timedTooFew: boolean; // timed catches below ownMin: no value per hour shown
	unpriced: number | null;
	revalued: boolean; // valued with today's prices (the document had the item list)
	lines: ValuedLine[] | null;
}

interface RowIn {
	key: string;
	kind: RowKind;
	o: Record<string, J>;
	zone: string;
	sub: string;
	water: string | null;
	pool: string | null;
	source: "own" | "ref";
	counts: boolean;
}

function rowOf(r: RowIn, quotes: Map<number, AhQuote>, ownMin: number): Row {
	const o = r.o;
	const n = num(o.n);
	const snap = { perCatch: num(o.perCatch), perCatchHigh: num(o.perCatchHigh), perHour: num(o.perHour) };
	const items = parseItems(o.items);
	const usable = items !== null && (!r.counts || (n !== null && n > 0));
	const v = usable ? valueLines(items, quotes, r.counts ? n! : 1) : null;
	const perCatch = v ? v.perCatch : snap.perCatch;
	const perCatchHigh = v ? (v.perCatchHigh !== v.perCatch ? v.perCatchHigh : null) : snap.perCatchHigh;
	const timed = num(o.timed);
	const minutes = num(o.minutes);
	let perHour: number | null = null;
	let timedTooFew = false;
	if (timed !== null && minutes !== null && minutes > 0) {
		// Own catches per hour (timed catches only) x value per catch, as the addon does for zones.
		// Without the item list nothing was valued again: the addon's own figure (exact seconds) stays.
		if (timed >= ownMin) perHour = !v && snap.perHour !== null ? snap.perHour : perCatch !== null ? Math.round(((timed * 60) / minutes) * perCatch) : null;
		else timedTooFew = true;
	} else if (snap.perHour !== null) {
		// An older document without the timing: the addon's own figure, scaled to today's value per catch,
		// and only where the sample behind it is large enough.
		if (n !== null && n >= ownMin && r.source === "own") {
			perHour = v && snap.perCatch ? Math.round((snap.perHour * v.perCatch) / snap.perCatch) : snap.perHour;
		} else timedTooFew = true;
	}
	return {
		key: r.key,
		kind: r.kind,
		zone: r.zone,
		sub: r.sub,
		water: r.water,
		pool: r.pool,
		source: r.source,
		n,
		small: n === null || n < ownMin,
		perCountUnits: r.counts,
		snap,
		perCatch,
		perCatchHigh,
		perHour,
		timed,
		minutes,
		timedTooFew,
		unpriced: v ? v.unpriced : num(o.unpriced),
		revalued: v !== null,
		lines: v ? v.lines : null,
	};
}

// ---- Own catches against the reference (fishingZones.compare) ---------------------------------------------

export interface Side {
	source: "own" | "ref";
	n: number; // own catches, or the reference's recorded loots
	perCatch: number;
	perCatchHigh: number | null; // only when it differs (reference stack ranges)
	unpriced: number;
	lines: ValuedLine[];
}

function side(source: Side["source"], n: number, v: Valued): Side {
	return { source, n, perCatch: v.perCatch, perCatchHigh: v.perCatchHigh !== v.perCatch ? v.perCatchHigh : null, unpriced: v.unpriced, lines: v.lines };
}

function shareItems(shares: ShareLine[]): ItemLine[] {
	return shares.map((l) => ({ id: l.id, units: l.units, unitsHigh: l.units, value: l.value, valueHigh: l.valueHigh, contents: l.contents, vendor: l.vendor }));
}

// The reference's chance of an item per fishing loot (its own outof where it has one).
function refChance(l: RefLine, total: number | null): number | null {
	const outof = l.outof ?? total;
	return outof && outof > 0 ? l.count / outof : null;
}

function refItems(refs: RefLine[], total: number | null): ItemLine[] {
	return refs.flatMap((l) => {
		const c = refChance(l, total);
		return c === null ? [] : [{ id: l.id, units: c * l.stack[0], unitsHigh: c * l.stack[1], value: l.value, valueHigh: l.valueHigh, contents: l.contents, vendor: l.vendor }];
	});
}

export interface CompLine {
	id: number;
	hits: number | null; // own catches that brought it (null: no own data)
	n: number | null;
	share: number | null; // hits / n
	lo: number | null; // 95% Wilson interval of the own share
	hi: number | null;
	refShare: number | null; // the reference's chance per loot
	diff: number | null; // share - refShare
	outside: boolean; // the own interval excludes the reference's share
	ownPerCatch: number | null; // this item's part of the value per catch now
	refPerCatch: number | null;
	refPerCatchHigh: number | null;
}

export interface Compare {
	own: Side | null;
	ref: Side | null;
	lines: CompLine[];
	outside: number; // items whose own interval excludes the reference's share
}

export function compareOf(shares: ShareLine[] | null, n: number | null, refs: RefLine[] | null, refN: number | null, quotes: Map<number, AhQuote>): Compare {
	const own = shares && n ? side("own", n, valueLines(shareItems(shares), quotes, n)) : null;
	const ref = refs ? side("ref", refN ?? 0, valueLines(refItems(refs, refN), quotes, 1)) : null;
	const ids = new Set<number>([...(shares ?? []).map((l) => l.id), ...(refs ?? []).map((l) => l.id)]);
	const lines = [...ids].map((id): CompLine => {
		const s = shares?.find((l) => l.id === id) ?? (shares ? { hits: 0 } : null);
		const r = refs?.find((l) => l.id === id) ?? null;
		const refShare = refs ? (r ? refChance(r, refN) : 0) : null;
		const hits = s && n ? s.hits : null;
		const [lo, hi] = hits !== null && n ? wilson(hits, n) : [null, null];
		const share = hits !== null && n ? hits / n : null;
		const ownLine = own?.lines.find((l) => l.id === id);
		const refLine = ref?.lines.find((l) => l.id === id);
		return {
			id,
			hits,
			n: hits !== null ? n : null,
			share,
			lo,
			hi,
			refShare,
			diff: share !== null && refShare !== null ? share - refShare : null,
			outside: lo !== null && hi !== null && refShare !== null && (refShare < lo || refShare > hi),
			ownPerCatch: ownLine?.perCatch ?? null,
			refPerCatch: refLine?.perCatch ?? null,
			refPerCatchHigh: refLine?.perCatchHigh ?? null,
		};
	});
	lines.sort((a, b) => Math.max(b.share ?? 0, b.refShare ?? 0) - Math.max(a.share ?? 0, a.refShare ?? 0) || a.id - b.id);
	return { own, ref, lines, outside: lines.filter((l) => l.outside).length };
}

export interface WaterCompare {
	key: string;
	water: string | null;
	obj: number | null;
	name: string | null;
	n: number | null;
	small: boolean;
	compare: Compare;
}

export interface ZoneRow extends Row {
	other: Side | null; // the source that isn't the primary one, for comparison
	compare: Compare | null;
	waters: WaterCompare[];
	watersMore: number | null;
}

function timing(o: Record<string, J> | null): { timed: number | null; minutes: number | null } {
	return { timed: num(o?.timed), minutes: num(o?.minutes) };
}

// One zone from the ranking entry (zones[]) and the comparison entry (compare[]), either may be missing.
// Own catches are the primary number from ownMin catches on (or when the reference lacks the zone), the
// reference otherwise; the other source stays as comparison. Without item lists: the snapshot's figures.
function zoneRow(key: string, z: Record<string, J> | null, c: Record<string, J> | null, quotes: Map<number, AhQuote>, ownMin: number): ZoneRow {
	const zSrc: "own" | "ref" = str(z?.source) === "ref" ? "ref" : "own";
	const zItems = z ? parseItems(z.items) : null;
	const cmp = c ? compareOf(parseShares(c.own), num(c.n), parseRef(c.ref), num(c.refN), quotes) : null;
	let own = cmp?.own ?? null;
	let ref = cmp?.ref ?? null;
	if (z && zItems) {
		const n = num(z.n) ?? 0;
		if (zSrc === "own" && !own && n > 0) own = side("own", n, valueLines(zItems, quotes, 1));
		if (zSrc === "ref" && !ref) ref = side("ref", n, valueLines(zItems, quotes, 1));
	}
	const name = str(z?.zone) ?? str(c?.zone) ?? "";
	const waters = arr(c?.waters).flatMap((w, k) => {
		const o = obj(w);
		if (!o) return [];
		const wn = num(o.n);
		return [{ key: `${key}:w${k}`, water: str(o.water), obj: num(o.obj), name: str(o.name), n: wn, small: wn === null || wn < ownMin, compare: compareOf(parseShares(o.own), wn, parseRef(o.ref), num(o.refN), quotes) }];
	});
	const t = c ? timing(c) : timing(z);
	if (!own && !ref) {
		// No item lists: the ranking entry as the addon wrote it.
		const row = rowOf({ key, kind: "zone", o: z ?? {}, zone: name, sub: "", water: null, pool: null, source: zSrc, counts: false }, quotes, ownMin);
		return { ...row, other: null, compare: cmp, waters, watersMore: num(c?.watersMore) };
	}
	const primary = own && (own.n >= ownMin || !ref) ? own : (ref ?? own)!;
	const other = primary === own ? ref : own;
	const snapOk = z !== null && zSrc === primary.source;
	// Value per hour from own timed catches: o carries the timing, the value per catch is the primary one's.
	const o: Record<string, J> = { n: primary.n, timed: t.timed, minutes: t.minutes, perHour: snapOk ? z!.perHour : null, perCatch: snapOk ? z!.perCatch : null };
	const base = rowOf({ key, kind: "zone", o, zone: name, sub: "", water: null, pool: null, source: primary.source, counts: false }, new Map(), ownMin);
	const perHour = t.timed !== null && t.minutes !== null && t.minutes > 0 && t.timed >= ownMin ? Math.round(((t.timed * 60) / t.minutes) * primary.perCatch) : null;
	return {
		...base,
		snap: snapOk ? { perCatch: num(z!.perCatch), perCatchHigh: num(z!.perCatchHigh), perHour: num(z!.perHour) } : { perCatch: null, perCatchHigh: null, perHour: null },
		perCatch: primary.perCatch,
		perCatchHigh: primary.perCatchHigh,
		perHour,
		timedTooFew: perHour === null && t.timed !== null,
		unpriced: primary.unpriced,
		revalued: true,
		lines: primary.lines,
		other,
		compare: cmp,
		waters,
		watersMore: num(c?.watersMore),
	};
}

export type SortBy = "hour" | "catch";

// Best first. "hour": rows with a value per hour first (by it), the rest by value per catch; small samples
// after the large ones either way, so a handful of lucky catches never tops the list.
export function sortRows<T extends { perHour: number | null; perCatch: number | null; small: boolean; n: number | null }>(rows: T[], by: SortBy): T[] {
	return [...rows].sort((a, b) => {
		if (a.small !== b.small) return a.small ? 1 : -1;
		if (by === "hour" && (a.perHour !== null) !== (b.perHour !== null)) return a.perHour !== null ? -1 : 1;
		if (by === "hour" && a.perHour !== null && b.perHour !== null && a.perHour !== b.perHour) return b.perHour - a.perHour;
		const pc = (b.perCatch ?? -1) - (a.perCatch ?? -1);
		return pc || (b.n ?? 0) - (a.n ?? 0);
	});
}

// ---- Pools -----------------------------------------------------------------------------------------

export interface PoolRow {
	key: string;
	obj: number | null;
	name: string;
	visits: number | null;
	going: number | null;
	min: number | null;
	max: number | null;
	avg: number | null; // catches per ended visit
	seen: number | null;
	notFished: number | null;
	catches: number | null;
	small: boolean;
	perCatch: number | null;
	perVisit: number | null; // avg x value per catch now
	revalued: boolean;
	lines: ValuedLine[] | null;
}

export function sortPools(pools: PoolRow[]): PoolRow[] {
	return [...pools].sort((a, b) => {
		if (a.small !== b.small) return a.small ? 1 : -1;
		return (b.perVisit ?? -1) - (a.perVisit ?? -1) || (b.visits ?? 0) - (a.visits ?? 0);
	});
}

function poolOf(o: Record<string, J>, i: number, quotes: Map<number, AhQuote>, ownMin: number): PoolRow {
	const id = num(o.obj);
	const m = /^(\d+)-(\d+), avg ([0-9.]+)$/.exec(str(o.perVisit) ?? "");
	const avg = m ? Number(m[3]) : null;
	const catches = num(o.catches);
	const items = parseItems(o.items);
	const v = items && catches ? valueLines(items, quotes, catches) : null;
	const perCatch = v ? v.perCatch : num(o.perCatch);
	return {
		key: `pool:${id ?? i}`,
		obj: id,
		name: str(o.name) ?? (id !== null ? `Pool ${id}` : "Pool"),
		visits: num(o.visits),
		going: num(o.going),
		min: m ? Number(m[1]) : null,
		max: m ? Number(m[2]) : null,
		avg,
		seen: num(o.seen),
		notFished: num(o.notFished),
		catches,
		small: catches === null || catches < ownMin,
		perCatch,
		perVisit: avg !== null && perCatch !== null ? Math.round(avg * perCatch) : null,
		revalued: v !== null,
		lines: v ? v.lines : null,
	};
}

// ---- The page --------------------------------------------------------------------------------------

export interface FishingPage {
	days: number | null;
	catches: number | null;
	containersOpened: number | null;
	sessionGap: number | null;
	ownMin: number;
	reference: boolean | null;
	findFish: { known: boolean | null; tracking: boolean | null } | null;
	skill: { skill: number; max: number } | null;
	zones: ZoneRow[];
	moreZones: number | null;
	compareMore: number | null; // own zones the comparison left out
	spots: Row[];
	moreSpots: number | null;
	waters: Row[];
	pools: PoolRow[];
	morePools: number | null;
	revalued: boolean; // at least one row valued with today's prices
	itemLists: boolean; // the document has the item lists at all
}

function fishingDoc(fishing: Doc | null, snapshot: Doc | null): { f: Record<string, J>; z: Record<string, J> | null } | null {
	const f = obj(fishing?.data) ?? obj(obj(snapshot?.data)?.fishing);
	if (!f) return null;
	return { f, z: obj(f.fishingZones) ?? obj(obj(snapshot?.data)?.fishingZones) };
}

// Every item ID in the item lists (the prices to look up) and the names the spots' `top` text carries.
export function fishingItems(fishing: Doc | null, snapshot: Doc | null): { ids: number[]; names: Map<number, string> } {
	const doc = fishingDoc(fishing, snapshot);
	const ids = new Set<number>();
	const names = new Map<number, string>();
	if (!doc) return { ids: [], names };
	const lists: J[] = [];
	for (const s of arr(doc.f.spots)) {
		lists.push(obj(s)?.items);
		for (const part of (str(obj(s)?.top) ?? "").split(";")) {
			const m = /^\s*(\d+) (.+) \d+\/\d+\s*$/.exec(part);
			if (m) names.set(Number(m[1]), m[2]!);
		}
	}
	for (const s of arr(doc.f.waters)) lists.push(obj(s)?.items);
	for (const s of arr(doc.f.pools)) lists.push(obj(s)?.items);
	for (const s of arr(doc.z?.zones)) lists.push(obj(s)?.items);
	for (const l of lists) for (const line of parseItems(l) ?? []) ids.add(line.id);
	for (const x of arr(doc.z?.compare)) {
		const c = obj(x);
		const all = [c, ...arr(c?.waters).map(obj)];
		for (const o of all) {
			for (const line of parseShares(o?.own) ?? []) ids.add(line.id);
			for (const line of parseRef(o?.ref) ?? []) ids.add(line.id);
		}
	}
	return { ids: [...ids].sort((a, b) => a - b), names };
}

export function waterLabel(water: string | null, pool: string | null): string {
	if (water === "open") return "Open water";
	if (water === "pool") return pool ? `Pool: ${pool}` : "Pools";
	return pool ? `Not known yet (${pool})` : "Water not known yet";
}

export function fishingSkill(snapshot: Doc | null): { skill: number; max: number } | null {
	for (const p of arr(obj(snapshot?.data)?.professions)) {
		const o = obj(p);
		const skill = num(o?.skill);
		const max = num(o?.max);
		if (str(o?.name) === "Fishing" && skill !== null && max !== null) return { skill, max };
	}
	return null;
}

export function fishingPage(fishing: Doc | null, snapshot: Doc | null, quotes: Map<number, AhQuote>): FishingPage | null {
	const doc = fishingDoc(fishing, snapshot);
	if (!doc) return null;
	const { f, z } = doc;
	const ownMin = num(z?.ownMin) ?? OWN_MIN_DEFAULT;
	const ff = obj(f.findFish);
	// Zones of the ranking and of the comparison, matched by name (any case), ranking order first.
	const entries = new Map<string, { z: Record<string, J> | null; c: Record<string, J> | null }>();
	for (const x of arr(z?.zones)) {
		const o = obj(x);
		const name = str(o?.zone);
		if (o && name !== null && !entries.has(name.toLowerCase())) entries.set(name.toLowerCase(), { z: o, c: null });
	}
	for (const x of arr(z?.compare)) {
		const o = obj(x);
		const name = str(o?.zone);
		if (!o || name === null) continue;
		const e = entries.get(name.toLowerCase());
		if (e) e.c = o;
		else entries.set(name.toLowerCase(), { z: null, c: o });
	}
	const zones = [...entries.values()].map((e, i) => zoneRow(`zone:${i}`, e.z, e.c, quotes, ownMin));
	const spots = arr(f.spots).flatMap((x, i) => {
		const o = obj(x);
		if (!o) return [];
		return [rowOf({ key: `spot:${i}`, kind: "spot", o, zone: str(o.zone) ?? "", sub: str(o.sub) ?? "", water: str(o.water), pool: str(o.pool), source: "own", counts: true }, quotes, ownMin)];
	});
	const waters = arr(f.waters).flatMap((x, i) => {
		const o = obj(x);
		if (!o) return [];
		return [rowOf({ key: `water:${i}`, kind: "water", o, zone: "", sub: "", water: str(o.water), pool: null, source: "own", counts: true }, quotes, ownMin)];
	});
	const pools = arr(f.pools).flatMap((x, i) => {
		const o = obj(x);
		return o ? [poolOf(o, i, quotes, ownMin)] : [];
	});
	const all: Row[] = [...zones, ...spots, ...waters];
	return {
		days: num(f.days),
		catches: num(f.catches),
		containersOpened: num(f.containersOpened),
		sessionGap: num(f.sessionGapMinutes),
		ownMin,
		reference: bool(z?.reference),
		findFish: ff ? { known: bool(ff.known), tracking: bool(ff.tracking) } : null,
		skill: fishingSkill(snapshot),
		zones,
		moreZones: num(z?.more),
		compareMore: num(z?.compareMore),
		spots,
		moreSpots: num(f.moreSpots),
		waters,
		pools,
		morePools: num(f.morePools),
		revalued: all.some((r) => r.revalued) || pools.some((p) => p.revalued),
		itemLists: all.some((r) => r.lines !== null) || pools.some((p) => p.lines !== null),
	};
}

// Prices the page looks up: Horde AH quotes by item ID.
export function quotesOf(items: Pick<BrowseItem, "id" | "typical" | "current">[]): Map<number, AhQuote> {
	const out = new Map<number, AhQuote>();
	for (const it of items) {
		const q = ahQuote(it);
		if (q) out.set(it.id, q);
	}
	return out;
}

// Units of one line as the detail shows them: per catch (zones) or caught of n (counts).
export function unitsText(line: ItemLine, row: { perCountUnits: boolean; n: number | null }): string {
	const f = (x: number) => (x >= 10 || Number.isInteger(x) ? x.toLocaleString("en-US", { maximumFractionDigits: 1 }) : x.toPrecision(2).replace(/\.?0+$/, ""));
	if (row.perCountUnits) return `${line.units.toLocaleString("en-US")} of ${row.n?.toLocaleString("en-US") ?? "?"} catches`;
	const pct = (x: number) => {
		const p = x * 100;
		return p >= 1 ? `${p.toFixed(p >= 10 ? 0 : 1)}%` : p >= 0.01 ? `${p.toFixed(2)}%` : "<0.01%";
	};
	if (line.units < 1 && line.unitsHigh <= 1 && line.units === line.unitsHigh) return `${pct(line.units)} of catches`;
	return line.unitsHigh !== line.units ? `${f(line.units)}–${f(line.unitsHigh)} per catch` : `${f(line.units)} per catch`;
}
