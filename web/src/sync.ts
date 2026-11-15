// GET /api/sync/market (#238): the merged market for the companion of a second machine (#237).
// The body has the shape of POST /api/upload (web/docs/api.md), built from what uploads of every
// machine stored: per item and house the newest `last`, the raw points of the last 48 h and the
// CraftWise day aggregates of the last 30 days. Nothing is computed or filled in here.
// Reads only (plus the token's rate-limit row that uploadAuth counts).
import { uploadAuth } from "./auth";
import type { Env } from "./env";
import { HttpError, intParam, json } from "./http";
import { DAY, MIN_TIME, SYNC_BYTES, SYNC_DAYS, SYNC_LIMIT, SYNC_LIMIT_MAX, SYNC_RAW_SECONDS, SYNC_SCANS, SYNC_SAFETY } from "./limits";

interface PriceRow {
	house: number;
	item: number;
	suffix: number;
	t: number;
	min: number | null;
	qty: number | null;
	listings: number | null;
	off: number | null;
	updated: number;
}
interface VariantRow {
	house: number;
	item: number;
	data: string;
	updated: number;
}
interface PointRow {
	house: number;
	item: number;
	suffix: number;
	t: number;
	total: number;
	listings: number | null;
	m: number | null;
	tiers: string;
}
interface DayRow {
	house: number;
	item: number;
	suffix: number;
	day: number;
	lo: number | null;
	typ: number | null;
	hi: number | null;
	qty_max: number | null;
	list_max: number | null;
	n: number | null;
	gone: number | null;
}
interface ItemRow {
	id: number;
	name: string | null;
	quality: number | null;
	icon: number | null;
	class: number | null;
	subclass: number | null;
	sell_price: number | null;
	updated: number;
}

// The position after the last entry of a page: "p.<updated>.<house id>.<item>.<suffix>" while walking
// `prices`, "v.<updated>.<house id>.<item>.0" while walking `variants`.
interface Cursor {
	phase: "p" | "v";
	updated: number;
	house: number;
	item: number;
	suffix: number;
}
const CURSOR = /^([pv])\.(\d{1,12})\.(\d{1,9})\.(\d{1,10})\.(\d{1,10})$/;

function parseCursor(raw: string | null): Cursor | null {
	if (raw === null) return null;
	const m = CURSOR.exec(raw);
	if (!m) throw new HttpError(400, "bad_query", "cursor: not a cursor from this endpoint");
	return { phase: m[1] as "p" | "v", updated: Number(m[2]), house: Number(m[3]), item: Number(m[4]), suffix: Number(m[5]) };
}

function cursorText(c: Cursor): string {
	return `${c.phase}.${c.updated}.${c.house}.${c.item}.${c.suffix}`;
}

// Leaves out null fields: the upload contract has them optional ("what the addon doesn't have").
function compact<T extends Record<string, unknown>>(o: T): Partial<T> {
	const out: Record<string, unknown> = {};
	for (const [k, v] of Object.entries(o)) if (v !== null && v !== undefined) out[k] = v;
	return out as Partial<T>;
}

function itemKey(item: number, suffix: number): string {
	return suffix === 0 ? String(item) : `${item}:${suffix}`;
}

function sinceParam(url: URL): number {
	const raw = url.searchParams.get("since");
	if (raw === null || raw === "") return 0;
	if (!/^\d{1,12}$/.test(raw)) throw new HttpError(400, "bad_query", "since: expected Unix seconds");
	return Number(raw);
}

type Entry = {
	last?: Record<string, unknown>;
	raw?: Record<string, unknown>[];
	days?: Record<string, unknown>;
};

export async function syncMarket(request: Request, env: Env, url: URL, now: number): Promise<Response> {
	await uploadAuth(request, env, "public", now);
	const since = sinceParam(url);
	const limit = intParam(url, "limit", SYNC_LIMIT, 1, SYNC_LIMIT_MAX);
	const cursor = parseCursor(url.searchParams.get("cursor"));
	const db = env.DB;

	// 1. The next entries in index order: price rows first, then packed variants.
	let prices: PriceRow[] = [];
	if (!cursor || cursor.phase === "p") {
		const c = cursor ?? { updated: 0, house: 0, item: 0, suffix: -1 };
		const from = Math.max(since, c.updated);
		prices = (
			await db
				.prepare(
					`SELECT house, item, suffix, t, min, qty, listings, off, updated FROM prices
					WHERE updated >= ?1 AND (updated, house, item, suffix) > (?2, ?3, ?4, ?5)
					ORDER BY updated, house, item, suffix LIMIT ?6`,
				)
				.bind(from, c.updated, c.house, c.item, c.suffix, limit + 1)
				.all<PriceRow>()
		).results;
	}
	let variants: VariantRow[] = [];
	if (prices.length <= limit) {
		const c = cursor?.phase === "v" ? cursor : { updated: 0, house: 0, item: 0, suffix: 0 };
		const from = Math.max(since, c.updated);
		variants = (
			await db
				.prepare(
					`SELECT house, item, data, updated FROM variants
					WHERE updated >= ?1 AND (updated, house, item) > (?2, ?3, ?4)
					ORDER BY updated, house, item LIMIT ?5`,
				)
				.bind(from, c.updated, c.house, c.item, limit + 1 - prices.length)
				.all<VariantRow>()
		).results;
	}
	// a price row and a variant row are one unit each; more than `limit` units: a next page
	type Unit = { price: PriceRow } | { variant: VariantRow };
	const units: Unit[] = [...prices.map((price) => ({ price })), ...variants.map((variant) => ({ variant }))];
	let more = units.length > limit;
	if (more) units.length = limit;

	// 2. Their raw points, day aggregates and item info, houses, and on the first page the names and scans.
	const keys = JSON.stringify(
		units.flatMap((u) => ("price" in u ? [[u.price.house, u.price.item, u.price.suffix]] : [])),
	);
	const itemIds = JSON.stringify([...new Set(units.map((u) => ("price" in u ? u.price.item : u.variant.item)))]);
	const rawFrom = now - SYNC_RAW_SECONDS;
	const dayFrom = Math.floor(now / DAY) - SYNC_DAYS;
	const first = cursor === null;
	const statements = [
		db
			.prepare(
				`SELECT p.house, p.item, p.suffix, p.t, p.total, p.listings, p.m, p.tiers FROM json_each(?1) k
				JOIN points p ON p.house = k.value->>0 AND p.item = k.value->>1 AND p.suffix = k.value->>2 AND p.t >= ?2
				ORDER BY p.house, p.item, p.suffix, p.t`,
			)
			.bind(keys, rawFrom),
		db
			.prepare(
				`SELECT d.house, d.item, d.suffix, d.day, d.lo, d.typ, d.hi, d.qty_max, d.list_max, d.n, d.gone FROM json_each(?1) k
				JOIN daily d ON d.house = k.value->>0 AND d.item = k.value->>1 AND d.suffix = k.value->>2 AND d.day >= ?2 AND d.src = 1
				ORDER BY d.house, d.item, d.suffix, d.day`,
			)
			.bind(keys, dayFrom),
		db
			.prepare("SELECT id, name, quality, icon, class, subclass, sell_price, updated FROM items WHERE id IN (SELECT value FROM json_each(?1))")
			.bind(itemIds),
		db.prepare("SELECT id, key, realm, kind, faction, label FROM houses ORDER BY id"),
		...(first
			? [
					db.prepare("SELECT class, name FROM item_classes ORDER BY class"),
					db.prepare("SELECT class, subclass, name FROM item_subclasses ORDER BY class, subclass"),
					db
						.prepare(
							`SELECT h.key AS house, s.t, s.kind, s.items, s.last_only, s.source FROM scans s JOIN houses h ON h.id = s.house
							ORDER BY s.t DESC LIMIT ?1`,
						)
						.bind(SYNC_SCANS),
				]
			: []),
	];
	const [points, days, items, houseRows, classes, subclasses, scanRows] = await db.batch(statements);

	// 3. The body, in the upload shape. A page is cut when it passes SYNC_BYTES (an estimate).
	const houseKey = new Map<number, string>();
	const houses: Record<string, unknown> = {};
	for (const h of houseRows!.results as unknown as { id: number; key: string; realm: string; kind: string; faction: string | null; label: string }[]) {
		houseKey.set(h.id, h.key);
		houses[h.key] = compact({ realm: h.realm, kind: h.kind, faction: h.faction, label: h.label });
	}
	const pointsBy = new Map<string, Record<string, unknown>[]>();
	for (const p of points!.results as unknown as PointRow[]) {
		const flat = JSON.parse(p.tiers) as number[];
		const tiers = [];
		for (let i = 0; i + 1 < flat.length; i += 2) tiers.push({ price: flat[i]!, qty: flat[i + 1]! });
		const k = `${p.house}:${p.item}:${p.suffix}`;
		let list = pointsBy.get(k);
		if (!list) pointsBy.set(k, (list = []));
		list.push(compact({ t: p.t, total: p.total, listings: p.listings, m: p.m, tiers }));
	}
	const daysBy = new Map<string, Record<string, unknown>>();
	for (const d of days!.results as unknown as DayRow[]) {
		const k = `${d.house}:${d.item}:${d.suffix}`;
		let map = daysBy.get(k);
		if (!map) daysBy.set(k, (map = {}));
		map[String(d.day)] = compact({ lo: d.lo, typ: d.typ, hi: d.hi, qtyMax: d.qty_max, listMax: d.list_max, n: d.n, gone: d.gone });
	}

	const out: Record<string, Record<string, Entry>> = {};
	const ids = new Set<number>();
	let bytes = 0;
	let last: Cursor | null = null;
	let taken = 0;
	for (const u of units) {
		let size = 0;
		const entries: [number, number, number, Entry][] = [];
		if ("price" in u) {
			const p = u.price;
			const e: Entry = {};
			if (p.min !== null && p.qty !== null) e.last = compact({ t: p.t, min: p.min, qty: p.qty, listings: p.listings, off: p.off });
			const raw = pointsBy.get(`${p.house}:${p.item}:${p.suffix}`);
			if (raw) e.raw = raw;
			const d = daysBy.get(`${p.house}:${p.item}:${p.suffix}`);
			if (d) e.days = d;
			size = 120 + (raw ? raw.length * 90 + raw.reduce((s, r) => s + (r.tiers as unknown[]).length * 24, 0) : 0) + (d ? Object.keys(d).length * 110 : 0);
			if (e.last || e.raw || e.days) entries.push([p.item, p.suffix, p.house, e]);
		} else {
			const v = u.variant;
			const parsed = JSON.parse(v.data) as Record<string, (number | null)[]>;
			for (const [suffix, a] of Object.entries(parsed)) {
				if (a[1] === null || a[1] === undefined || a[2] === null || a[2] === undefined) continue;
				entries.push([v.item, Number(suffix), v.house, { last: compact({ t: a[0], min: a[1], qty: a[2], listings: a[3], off: a[4] }) }]);
				size += 130;
			}
		}
		// the page ends before an entry that would take it over the size limit (but holds at least one)
		if (taken > 0 && bytes + size > SYNC_BYTES) {
			more = true;
			break;
		}
		for (const [item, suffix, house, e] of entries) {
			const hk = houseKey.get(house);
			if (hk === undefined) continue;
			(out[itemKey(item, suffix)] ??= {})[hk] = e;
			ids.add(item);
		}
		bytes += size;
		taken++;
		last =
			"price" in u
				? { phase: "p", updated: u.price.updated, house: u.price.house, item: u.price.item, suffix: u.price.suffix }
				: { phase: "v", updated: u.variant.updated, house: u.variant.house, item: u.variant.item, suffix: 0 };
	}

	const names: Record<string, string> = {};
	const itemInfo: Record<string, unknown> = {};
	for (const i of items!.results as unknown as ItemRow[]) {
		if (!ids.has(i.id)) continue;
		if (i.name !== null) names[String(i.id)] = i.name;
		const info = compact({ q: i.quality, i: i.icon, c: i.class, s: i.subclass, t: i.updated, p: i.sell_price });
		if (Object.keys(info).length > 1) itemInfo[String(i.id)] = info;
	}

	const body: Record<string, unknown> = { v: 1, houses, names, itemInfo, items: out };
	if (first) {
		const classNames: Record<string, string> = {};
		for (const c of classes!.results as unknown as { class: number; name: string }[]) classNames[String(c.class)] = c.name;
		const subclassNames: Record<string, Record<string, string>> = {};
		for (const s of subclasses!.results as unknown as { class: number; subclass: number; name: string }[]) {
			(subclassNames[String(s.class)] ??= {})[String(s.subclass)] = s.name;
		}
		const scans: Record<string, unknown[]> = {};
		for (const s of scanRows!.results as unknown as { house: string; t: number; kind: string; items: number | null; last_only: number | null; source: string | null }[]) {
			(scans[s.house] ??= []).push(compact({ t: s.t, kind: s.kind, items: s.items, lastOnly: s.last_only, source: s.source }));
		}
		body.scans = scans;
		body.classNames = classNames;
		body.subclassNames = subclassNames;
	}
	body.next = more && last ? cursorText(last) : null;
	// what to send as `since` next time: a margin behind now, so a write that was still running
	// when this was read is returned again (merging is idempotent)
	body.until = Math.max(MIN_TIME, now - SYNC_SAFETY);
	return json(body, 200, { "cache-control": "private, no-store" });
}
