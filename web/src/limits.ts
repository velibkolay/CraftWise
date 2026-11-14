// Limits and retention (#95). Sized for the free plans: Workers 10 ms CPU per request, D1 100,000
// rows written and 5 million rows read per day, 500 MB per database (the account is on Workers Paid
// since 2026-11-12, #145; the design still fits Free). Measured numbers are in
// web/docs/api.md ("Budget").

export const DAY = 86400;

// Upload request bodies. The companion splits larger uploads into several requests.
export const MAX_PUBLIC_BYTES = 500_000; // ~5 ms CPU at most (npm run bench)
export const MAX_PRIVATE_BYTES = 500_000;
export const MAX_PRICE_ENTRIES = 2000; // item and house entries
export const MAX_ITEMS = 5000; // item IDs in names + itemInfo
export const MAX_CLASS_NAMES = 1000; // class and subclass names together (#120)
export const MAX_CLASS_NAME = 64; // characters
export const MAX_CLASS_ID = 65535;
export const MAX_HOUSES = 20;
export const MAX_SCANS = 200;
export const MAX_RAW_POINTS = 500; // per price entry (the addon keeps 48 h)
export const MAX_DAYS = 400; // per price entry (the addon keeps 30 days)
export const MAX_TIERS = 8; // price levels per raw point
export const MAX_LEDGER_ENTRIES = 5000;
export const MAX_PRIVATE_DOC_BYTES = 450_000; // one snapshot / auctions / fishing document (a snapshot is ~60 KB)
export const MAX_CHARACTERS = 50;
export const MAX_WATCH = 1000; // watched items in one private upload (#165)

// Upload requests per token per minute.
export const UPLOADS_PER_MINUTE = 30;
// Daily D1 write budget (#145): rows written a day CraftWise may use, the Worker var WRITE_BUDGET
// (wrangler.jsonc "vars"); DEFAULT_WRITE_BUDGET when it is missing or not a whole number from 1 to
// MAX_WRITE_BUDGET. Workers Paid (the account's plan since 2026-11-12): D1 has no daily limit, 50
// million rows written a month are included, then $1 per million; the default, 1,000,000 a day, is
// effectively no limit and at most 30 million a month, so it never costs extra. Workers Free:
// 100,000 rows a day per Cloudflare ACCOUNT, shared by every D1 database on it (Hivemind's too), so
// set the var to 30000 there.
export const DEFAULT_WRITE_BUDGET = 1_000_000;
export const MAX_WRITE_BUDGET = 1_000_000; // a larger value counts as a typo: the default applies
// Above this share of the budget only price data and private data are written; item info, names,
// sell prices, search words and class names wait for the next day (429 write_budget).
export const SOFT_BUDGET_SHARE = 0.8;

export function parseWriteBudget(value: unknown): number {
	const n = typeof value === "number" ? value : typeof value === "string" && /^\s*\d+\s*$/.test(value) ? Number(value) : NaN;
	return Number.isSafeInteger(n) && n >= 1 && n <= MAX_WRITE_BUDGET ? n : DEFAULT_WRITE_BUDGET;
}

export function softBudget(budget: number): number {
	return Math.floor(budget * SOFT_BUDGET_SHARE);
}
export const MAX_ACTIVE_TOKENS = 20;

// Earliest accepted timestamp (2020-09-13) and allowed clock skew into the future.
export const MIN_TIME = 1_600_000_000;
export const MAX_FUTURE = DAY;

// Retention (cron, daily). Daily aggregates, items, prices, private data: kept.
export const RAW_DAYS = 30;
export const SCANS_DAYS = 90;
export const USAGE_DAYS = 90;
export const CACHE_DAYS = 7;

// Read API.
export const SEARCH_LIMIT = 20;
export const SEARCH_MAX = 50;
export const HISTORY_DAYS = 90;
export const HISTORY_DAYS_MAX = 3650;
export const RAW_HOURS = 48;
export const RAW_HOURS_MAX = RAW_DAYS * 24;
export const SCANS_LIMIT = 20;
export const SCANS_MAX = 100;
export const MOVERS_LIMIT = 10;
export const MOVERS_MAX = 25;
export const MOVERS_MAX_AGE = 2 * DAY; // current price must be this recent
export const BROWSE_MAX = 500; // items per /api/browse answer (more: true beyond)
export const BROWSE_IDS_MAX = 100; // ids=... (the site's favourites)
export const BROWSE_DAYS = 9; // daily rows per item: enough for a change against the same day a week ago
export const PUBLIC_MAX_AGE = 60; // Cache-Control for public reads, seconds

// The same rules as CraftWise/Market.lua.
export const TYPICAL_DAYS = 7;
export const MIN_HISTORY_DAYS = 3;
