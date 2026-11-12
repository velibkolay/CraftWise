// Data shaping for the Waylaid Crates page /me/crates (#129). No DOM here: the Worker tests import it.
// Everything comes from the snapshot's `crates` and `favor` sections (docs/snapshot.md) and the public read API
// (current Horde AH prices). A field the upload lacks stays missing (null), it is never filled in; the one
// exception is the guide's Favor per crate (crateFavorGuide.ts), shown only where nothing was measured and
// always labelled as a guide value.
import { crateParts, guideFavor, type Rank } from "./crateFavorGuide";

type J = unknown;
const obj = (v: J): Record<string, J> | null => (v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, J>) : null);
const arr = (v: J): J[] => (Array.isArray(v) ? v : []);
const num = (v: J): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);
const str = (v: J): string | null => (typeof v === "string" ? v : null);

// The cut the faction house takes from a sale (CraftWise/Prices.lua AH_CUT, "5% cut (confirmed)" in game).
export const AH_CUT = 0.05;

// ---- Prices -------------------------------------------------------------------------------------

// A current AH price from /api/browse (`current` and `typical` of one item at the Horde AH).
export interface AhPrice {
	t: number; // when it was seen
	min: number | null; // lowest unit price
	listed: boolean; // false: the latest full scan didn't list it
	typical: number | null; // median daily typical of 7 days, when there is one
}

// A price as the page uses it: where it comes from and when it was seen.
export interface Priced {
	copper: number;
	source: "snapshot" | "ah";
	label: string; // the snapshot's price label ("crafted", "vendor", "typical · Horde AH"), or "Horde AH now"
	t: number | null; // snapshot time, or when the AH price was seen
}

const fixedSource = (label: string | null) => label === "crafted" || (label ?? "").startsWith("vendor");

// The snapshot froze its prices at upload; the AH prices of the public API move on. A newer listed AH price
// replaces an AH-based one; a crafted or vendor cost stays unless the newer AH price is cheaper (the addon
// takes the cheapest way, #47). Without a snapshot price any AH price is used. `units` = units bought.
export function reprice(snap: number | null, snapLabel: string | null, snapT: number | null, ah: AhPrice | undefined, units = 1): Priced | null {
	const fromSnap: Priced | null = snap !== null ? { copper: snap, source: "snapshot", label: snapLabel ?? "snapshot", t: snapT } : null;
	const fromAh: Priced | null = ah && ah.listed && ah.min !== null ? { copper: ah.min * units, source: "ah", label: "Horde AH now", t: ah.t } : null;
	if (!fromAh) return fromSnap;
	if (!fromSnap) return fromAh;
	if (snapT !== null && ah!.t <= snapT) return fromSnap;
	if (fixedSource(snapLabel)) return fromAh.copper < fromSnap.copper ? fromAh : fromSnap;
	return fromAh;
}

// ---- Crates -------------------------------------------------------------------------------------

export interface Bundle {
	n: number | null;
	name: string;
	id: number | null;
	cost: Priced | null;
	crafted: boolean; // the snapshot priced it as crafted by this character (and that is still the price used)
	best: boolean;
}

export interface Favor {
	amount: number;
	from: "tooltip" | "seen" | "guide" | "guide rule";
	observed: number | null;
}

export interface Crate {
	id: number;
	name: string;
	rank: Rank | null; // from the name (the snapshot's tier is the first word: "Earthly")
	tier: string | null;
	kind: string | null;
	held: number;
	crate: Priced | null;
	bundles: Bundle[];
	fill: Bundle | null; // the cheapest priced bundle
	favor: Favor | null;
	total: number | null; // crate + cheapest bundle
	perFavor: number | null;
	fillPerFavor: number | null;
	missing: string | null; // the snapshot's reason
}

export interface CrateList {
	list: Crate[];
	best: number | null; // cheapest to buy and fill per Favor
	bestHeld: number | null; // cheapest to fill per Favor among the crates held
	snapT: number | null;
}

// The item IDs whose current AH price the page needs: crates and bundles.
export function crateIds(data: J): number[] {
	const ids = new Set<number>();
	for (const c of arr(obj(obj(data)?.crates)?.list)) {
		const o = obj(c);
		const id = num(o?.id);
		if (id !== null) ids.add(id);
		for (const b of arr(o?.options)) {
			const bid = num(obj(b)?.id);
			if (bid !== null) ids.add(bid);
		}
	}
	return [...ids];
}

function measured(o: Record<string, J>): Favor | null {
	const reward = num(o.reward);
	const from = str(o.rewardFrom);
	if (reward === null || reward <= 0 || (from !== "tooltip" && from !== "seen")) return null;
	return { amount: reward, from, observed: num(o.observed) };
}

export function crateFavor(o: Record<string, J>, name: string | null): Favor | null {
	const m = measured(o);
	if (m) return m;
	const g = guideFavor(name);
	return g ? { amount: g.favor, from: g.basis === "listed" ? "guide" : "guide rule", observed: null } : null;
}

// Ranked as Crates.lua C.Ranked(): cost per Favor (crate + bundle) first, then fill-only cost per Favor, then
// by name. Prices are the newer of snapshot and AH (reprice), so best and bestHeld are worked out again.
export function crateList(data: J, snapT: number | null, prices: Map<number, AhPrice>): CrateList {
	const list: Crate[] = arr(obj(obj(data)?.crates)?.list).flatMap((c) => {
		const o = obj(c);
		const id = num(o?.id);
		if (!o || id === null) return [];
		const name = str(o.name) ?? `Item ${id}`;
		const parts = crateParts(name);
		const bundles: Bundle[] = arr(o.options).flatMap((b) => {
			const ob = obj(b);
			if (!ob) return [];
			const n = num(ob.n);
			const bid = num(ob.id);
			const how = str(ob.how);
			const cost = reprice(num(ob.cost), how, snapT, bid !== null ? prices.get(bid) : undefined, n ?? 1);
			return [{ n, name: str(ob.name) ?? (bid !== null ? `Item ${bid}` : "Unknown item"), id: bid, cost, crafted: cost?.source === "snapshot" && how === "crafted", best: false }];
		});
		let fill: Bundle | null = null;
		for (const b of bundles) if (b.cost && (!fill || b.cost.copper < fill.cost!.copper)) fill = b;
		if (fill) fill.best = true;
		const crate = reprice(num(o.crate), str(o.crateFrom), snapT, prices.get(id));
		const favor = crateFavor(o, name);
		const fillCost = fill?.cost?.copper ?? null;
		const total = crate && fillCost !== null ? crate.copper + fillCost : null;
		return [
			{
				id,
				name,
				rank: parts.rank,
				tier: str(o.tier),
				kind: parts.kind,
				held: num(o.held) ?? 0,
				crate,
				bundles,
				fill,
				favor,
				total,
				perFavor: favor && total !== null ? total / favor.amount : null,
				fillPerFavor: favor && fillCost !== null ? fillCost / favor.amount : null,
				missing: str(o.missing),
			},
		];
	});
	list.sort((a, b) => {
		if ((a.perFavor !== null) !== (b.perFavor !== null)) return a.perFavor !== null ? -1 : 1;
		if (a.perFavor !== null && a.perFavor !== b.perFavor) return a.perFavor - b.perFavor!;
		if ((a.fillPerFavor !== null) !== (b.fillPerFavor !== null)) return a.fillPerFavor !== null ? -1 : 1;
		if (a.fillPerFavor !== null && a.fillPerFavor !== b.fillPerFavor) return a.fillPerFavor - b.fillPerFavor!;
		return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
	});
	let bestHeld: Crate | null = null;
	for (const c of list) if (c.held > 0 && c.fillPerFavor !== null && (!bestHeld || c.fillPerFavor < bestHeld.fillPerFavor!)) bestHeld = c;
	return { list, best: list[0]?.perFavor != null ? list[0].id : null, bestHeld: bestHeld?.id ?? null, snapT };
}

// "15 Favor (measured, n=4)", "5 Favor (guide, beta)".
export function favorText(f: Favor | null): string {
	if (!f) return "Favor not known yet";
	if (f.from === "seen") return `${f.amount} Favor (measured${f.observed !== null ? `, n=${f.observed}` : ""})`;
	if (f.from === "tooltip") return `${f.amount} Favor (tooltip)`;
	if (f.from === "guide") return `${f.amount} Favor (guide, beta)`;
	return `${f.amount} Favor (guide rule, beta)`;
}

export const RANK_ORDER: string[] = ["Apprentice", "Journeyman", "Expert", "Artisan"];

// Tree groups: rank, then kind, in a fixed order; crates without a known rank under "Other".
export function crateGroups(list: Crate[]): { rank: string; kinds: { kind: string; n: number }[]; n: number }[] {
	const by = new Map<string, Map<string, number>>();
	for (const c of list) {
		const r = c.rank ?? "Other";
		const k = c.kind ?? "Other";
		const m = by.get(r) ?? new Map<string, number>();
		m.set(k, (m.get(k) ?? 0) + 1);
		by.set(r, m);
	}
	const order = (r: string) => (RANK_ORDER.includes(r) ? RANK_ORDER.indexOf(r) : RANK_ORDER.length);
	return [...by.entries()]
		.sort((a, b) => order(a[0]) - order(b[0]) || (a[0] < b[0] ? -1 : 1))
		.map(([rank, m]) => ({ rank, kinds: [...m.entries()].sort((a, b) => (a[0] < b[0] ? -1 : 1)).map(([kind, n]) => ({ kind, n })), n: [...m.values()].reduce((s, x) => s + x, 0) }));
}

export function matchesQuery(c: Crate, q: string): boolean {
	const t = q.trim().toLowerCase();
	if (!t) return true;
	return c.name.toLowerCase().includes(t) || c.bundles.some((b) => b.name.toLowerCase().includes(t));
}

// ---- Favor and its merchants ----------------------------------------------------------------------

export const STANDINGS = ["Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted"];

export interface Balance {
	name: string;
	balance: number | null;
	max: number | null;
	earned: number | null;
}

export interface Ware {
	id: number | null;
	name: string;
	favor: number;
	copper: number | null; // `p`: copper on top
	other: string | null;
	stack: number; // `s`, units bought
	req: string | null;
	reqMet: boolean | null; // null: the requirement is not a standing with this merchant's faction (or none)
	known: boolean;
	unusable: boolean;
	stock: number | null;
	value: { copper: number; basis: "current" | "typical"; t: number | null } | null; // AH value after the cut, whole purchase
	perFavor: number | null; // (value - copper on top) / favor
}

export interface Merchant {
	npc: number | null;
	name: string;
	zone: string | null;
	sub: string | null;
	faction: string | null;
	standing: string | null; // when the list was recorded
	standingNow: string | null;
	rep: { value: number; min: number; max: number } | null;
	full: boolean;
	t: number | null;
	wares: Ware[];
}

export function favorBalance(data: J): Balance | null {
	const f = obj(obj(data)?.favor);
	if (!f) return null;
	return { name: str(f.name) ?? "Merchant's Favor", balance: num(f.balance), max: num(f.max), earned: num(f.earned) };
}

export function favorIds(data: J): number[] {
	const ids = new Set<number>();
	for (const v of arr(obj(obj(data)?.favor)?.vendors)) for (const it of arr(obj(v)?.items)) {
		const id = num(obj(it)?.id);
		if (id !== null) ids.add(id);
	}
	return [...ids];
}

export function standingMet(req: string | null, now: string | null): boolean | null {
	if (!req || !now) return null;
	const r = STANDINGS.indexOf(req);
	const n = STANDINGS.indexOf(now);
	return r < 0 || n < 0 ? null : n >= r;
}

// AH value of one ware: the current lowest listed price, else the 7-day typical, after the house cut.
export function wareValue(price: AhPrice | undefined, stack: number): Ware["value"] {
	if (!price) return null;
	if (price.listed && price.min !== null) return { copper: Math.floor(price.min * stack * (1 - AH_CUT)), basis: "current", t: price.t };
	if (price.typical !== null) return { copper: Math.floor(price.typical * stack * (1 - AH_CUT)), basis: "typical", t: null };
	return null;
}

// The merchants with their wares ranked by AH value per Favor point (highest first); wares without an AH
// price follow, cheapest Favor first.
export function merchants(data: J, prices: Map<number, AhPrice>): Merchant[] {
	return arr(obj(obj(data)?.favor)?.vendors).flatMap((v) => {
		const o = obj(v);
		if (!o) return [];
		const standingNow = str(o.standingNow);
		const rep = obj(o.rep);
		const rv = num(rep?.value);
		const rmin = num(rep?.min);
		const rmax = num(rep?.max);
		const wares: Ware[] = arr(o.items).flatMap((it) => {
			const w = obj(it);
			const favor = num(w?.favor);
			if (!w || favor === null || favor <= 0) return [];
			const id = num(w.id);
			const stack = num(w.s) ?? 1;
			const copper = num(w.p);
			const req = str(w.req);
			const value = wareValue(id !== null ? prices.get(id) : undefined, stack);
			return [
				{
					id,
					name: str(w.name) ?? (id !== null ? `Item ${id}` : "Unknown item"),
					favor,
					copper,
					other: str(w.other),
					stack,
					req,
					reqMet: standingMet(req, standingNow),
					known: w.known === true,
					unusable: w.unusable === true,
					stock: num(w.n),
					value,
					perFavor: value ? (value.copper - (copper ?? 0)) / favor : null,
				},
			];
		});
		wares.sort((a, b) => {
			if ((a.perFavor !== null) !== (b.perFavor !== null)) return a.perFavor !== null ? -1 : 1;
			if (a.perFavor !== null && b.perFavor !== null && a.perFavor !== b.perFavor) return b.perFavor - a.perFavor;
			if (a.favor !== b.favor) return a.favor - b.favor;
			return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
		});
		return [
			{
				npc: num(o.npc),
				name: str(o.name) ?? "Merchant",
				zone: str(o.zone),
				sub: str(o.sub),
				faction: str(o.faction),
				standing: str(o.standing),
				standingNow,
				rep: rv !== null && rmin !== null && rmax !== null ? { value: rv, min: rmin, max: rmax } : null,
				full: o.full === true,
				t: num(o.t),
				wares,
			},
		];
	});
}

// What the merchant's ware costs besides Favor, and its flags, as short text.
export function wareNotes(w: Ware): string[] {
	const out: string[] = [];
	if (w.stack > 1) out.push(`stack of ${w.stack}`);
	if (w.other) out.push(`also ${w.other}`);
	if (w.known) out.push("already known");
	if (w.unusable) out.push("unusable for you");
	if (w.stock !== null) out.push(`${w.stock} in stock`);
	return out;
}
