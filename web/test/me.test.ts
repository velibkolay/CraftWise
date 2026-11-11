// The private page's data shaping (web/site/lib/me.ts): ledger totals and periods, snapshot fields,
// auctions, fishing, tokens. All data here is invented.
import { describe, expect, it } from "vitest";
import {
	auctionGroups,
	auctionView,
	charView,
	clockLabel,
	type CreatedToken,
	filterEntries,
	fishingView,
	fullName,
	kindLabel,
	kindsPresent,
	type LedgerEntry,
	localDayStart,
	megabytes,
	parseLedger,
	periodSince,
	periodTotals,
	scopesText,
	share,
	sortTokens,
	timeLeft,
	type Token,
	TokenReveal,
	totals,
	waterText,
} from "../site/lib/me";

const NOW = 1_800_000_000; // a fixed "now" (the tests run in UTC)
const DAY0 = localDayStart(NOW);
const C = "Example Realm-Tarvok Stonehide";

const e = (t: number, kind: string, money: number, extra: Partial<LedgerEntry> = {}): LedgerEntry => ({
	char: C,
	t,
	kind,
	item: 2318,
	qty: 1,
	money,
	place: "Kaja",
	name: "Light Leather",
	...extra,
});

describe("ledger totals", () => {
	const entries = [
		e(DAY0 + 600, "ahsell", 10240),
		e(DAY0 + 500, "ahbuy", 8446),
		e(DAY0 + 400, "vsell", 1800),
		e(DAY0 + 300, "vbuy", 100),
		e(DAY0 + 200, "buyback", 309),
		e(DAY0 + 100, "mailgift", 5000), // a kind the totals don't know
		e(DAY0 - 3600, "vsell", 900), // yesterday
		e(DAY0 - 5 * 86400, "ahbuy", 700), // before the reset below
	];

	it("adds up like Ledger.lua: buys are spent, sales received, buybacks taken back", () => {
		const t = totals(entries, DAY0);
		expect(t.spent).toBe(8446 + 100);
		expect(t.received).toBe(10240 + 1800 - 309);
		expect(t.net).toBe(10240 + 1800 - 309 - 8446 - 100);
		expect(t.count).toBe(6);
		expect(t.uncounted).toBe(1);
		expect(t.other).toBeNull();
	});

	it("filters by kind and start time", () => {
		expect(totals(entries, DAY0, "ahbuy")).toMatchObject({ spent: 8446, received: 0, net: -8446, count: 1 });
		expect(totals(entries, 0).spent).toBe(8446 + 100 + 700);
		expect(filterEntries(entries, DAY0 - 86400, "vsell").map((x) => x.money)).toEqual([1800, 900]);
		expect(totals([], DAY0)).toMatchObject({ spent: 0, received: 0, net: 0, count: 0 });
	});

	it("takes Today from local midnight, Since Reset from the snapshot, All from the start", () => {
		const ledger = { today: { since: DAY0, spent: 0, received: 0, net: 0, other: 4612 }, reset: { since: DAY0 - 2 * 86400, spent: 0, received: 0, net: 0, other: -250 } };
		expect(periodSince("today", NOW, ledger)).toBe(DAY0);
		expect(periodSince("reset", NOW, ledger)).toBe(DAY0 - 2 * 86400);
		expect(periodSince("all", NOW, ledger)).toBe(0);
		expect(periodSince("reset", NOW, { today: null, reset: null })).toBeNull();
		expect(periodTotals(entries, "reset", NOW, { today: null, reset: null })).toBeNull();

		// "Other money" only comes from the snapshot: for its own period, without a kind filter.
		expect(periodTotals(entries, "today", NOW, ledger)?.other).toBe(4612);
		expect(periodTotals(entries, "reset", NOW, ledger)?.other).toBe(-250);
		expect(periodTotals(entries, "reset", NOW, ledger)?.received).toBe(10240 + 1800 - 309 + 900);
		expect(periodTotals(entries, "all", NOW, ledger)?.other).toBeNull();
		expect(periodTotals(entries, "today", NOW, ledger, "vsell")?.other).toBeNull();
		// a snapshot of another day says nothing about today
		const stale = { ...ledger, today: { ...ledger.today, since: DAY0 - 86400 } };
		expect(periodTotals(entries, "today", NOW, stale)?.other).toBeNull();
	});

	it("starts the local day at midnight", () => {
		expect(localDayStart(NOW)).toBeLessThanOrEqual(NOW);
		expect(NOW - localDayStart(NOW)).toBeLessThan(86400);
		const d = new Date(localDayStart(NOW) * 1000);
		expect([d.getHours(), d.getMinutes(), d.getSeconds()]).toEqual([0, 0, 0]);
	});

	it("names the kinds as recorded and lists those present", () => {
		expect(kindLabel("ahsell")).toBe("AH sale");
		expect(kindLabel("vbuy")).toBe("Vendor buy");
		expect(kindLabel("mailgift")).toBe("mailgift");
		expect(kindsPresent(entries)).toEqual(["ahbuy", "ahsell", "vbuy", "vsell", "buyback", "mailgift"]);
	});

	it("reads the API's entries and drops broken ones", () => {
		const parsed = parseLedger({
			entries: [
				{ char: C, t: 5, kind: "vsell", item: 3300, qty: 6, money: 1800, place: "Kaja", name: null },
				{ char: C, t: "x", kind: "vsell" },
				{ char: C, t: 6 },
				"junk",
			],
		});
		expect(parsed).toEqual([{ char: C, t: 5, kind: "vsell", item: 3300, qty: 6, money: 1800, place: "Kaja", name: null }]);
		expect(parseLedger(null)).toEqual([]);
	});
});

describe("snapshot", () => {
	it("shows what the snapshot has and leaves out what it lacks", () => {
		const v = charView({
			t: NOW - 7200,
			data: {
				t: NOW - 7200,
				char: { name: "Tarvok", surname: "Stonehide", realm: "Example Realm", faction: "Horde", race: "Tauren", class: "Hunter", level: 21, xp: 4210, xpMax: 13700, rested: 2100, money: 143820, guild: "Ashen Hoof" },
				location: { zone: "Orgrimmar", subzone: "The Drag" },
				professions: [{ name: "Leatherworking", kind: "primary", skill: 193, max: 225 }, { name: "Broken" }],
				holdings: { bags: { "2318": 3, "783": 1 }, bank: { t: NOW - 86400, items: { "2318": 20 } }, mail: { t: NOW - 3600, mails: 2 }, notCounted: ["account bank (not read)"] },
				ledger: { today: { since: DAY0, spent: 1, received: 2, net: 1, other: 3 } },
			},
		});
		expect(v.money).toBe(143820);
		expect(v.location).toBe("Orgrimmar, The Drag");
		expect(v.guild).toBe("Ashen Hoof");
		expect(v.xp).toEqual({ xp: 4210, max: 13700, rested: 2100 });
		expect(v.professions).toEqual([{ name: "Leatherworking", kind: "primary", skill: 193, max: 225 }]);
		expect(v.holdings).toEqual({ bags: 2, bank: { kinds: 1, t: NOW - 86400 }, mail: { mails: 2, t: NOW - 3600 }, notCounted: ["account bank (not read)"] });
		expect(v.ledger.today?.other).toBe(3);
		expect(v.ledger.reset).toBeNull();
		expect(v.auctions).toBeNull();
	});

	it("has no guild for false, no XP bar without xpMax, no subzone when empty", () => {
		const v = charView({ t: 1, data: { char: { guild: false, xp: 0, xpMax: 0, money: 0 }, location: { zone: "Durotar", subzone: "" } } });
		expect(v.guild).toBeNull();
		expect(v.xp).toBeNull();
		expect(v.money).toBe(0);
		expect(v.location).toBe("Durotar");
		expect(v.holdings).toBeNull();
		expect(charView(null).professions).toEqual([]);
	});

	it("names characters by first name and surname", () => {
		expect(fullName({ key: C, name: "Tarvok", surname: "Stonehide" })).toBe("Tarvok Stonehide");
		expect(fullName({ key: "Example Realm-Zalli", name: "Zalli", surname: null })).toBe("Zalli");
		expect(fullName({ key: "k", name: null, surname: null })).toBe("k");
	});
});

describe("auctions", () => {
	const raw = {
		active: [
			{ item: 2319, name: "Medium Leather", q: 20, status: "active", unitBuyout: 610, expires: NOW + 11 * 3600, houseLabel: "Horde AH" },
			{ item: 4246, name: "Fine Leather Belt", q: 1, status: "active", unitBid: 900, untracked: true },
		],
		sold: [
			{ item: 2318, name: "Light Leather", q: 20, status: "sold", soldAt: NOW - 2400, expected: 10240, expectedNote: "5% cut (confirmed)" },
			{ item: 4307, name: "Embossed Leather Gloves", q: 1, status: "sold", soldAt: NOW - 7200, expectedNote: "cut unverified", houseLabel: "Booty Bay" },
		],
		returning: [{ item: 7280, name: "Rugged Leather Pants", q: 1, status: "expired", statusText: "expired, returned via mail", at: NOW - 5 * 3600 }],
		expectedTotal: 10240,
		expectedMissing: 1,
		listedNoBuyout: 1,
	};

	it("keeps the totals the addon computed and says what it left out", () => {
		const a = auctionView(raw)!;
		expect(a.expectedTotal).toBe(10240);
		expect(a.expectedMissing).toBe(1);
		expect(a.listedTotal).toBeNull(); // older uploads have no listedTotal (#116)
		expect(a.listedLeftOut).toEqual(["1 without a buyout"]);
		expect(auctionView({ ...raw, listedTotal: 11590, listedNote: "5% cut (confirmed)" })!.listedTotal).toBe(11590);
		expect(auctionView(undefined)).toBeNull();
	});

	it("shows the expected payout for sales and the buyout for listings", () => {
		const groups = auctionGroups(auctionView(raw)!, NOW);
		expect(groups.map((g) => [g.key, g.rows.length])).toEqual([
			["sold", 2],
			["active", 2],
			["returning", 1],
			["uncertain", 0],
		]);
		const [sold, active, returning] = groups;
		expect(sold!.rows[0]).toMatchObject({ money: 10240, moneyLabel: "expected", note: "sold 40 min ago, after 5% cut (confirmed)" });
		expect(sold!.rows[1]).toMatchObject({ money: null, note: "sold 2 h ago, cut unverified, Booty Bay" });
		expect(active!.rows[0]).toMatchObject({ money: 12200, moneyLabel: "buyout", note: "buyout 6s 10c each, 11 h left" });
		expect(active!.rows[1]).toMatchObject({ money: null, note: "bid 9s each, no buyout, listed before tracking" });
		expect(returning!.rows[0]).toMatchObject({ note: "expired, returned via mail, 5 h ago" });
	});

	it("counts time left", () => {
		expect(timeLeft(-5)).toBe("time is up");
		expect(timeLeft(600)).toBe("10 min left");
		expect(timeLeft(11 * 3600)).toBe("11 h left");
		expect(timeLeft(3 * 86400)).toBe("3 days left");
	});
});

describe("fishing", () => {
	it("reads the fishing document with its zones", () => {
		const f = fishingView(
			{
				t: NOW,
				data: {
					days: 90,
					catches: 412,
					containersOpened: 9,
					findFish: { known: true, tracking: false },
					spots: [
						{ zone: "Durotar", sub: "Razor Hill", water: "open", n: 186, perCatch: 940, perHour: 19200 },
						{ zone: "The Barrens", sub: "", water: "?", n: 31, perCatch: 820 },
					],
					pools: [],
					fishingZones: { reference: true, zones: [{ zone: "Durotar", source: "own", n: 212, perCatch: 960 }, { zone: "Feralas", source: "ref", n: 5000, perCatch: 200, perCatchHigh: 230, unpriced: 1 }], more: 4 },
				},
			},
			null,
		)!;
		expect(f.findFish).toBe("known, tracking off");
		expect(f.spots.map((s) => [s.water, s.perHour])).toEqual([
			["Open water", 19200],
			["Not known yet", null],
		]);
		expect(f.zones.map((z) => [z.source, z.perCatchHigh, z.unpriced])).toEqual([
			["Your catches", null, null],
			["Reference", 230, 1],
		]);
		expect(f.moreZones).toBe(4);
		expect(fishingView(null, null)).toBeNull();
	});

	it("falls back to the snapshot's fishing summary", () => {
		const f = fishingView(null, { t: 1, data: { fishing: { days: 90, catches: 3 }, fishingZones: { zones: [] } } });
		expect(f?.catches).toBe(3);
		expect(f?.findFish).toBeNull();
	});

	it("names the water", () => {
		expect(waterText("pool", "Oily Blackmouth School")).toBe("Pool: Oily Blackmouth School");
		expect(waterText("pool", null)).toBe("Pool");
		expect(waterText("?", "Floating Wreckage")).toBe("Not known yet (Floating Wreckage)");
	});
});

describe("upload tokens", () => {
	const created: CreatedToken = { id: 7, token: "cw_invented-token-for-the-test-0000000000000000", prefix: "cw_inve", name: "Companion PC", scopes: ["public", "private"], created: NOW };

	it("shows a new token once: until the popup is closed, never in the list", () => {
		const reveal = new TokenReveal();
		expect(reveal.current).toBeNull();
		expect(reveal.show(created)).toEqual({ name: "Companion PC", token: created.token });
		expect(reveal.current?.token).toBe(created.token);
		reveal.dismiss();
		expect(reveal.current).toBeNull();
		// the list the page renders comes from GET /api/me/tokens, which has no token field
		const listed: Token = { id: 7, prefix: "cw_inve", name: "Companion PC", scopes: ["public", "private"], created: NOW, createdBy: "a@example.com", lastUsed: null, revoked: null };
		expect(JSON.stringify(sortTokens([listed]))).not.toContain(created.token);
	});

	it("lists active tokens first, newest first", () => {
		const tok = (id: number, revoked: number | null): Token => ({ id, prefix: "cw_x", name: `t${id}`, scopes: ["public"], created: 0, createdBy: null, lastUsed: null, revoked });
		expect(sortTokens([tok(1, null), tok(2, 5), tok(3, null), tok(4, 9)]).map((t) => t.id)).toEqual([3, 1, 4, 2]);
	});

	it("says what a token may upload", () => {
		expect(scopesText(["public", "private"])).toBe("prices and private data");
		expect(scopesText(["public"])).toBe("prices only");
		expect(scopesText(["private"])).toBe("private data only");
	});
});

describe("formatting", () => {
	it("shows database sizes and bar shares", () => {
		expect(megabytes(3.4 * 1024 * 1024)).toBe("3.4 MB");
		expect(megabytes(500 * 1024 * 1024)).toBe("500 MB");
		expect(share(18769, 90000)).toBeCloseTo(0.2085, 3);
		expect(share(5, 0)).toBe(0);
		expect(share(120, 100)).toBe(1);
	});

	it("shows today's times as a clock and older ones with the date", () => {
		const d = new Date(DAY0 * 1000 + (22 * 60 + 41) * 60000);
		expect(clockLabel(d.getTime() / 1000, DAY0 + 23 * 3600)).toBe("22:41");
		const y = new Date((DAY0 - 86400) * 1000 + (9 * 60 + 5) * 60000);
		const label = clockLabel(y.getTime() / 1000, NOW);
		expect(label).toMatch(/^[A-Z][a-z]{2} \d{1,2}, 09:05$/);
	});
});
