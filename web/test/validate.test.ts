import { describe, expect, it } from "vitest";
import { HttpError } from "../src/http";
import { typical, listed } from "../src/market";
import { nameWords } from "../src/upload";
import { validatePrivate, validatePublic } from "../src/validate";
import { BOOTY, HORDE, houses, REALM } from "./helpers";

const NOW = 1_794_000_000;

function message(fn: () => unknown): string {
	try {
		fn();
	} catch (e) {
		if (e instanceof HttpError) return e.message;
		throw e;
	}
	throw new Error("did not throw");
}

const base = () => ({ v: 1, houses: houses() });

describe("public upload shape", () => {
	const last = { t: NOW, min: 1, qty: 1 };
	const withItems = (items: unknown) => validatePublic({ ...base(), items }, NOW);

	it("accepts the companion's MarketDB JSON and splits item keys", () => {
		const out = validatePublic(
			{
				...base(),
				scans: { [HORDE]: [{ t: NOW, kind: "full", items: 1, lastOnly: 1, source: "ui" }] },
				names: { "15210": "Burnished Leggings" },
				itemInfo: { "15210": { q: 2, i: 1, c: 4, s: 2, t: NOW } },
				items: {
					"15210:1017": { [BOOTY]: { last } },
					"2589": {
						[HORDE]: {
							last,
							raw: [{ t: NOW, total: 30, tiers: [{ price: 5, qty: 10 }, { price: 6, qty: 20 }] }],
							days: { "20763": { lo: 5, typ: 6, n: 1 } },
						},
					},
				},
			},
			NOW,
		);
		expect(out.prices).toEqual([
			{
				house: HORDE,
				item: 2589,
				suffix: 0,
				last: { ...last, listings: null, off: null },
				raw: [{ t: NOW, total: 30, listings: null, m: null, tiers: [5, 10, 6, 20] }],
				days: [{ day: 20763, lo: 5, typ: 6, hi: null, qtyMax: null, listMax: null, n: 1, gone: null }],
			},
			// integer-like keys come first in a JS object
			{ house: BOOTY, item: 15210, suffix: 1017, last: { ...last, listings: null, off: null }, raw: [], days: [] },
		]);
		expect(out.items).toEqual([{ id: 15210, n: "Burnished Leggings", q: 2, i: 1, c: 4, s: 2 }]);
		expect(out.scans).toEqual([{ house: HORDE, t: NOW, kind: "full", items: 1, lastOnly: 1, source: "ui" }]);
		expect(out.houses.map((h) => [h.key, h.kind, h.faction])).toEqual([
			[HORDE, "faction", "Horde"],
			[BOOTY, "neutral", null],
		]);
	});

	it("checks versions, house keys and house fields", () => {
		expect(message(() => validatePublic({ v: 2, houses: {} }, NOW))).toBe("v: unsupported version (expected 1)");
		expect(message(() => validatePublic({ v: 1, houses: { [`${REALM}|X`]: {} } }, NOW))).toMatch(/house key must be/);
		expect(message(() => validatePublic({ v: 1, houses: { [HORDE]: { realm: "Other", kind: "faction", faction: "Horde", label: "x" } } }, NOW))).toMatch(
			/realm: does not match/,
		);
		expect(message(() => validatePublic({ v: 1, houses: { [HORDE]: { realm: REALM, kind: "faction", faction: "Alliance", label: "x" } } }, NOW))).toMatch(
			/faction: expected "Horde"/,
		);
		expect(message(() => validatePublic({ v: 1, houses: { [BOOTY]: { realm: REALM, kind: "faction", label: "x" } } }, NOW))).toMatch(
			/kind: expected "neutral"/,
		);
	});

	it("refuses unknown houses, bad item keys and empty entries", () => {
		expect(message(() => withItems({ "1": { "Other|H": { last } } }))).toBe('items["1"]["Other|H"]: house not listed in `houses`');
		expect(message(() => withItems({ "0": { [HORDE]: { last } } }))).toMatch(/expected an item key/);
		expect(message(() => withItems({ "1": { [HORDE]: {} } }))).toBe(`items["1"]["${HORDE}"]: no last, raw or days`);
		expect(message(() => validatePublic({ ...base(), scans: { "Other|H": [] } }, NOW))).toMatch(/house not listed/);
	});

	it("checks times, tiers and days", () => {
		const e = (x: object) => withItems({ "1": { [HORDE]: x } });
		const p = `items["1"]["${HORDE}"]`;
		expect(message(() => e({ last: { t: NOW + 2 * 86400, min: 1, qty: 1 } }))).toBe(`${p}.last.t: time out of range`);
		expect(message(() => e({ last: { t: 1000, min: 1, qty: 1 } }))).toBe(`${p}.last.t: time out of range`);
		expect(message(() => e({ last: { t: NOW, min: 1.5, qty: 1 } }))).toBe(`${p}.last.min: expected a non-negative integer`);
		expect(message(() => e({ raw: [{ t: NOW, total: 3, tiers: [5, 1] }] }))).toBe(`${p}.raw[0].tiers[0]: expected { price, qty }`);
		expect(message(() => e({ raw: [{ t: NOW, total: 3, tiers: [{ price: 5, qty: 1 }, { price: 4, qty: 2 }] }] }))).toBe(
			`${p}.raw[0].tiers[1].price: prices must rise`,
		);
		expect(message(() => e({ raw: [{ t: NOW, total: 3, tiers: Array.from({ length: 9 }, (_, i) => ({ price: i, qty: 1 })) }] }))).toMatch(
			/more than 8 entries/,
		);
		expect(message(() => e({ days: { "5": { lo: 1 } } }))).toBe(`${p}.days["5"]: day out of range`);
		expect(message(() => e({ days: { x: {} } }))).toBe(`${p}.days["x"]: day key must be a day number`);
	});

	it("checks names and item info", () => {
		expect(message(() => validatePublic({ ...base(), itemInfo: { abc: {} } }, NOW))).toMatch(/item ID must be a positive integer/);
		expect(message(() => validatePublic({ ...base(), names: { "5": "" } }, NOW))).toMatch(/names\["5"\]: expected a string/);
		expect(validatePublic({ ...base(), itemInfo: { "5": {} } }, NOW).items).toEqual([{ id: 5, n: null, q: null, i: null, c: null, s: null }]);
	});
});

describe("private upload shape", () => {
	it("needs something to store and well-formed character keys", () => {
		expect(message(() => validatePrivate({ v: 1 }, NOW))).toBe("body: nothing to store");
		expect(message(() => validatePrivate({ v: 1, fishing: { x: { t: NOW, data: {} } } }, NOW))).toMatch(/character key/);
		expect(message(() => validatePrivate({ v: 1, fishing: { "R-N": { t: NOW, data: [] } } }, NOW))).toBe('fishing["R-N"].data: expected an object');
	});

	it("numbers identical ledger entries so both are kept and a re-upload maps to the same rows", () => {
		const e = { t: NOW, c: "R-N", k: "vsell", i: 1, q: 1, m: 5, w: "Vendor" };
		const a = validatePrivate({ v: 1, ledger: [e, e] }, NOW).ledger.map((x) => x.uid);
		const b = validatePrivate({ v: 1, ledger: [e, e] }, NOW).ledger.map((x) => x.uid);
		expect(a[0]).not.toBe(a[1]);
		expect(a).toEqual(b);
	});

	it("takes character fields from the snapshot only when they have the right type", () => {
		const out = validatePrivate({ v: 1, snapshots: { "R-N": { t: NOW, data: { char: { name: "N", level: "20", class: 5 } } } } }, NOW);
		expect(out.characters[0]).toMatchObject({ key: "R-N", name: "N", level: null, class: null });
	});
});

describe("market rules (Market.lua)", () => {
	const today = 20000;
	it("typical: median of the last 7 days' typ, at least 3 days", () => {
		const d = (day: number, typ: number | null) => ({ day, typ });
		expect(typical([], today, false)).toEqual({ status: "no_data", days: 0 });
		expect(typical([d(today, 5), d(today - 1, 7)], today, true)).toEqual({ status: "too_little_history", days: 2 });
		expect(typical([d(today, 5), d(today - 1, 7), d(today - 2, 9), d(today - 7, 1)], today, true)).toEqual({ status: "ok", price: 7, days: 3 });
		expect(typical([d(today, 5), d(today - 1, 8), d(today - 2, 9), d(today - 3, 1), d(today - 4, null)], today, true)).toEqual({
			status: "ok",
			price: 6,
			days: 4,
		});
	});

	it("listed: off after the observation, or an empty latest point", () => {
		expect(listed({ t: 10, off: null, depth_t: null, depth_total: null })).toBe(true);
		expect(listed({ t: 10, off: 12, depth_t: null, depth_total: null })).toBe(false);
		expect(listed({ t: 10, off: 5, depth_t: null, depth_total: null })).toBe(true);
		expect(listed({ t: 10, off: null, depth_t: 10, depth_total: 0 })).toBe(false);
	});

	it("search words: lower case, no stop words", () => {
		expect(nameWords("Elixir of the Mongoose")).toEqual(["elixir", "mongoose"]);
		expect(nameWords("Arthas' Tears")).toEqual(["arthas'", "tears"]);
	});
});
