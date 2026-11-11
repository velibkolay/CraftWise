// POST /api/upload (public market data) and POST /api/private/upload (private data).
// Bulk writes go through json_each(): one statement per table with the rows bound as one JSON
// text, so the Worker's CPU time stays small and an upload is one D1 transaction (batch).
// Every write is idempotent: sending the same body again changes nothing and writes ~0 rows.
import { checkBudget, rowsWritten, uploadAuth, usageStatement } from "./auth";
import type { Env } from "./env";
import { HttpError, json, parseJson, readBody } from "./http";
import { MAX_PRIVATE_BYTES, MAX_PUBLIC_BYTES } from "./limits";
import { validatePrivate, validatePublic, type ItemInfo, type PublicUpload } from "./validate";

// Lower-case words of an item name for the search index ("Arthas' Tears" -> arthas', tears).
// "of", "the" and the like are left out: every row costs a write.
const STOP_WORDS = new Set(["a", "an", "and", "of", "the", "to"]);
export function nameWords(name: string): string[] {
	const words = name.toLowerCase().split(/[^\p{L}\p{N}']+/u).filter((w) => w.length > 0 && !STOP_WORDS.has(w));
	return [...new Set(words)].slice(0, 12);
}

interface ItemRow {
	id: number;
	name: string | null;
	quality: number | null;
	icon: number | null;
	class: number | null;
	subclass: number | null;
}

const PRICES_SQL = `INSERT INTO prices (house, item, suffix, t, min, qty, listings, off, depth_t, depth_total, depth)
	SELECT value->>0, value->>1, value->>2, value->>3, value->>4, value->>5, value->>6, value->>7, value->>8, value->>9, value->>10
	FROM json_each(?1) WHERE true
	ON CONFLICT (house, item, suffix) DO UPDATE SET
		t = excluded.t, min = excluded.min, qty = excluded.qty, listings = excluded.listings, off = excluded.off,
		depth_t = coalesce(excluded.depth_t, depth_t),
		depth_total = CASE WHEN excluded.depth_t IS NULL THEN depth_total ELSE excluded.depth_total END,
		depth = CASE WHEN excluded.depth_t IS NULL THEN depth ELSE excluded.depth END
	WHERE excluded.t > prices.t
		OR (excluded.t = prices.t AND (excluded.off IS NOT prices.off
			OR coalesce(excluded.depth_t, 0) > coalesce(prices.depth_t, 0)))`;

// Daily row from a `last` observation (items outside the scope): lowest/highest minimum and most
// units/listings seen that day. Never touches a CraftWise aggregate (src 1).
const DAILY_LAST_SQL = `INSERT INTO daily (house, item, suffix, day, src, lo, hi, qty_max, list_max)
	SELECT value->>0, value->>1, value->>2, value->>3, 0, value->>4, value->>4, value->>5, value->>6
	FROM json_each(?1) WHERE true
	ON CONFLICT (house, item, suffix, day) DO UPDATE SET
		lo = min(lo, excluded.lo), hi = max(hi, excluded.hi), qty_max = max(qty_max, excluded.qty_max),
		list_max = CASE WHEN excluded.list_max IS NULL THEN list_max WHEN list_max IS NULL THEN excluded.list_max
			ELSE max(list_max, excluded.list_max) END
	WHERE daily.src = 0 AND (excluded.lo < daily.lo OR excluded.hi > daily.hi OR excluded.qty_max > daily.qty_max
		OR (excluded.list_max IS NOT NULL AND (daily.list_max IS NULL OR excluded.list_max > daily.list_max)))`;

// CraftWise's own daily aggregate (scope items). Replaces a src 0 row; replaces a src 1 row when it
// covers at least as many points (n) and differs.
const DAILY_DAYS_SQL = `INSERT INTO daily (house, item, suffix, day, src, lo, typ, hi, qty_max, list_max, n, gone)
	SELECT value->>0, value->>1, value->>2, value->>3, 1, value->>4, value->>5, value->>6, value->>7, value->>8, value->>9, value->>10
	FROM json_each(?1) WHERE true
	ON CONFLICT (house, item, suffix, day) DO UPDATE SET
		src = 1, lo = excluded.lo, typ = excluded.typ, hi = excluded.hi, qty_max = excluded.qty_max,
		list_max = excluded.list_max, n = excluded.n, gone = excluded.gone
	WHERE daily.src = 0 OR (coalesce(excluded.n, 0) >= coalesce(daily.n, 0) AND (
		excluded.lo IS NOT daily.lo OR excluded.typ IS NOT daily.typ OR excluded.hi IS NOT daily.hi
		OR excluded.qty_max IS NOT daily.qty_max OR excluded.list_max IS NOT daily.list_max
		OR excluded.n IS NOT daily.n OR excluded.gone IS NOT daily.gone))`;

const POINTS_SQL = `INSERT OR IGNORE INTO points (house, item, suffix, t, total, listings, m, tiers)
	SELECT value->>0, value->>1, value->>2, value->>3, value->>4, value->>5, value->>6, value->>7 FROM json_each(?1)`;

const SCANS_SQL = `INSERT OR IGNORE INTO scans (house, t, kind, items, last_only, source)
	SELECT value->>0, value->>1, value->>2, value->>3, value->>4, value->>5 FROM json_each(?1)`;

// Random-suffix variants (#118, migrations/0002_variants.sql), one row per item and house holding
// every variant: {"<suffix>": [t, min, qty, listings, off]}. Per variant the newer `t` wins, or the
// same `t` with another `off` (as PRICES_SQL). The row is written only when a variant changes.
const VARIANT_WINS = `n.value->>0 > o.value->>0 OR (n.value->>0 = o.value->>0 AND n.value->>4 IS NOT o.value->>4)`;
const VARIANTS_SQL = `INSERT INTO variants (house, item, data)
	SELECT value->>0, value->>1, value->>2 FROM json_each(?1) WHERE true
	ON CONFLICT (house, item) DO UPDATE SET data = (
		SELECT json_group_object(k, json(v)) FROM (
			SELECT o.key AS k, CASE WHEN n.key IS NOT NULL AND (${VARIANT_WINS}) THEN n.value ELSE o.value END AS v
			FROM json_each(variants.data) o LEFT JOIN json_each(excluded.data) n ON n.key = o.key
			UNION ALL
			SELECT n.key, n.value FROM json_each(excluded.data) n WHERE n.key NOT IN (SELECT key FROM json_each(variants.data))))
	WHERE EXISTS (SELECT 1 FROM json_each(excluded.data) n LEFT JOIN json_each(variants.data) o ON o.key = n.key
		WHERE o.key IS NULL OR ${VARIANT_WINS})`;

// Their daily rows, as DAILY_LAST_SQL per variant: {"<suffix>": [lo, hi, qtyMax, listMax]}.
const VARIANT_WIDER = `n.value->>0 < o.value->>0 OR n.value->>1 > o.value->>1 OR n.value->>2 > o.value->>2
	OR (n.value->>3 IS NOT NULL AND (o.value->>3 IS NULL OR n.value->>3 > o.value->>3))`;
const VARIANT_DAYS_SQL = `INSERT INTO variant_days (house, item, day, data)
	SELECT value->>0, value->>1, value->>2, value->>3 FROM json_each(?1) WHERE true
	ON CONFLICT (house, item, day) DO UPDATE SET data = (
		SELECT json_group_object(k, json(v)) FROM (
			SELECT o.key AS k, CASE WHEN n.key IS NULL THEN o.value ELSE json_array(
				min(o.value->>0, n.value->>0), max(o.value->>1, n.value->>1), max(o.value->>2, n.value->>2),
				CASE WHEN n.value->>3 IS NULL THEN o.value->>3 WHEN o.value->>3 IS NULL THEN n.value->>3
					ELSE max(o.value->>3, n.value->>3) END) END AS v
			FROM json_each(variant_days.data) o LEFT JOIN json_each(excluded.data) n ON n.key = o.key
			UNION ALL
			SELECT n.key, n.value FROM json_each(excluded.data) n WHERE n.key NOT IN (SELECT key FROM json_each(variant_days.data))))
	WHERE EXISTS (SELECT 1 FROM json_each(excluded.data) n LEFT JOIN json_each(variant_days.data) o ON o.key = n.key
		WHERE o.key IS NULL OR ${VARIANT_WIDER})`;

// Variants that keep their rows in `prices` although this record has no raw points: their stored
// row has a depth (a scope item). Looked up for every suffix record without raw points.
const DEPTH_ROWS_SQL = `SELECT h.key AS house, p.item, p.suffix FROM json_each(?1) j
	JOIN houses h ON h.key = j.value->>0
	JOIN prices p ON p.house = h.id AND p.item = j.value->>1 AND p.suffix = j.value->>2
	WHERE p.depth_t IS NOT NULL`;

// A record goes to `variants` when it has a suffix, a `last`, no raw points and no stored depth.
export function packedVariant(p: PublicUpload["prices"][number], depth?: Set<string>): boolean {
	return p.suffix !== 0 && p.last !== null && p.raw.length === 0 && !depth?.has(`${p.house}\x1f${p.item}:${p.suffix}`);
}

// Rows for the bulk statements below, one JSON array per row (pure; also used by tools/bench).
// `depth`: "<house key>\x1f<item>:<suffix>" of variants whose `prices` row has a depth.
export function priceRows(data: PublicUpload, hid: (key: string) => number, depth?: Set<string>) {
	const prices: unknown[][] = [];
	const dailyLast: unknown[][] = [];
	const dailyDays: unknown[][] = [];
	const points: unknown[][] = [];
	// "<suffix>":[...] parts per item and house (and day); a variant comes once per request
	const variants = new Map<string, [number, number, string[]]>();
	const variantDays = new Map<string, [number, number, number, string[]]>();
	for (const p of data.prices) {
		const h = hid(p.house);
		for (const d of p.days) {
			dailyDays.push([h, p.item, p.suffix, d.day, d.lo, d.typ, d.hi, d.qtyMax, d.listMax, d.n, d.gone]);
		}
		if (packedVariant(p, depth)) {
			const l = p.last!;
			const day = Math.floor(l.t / 86400);
			let v = variants.get(`${h}:${p.item}`);
			if (!v) variants.set(`${h}:${p.item}`, (v = [h, p.item, []]));
			v[2].push(`"${p.suffix}":[${l.t},${l.min},${l.qty},${l.listings},${l.off}]`);
			let d = variantDays.get(`${h}:${p.item}:${day}`);
			if (!d) variantDays.set(`${h}:${p.item}:${day}`, (d = [h, p.item, day, []]));
			d[3].push(`"${p.suffix}":[${l.min},${l.min},${l.qty},${l.listings}]`);
			continue;
		}
		let latest = null;
		for (const r of p.raw) {
			points.push([h, p.item, p.suffix, r.t, r.total, r.listings, r.m, r.tiers]);
			if (!latest || r.t > latest.t) latest = r;
		}
		if (p.last) {
			const l = p.last;
			prices.push([h, p.item, p.suffix, l.t, l.min, l.qty, l.listings, l.off, latest?.t ?? null, latest?.total ?? null, latest?.tiers ?? null]);
			dailyLast.push([h, p.item, p.suffix, Math.floor(l.t / 86400), l.min, l.qty, l.listings]);
		}
	}
	const scans = data.scans.map((s) => [hid(s.house), s.t, s.kind, s.items, s.lastOnly, s.source]);
	return {
		prices,
		dailyLast,
		dailyDays,
		points,
		scans,
		variants: [...variants.values()].map(([h, item, parts]) => [h, item, `{${parts.join(",")}}`]),
		variantDays: [...variantDays.values()].map(([h, item, day, parts]) => [h, item, day, `{${parts.join(",")}}`]),
	};
}

export async function publicUpload(request: Request, env: Env, now: number): Promise<Response> {
	const { written: today } = await uploadAuth(request, env, "public", now);
	const data = validatePublic(parseJson(await readBody(request, MAX_PUBLIC_BYTES)), now);
	const db = env.DB;

	// 1. Houses (insert or update their names) and the stored info of the uploaded items.
	const houseRows = JSON.stringify(data.houses.map((h) => [h.key, h.realm, h.kind, h.faction, h.label]));
	const itemIds = JSON.stringify(data.items.map((i) => i.id));
	const suffixed = data.prices.filter((p) => packedVariant(p)).map((p) => [p.house, p.item, p.suffix]);
	const [houseWrite, houseIds, stored, depthRows] = await db.batch([
		db.prepare(
			`INSERT INTO houses (key, realm, kind, faction, label)
			SELECT value->>0, value->>1, value->>2, value->>3, value->>4 FROM json_each(?1) WHERE true
			ON CONFLICT (key) DO UPDATE SET realm = excluded.realm, kind = excluded.kind, faction = excluded.faction, label = excluded.label
			WHERE realm IS NOT excluded.realm OR kind IS NOT excluded.kind OR faction IS NOT excluded.faction OR label IS NOT excluded.label`,
		).bind(houseRows),
		db.prepare("SELECT id, key FROM houses WHERE key IN (SELECT value->>0 FROM json_each(?1))").bind(houseRows),
		db.prepare("SELECT id, name, quality, icon, class, subclass FROM items WHERE id IN (SELECT value FROM json_each(?1))").bind(itemIds),
		db.prepare(DEPTH_ROWS_SQL).bind(JSON.stringify(suffixed)),
	]);
	const houseId = new Map<string, number>();
	for (const r of (houseIds!.results as { id: number; key: string }[])) houseId.set(r.key, r.id);
	const hid = (key: string) => houseId.get(key)!;

	// 2. Item info: only new or changed items are written (a field missing in the upload keeps the
	//    stored value). Their search words are rebuilt when the name changed.
	const old = new Map<number, ItemRow>();
	for (const r of stored!.results as unknown as ItemRow[]) old.set(r.id, r);
	const itemRows: unknown[][] = [];
	const renamed: number[] = [];
	const wordRows: [string, number][] = [];
	for (const i of data.items as ItemInfo[]) {
		const o = old.get(i.id);
		const row = {
			name: i.n ?? o?.name ?? null,
			quality: i.q ?? o?.quality ?? null,
			icon: i.i ?? o?.icon ?? null,
			class: i.c ?? o?.class ?? null,
			subclass: i.s ?? o?.subclass ?? null,
		};
		if (o && o.name === row.name && o.quality === row.quality && o.icon === row.icon && o.class === row.class && o.subclass === row.subclass) {
			continue;
		}
		itemRows.push([i.id, row.name, row.quality, row.icon, row.class, row.subclass]);
		if ((o?.name ?? null) !== row.name) {
			if (o) renamed.push(i.id);
			for (const w of row.name ? nameWords(row.name) : []) wordRows.push([w, i.id]);
		}
	}

	// 3. Prices, daily rows, raw points, scans; suffix variants packed per item.
	const depth = new Set((depthRows!.results as { house: string; item: number; suffix: number }[]).map((r) => `${r.house}\x1f${r.item}:${r.suffix}`));
	const { prices, dailyLast, dailyDays, points, scans, variants, variantDays } = priceRows(data, hid, depth);

	checkBudget(
		today,
		// an upper bound: every upserted row counted twice (a daily aggregate costs 2 with daily_typ, the
		// others 1); a packed variant row never counts more than the companion's 4 per `last`-only entry
		2 * (itemRows.length + prices.length + dailyLast.length + dailyDays.length + scans.length + variants.length + variantDays.length) +
			renamed.length * 12 + wordRows.length + points.length,
		now,
	);

	const statements: D1PreparedStatement[] = [];
	const add = (sql: string, rows: unknown[]) => {
		if (rows.length) statements.push(db.prepare(sql).bind(JSON.stringify(rows)));
	};
	add(
		`INSERT INTO items (id, name, quality, icon, class, subclass, updated)
		SELECT value->>0, value->>1, value->>2, value->>3, value->>4, value->>5, ${now} FROM json_each(?1) WHERE true
		ON CONFLICT (id) DO UPDATE SET name = excluded.name, quality = excluded.quality, icon = excluded.icon,
			class = excluded.class, subclass = excluded.subclass, updated = excluded.updated`,
		itemRows,
	);
	add("DELETE FROM item_words WHERE item IN (SELECT value FROM json_each(?1))", renamed);
	add("INSERT OR IGNORE INTO item_words (word, item) SELECT value->>0, value->>1 FROM json_each(?1)", wordRows);
	add(PRICES_SQL, prices);
	add(POINTS_SQL, points);
	add(DAILY_LAST_SQL, dailyLast); // before the aggregates, so a CraftWise aggregate wins
	add(DAILY_DAYS_SQL, dailyDays);
	add(VARIANTS_SQL, variants);
	add(VARIANT_DAYS_SQL, variantDays);
	add(SCANS_SQL, scans);
	// Houses: latest scan, latest full scan.
	const latest = new Map<number, { any: number; full?: { t: number; items: number | null } }>();
	for (const s of data.scans) {
		const h = hid(s.house);
		const cur = latest.get(h) ?? { any: 0 };
		cur.any = Math.max(cur.any, s.t);
		if (s.kind === "full" && (!cur.full || s.t > cur.full.t)) {
			cur.full = { t: s.t, items: s.items === null && s.lastOnly === null ? null : (s.items ?? 0) + (s.lastOnly ?? 0) };
		}
		latest.set(h, cur);
	}
	for (const [h, l] of latest) {
		statements.push(db.prepare("UPDATE houses SET last_scan = ?2 WHERE id = ?1 AND (last_scan IS NULL OR last_scan < ?2)").bind(h, l.any));
		if (l.full) {
			statements.push(
				db.prepare(
					"UPDATE houses SET last_full_scan = ?2, last_full_scan_items = ?3 WHERE id = ?1 AND (last_full_scan IS NULL OR last_full_scan < ?2)",
				).bind(h, l.full.t, l.full.items),
			);
		}
	}

	const results = statements.length ? await db.batch(statements) : [];
	// + 1 for the token's rate-limit row
	const written = rowsWritten([houseWrite!, ...results]) + 1;
	await usageStatement(env, now, written, 1).run();
	return json({
		ok: true,
		received: {
			houses: data.houses.length,
			scans: data.scans.length,
			items: data.items.length,
			prices: data.prices.length,
			points: points.length,
			days: dailyDays.length,
		},
		itemsChanged: itemRows.length,
		rowsWritten: written,
	});
}

const DOC_TABLES = ["snapshots", "auctions", "fishing"] as const;

export async function privateUpload(request: Request, env: Env, now: number): Promise<Response> {
	const { written: today } = await uploadAuth(request, env, "private", now);
	const data = validatePrivate(parseJson(await readBody(request, MAX_PRIVATE_BYTES)), now);
	checkBudget(today, 3 * (data.snapshots.length + data.auctions.length + data.fishing.length) + data.ledger.length, now);
	const db = env.DB;
	const statements: D1PreparedStatement[] = [];

	const chars = new Set<string>();
	for (const table of DOC_TABLES) for (const d of data[table]) chars.add(d.char);
	for (const e of data.ledger) chars.add(e.char);
	if (chars.size) {
		statements.push(
			db.prepare("INSERT OR IGNORE INTO characters (key, updated) SELECT value, 0 FROM json_each(?1)").bind(JSON.stringify([...chars])),
		);
	}
	for (const c of data.characters) {
		statements.push(
			db.prepare(
				`UPDATE characters SET realm = ?2, name = ?3, surname = ?4, faction = ?5, race = ?6, class = ?7, level = ?8, updated = ?9
				WHERE key = ?1 AND updated < ?9`,
			).bind(c.key, c.realm, c.name, c.surname, c.faction, c.race, c.class, c.level, c.t),
		);
	}
	for (const table of DOC_TABLES) {
		for (const d of data[table]) {
			statements.push(
				db.prepare(
					`INSERT INTO ${table} (char, t, data) VALUES (?1, ?2, ?3)
					ON CONFLICT (char) DO UPDATE SET t = excluded.t, data = excluded.data WHERE excluded.t > ${table}.t`,
				).bind(d.char, d.t, d.text),
			);
		}
	}
	if (data.ledger.length) {
		const rows = data.ledger.map((e) => [e.uid, e.char, e.t, e.kind, e.item, e.qty, e.money, e.place, e.name]);
		statements.push(
			db.prepare(
				`INSERT OR IGNORE INTO ledger (uid, char, t, kind, item, qty, money, place, name)
				SELECT value->>0, value->>1, value->>2, value->>3, value->>4, value->>5, value->>6, value->>7, value->>8 FROM json_each(?1)`,
			).bind(JSON.stringify(rows)),
		);
	}
	const results = await db.batch(statements);
	const written = rowsWritten(results) + 1;
	await usageStatement(env, now, written, 1).run();
	return json({
		ok: true,
		received: {
			snapshots: data.snapshots.length,
			auctions: data.auctions.length,
			fishing: data.fishing.length,
			ledger: data.ledger.length,
		},
		rowsWritten: written,
	});
}

export function assertJson(request: Request): void {
	const type = request.headers.get("content-type") ?? "";
	if (!/^application\/json\b/i.test(type)) throw new HttpError(415, "unsupported_media_type", "Content-Type must be application/json");
}
