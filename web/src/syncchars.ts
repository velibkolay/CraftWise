// GET /api/sync/characters (#242): the private character data of every machine, for the companion of
// the other machine (#237). Token auth with the `private` scope (the data is private; the market
// download of #238 is public). Each character comes whole, as the uploads stored it (a snapshot, the
// auction tracker, the fishing summary, the newest ledger entries and craft days), labelled with the
// machine that uploaded it and when. Nothing is computed or filled in. Reads only (plus the token's
// rate-limit row that uploadAuth counts).
import { uploadAuth } from "./auth";
import type { Env } from "./env";
import { HttpError, intParam } from "./http";
import { DAY, MIN_TIME, SYNC_CHARS, SYNC_CHARS_BYTES, SYNC_CHARS_MAX, SYNC_CRAFTED_DAYS, SYNC_LEDGER_DAYS, SYNC_LEDGER_DAYS_MAX, SYNC_LEDGER_ENTRIES, SYNC_SAFETY } from "./limits";

interface CharRow {
	key: string;
	realm: string | null;
	name: string | null;
	surname: string | null;
	faction: string | null;
	race: string | null;
	class: string | null;
	level: number | null;
	updated: number;
	machine: string | null;
	uploaded: number;
}
interface DocRow {
	char: string;
	t: number;
	data: string;
}
interface LedgerRow {
	char: string;
	t: number;
	kind: string;
	item: number | null;
	qty: number | null;
	money: number | null;
	place: string | null;
	name: string | null;
}
interface CraftedRow {
	char: string;
	recipe: number;
	day: number;
	n: number;
	items: number | null;
	profit: number | null;
	known: number | null;
	active: number | null;
}

// The position after the last character of a page: "c.<uploaded>.<character key as base64url>".
const CURSOR = /^c\.(\d{1,12})\.([A-Za-z0-9_-]{1,600})$/;

function compact<T extends Record<string, unknown>>(o: T): Partial<T> {
	const out: Record<string, unknown> = {};
	for (const [k, v] of Object.entries(o)) if (v !== null && v !== undefined) out[k] = v;
	return out as Partial<T>;
}

function timeParam(url: URL, name: string): number | null {
	const raw = url.searchParams.get(name);
	if (raw === null || raw === "") return null;
	if (!/^\d{1,12}$/.test(raw)) throw new HttpError(400, "bad_query", `${name}: expected Unix seconds`);
	return Number(raw);
}

// A day as YYYYMMDD, the craft log's day number.
function ymd(t: number): number {
	const d = new Date(t * 1000);
	return d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 + d.getUTCDate();
}

// base64url of the key's UTF-8 bytes: nothing in a cursor needs URL escaping.
function encodeKey(key: string): string {
	let s = "";
	for (const b of new TextEncoder().encode(key)) s += String.fromCharCode(b);
	return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeKey(text: string): string {
	const b = atob(text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4));
	return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(Uint8Array.from(b, (c) => c.charCodeAt(0)));
}

export async function syncCharacters(request: Request, env: Env, url: URL, now: number): Promise<Response> {
	await uploadAuth(request, env, "private", now);
	const since = timeParam(url, "since") ?? 0;
	const limit = intParam(url, "limit", SYNC_CHARS, 1, SYNC_CHARS_MAX);
	const notMachine = url.searchParams.get("notMachine");
	if (notMachine !== null && notMachine.length > 64) throw new HttpError(400, "bad_query", "notMachine: at most 64 characters");
	const ledgerSince = Math.max(timeParam(url, "ledgerSince") ?? now - SYNC_LEDGER_DAYS * DAY, now - SYNC_LEDGER_DAYS_MAX * DAY);
	const rawCursor = url.searchParams.get("cursor");
	let after = { uploaded: -1, key: "" };
	if (rawCursor !== null) {
		const m = CURSOR.exec(rawCursor);
		if (!m) throw new HttpError(400, "bad_query", "cursor: not a cursor from this endpoint");
		try {
			after = { uploaded: Number(m[1]), key: decodeKey(m[2]!) };
		} catch {
			throw new HttpError(400, "bad_query", "cursor: not a cursor from this endpoint");
		}
	}
	const db = env.DB;
	const rows = (
		await db
			.prepare(
				`SELECT key, realm, name, surname, faction, race, class, level, updated, machine, COALESCE(uploaded, 0) AS uploaded
				FROM characters
				WHERE COALESCE(uploaded, 0) >= ?1 AND (COALESCE(uploaded, 0), key) > (?2, ?3) AND (?4 IS NULL OR machine IS NOT ?4)
				ORDER BY COALESCE(uploaded, 0), key LIMIT ?5`,
			)
			.bind(since, after.uploaded, after.key, notMachine, limit + 1)
			.all<CharRow>()
	).results;
	let more = rows.length > limit;
	if (more) rows.length = limit;

	const keys = JSON.stringify(rows.map((r) => r.key));
	const [snapshots, auctions, fishing, ledger, crafted] = rows.length
		? await db.batch([
				db.prepare("SELECT char, t, data FROM snapshots WHERE char IN (SELECT value FROM json_each(?1))").bind(keys),
				db.prepare("SELECT char, t, data FROM auctions WHERE char IN (SELECT value FROM json_each(?1))").bind(keys),
				db.prepare("SELECT char, t, data FROM fishing WHERE char IN (SELECT value FROM json_each(?1))").bind(keys),
				db
					.prepare(
						`SELECT char, t, kind, item, qty, money, place, name FROM (
							SELECT *, ROW_NUMBER() OVER (PARTITION BY char ORDER BY t DESC, uid) AS rn FROM ledger
							WHERE char IN (SELECT value FROM json_each(?1)) AND t >= ?2
						) WHERE rn <= ?3 ORDER BY char, t DESC, uid`,
					)
					.bind(keys, ledgerSince, SYNC_LEDGER_ENTRIES),
				db
					.prepare(
						`SELECT char, recipe, day, n, items, profit, known, active FROM crafted
						WHERE char IN (SELECT value FROM json_each(?1)) AND day >= ?2 ORDER BY char, day, recipe`,
					)
					.bind(keys, ymd(now - SYNC_CRAFTED_DAYS * DAY)),
			])
		: [];
	const docs = (r: D1Result | undefined): Map<string, DocRow> => new Map(((r?.results ?? []) as unknown as DocRow[]).map((d) => [d.char, d]));
	const snap = docs(snapshots);
	const auc = docs(auctions);
	const fish = docs(fishing);
	const ledgerBy = new Map<string, LedgerRow[]>();
	for (const e of (ledger?.results ?? []) as unknown as LedgerRow[]) {
		const list = ledgerBy.get(e.char) ?? [];
		if (list.length < SYNC_LEDGER_ENTRIES) list.push(e);
		ledgerBy.set(e.char, list);
	}
	const craftedBy = new Map<string, CraftedRow[]>();
	for (const c of (crafted?.results ?? []) as unknown as CraftedRow[]) {
		let list = craftedBy.get(c.char);
		if (!list) craftedBy.set(c.char, (list = []));
		list.push(c);
	}

	// The body is built from the stored document texts as they are (they are JSON already), so the
	// Worker doesn't parse and write back up to 450 KB per document.
	const parts: string[] = [];
	let bytes = 0;
	let last: CharRow | null = null;
	for (const r of rows) {
		const fields: string[] = [
			`"machine":${JSON.stringify(r.machine)}`,
			`"uploaded":${r.uploaded > 0 ? r.uploaded : r.updated}`,
			`"info":${JSON.stringify(compact({ realm: r.realm, name: r.name, surname: r.surname, faction: r.faction, race: r.race, class: r.class, level: r.level, t: r.updated > 0 ? r.updated : null }))}`,
		];
		for (const [name, d] of [["snapshot", snap.get(r.key)], ["auctions", auc.get(r.key)], ["fishing", fish.get(r.key)]] as const) {
			if (d) fields.push(`"${name}":{"t":${d.t},"data":${d.data}}`);
		}
		const entries = (ledgerBy.get(r.key) ?? []).reverse().map((e) => compact({ t: e.t, k: e.kind, i: e.item, q: e.qty, m: e.money, w: e.place, n: e.name }));
		fields.push(`"ledger":${JSON.stringify(entries)}`);
		const days = (craftedBy.get(r.key) ?? []).map((c) => compact({ r: c.recipe, d: c.day, n: c.n, i: c.items, p: c.profit, k: c.known, a: c.active }));
		fields.push(`"crafted":${JSON.stringify(days)}`);
		const text = `${JSON.stringify(r.key)}:{${fields.join(",")}}`;
		// the page ends before a character that would take it over the size limit (but holds at least one)
		if (parts.length > 0 && bytes + text.length > SYNC_CHARS_BYTES) {
			more = true;
			break;
		}
		parts.push(text);
		bytes += text.length;
		last = r;
	}
	const next = more && last ? `c.${last.uploaded}.${encodeKey(last.key)}` : null;
	// what to send as `since` next time: a margin behind now, so an upload that was still running when this
	// was read is returned again (the companion replaces a character whole, so a repeat is harmless)
	const until = Math.max(MIN_TIME, now - SYNC_SAFETY);
	return new Response(`{"v":1,"characters":{${parts.join(",")}},"next":${JSON.stringify(next)},"until":${until}}`, {
		status: 200,
		headers: { "content-type": "application/json; charset=utf-8", "cache-control": "private, no-store" },
	});
}
