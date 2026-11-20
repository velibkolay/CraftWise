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
// Two realms proved connected (#366), in the fixed order a < b; t is the earliest time reported.
export interface Connected {
	a: string;
	b: string;
	t: number;
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
	p: number | null; // vendor sell price per unit (#120); 0 = vendors don't buy it
}
// The client's name of an item class (sub null) or subclass (#120).
export interface ClassName {
	class: number;
	sub: number | null;
	name: string;
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
	connected: Connected[];
	scans: Scan[];
	items: ItemInfo[];
	prices: Price[];
	classNames: ClassName[];
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
// One day of the craft log (#266); null = not recorded.
export interface CraftedRow {
	char: string;
	recipe: number;
	day: number; // YYYYMMDD
	n: number;
	items: number | null;
	profit: number | null; // copper, may be negative
	known: number | null;
	active: number | null; // seconds
}
export interface PrivateUpload {
	crafted: CraftedRow[];
	snapshots: PrivateDoc[];
	auctions: PrivateDoc[];
	fishing: PrivateDoc[];
	characters: Character[];
	ledger: LedgerEntry[];
	// The addon's watch list (#165), replacing the stored one; null = the upload doesn't carry it.
	watch: { item: number; added: number }[] | null;
}

type Obj = Record<string, unknown>;

// A path is built only when a check fails (building one per value costs more CPU than the checks).
type Path = string | (() => string);
const at = (path: Path, field: string): Path => () => `${typeof path === "string" ? path : path()}${field}`;

function fail(path: Path, message: string): never {
	throw new HttpError(400, "bad_shape", `${typeof path === "string" ? path : path()}: ${message}`);
}

// A local day as the addon writes it: YYYYMMDD, 2020 to 2100 (the day of the month isn't checked per month).
function validDay(d: number): boolean {
	const y = Math.floor(d / 10000);
	const m = Math.floor(d / 100) % 100;
	const dd = d % 100;
	return y >= 2020 && y <= 2100 && m >= 1 && m <= 12 && dd >= 1 && dd <= 31;
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
const CLASS_ID = /^(0|[1-9][0-9]{0,4})$/;

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

// { "<realm>": { "<other realm>": firstSeen } } (CraftWiseMarketDB.connected, #366). Realm names as in the
// house keys (no "|"), never paired with themselves. A pair may come from both sides: it is kept once
// with the earlier time. Nothing here is guessed or completed: only what the addon recorded.
function connectedRealms(v: unknown, now: number): Connected[] {
	if (v === undefined || v === null) return [];
	const o = obj(v, "connected");
	const realms = Object.keys(o);
	if (realms.length > L.MAX_HOUSES) fail("connected", `more than ${L.MAX_HOUSES} realms`);
	const pairs = new Map<string, Connected>();
	for (const a of realms) {
		const path = `connected[${JSON.stringify(a)}]`;
		if (a.length < 1 || a.length > 64 || a.includes("|")) fail(path, "realm name must be 1 to 64 characters without |");
		const others = obj(o[a], path);
		const names = Object.keys(others);
		if (names.length > L.MAX_CONNECTED) fail(path, `more than ${L.MAX_CONNECTED} connected realms`);
		for (const b of names) {
			const p = `${path}[${JSON.stringify(b)}]`;
			if (b.length < 1 || b.length > 64 || b.includes("|")) fail(p, "realm name must be 1 to 64 characters without |");
			if (a === b) fail(p, "a realm is not connected to itself");
			const t = time(others[b], p, now);
			const lo = a < b ? a : b;
			const hi = a < b ? b : a;
			const key = `${lo} ${hi}`;
			const old = pairs.get(key);
			if (!old) pairs.set(key, { a: lo, b: hi, t });
			else if (t < old.t) old.t = t;
		}
	}
	return [...pairs.values()];
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

// [{ price, qty }, ...] cheapest first (at most 8) -> [price, qty, price, qty, ...] as stored.
function tiers(v: unknown, path: Path): number[] {
	const list = arr(v, path, L.MAX_TIERS);
	const out: number[] = new Array(list.length * 2);
	let prev = -1;
	for (let i = 0; i < list.length; i++) {
		const t = list[i];
		if (!isObj(t)) fail(at(path, `[${i}]`), "expected { price, qty }");
		const price = isInt(t.price) ? t.price : int(t.price, at(path, `[${i}].price`));
		const qty = isInt(t.qty) ? t.qty : int(t.qty, at(path, `[${i}].qty`));
		if (price <= prev) fail(at(path, `[${i}].price`), "prices must rise");
		prev = price;
		out[2 * i] = price;
		out[2 * i + 1] = qty;
	}
	return out;
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

function day(key: string, v: unknown, path: Path, now: number): Day {
	if (!/^[0-9]{1,6}$/.test(key)) fail(path, "day key must be a day number");
	const d = Number(key);
	if (d < Math.floor(L.MIN_TIME / L.DAY) || d > Math.floor((now + L.MAX_FUTURE) / L.DAY)) fail(path, "day out of range");
	const o = obj(v, path);
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

	// scans: { "<house>": [{ t, kind, items, lastOnly, source }, ...] } (CraftWiseMarketDB.scans)
	const scans: Scan[] = [];
	if (b.scans !== undefined && b.scans !== null) {
		const o = obj(b.scans, "scans");
		for (const key of Object.keys(o)) {
			const hp = `scans[${JSON.stringify(key)}]`;
			const h = house(key, hp);
			arr(o[key], hp, L.MAX_SCANS).forEach((v, i) => {
				const path = `${hp}[${i}]`;
				const s = obj(v, path);
				const kind = str(s.kind, `${path}.kind`, 16);
				if (!SCAN_KIND.test(kind)) fail(`${path}.kind`, "expected lower-case letters");
				scans.push({
					house: h,
					t: time(s.t, `${path}.t`, now),
					kind,
					items: optInt(s.items, `${path}.items`),
					lastOnly: optInt(s.lastOnly, `${path}.lastOnly`),
					source: optStr(s.source, `${path}.source`, 32),
				});
			});
		}
		if (scans.length > L.MAX_SCANS) fail("scans", `more than ${L.MAX_SCANS} scans`);
	}

	// names: { "<itemID>": name } and itemInfo: { "<itemID>": { q, i, c, s, t, p } } (#92, p #120)
	const info = new Map<number, ItemInfo>();
	const entry = (id: string, path: string): ItemInfo => {
		if (!/^[1-9][0-9]{0,9}$/.test(id)) fail(path, "item ID must be a positive integer");
		let e = info.get(Number(id));
		if (!e) {
			e = { id: Number(id), n: null, q: null, i: null, c: null, s: null, p: null };
			info.set(e.id, e);
		}
		return e;
	};
	if (b.names !== undefined && b.names !== null) {
		const o = obj(b.names, "names");
		for (const id of Object.keys(o)) {
			const path = `names[${JSON.stringify(id)}]`;
			entry(id, path).n = str(o[id], path, 200);
		}
	}
	if (b.itemInfo !== undefined && b.itemInfo !== null) {
		const o = obj(b.itemInfo, "itemInfo");
		for (const id of Object.keys(o)) {
			const path = `itemInfo[${JSON.stringify(id)}]`;
			const v = obj(o[id], path);
			const e = entry(id, path);
			e.q = optInt(v.q, `${path}.q`);
			e.i = optInt(v.i, `${path}.i`);
			e.c = optInt(v.c, `${path}.c`);
			e.s = optInt(v.s, `${path}.s`);
			e.p = optInt(v.p, `${path}.p`);
			optTime(v.t, `${path}.t`, now); // when the client gave it; checked, not stored
		}
	}
	if (info.size > L.MAX_ITEMS) fail("itemInfo", `more than ${L.MAX_ITEMS} items in names and itemInfo`);
	const items = [...info.values()];

	// items: { "<item key>": { "<house>": { last, raw, days } } } (CraftWiseMarketDB.items, decoded)
	const prices: Price[] = [];
	if (b.items !== undefined && b.items !== null) {
		const o = obj(b.items, "items");
		for (const k of Object.keys(o)) {
			const ip: Path = () => `items[${JSON.stringify(k)}]`;
			const key = itemKey(k, ip);
			const perHouse = obj(o[k], ip);
			for (const hk of Object.keys(perHouse)) {
				const path = at(ip, `[${JSON.stringify(hk)}]`);
				const h = house(hk, path);
				const e = obj(perHouse[hk], path);
				const raw = arr(e.raw, at(path, ".raw"), L.MAX_RAW_POINTS).map((p, j) => rawPoint(p, at(path, `.raw[${j}]`), now));
				const days: Day[] = [];
				if (e.days !== undefined && e.days !== null) {
					const d = obj(e.days, at(path, ".days"));
					const dayKeys = Object.keys(d);
					if (dayKeys.length > L.MAX_DAYS) fail(at(path, ".days"), `more than ${L.MAX_DAYS} days`);
					for (const dk of dayKeys) days.push(day(dk, d[dk], at(path, `.days[${JSON.stringify(dk)}]`), now));
				}
				const l = e.last === undefined || e.last === null ? null : last(e.last, at(path, ".last"), now);
				if (!l && raw.length === 0 && days.length === 0) fail(path, "no last, raw or days");
				prices.push({ house: h, ...key, last: l, raw, days });
				if (prices.length > L.MAX_PRICE_ENTRIES) fail("items", `more than ${L.MAX_PRICE_ENTRIES} item and house entries`);
			}
		}
	}

	// classNames: { "<classID>": name }, subclassNames: { "<classID>": { "<subclassID>": name } } (#120)
	const classNames: ClassName[] = [];
	const classId = (k: string, path: string): number => {
		if (!CLASS_ID.test(k)) fail(path, `class and subclass IDs must be integers from 0 to ${L.MAX_CLASS_ID}`);
		const n = Number(k);
		if (n > L.MAX_CLASS_ID) fail(path, `class and subclass IDs must be integers from 0 to ${L.MAX_CLASS_ID}`);
		return n;
	};
	const className = (v: unknown, path: string): string => {
		const name = str(v, path, L.MAX_CLASS_NAME);
		if (/[\u0000-\u001f]/.test(name)) fail(path, "control characters in a name");
		return name;
	};
	if (b.classNames !== undefined && b.classNames !== null) {
		const o = obj(b.classNames, "classNames");
		for (const k of Object.keys(o)) {
			const path = `classNames[${JSON.stringify(k)}]`;
			classNames.push({ class: classId(k, path), sub: null, name: className(o[k], path) });
		}
	}
	if (b.subclassNames !== undefined && b.subclassNames !== null) {
		const o = obj(b.subclassNames, "subclassNames");
		for (const k of Object.keys(o)) {
			const cp = `subclassNames[${JSON.stringify(k)}]`;
			const c = classId(k, cp);
			const subs = obj(o[k], cp);
			for (const sk of Object.keys(subs)) {
				const path = `${cp}[${JSON.stringify(sk)}]`;
				classNames.push({ class: c, sub: classId(sk, path), name: className(subs[sk], path) });
				if (classNames.length > L.MAX_CLASS_NAMES) break;
			}
			if (classNames.length > L.MAX_CLASS_NAMES) break;
		}
	}
	if (classNames.length > L.MAX_CLASS_NAMES) fail("classNames", `more than ${L.MAX_CLASS_NAMES} names in classNames and subclassNames`);

	return { houses: houseList, connected: connectedRealms(b.connected, now), scans, items, prices, classNames };
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
		optStr(o.l, `${path}.l`, 500); // item link: checked, not stored
		const base = JSON.stringify([e.char, e.t, e.kind, e.item, e.qty, e.money, e.place]);
		const n = (occurrences.get(base) ?? 0) + 1;
		occurrences.set(base, n);
		return { uid: `${base}#${n}`, ...e };
	});

	const crafted = arr(b.crafted, "crafted", L.MAX_CRAFTED_ROWS).map((v, i): CraftedRow => {
		const path = `crafted[${i}]`;
		const o = obj(v, path);
		const char = charKey(str(o.c, `${path}.c`, 130), `${path}.c`);
		const recipe = int(o.r, `${path}.r`);
		if (recipe < 1) fail(`${path}.r`, "expected a recipe spell ID");
		const day = int(o.d, `${path}.d`);
		if (!validDay(day)) fail(`${path}.d`, "expected a day as YYYYMMDD");
		const n = int(o.n, `${path}.n`);
		if (n < 1 || n > 10_000_000) fail(`${path}.n`, "expected a craft count from 1");
		const items = optInt(o.i, `${path}.i`);
		const known = optInt(o.k, `${path}.k`);
		if (known !== null && known > n) fail(`${path}.k`, "more priced crafts than crafts");
		let profit: number | null = null;
		if (o.p !== undefined && o.p !== null) {
			if (typeof o.p !== "number" || !Number.isSafeInteger(o.p) || Math.abs(o.p) > 1e12) fail(`${path}.p`, "expected an integer");
			profit = o.p;
		}
		let active: number | null = null;
		if (o.a !== undefined && o.a !== null) {
			if (typeof o.a !== "number" || !Number.isFinite(o.a) || o.a < 0 || o.a > 86_400) fail(`${path}.a`, "expected seconds from 0 to 86400");
			active = o.a;
		}
		return { char, recipe, day, n, items, profit, known, active };
	});

	// `watch` present (even empty) = the whole list; absent = leave the stored one alone.
	let watch: PrivateUpload["watch"] = null;
	if (b.watch !== undefined && b.watch !== null) {
		const seen = new Set<number>();
		watch = [];
		arr(b.watch, "watch", L.MAX_WATCH).forEach((v, i) => {
			const path = `watch[${i}]`;
			const o = obj(v, path);
			const item = int(o.i, `${path}.i`);
			if (item < 1) fail(`${path}.i`, "expected an item ID");
			if (seen.has(item)) return;
			seen.add(item);
			watch!.push({ item, added: time(o.t, `${path}.t`, now) });
		});
	}

	if (!snapshots.length && !auctions.length && !fishing.length && !ledger.length && !crafted.length && watch === null) fail("body", "nothing to store");
	return { snapshots, auctions, fishing, characters: snapshots.map(charInfo), ledger, crafted, watch };
}
