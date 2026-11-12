// Public read API: houses, recent scans, item search, item detail, top movers.
import type { Env } from "./env";
import { HttpError, intParam, json } from "./http";
import * as L from "./limits";
import { dayNumber, listed, medianFloor, tierList, typical, type Typical } from "./market";
import { nameWords } from "./upload";

const CACHE = { "cache-control": `public, max-age=${L.PUBLIC_MAX_AGE}` };

interface HouseRow {
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

interface PriceRow {
	house: number;
	item: number;
	suffix: number;
	t: number;
	min: number | null;
	qty: number | null;
	listings: number | null;
	off: number | null;
	depth_t: number | null;
	depth_total: number | null;
	depth?: string | null;
}

interface ItemRow {
	id: number;
	name: string | null;
	quality: number | null;
	icon: number | null;
	class: number | null;
	subclass: number | null;
	sell_price: number | null;
}

// The client's class and subclass names (#120, migrations/0003_names_sell_price.sql), null where none
// was uploaded (the site then falls back to Blizzard's enum identifiers).
interface ClassNames {
	cls: Map<number, string>;
	sub: Map<string, string>;
}
const NO_NAMES: ClassNames = { cls: new Map(), sub: new Map() };

// Statements reading the names of the given classes (all of them, subclasses included).
function classNameStatements(db: D1Database, classes: Iterable<number | null>): [D1PreparedStatement, D1PreparedStatement] {
	const list = JSON.stringify([...new Set([...classes].filter((c): c is number => c !== null))]);
	return [
		db.prepare("SELECT class, name FROM item_classes WHERE class IN (SELECT value FROM json_each(?1))").bind(list),
		db.prepare("SELECT class, subclass, name FROM item_subclasses WHERE class IN (SELECT value FROM json_each(?1))").bind(list),
	];
}
function classNamesOf(cls: D1Result, sub: D1Result): ClassNames {
	return {
		cls: new Map((cls.results as { class: number; name: string }[]).map((r) => [r.class, r.name])),
		sub: new Map((sub.results as { class: number; subclass: number; name: string }[]).map((r) => [`${r.class}:${r.subclass}`, r.name])),
	};
}
async function readClassNames(env: Env, classes: Iterable<number | null>): Promise<ClassNames> {
	const list = [...classes];
	if (!list.some((c) => c !== null)) return NO_NAMES;
	const [cls, sub] = await env.DB.batch(classNameStatements(env.DB, list));
	return classNamesOf(cls!, sub!);
}
function namesOut(names: ClassNames, cls: number | null, sub: number | null) {
	return {
		className: cls === null ? null : (names.cls.get(cls) ?? null),
		subclassName: cls === null || sub === null ? null : (names.sub.get(`${cls}:${sub}`) ?? null),
	};
}

async function allHouses(env: Env): Promise<HouseRow[]> {
	const { results } = await env.DB.prepare(
		"SELECT * FROM houses ORDER BY kind = 'faction' DESC, realm, label",
	).all<HouseRow>();
	return results;
}

function houseOut(h: HouseRow) {
	return {
		key: h.key,
		realm: h.realm,
		kind: h.kind,
		faction: h.faction,
		label: h.label,
		lastScan: h.last_scan,
		lastFullScan: h.last_full_scan,
		lastFullScanItems: h.last_full_scan_items,
	};
}

function itemOut(i: ItemRow, names: ClassNames) {
	return {
		id: i.id,
		name: i.name,
		quality: i.quality,
		icon: i.icon,
		class: i.class,
		subclass: i.subclass,
		...namesOut(names, i.class, i.subclass),
		sellPrice: i.sell_price ?? null,
	};
}

// Random-suffix variants packed per item (#118, migrations/0002_variants.sql) as price rows.
interface VariantRow {
	house: number;
	item: number;
	data: string;
}
function variantPrices(rows: VariantRow[]): PriceRow[] {
	const out: PriceRow[] = [];
	for (const r of rows) {
		for (const [s, v] of Object.entries(JSON.parse(r.data) as Record<string, (number | null)[]>)) {
			out.push({ house: r.house, item: r.item, suffix: Number(s), t: v[0]!, min: v[1]!, qty: v[2]!, listings: v[3] ?? null, off: v[4] ?? null, depth_t: null, depth_total: null, depth: null });
		}
	}
	return out;
}

// `prices` rows plus packed variants: per house, item and suffix the newer `t` is the current
// price; a depth stored in `prices` stays. Sorted by house, item, suffix.
function mergePrices(rows: PriceRow[], variants: PriceRow[]): PriceRow[] {
	const byKey = new Map(rows.map((r) => [`${r.house}:${r.item}:${r.suffix}`, r]));
	for (const v of variants) {
		const key = `${v.house}:${v.item}:${v.suffix}`;
		const p = byKey.get(key);
		if (!p) byKey.set(key, v);
		else if (v.t > p.t) byKey.set(key, { ...p, t: v.t, min: v.min, qty: v.qty, listings: v.listings, off: v.off });
	}
	return [...byKey.values()].sort((a, b) => a.house - b.house || a.item - b.item || a.suffix - b.suffix);
}

function currentOut(p: PriceRow) {
	return { t: p.t, min: p.min, qty: p.qty, listings: p.listings, off: p.off, listed: listed(p) };
}

export async function houses(env: Env): Promise<Response> {
	return json({ houses: (await allHouses(env)).map(houseOut) }, 200, CACHE);
}

export async function scans(env: Env, url: URL): Promise<Response> {
	const limit = intParam(url, "limit", L.SCANS_LIMIT, 1, L.SCANS_MAX);
	const house = url.searchParams.get("house");
	const sql = `SELECT s.t, s.kind, s.items, s.last_only, s.source, h.key, h.label FROM scans s JOIN houses h ON h.id = s.house
		${house ? "WHERE h.key = ?2" : ""} ORDER BY s.t DESC LIMIT ?1`;
	const stmt = house ? env.DB.prepare(sql).bind(limit, house) : env.DB.prepare(sql).bind(limit);
	const { results } = await stmt.all<{ t: number; kind: string; items: number | null; last_only: number | null; source: string | null; key: string; label: string }>();
	return json(
		{
			scans: results.map((s) => ({ house: s.key, label: s.label, t: s.t, kind: s.kind, items: s.items, lastOnly: s.last_only, source: s.source })),
		},
		200,
		CACHE,
	);
}

// Items whose name matches every word of `q` (word prefixes), or the item with that ID.
async function findItems(env: Env, q: string, limit: number): Promise<ItemRow[]> {
	if (/^[1-9][0-9]{0,9}$/.test(q)) {
		return (await env.DB.prepare("SELECT * FROM items WHERE id = ?1").bind(Number(q)).all<ItemRow>()).results;
	}
	const words = nameWords(q).slice(0, 5);
	if (words.join("").length < 2) {
		throw new HttpError(400, "bad_query", "q needs at least 2 letters or an item ID");
	}
	const where = words.map((_, i) => `id IN (SELECT item FROM item_words WHERE word >= ?${2 * i + 2} AND word < ?${2 * i + 3})`).join(" AND ");
	const params: (string | number)[] = [limit];
	for (const w of words) params.push(w, w + "\u{10FFFF}");
	return (await env.DB.prepare(`SELECT * FROM items WHERE ${where} ORDER BY name LIMIT ?1`).bind(...params).all<ItemRow>()).results;
}

export async function search(env: Env, url: URL): Promise<Response> {
	const q = (url.searchParams.get("q") ?? "").trim();
	const limit = intParam(url, "limit", L.SEARCH_LIMIT, 1, L.SEARCH_MAX);
	const items = await findItems(env, q, limit);
	const hs = await allHouses(env);
	const byId = new Map(hs.map((h) => [h.id, h]));
	let prices: PriceRow[] = [];
	let names = NO_NAMES;
	if (items.length) {
		const ids = JSON.stringify(items.map((i) => i.id));
		const [rows, variants, cls, sub] = await env.DB.batch([
			env.DB.prepare(
				`SELECT house, item, suffix, t, min, qty, listings, off, depth_t, depth_total FROM prices
				WHERE house IN (SELECT id FROM houses) AND item IN (SELECT value FROM json_each(?1))`,
			).bind(ids),
			env.DB.prepare("SELECT house, item, data FROM variants WHERE house IN (SELECT id FROM houses) AND item IN (SELECT value FROM json_each(?1))").bind(ids),
			...classNameStatements(env.DB, items.map((i) => i.class)),
		]);
		prices = mergePrices(rows!.results as unknown as PriceRow[], variantPrices(variants!.results as unknown as VariantRow[]));
		names = classNamesOf(cls!, sub!);
	}
	return json(
		{
			query: q,
			items: items.map((i) => ({
				...itemOut(i, names),
				prices: prices
					.filter((p) => p.item === i.id)
					.map((p) => ({ house: byId.get(p.house)!.key, label: byId.get(p.house)!.label, suffix: p.suffix, ...currentOut(p) })),
			})),
		},
		200,
		CACHE,
	);
}

interface DailyRow {
	house: number;
	suffix: number;
	day: number;
	src: number;
	lo: number | null;
	typ: number | null;
	hi: number | null;
	qty_max: number | null;
	list_max: number | null;
	n: number | null;
	gone: number | null;
}

interface PointRow {
	house: number;
	suffix: number;
	t: number;
	total: number;
	listings: number | null;
	m: number | null;
	tiers: string;
}

interface VariantDayRow {
	house: number;
	day: number;
	data: string;
}

// `daily` rows plus packed variant days (src 0): a CraftWise aggregate (src 1) wins the day, two
// rows built from `last` are combined (lowest lo, highest hi, most units and listings). By day.
function mergeDays(rows: DailyRow[], variantDays: VariantDayRow[]): DailyRow[] {
	const byKey = new Map(rows.map((r) => [`${r.house}:${r.suffix}:${r.day}`, r]));
	const most = (a: number | null, b: number | null) => (a === null ? b : b === null ? a : Math.max(a, b));
	for (const r of variantDays) {
		for (const [s, v] of Object.entries(JSON.parse(r.data) as Record<string, (number | null)[]>)) {
			const d: DailyRow = { house: r.house, suffix: Number(s), day: r.day, src: 0, lo: v[0]!, typ: null, hi: v[1]!, qty_max: v[2]!, list_max: v[3] ?? null, n: null, gone: null };
			const key = `${d.house}:${d.suffix}:${d.day}`;
			const o = byKey.get(key);
			if (!o) byKey.set(key, d);
			else if (o.src === 0) {
				byKey.set(key, { ...o, lo: Math.min(o.lo ?? d.lo!, d.lo!), hi: Math.max(o.hi ?? d.hi!, d.hi!), qty_max: most(o.qty_max, d.qty_max), list_max: most(o.list_max, d.list_max) });
			}
		}
	}
	return [...byKey.values()].sort((a, b) => a.day - b.day);
}

export async function itemDetail(env: Env, url: URL, id: number, now: number): Promise<Response> {
	const days = intParam(url, "days", L.HISTORY_DAYS, L.TYPICAL_DAYS, L.HISTORY_DAYS_MAX);
	const hours = intParam(url, "hours", L.RAW_HOURS, 0, L.RAW_HOURS_MAX);
	const today = dayNumber(now);
	const db = env.DB;
	const [item, prices, daily, points, variants, variantDays] = await db.batch([
		db.prepare(
			`SELECT i.*, c.name AS class_name, s.name AS subclass_name FROM items i
			LEFT JOIN item_classes c ON c.class = i.class
			LEFT JOIN item_subclasses s ON s.class = i.class AND s.subclass = i.subclass
			WHERE i.id = ?1`,
		).bind(id),
		db.prepare("SELECT * FROM prices WHERE house IN (SELECT id FROM houses) AND item = ?1").bind(id),
		db.prepare(
			`SELECT house, suffix, day, src, lo, typ, hi, qty_max, list_max, n, gone FROM daily
			WHERE house IN (SELECT id FROM houses) AND item = ?1 AND day > ?2 ORDER BY day`,
		).bind(id, today - days),
		db.prepare(
			`SELECT house, suffix, t, total, listings, m, tiers FROM points
			WHERE house IN (SELECT id FROM houses) AND item = ?1 AND t >= ?2 ORDER BY t`,
		).bind(id, now - hours * 3600),
		db.prepare("SELECT house, item, data FROM variants WHERE house IN (SELECT id FROM houses) AND item = ?1").bind(id),
		db.prepare("SELECT house, day, data FROM variant_days WHERE house IN (SELECT id FROM houses) AND item = ?1 AND day > ?2").bind(id, today - days),
	]);
	const info = (item!.results as unknown as (ItemRow & { class_name: string | null; subclass_name: string | null })[])[0] ?? null;
	const priceRows = mergePrices(prices!.results as unknown as PriceRow[], variantPrices(variants!.results as unknown as VariantRow[]));
	const dailyRows = mergeDays(daily!.results as unknown as DailyRow[], variantDays!.results as unknown as VariantDayRow[]);
	const pointRows = points!.results as unknown as PointRow[];
	if (!info && !priceRows.length && !dailyRows.length) {
		throw new HttpError(404, "not_found", `no data for item ${id}`);
	}

	const hs = await allHouses(env);
	const markets = new Map<string, { house: HouseRow; suffix: number; price: PriceRow | null; days: DailyRow[]; raw: PointRow[] }>();
	const market = (house: number, suffix: number) => {
		const key = `${house}:${suffix}`;
		let m = markets.get(key);
		if (!m) {
			m = { house: hs.find((h) => h.id === house)!, suffix, price: null, days: [], raw: [] };
			markets.set(key, m);
		}
		return m;
	};
	for (const p of priceRows) market(p.house, p.suffix).price = p;
	for (const d of dailyRows) market(d.house, d.suffix).days.push(d);
	for (const r of pointRows) market(r.house, r.suffix).raw.push(r);

	const order = new Map(hs.map((h, i) => [h.id, i]));
	const out = [...markets.values()]
		.sort((a, b) => order.get(a.house.id)! - order.get(b.house.id)! || a.suffix - b.suffix)
		.map((m) => {
			const p = m.price;
			const typ: Typical = typical(m.days, today, Boolean(p || m.days.length || m.raw.length));
			return {
				house: m.house.key,
				label: m.house.label,
				kind: m.house.kind,
				lastScan: m.house.last_scan,
				suffix: m.suffix,
				current: p ? currentOut(p) : null,
				depth: p && p.depth_t !== null ? { t: p.depth_t, total: p.depth_total, tiers: tierList(p.depth ?? null) } : null,
				typical: typ,
				days: m.days.map((d) => ({
					day: d.day,
					src: d.src === 1 ? "craftwise" : "last",
					lo: d.lo,
					typ: d.typ,
					hi: d.hi,
					qtyMax: d.qty_max,
					listMax: d.list_max,
					n: d.n,
					gone: d.gone,
				})),
				raw: m.raw.map((r) => ({ t: r.t, total: r.total, listings: r.listings, m: r.m, tiers: tierList(r.tiers) })),
			};
		});
	const names: ClassNames = {
		cls: new Map(info && info.class !== null && info.class_name !== null ? [[info.class, info.class_name]] : []),
		sub: new Map(info && info.subclass_name !== null ? [[`${info.class}:${info.subclass}`, info.subclass_name]] : []),
	};
	return json({ id, item: info ? itemOut(info, names) : null, markets: out }, 200, CACHE);
}

interface Mover {
	item: number;
	suffix: number;
	name: string | null;
	quality: number | null;
	icon: number | null;
	t: number;
	min: number;
	qty: number | null;
	listings: number | null;
	typical: number;
	typicalDays: number;
	change: number;
}

// Items whose current lowest price is furthest above (up) or below (down) their typical price.
// Only items with a typical price (CraftWise history of at least 3 of the last 7 days) and a
// listed price seen in the last 2 days. Cached in D1 until the house's next scan or the next day.
export async function movers(env: Env, url: URL, now: number): Promise<Response> {
	const key = url.searchParams.get("house");
	const limit = intParam(url, "limit", L.MOVERS_LIMIT, 1, L.MOVERS_MAX);
	if (!key) throw new HttpError(400, "bad_query", "house is required");
	const db = env.DB;
	const house = await db.prepare("SELECT * FROM houses WHERE key = ?1").bind(key).first<HouseRow>();
	if (!house) throw new HttpError(404, "not_found", "unknown house");
	const today = dayNumber(now);
	const cacheKey = `movers:${house.id}`;
	const cached = await db.prepare("SELECT t, data FROM cache WHERE key = ?1").bind(cacheKey).first<{ t: number; data: string }>();
	let result: { computedAt: number; up: Mover[]; down: Mover[] };
	if (cached && cached.t >= (house.last_scan ?? 0) && dayNumber(cached.t) === today) {
		result = JSON.parse(cached.data);
	} else {
		// Items with a typical price (>= 3 of the last 7 days) and a recent price; SQLite does the
		// join so only those rows reach the Worker.
		const { results } = await db
			.prepare(
				`SELECT p.item, p.suffix, p.t, p.min, p.qty, p.listings, p.off, p.depth_t, p.depth_total, d.typs
				FROM (SELECT item, suffix, group_concat(typ) AS typs FROM daily
					WHERE house = ?1 AND day > ?3 AND day <= ?4 AND typ IS NOT NULL
					GROUP BY item, suffix HAVING count(*) >= ?5) d
				JOIN prices p ON p.house = ?1 AND p.item = d.item AND p.suffix = d.suffix
				WHERE p.t >= ?2 AND p.min IS NOT NULL`,
			)
			.bind(house.id, now - L.MOVERS_MAX_AGE, today - L.TYPICAL_DAYS, today, L.MIN_HISTORY_DAYS)
			.all<PriceRow & { typs: string }>();
		const list: Mover[] = [];
		for (const p of results) {
			if (!listed(p)) continue;
			const typs = p.typs.split(",").map(Number).sort((a, b) => a - b);
			const typ = medianFloor(typs);
			if (typ <= 0) continue;
			list.push({
				item: p.item,
				suffix: p.suffix,
				name: null,
				quality: null,
				icon: null,
				t: p.t,
				min: p.min!,
				qty: p.qty,
				listings: p.listings,
				typical: typ,
				typicalDays: typs.length,
				change: Math.round(((p.min! - typ) / typ) * 10000) / 10000,
			});
		}
		const up = list.filter((m) => m.change > 0).sort((a, b) => b.change - a.change).slice(0, L.MOVERS_MAX);
		const down = list.filter((m) => m.change < 0).sort((a, b) => a.change - b.change).slice(0, L.MOVERS_MAX);
		const ids = [...new Set([...up, ...down].map((m) => m.item))];
		if (ids.length) {
			const { results } = await db
				.prepare("SELECT id, name, quality, icon FROM items WHERE id IN (SELECT value FROM json_each(?1))")
				.bind(JSON.stringify(ids))
				.all<ItemRow>();
			const info = new Map(results.map((r) => [r.id, r]));
			for (const m of [...up, ...down]) {
				const i = info.get(m.item);
				m.name = i?.name ?? null;
				m.quality = i?.quality ?? null;
				m.icon = i?.icon ?? null;
			}
		}
		result = { computedAt: now, up, down };
		await db
			.prepare("INSERT INTO cache (key, t, data) VALUES (?1, ?2, ?3) ON CONFLICT (key) DO UPDATE SET t = excluded.t, data = excluded.data")
			.bind(cacheKey, now, JSON.stringify(result))
			.run();
	}
	return json(
		{ house: house.key, label: house.label, computedAt: result.computedAt, up: result.up.slice(0, limit), down: result.down.slice(0, limit) },
		200,
		CACHE,
	);
}

// ------------------------------------------------------------------------------------------
// Browse (#97): the site's item list, one house at a time.
// ------------------------------------------------------------------------------------------

async function houseParam(env: Env, url: URL): Promise<HouseRow> {
	const key = url.searchParams.get("house");
	if (!key) throw new HttpError(400, "bad_query", "house is required");
	const house = await env.DB.prepare("SELECT * FROM houses WHERE key = ?1").bind(key).first<HouseRow>();
	if (!house) throw new HttpError(404, "not_found", "unknown house");
	return house;
}

// Item class and subclass (null without item info) -> the items priced at the house (suffix 0).
type CategoryList = [number | null, number | null, number[]][];
interface CategoryIndex {
	computedAt: number;
	cats: CategoryList;
}

// Built from every price row of the house (one read per item and its info), so it is cached in D1
// until the house's next scan or the next UTC day, like the top movers.
async function categoryIndex(env: Env, house: HouseRow, now: number): Promise<CategoryIndex> {
	const db = env.DB;
	const cacheKey = `categories:${house.id}`;
	const cached = await db.prepare("SELECT t, data FROM cache WHERE key = ?1").bind(cacheKey).first<{ t: number; data: string }>();
	if (cached && cached.t >= (house.last_scan ?? 0) && dayNumber(cached.t) === dayNumber(now)) {
		return JSON.parse(cached.data) as CategoryIndex;
	}
	const { results } = await db
		.prepare(
			`SELECT p.item, i.class, i.subclass FROM prices p LEFT JOIN items i ON i.id = p.item
			WHERE p.house = ?1 AND p.suffix = 0 ORDER BY i.class, i.subclass, p.item`,
		)
		.bind(house.id)
		.all<{ item: number; class: number | null; subclass: number | null }>();
	const cats: CategoryList = [];
	let last: CategoryList[number] | undefined;
	for (const r of results) {
		if (!last || last[0] !== r.class || last[1] !== r.subclass) {
			last = [r.class, r.subclass, []];
			cats.push(last);
		}
		last[2].push(r.item);
	}
	const index: CategoryIndex = { computedAt: now, cats };
	await db
		.prepare("INSERT INTO cache (key, t, data) VALUES (?1, ?2, ?3) ON CONFLICT (key) DO UPDATE SET t = excluded.t, data = excluded.data")
		.bind(cacheKey, now, JSON.stringify(index))
		.run();
	return index;
}

export async function categories(env: Env, url: URL, now: number): Promise<Response> {
	const house = await houseParam(env, url);
	const index = await categoryIndex(env, house, now);
	// Names are read on every request (a few dozen rows), so a name uploaded after the index was built
	// shows at once.
	const names = await readClassNames(env, index.cats.map(([c]) => c));
	return json(
		{
			house: house.key,
			label: house.label,
			lastScan: house.last_scan,
			computedAt: index.computedAt,
			categories: index.cats.map(([c, s, ids]) => ({ class: c, subclass: s, ...namesOut(names, c, s), items: ids.length })),
		},
		200,
		CACHE,
	);
}

function classParam(raw: string | null, name: string): number | null | undefined {
	if (raw === null) return undefined;
	if (raw === "none") return null;
	if (!/^(0|[1-9][0-9]{0,4})$/.test(raw)) throw new HttpError(400, "bad_query", `${name} must be a number or "none"`);
	return Number(raw);
}

// One of: class (+ subclass), q (as /api/items), ids (comma-separated). Every item with its info,
// its current price at the house, its typical price and the daily rows of the last BROWSE_DAYS days.
export async function browse(env: Env, url: URL, now: number): Promise<Response> {
	const house = await houseParam(env, url);
	const today = dayNumber(now);
	const q = url.searchParams.get("q");
	const idsRaw = url.searchParams.get("ids");
	const cls = classParam(url.searchParams.get("class"), "class");
	const sub = classParam(url.searchParams.get("subclass"), "subclass");
	if (Number(q !== null) + Number(idsRaw !== null) + Number(cls !== undefined) !== 1) {
		throw new HttpError(400, "bad_query", "give exactly one of class, q or ids");
	}
	let ids: number[];
	if (q !== null) {
		ids = (await findItems(env, q.trim(), L.SEARCH_MAX)).map((i) => i.id);
	} else if (idsRaw !== null) {
		const parts = idsRaw.split(",").filter((p) => p !== "");
		if (parts.length > L.BROWSE_IDS_MAX || !parts.every((p) => /^[1-9][0-9]{0,9}$/.test(p))) {
			throw new HttpError(400, "bad_query", `ids: at most ${L.BROWSE_IDS_MAX} item IDs, comma-separated`);
		}
		ids = [...new Set(parts.map(Number))];
	} else {
		const index = await categoryIndex(env, house, now);
		ids = index.cats.filter(([c, s]) => c === cls && (sub === undefined || s === sub)).flatMap(([, , list]) => list);
	}
	const more = ids.length > L.BROWSE_MAX;
	if (more) ids = ids.slice(0, L.BROWSE_MAX);

	const db = env.DB;
	const list = JSON.stringify(ids);
	const [items, prices, daily] = ids.length
		? await db.batch([
				db.prepare("SELECT * FROM items WHERE id IN (SELECT value FROM json_each(?1))").bind(list),
				db.prepare("SELECT * FROM prices WHERE house = ?1 AND suffix = 0 AND item IN (SELECT value FROM json_each(?2))").bind(house.id, list),
				db.prepare(
					`SELECT item, day, src, lo, typ, hi, qty_max FROM daily
					WHERE house = ?1 AND suffix = 0 AND item IN (SELECT value FROM json_each(?2)) AND day > ?3 ORDER BY item, day`,
				).bind(house.id, list, today - L.BROWSE_DAYS),
			])
		: [{ results: [] }, { results: [] }, { results: [] }];
	const info = new Map((items!.results as unknown as ItemRow[]).map((i) => [i.id, i]));
	const names = await readClassNames(env, [...info.values()].map((i) => i.class));
	const price = new Map((prices!.results as unknown as PriceRow[]).map((p) => [p.item, p]));
	const days = new Map<number, (DailyRow & { item: number })[]>();
	for (const d of daily!.results as unknown as (DailyRow & { item: number })[]) {
		let l = days.get(d.item);
		if (!l) days.set(d.item, (l = []));
		l.push(d);
	}
	return json(
		{
			house: house.key,
			label: house.label,
			lastScan: house.last_scan,
			today,
			more,
			items: ids.map((id) => {
				const i = info.get(id);
				const p = price.get(id) ?? null;
				const d = days.get(id) ?? [];
				return {
					id,
					name: i?.name ?? null,
					quality: i?.quality ?? null,
					icon: i?.icon ?? null,
					class: i?.class ?? null,
					subclass: i?.subclass ?? null,
					...namesOut(names, i?.class ?? null, i?.subclass ?? null),
					sellPrice: i?.sell_price ?? null,
					current: p ? currentOut(p) : null,
					typical: typical(d, today, Boolean(p || d.length)),
					days: d.map((r) => ({ day: r.day, src: r.src === 1 ? "craftwise" : "last", lo: r.lo, typ: r.typ, hi: r.hi, qtyMax: r.qty_max })),
				};
			}),
		},
		200,
		CACHE,
	);
}
