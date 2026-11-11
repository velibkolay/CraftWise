// Limits and retention (#95). Sized for the free plans: Workers 10 ms CPU per request, D1 100,000
// rows written and 5 million rows read per day, 500 MB per database. Measured numbers are in
// web/docs/api.md ("Budget").

export const DAY = 86400;

// Upload request bodies. The companion splits larger uploads into several requests.
export const MAX_PUBLIC_BYTES = 500_000; // ~5 ms CPU at most (npm run bench)
export const MAX_PRIVATE_BYTES = 500_000;
export const MAX_PRICE_ENTRIES = 2000; // item and house entries
export const MAX_ITEMS = 5000; // item IDs in names + itemInfo
export const MAX_HOUSES = 20;
export const MAX_SCANS = 200;
export const MAX_RAW_POINTS = 500; // per price entry (the addon keeps 48 h)
export const MAX_DAYS = 400; // per price entry (the addon keeps 30 days)
export const MAX_TIERS = 8; // price levels per raw point
export const MAX_LEDGER_ENTRIES = 5000;
export const MAX_PRIVATE_DOC_BYTES = 450_000; // one snapshot / auctions / fishing document (a snapshot is ~60 KB)
export const MAX_CHARACTERS = 50;

// Upload requests per token per minute.
export const UPLOADS_PER_MINUTE = 30;
// Uploads are refused (429) once D1 reported this many rows written today (free plan: 100,000).
export const WRITE_BUDGET = 90_000;
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
export const PUBLIC_MAX_AGE = 60; // Cache-Control for public reads, seconds

// The same rules as CraftWise/Market.lua.
export const TYPICAL_DAYS = 7;
export const MIN_HISTORY_DAYS = 3;
