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

function itemOut(i: ItemRow) {
	return { id: i.id, name: i.name, quality: i.quality, icon: i.icon, class: i.class, subclass: i.subclass };
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

export async function search(env: Env, url: URL): Promise<Response> {
	const q = (url.searchParams.get("q") ?? "").trim();
	const limit = intParam(url, "limit", L.SEARCH_LIMIT, 1, L.SEARCH_MAX);
	let items: ItemRow[];
	if (/^[1-9][0-9]{0,9}$/.test(q)) {
		items = (await env.DB.prepare("SELECT * FROM items WHERE id = ?1").bind(Number(q)).all<ItemRow>()).results;
	} else {
		const words = nameWords(q).slice(0, 5);
		if (words.join("").length < 2) {
			throw new HttpError(400, "bad_query", "q needs at least 2 letters or an item ID");
		}
		const where = words.map((_, i) => `id IN (SELECT item FROM item_words WHERE word >= ?${2 * i + 2} AND word < ?${2 * i + 3})`).join(" AND ");
		const params: (string | number)[] = [limit];
		for (const w of words) params.push(w, w + "\u{10FFFF}");
		items = (await env.DB.prepare(`SELECT * FROM items WHERE ${where} ORDER BY name LIMIT ?1`).bind(...params).all<ItemRow>()).results;
	}
	const hs = await allHouses(env);
	const byId = new Map(hs.map((h) => [h.id, h]));
	const prices = items.length
		? (
				await env.DB.prepare(
					`SELECT house, item, suffix, t, min, qty, listings, off, depth_t, depth_total FROM prices
					WHERE house IN (SELECT id FROM houses) AND item IN (SELECT value FROM json_each(?1))`,
				)
					.bind(JSON.stringify(items.map((i) => i.id)))
					.all<PriceRow>()
			).results
		: [];
	return json(
		{
			query: q,
			items: items.map((i) => ({
				...itemOut(i),
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

export async function itemDetail(env: Env, url: URL, id: number, now: number): Promise<Response> {
	const days = intParam(url, "days", L.HISTORY_DAYS, L.TYPICAL_DAYS, L.HISTORY_DAYS_MAX);
	const hours = intParam(url, "hours", L.RAW_HOURS, 0, L.RAW_HOURS_MAX);
	const today = dayNumber(now);
	const db = env.DB;
	const [item, prices, daily, points] = await db.batch([
		db.prepare("SELECT * FROM items WHERE id = ?1").bind(id),
		db.prepare("SELECT * FROM prices WHERE house IN (SELECT id FROM houses) AND item = ?1").bind(id),
		db.prepare(
			`SELECT house, suffix, day, src, lo, typ, hi, qty_max, list_max, n, gone FROM daily
			WHERE house IN (SELECT id FROM houses) AND item = ?1 AND day > ?2 ORDER BY day`,
		).bind(id, today - days),
		db.prepare(
			`SELECT house, suffix, t, total, listings, m, tiers FROM points
			WHERE house IN (SELECT id FROM houses) AND item = ?1 AND t >= ?2 ORDER BY t`,
		).bind(id, now - hours * 3600),
	]);
	const info = (item!.results as unknown as ItemRow[])[0] ?? null;
	const priceRows = prices!.results as unknown as PriceRow[];
	const dailyRows = daily!.results as unknown as DailyRow[];
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
	return json({ id, item: info ? itemOut(info) : null, markets: out }, 200, CACHE);
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
