// The daily write budget as a Worker var and its soft limit for low-priority writes (#145).
import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { DEFAULT_WRITE_BUDGET, parseWriteBudget, softBudget } from "../src/limits";
import { usage } from "../src/me";
import { bearer, body, clearData, HORDE, makeToken, now, ORIGIN, type Short } from "./helpers";

const DAY = 86400;
const CHAR = "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner";

describe("parseWriteBudget", () => {
	it("reads whole numbers from 1 to 1,000,000", () => {
		expect(parseWriteBudget("30000")).toBe(30000);
		expect(parseWriteBudget(" 12000 ")).toBe(12000);
		expect(parseWriteBudget(25000)).toBe(25000);
		expect(parseWriteBudget("1")).toBe(1);
		expect(parseWriteBudget("100000")).toBe(100000);
		expect(parseWriteBudget("1000000")).toBe(1000000);
	});

	it("falls back to 1,000,000 for anything else", () => {
		for (const v of [undefined, null, "", "abc", "0", "-5", "1e4", "20_000", "12000.5", "1000001", 0, -1, 1.5, NaN, Infinity, {}]) {
			expect(parseWriteBudget(v)).toBe(DEFAULT_WRITE_BUDGET);
		}
		expect(DEFAULT_WRITE_BUDGET).toBe(1000000);
	});

	it("puts the soft limit at 80%", () => {
		expect(softBudget(1000000)).toBe(800000);
		expect(softBudget(30000)).toBe(24000);
		expect(softBudget(1001)).toBe(800);
	});

	it("is set in wrangler.jsonc", () => {
		expect(env.WRITE_BUDGET).toBe("1000000");
	});
});

// Calls the Worker with WRITE_BUDGET set to `budget`.
async function post(path: string, token: string, payload: unknown, budget = "1000"): Promise<Response> {
	const request = new Request<unknown, IncomingRequestCfProperties>(ORIGIN + path, {
		method: "POST",
		headers: { ...bearer(token), "content-type": "application/json" },
		body: JSON.stringify(payload),
	});
	const ctx = createExecutionContext();
	const res = await worker.fetch(request, { ...env, WRITE_BUDGET: budget }, ctx);
	await waitOnExecutionContext(ctx);
	return res;
}

async function setWritten(rows: number): Promise<void> {
	await env.DB.prepare("INSERT OR REPLACE INTO usage (day, rows_written, uploads) VALUES (?1, ?2, 0)").bind(Math.floor(now() / DAY), rows).run();
}

function prices(t: number): Short {
	return { prices: [{ item: "2589", house: HORDE, last: { t, min: 95, qty: 400, listings: 6 } }] };
}

function names(): Short {
	return { items: { "2589": { n: "Linen Cloth", q: 1, i: 132889, c: 7, s: 5, p: 10 } } };
}

function privateBody(t: number) {
	return {
		v: 1,
		snapshots: { [CHAR]: { t, data: { v: 1 } } },
		ledger: [{ t, c: CHAR, k: "buy", i: 2589, q: 5, m: 500 }],
	};
}

// Retry-After is the seconds left until 00:00 UTC at the moment the Worker handled the request, which lies
// somewhere between `before` and `after`; every second in that window is a valid answer (#148). Walking the
// window also covers a midnight wrap in between.
function expectRetryAfter(res: Response, before: number, after: number): void {
	const accepted: string[] = [];
	for (let s = before; s <= after; s++) accepted.push(String(DAY - (s % DAY)));
	expect(accepted).toContain(res.headers.get("retry-after"));
}

let token: string;
beforeEach(async () => {
	await clearData();
	token = await makeToken();
});

describe("write budget from the Worker var", () => {
	it("stops every upload at the configured budget", async () => {
		await setWritten(1000);
		const t = now();
		const before = now();
		for (const res of [await post("/api/upload", token, body(prices(t))), await post("/api/private/upload", token, privateBody(t))]) {
			expect(res.status).toBe(429);
			expect(await res.json()).toMatchObject({ error: "write_budget" });
			expectRetryAfter(res, before, now());
		}
		// the same day's count is far below 30,000 (the Free plan setting)
		expect((await post("/api/upload", token, body(prices(t)), "30000")).status).toBe(200);
	});

	it("reports the budget and the soft limit on /api/me/usage", async () => {
		await setWritten(321);
		const read = async (budget: string | undefined) =>
			(await usage({ ...env, WRITE_BUDGET: budget }, now())).json<{ rowsWritten: number; budget: number; softBudget: number }>();
		expect(await read("12000")).toMatchObject({ rowsWritten: 321, budget: 12000, softBudget: 9600 });
		expect(await read(undefined)).toMatchObject({ budget: 1000000, softBudget: 800000 });
		expect(await read("nonsense")).toMatchObject({ budget: 1000000, softBudget: 800000 });
	});
});

describe("soft limit: low-priority writes wait above 80%", () => {
	it("below the soft limit item info and prices go through together", async () => {
		await setWritten(700);
		const res = await post("/api/upload", token, body({ ...names(), ...prices(now()) }));
		expect(res.status).toBe(200);
	});

	it("above it new item info, names and sell prices are refused until 00:00 UTC", async () => {
		await setWritten(800); // soft limit of 1,000
		const t = now();
		const before = now();
		let res = await post("/api/upload", token, body(names()));
		const after = now();
		expect(res.status).toBe(429);
		expectRetryAfter(res, before, after);
		expect(await res.json()).toMatchObject({ error: "write_budget" });
		// a request mixing item info with prices is refused as a whole: nothing is written
		res = await post("/api/upload", token, body({ ...names(), ...prices(t) }));
		expect(res.status).toBe(429);
		expect(await env.DB.prepare("SELECT count(*) AS n FROM prices").first("n")).toBe(0);
		expect(await env.DB.prepare("SELECT count(*) AS n FROM items").first("n")).toBe(0);
		// class names too
		res = await post("/api/upload", token, body({ classNames: { "7": "Trade Goods" } }));
		expect(res.status).toBe(429);
	});

	it("above it price data and private data still go through, up to the full budget", async () => {
		await setWritten(900);
		const t = now();
		const pub = await post("/api/upload", token, body({ scans: [{ house: HORDE, t, kind: "full", items: 1 }], ...prices(t) }));
		expect(pub.status).toBe(200);
		expect(await env.DB.prepare("SELECT count(*) AS n FROM prices").first("n")).toBe(1);
		const priv = await post("/api/private/upload", token, privateBody(t));
		expect(priv.status).toBe(200);
		expect(await env.DB.prepare("SELECT count(*) AS n FROM ledger").first("n")).toBe(1);
	});

	it("item info already stored unchanged is no write and not refused", async () => {
		expect((await post("/api/upload", token, body(names()), "30000")).status).toBe(200);
		await setWritten(900);
		const res = await post("/api/upload", token, body({ ...names(), ...prices(now()) }));
		expect(res.status).toBe(200);
		expect(await res.json()).toMatchObject({ itemsChanged: 0 });
	});
});
