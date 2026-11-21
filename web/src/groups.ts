// One auction house per slot (#382). Pure: no I/O, so the grouping and the merges are tested alone.
//
// Since the 20 Nov 2026 client update the realm name is hidden from addons, and the connected realms of a
// group share their auction houses (the Horde AH of Realms 4, 6 and 8 showed the same lowest price on all 327
// items compared). A house is "H", "A" or "N:<Zone>" with no realm. Rows uploaded before have "<realm>|H"
// and the like; at read time every row of the same slot is one house, whatever the realm:
//
//   - a faction house joins the faction house of the same faction (Horde with Horde, Alliance with
//     Alliance: opposite factions never merge) and a neutral house the neutral house of the same zone
//     ("N:Gadgetzan" with "N:Gadgetzan"). A faction house never joins a neutral one.
//   - the newest entry wins per item (mergeGroupPrices and the merges below, as Market.lua's MergeEntry).
//
// Stored rows stay per house key (no migration). The `connected` table of #366 (0009_connected.sql) is no
// longer read: the addon records no new pairs, and the grouping does not need them.
//
// The work of a merge is one pass over the rows of the group's members: bounded by the group size
// times the rows of a single house.

export interface HouseRow {
	id: number;
	key: string;
	realm: string;
	kind: string;
	faction: string | null;
	label: string;
	last_scan: number | null;
	last_full_scan: number | null;
	last_full_scan_items: number | null;
}

// The realm pairs of #366 (the upload still accepts them from an older companion); not used for grouping.
export interface Pair {
	a: string;
	b: string;
}

// One auction house as the site shows it. `house` is the row the group is known by (its key is the
// group's key); `ids` and `keys` are all the member rows, `realms` their realm names, sorted.
export interface Group {
	house: HouseRow;
	ids: number[];
	keys: string[];
	realms: string[];
}

// "CAMWOW EU4 Realm 4 PvP" -> "Realm 4", as the addon's Status line does; any other name stays whole.
export function shortRealm(name: string): string {
	return /Realm \d+/.exec(name)?.[0] ?? name;
}

// "H" -> "H", "<realm>|H" -> "H", "<realm>|N:Gadgetzan" -> "N:Gadgetzan": the key without its realm.
export function slot(key: string): string {
	const i = key.indexOf("|");
	return i < 0 ? key : key.slice(i + 1);
}

// The groups of `rows`, in the order of the first row of each. The group is known by its realm-less row
// when there is one, else by the member whose key sorts first; any member's key finds the group (groupOf).
export function groupHouses(rows: HouseRow[]): Group[] {
	const bySlot = new Map<string, HouseRow[]>();
	for (const h of rows) {
		const key = slot(h.key);
		let list = bySlot.get(key);
		if (!list) bySlot.set(key, (list = []));
		list.push(h);
	}
	const out: Group[] = [];
	for (const list of bySlot.values()) {
		const members = [...list].sort((x, y) => (x.key < y.key ? -1 : x.key > y.key ? 1 : 0));
		const first = members.find((m) => !m.key.includes("|")) ?? members[0]!;
		const realms = [...new Set(members.map((m) => m.realm).filter((r) => r !== ""))].sort();
		let house = first;
		if (members.length > 1) {
			let scan: number | null = null;
			let full: HouseRow | null = null;
			for (const m of members) {
				if (m.last_scan !== null && (scan === null || m.last_scan > scan)) scan = m.last_scan;
				if (m.last_full_scan !== null && (full === null || m.last_full_scan > full.last_full_scan!)) full = m;
			}
			house = {
				...first,
				last_scan: scan,
				last_full_scan: full?.last_full_scan ?? null,
				last_full_scan_items: full?.last_full_scan_items ?? null,
			};
		}
		out.push({ house, ids: members.map((m) => m.id), keys: members.map((m) => m.key), realms });
	}
	const at = new Map(rows.map((r, i) => [r.id, i]));
	const firstAt = (g: Group) => Math.min(...g.ids.map((i) => at.get(i)!));
	return out.sort((x, y) => firstAt(x) - firstAt(y));
}

// The group a house key belongs to (any member's key), or undefined.
export function groupOf(groups: Group[], key: string): Group | undefined {
	return groups.find((g) => g.keys.includes(key));
}

// House row id -> the id of the row its group is known by.
export function repIds(groups: Group[]): Map<number, number> {
	const out = new Map<number, number>();
	for (const g of groups) for (const id of g.ids) out.set(id, g.house.id);
	return out;
}

// ---------------------------------------------------------------------------------------------
// Merges. Same rules as CraftWise/Market.lua (MergeEntry), applied to the rows of several houses.
// ---------------------------------------------------------------------------------------------

export interface PriceLike {
	house: number;
	item: number;
	suffix: number;
	t: number;
	depth_t: number | null;
	depth_total: number | null;
	depth?: string | null;
}

// Per group, item and suffix the newest `last` wins (Market.lua: `b.t > a.t`; on a tie the first row
// stays). The depth is the newest depth of any member.
export function mergeGroupPrices<T extends PriceLike>(rows: T[], rep: Map<number, number>): T[] {
	const byKey = new Map<string, T>();
	for (const r of rows) {
		const house = rep.get(r.house) ?? r.house;
		const key = `${house}:${r.item}:${r.suffix}`;
		const o = byKey.get(key);
		if (!o) {
			byKey.set(key, { ...r, house });
			continue;
		}
		const [win, lose] = r.t > o.t ? [r, o] : [o, r];
		const merged: T = { ...win, house };
		if (lose.depth_t !== null && (win.depth_t === null || lose.depth_t > win.depth_t)) {
			merged.depth_t = lose.depth_t;
			merged.depth_total = lose.depth_total;
			merged.depth = lose.depth;
		}
		byKey.set(key, merged);
	}
	return [...byKey.values()];
}

export interface DayLike {
	house: number;
	item?: number; // when rows of several items are merged together (the top movers)
	suffix: number;
	day: number;
	src: number;
	lo: number | null;
	hi: number | null;
	qty_max: number | null;
	list_max: number | null;
	n: number | null;
}

const most = (a: number | null, b: number | null) => (a === null ? b : b === null ? a : Math.max(a, b));
const least = (a: number | null, b: number | null) => (a === null ? b : b === null ? a : Math.min(a, b));

// Per group, suffix and day: a CraftWise aggregate (src 1) beats a day built from `last` (src 0); of two
// aggregates the one with more points (`n`) wins and the first stays on a tie (Market.lua MergeEntry);
// two `last` days are combined (lowest lo, highest hi, most units and listings). Sorted by day.
export function mergeGroupDays<T extends DayLike>(rows: T[], rep: Map<number, number>): T[] {
	const byKey = new Map<string, T>();
	for (const r of rows) {
		const house = rep.get(r.house) ?? r.house;
		const key = `${house}:${r.item ?? ""}:${r.suffix}:${r.day}`;
		const o = byKey.get(key);
		if (!o) {
			byKey.set(key, { ...r, house });
		} else if (o.src === 0 && r.src === 0) {
			byKey.set(key, { ...o, lo: least(o.lo, r.lo), hi: most(o.hi, r.hi), qty_max: most(o.qty_max, r.qty_max), list_max: most(o.list_max, r.list_max) });
		} else if (r.src === 1 && (o.src === 0 || (r.n ?? 0) > (o.n ?? 0))) {
			byKey.set(key, { ...r, house });
		}
	}
	return [...byKey.values()].sort((a, b) => a.day - b.day);
}

export interface PointLike {
	house: number;
	suffix: number;
	t: number;
}

// Raw points are the union by time per group and suffix, as Market.lua keeps them (the first of a time stays).
export function mergeGroupPoints<T extends PointLike>(rows: T[], rep: Map<number, number>): T[] {
	const seen = new Set<string>();
	const out: T[] = [];
	for (const r of rows) {
		const house = rep.get(r.house) ?? r.house;
		const key = `${house}:${r.suffix}:${r.t}`;
		if (seen.has(key)) continue;
		seen.add(key);
		out.push({ ...r, house });
	}
	return out.sort((a, b) => a.t - b.t);
}
