// Shape validation of upload bodies (contract: web/docs/api.md). Pure: no I/O.
// Every value is checked; nothing is filled in. A field the addon doesn't have is left out (or null)
// and stored as NULL.
import { HttpError } from "./http";
import * as L from "./limits";

export interface House {
	key: string;
	realm: string;
	kind: "faction" | "neutral";
	faction: "Horde" | "Alliance" | null;
	label: string;
}
export interface Scan {
	house: string;
	t: number;
	kind: string;
	items: number | null;
	lastOnly: number | null;
	source: string | null;
}
export interface ItemInfo {
	id: number;
	n: string | null;
	q: number | null;
	i: number | null;
	c: number | null;
	s: number | null;
}
export interface Last {
	t: number;
	min: number;
	qty: number;
	listings: number | null;
	off: number | null;
}
export interface RawPoint {
	t: number;
	total: number;
	listings: number | null;
	m: number | null;
	tiers: number[];
}
export interface Day {
	day: number;
	lo: number | null;
	typ: number | null;
	hi: number | null;
	qtyMax: number | null;
	listMax: number | null;
	n: number | null;
	gone: number | null;
}
export interface Price {
	house: string;
	item: number;
	suffix: number;
	last: Last | null;
	raw: RawPoint[];
	days: Day[];
}
export interface PublicUpload {
	houses: House[];
	scans: Scan[];
	items: ItemInfo[];
	prices: Price[];
}

export interface PrivateDoc {
	char: string;
	t: number;
	data: unknown;
	text: string; // data as stored (JSON)
}
export interface Character {
	key: string;
	t: number;
	realm: string | null;
	name: string | null;
	surname: string | null;
	faction: string | null;
	race: string | null;
	class: string | null;
	level: number | null;
}
export interface LedgerEntry {
	uid: string;
	char: string;
	t: number;
	kind: string;
	item: number | null;
	qty: number | null;
	money: number | null;
	place: string | null;
	name: string | null;
}
export interface PrivateUpload {
	snapshots: PrivateDoc[];
	auctions: PrivateDoc[];
	fishing: PrivateDoc[];
	characters: Character[];
	ledger: LedgerEntry[];
}

type Obj = Record<string, unknown>;

// A path is built only when a check fails (building one per value costs more CPU than the checks).
type Path = string | (() => string);
const at = (path: Path, field: string): Path => () => `${typeof path === "string" ? path : path()}${field}`;

function fail(path: Path, message: string): never {
	throw new HttpError(400, "bad_shape", `${typeof path === "string" ? path : path()}: ${message}`);
}

function isInt(v: unknown): v is number {
	return typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
}

function isObj(v: unknown): v is Obj {
	return typeof v === "object" && v !== null && !Array.isArray(v);
}

function obj(v: unknown, path: Path): Obj {
	if (!isObj(v)) fail(path, "expected an object");
	return v;
}

function arr(v: unknown, path: Path, max: number): unknown[] {
	if (v === undefined || v === null) return [];
	if (!Array.isArray(v)) fail(path, "expected an array");
	if (v.length > max) fail(path, `more than ${max} entries`);
	return v;
}

function int(v: unknown, path: Path): number {
	if (!isInt(v)) fail(path, "expected a non-negative integer");
	return v;
}

function optInt(v: unknown, path: Path): number | null {
	return v === undefined || v === null ? null : isInt(v) ? v : int(v, path);
}

function str(v: unknown, path: Path, max: number): string {
	if (typeof v !== "string" || v.length === 0 || v.length > max) fail(path, `expected a string of 1 to ${max} characters`);
	return v;
}

function optStr(v: unknown, path: Path, max: number): string | null {
	return v === undefined || v === null ? null : str(v, path, max);
}

function time(v: unknown, path: Path, now: number): number {
	const t = int(v, path);
	if (t < L.MIN_TIME || t > now + L.MAX_FUTURE) fail(path, "time out of range");
	return t;
}

function optTime(v: unknown, path: Path, now: number): number | null {
	return v === undefined || v === null ? null : time(v, path, now);
}

function version(body: Obj): void {
	if (body.v !== 1) fail("v", "unsupported version (expected 1)");
}

// "<realm>|H", "<realm>|A" or "<realm>|N:<Name>" as CraftWise/Market.lua builds it.
const HOUSE_KEY = /^([^|]{1,64})\|(H|A|N:[A-Za-z]{1,32})$/;
const ITEM_KEY = /^([1-9][0-9]{0,9})(?::([0-9]{1,10}))?$/;
const SCAN_KIND = /^[a-z]{1,16}$/;

function houses(v: unknown): House[] {
	const o = obj(v, "houses");
	const keys = Object.keys(o);
	if (keys.length > L.MAX_HOUSES) fail("houses", `more than ${L.MAX_HOUSES} houses`);
	return keys.map((key) => {
		const path = `houses[${JSON.stringify(key)}]`;
		const m = HOUSE_KEY.exec(key);
		if (!m) fail(path, "house key must be <realm>|H, <realm>|A or <realm>|N:<name>");
		const h = obj(o[key], path);
		const realm = str(h.realm, `${path}.realm`, 64);
		if (realm !== m[1]) fail(`${path}.realm`, "does not match the house key");
		const neutral = m[2]!.startsWith("N:");
		const kind = neutral ? "neutral" : "faction";
		if (h.kind !== kind) fail(`${path}.kind`, `expected "${kind}"`);
		let faction: House["faction"] = null;
		if (!neutral) {
			const want = m[2] === "H" ? "Horde" : "Alliance";
			if (h.faction !== want) fail(`${path}.faction`, `expected "${want}"`);
			faction = want;
		} else if (h.faction !== undefined && h.faction !== null) {
			fail(`${path}.faction`, "a neutral house has no faction");
		}
		return { key, realm, kind, faction, label: str(h.label, `${path}.label`, 64) };
	});
}

function itemKey(v: unknown, path: Path): { item: number; suffix: number } {
	const m = typeof v === "string" ? ITEM_KEY.exec(v) : null;
	if (!m) fail(path, 'expected an item key "<itemID>" or "<itemID>:<suffixID>"');
	const item = Number(m[1]);
	const suffix = m[2] === undefined ? 0 : Number(m[2]);
	if (!Number.isSafeInteger(item) || !Number.isSafeInteger(suffix)) fail(path, "item key out of range");
	return { item, suffix };
}

function last(v: unknown, path: Path, now: number): Last {
	const o = obj(v, path);
	return {
		t: time(o.t, at(path, ".t"), now),
		min: isInt(o.min) ? o.min : int(o.min, at(path, ".min")),
		qty: isInt(o.qty) ? o.qty : int(o.qty, at(path, ".qty")),
		listings: optInt(o.listings, at(path, ".listings")),
		off: optTime(o.off, at(path, ".off"), now),
	};
}

function tiers(v: unknown, path: Path): number[] {
	const list = arr(v, path, L.MAX_TIER_VALUES);
	if (list.length % 2 !== 0) fail(path, "expected [price, qty, price, qty, ...]");
	let prev = -1;
	for (let i = 0; i < list.length; i++) {
		const n = list[i];
		if (!isInt(n)) int(n, at(path, `[${i}]`));
		if (i % 2 === 0) {
			if ((n as number) <= prev) fail(at(path, `[${i}]`), "prices must rise");
			prev = n as number;
		}
	}
	return list as number[];
}

function rawPoint(v: unknown, path: Path, now: number): RawPoint {
	const o = obj(v, path);
	return {
		t: time(o.t, at(path, ".t"), now),
		total: isInt(o.total) ? o.total : int(o.total, at(path, ".total")),
		listings: optInt(o.listings, at(path, ".listings")),
		m: optInt(o.m, at(path, ".m")),
		tiers: tiers(o.tiers, at(path, ".tiers")),
	};
}

function day(v: unknown, path: Path, now: number): Day {
	const o = obj(v, path);
	const d = int(o.day, at(path, ".day"));
	if (d < Math.floor(L.MIN_TIME / L.DAY) || d > Math.floor((now + L.MAX_FUTURE) / L.DAY)) fail(at(path, ".day"), "day out of range");
	return {
		day: d,
		lo: optInt(o.lo, at(path, ".lo")),
		typ: optInt(o.typ, at(path, ".typ")),
		hi: optInt(o.hi, at(path, ".hi")),
		qtyMax: optInt(o.qtyMax, at(path, ".qtyMax")),
		listMax: optInt(o.listMax, at(path, ".listMax")),
		n: optInt(o.n, at(path, ".n")),
		gone: optInt(o.gone, at(path, ".gone")),
	};
}

export function validatePublic(body: unknown, now: number): PublicUpload {
	const b = obj(body, "body");
	version(b);
	const houseList = houses(b.houses);
	const known = new Set(houseList.map((h) => h.key));
	const house = (v: unknown, path: Path): string => {
		if (typeof v === "string" && known.has(v)) return v;
		const key = str(v, path, 100);
		if (!known.has(key)) fail(path, "house not listed in `houses`");
		return key;
	};

	const scans = arr(b.scans, "scans", L.MAX_SCANS).map((v, i): Scan => {
		const path = `scans[${i}]`;
		const o = obj(v, path);
		const kind = str(o.kind, `${path}.kind`, 16);
		if (!SCAN_KIND.test(kind)) fail(`${path}.kind`, "expected lower-case letters");
		return {
			house: house(o.house, `${path}.house`),
			t: time(o.t, `${path}.t`, now),
			kind,
			items: optInt(o.items, `${path}.items`),
			lastOnly: optInt(o.lastOnly, `${path}.lastOnly`),
			source: optStr(o.source, `${path}.source`, 32),
		};
	});

	const items: ItemInfo[] = [];
	if (b.items !== undefined && b.items !== null) {
		const o = obj(b.items, "items");
		const ids = Object.keys(o);
		if (ids.length > L.MAX_ITEMS) fail("items", `more than ${L.MAX_ITEMS} items`);
		for (const id of ids) {
			const path = `items[${JSON.stringify(id)}]`;
			if (!/^[1-9][0-9]{0,9}$/.test(id)) fail(path, "item ID must be a positive integer");
			const info = obj(o[id], path);
			items.push({
				id: Number(id),
				n: optStr(info.n, `${path}.n`, 200),
				q: optInt(info.q, `${path}.q`),
				i: optInt(info.i, `${path}.i`),
				c: optInt(info.c, `${path}.c`),
				s: optInt(info.s, `${path}.s`),
			});
		}
	}

	const seen = new Set<string>();
	const prices = arr(b.prices, "prices", L.MAX_PRICE_ENTRIES).map((v, i): Price => {
		const path = () => `prices[${i}]`;
		const o = obj(v, path);
		const h = house(o.house, at(path, ".house"));
		const key = itemKey(o.item, at(path, ".item"));
		const id = `${h}\u0000${key.item}:${key.suffix}`;
		if (seen.has(id)) fail(path, "item and house twice in one upload");
		seen.add(id);
		const raw = arr(o.raw, at(path, ".raw"), L.MAX_RAW_POINTS).map((p, j) => rawPoint(p, at(path, `.raw[${j}]`), now));
		const days = arr(o.days, at(path, ".days"), L.MAX_DAYS).map((d, j) => day(d, at(path, `.days[${j}]`), now));
		const l = o.last === undefined || o.last === null ? null : last(o.last, at(path, ".last"), now);
		if (!l && raw.length === 0 && days.length === 0) fail(path, "no last, raw or days");
		return { house: h, ...key, last: l, raw, days };
	});

	return { houses: houseList, scans, items, prices };
}

// Character key as CraftWise builds it: "<realm>-<name> <surname>" or "<realm>-<name>".
const CHAR_KEY = /^[^\u0000-\u001f]{1,64}-[^\u0000-\u001f]{1,64}$/;

function charKey(key: string, path: string): string {
	if (!CHAR_KEY.test(key)) fail(path, 'character key must be "<realm>-<name>[ <surname>]"');
	return key;
}

function docs(v: unknown, field: string, now: number): PrivateDoc[] {
	if (v === undefined || v === null) return [];
	const o = obj(v, field);
	const keys = Object.keys(o);
	if (keys.length > L.MAX_CHARACTERS) fail(field, `more than ${L.MAX_CHARACTERS} characters`);
	return keys.map((key) => {
		const path = `${field}[${JSON.stringify(key)}]`;
		charKey(key, path);
		const d = obj(o[key], path);
		const data = obj(d.data, `${path}.data`);
		const text = JSON.stringify(data);
		if (text.length > L.MAX_PRIVATE_DOC_BYTES) fail(`${path}.data`, `over ${L.MAX_PRIVATE_DOC_BYTES} bytes`);
		return { char: key, t: time(d.t, `${path}.t`, now), data, text };
	});
}

function charInfo(doc: PrivateDoc): Character {
	const c = isObj(doc.data) && isObj(doc.data.char) ? doc.data.char : {};
	const s = (v: unknown) => (typeof v === "string" && v.length > 0 && v.length <= 64 ? v : null);
	const level = typeof c.level === "number" && Number.isSafeInteger(c.level) && c.level >= 0 ? c.level : null;
	return {
		key: doc.char,
		t: doc.t,
		realm: s(c.realm),
		name: s(c.name),
		surname: s(c.surname),
		faction: s(c.faction),
		race: s(c.race),
		class: s(c.class),
		level,
	};
}

export function validatePrivate(body: unknown, now: number): PrivateUpload {
	const b = obj(body, "body");
	version(b);
	const snapshots = docs(b.snapshots, "snapshots", now);
	const auctions = docs(b.auctions, "auctions", now);
	const fishing = docs(b.fishing, "fishing", now);

	// Identical entries (same second, item, quantity, money and place) are numbered in list order,
	// so a re-upload of the same log maps every entry to the same row.
	const occurrences = new Map<string, number>();
	const ledger = arr(b.ledger, "ledger", L.MAX_LEDGER_ENTRIES).map((v, i): LedgerEntry => {
		const path = `ledger[${i}]`;
		const o = obj(v, path);
		const char = charKey(str(o.c, `${path}.c`, 130), `${path}.c`);
		const kind = str(o.k, `${path}.k`, 16);
		if (!/^[a-z]{1,16}$/.test(kind)) fail(`${path}.k`, "expected lower-case letters");
		const e = {
			char,
			t: time(o.t, `${path}.t`, now),
			kind,
			item: optInt(o.i, `${path}.i`),
			qty: optInt(o.q, `${path}.q`),
			money: optInt(o.m, `${path}.m`),
			place: optStr(o.w, `${path}.w`, 100),
			name: optStr(o.n, `${path}.n`, 200),
		};
		const base = JSON.stringify([e.char, e.t, e.kind, e.item, e.qty, e.money, e.place]);
		const n = (occurrences.get(base) ?? 0) + 1;
		occurrences.set(base, n);
		return { uid: `${base}#${n}`, ...e };
	});

	if (!snapshots.length && !auctions.length && !fishing.length && !ledger.length) fail("body", "nothing to store");
	return { snapshots, auctions, fishing, characters: snapshots.map(charInfo), ledger };
}
