-- wow.velikopter.com schema (#95). Money is copper, times are Unix seconds, `day` is floor(t / 86400)
-- (UTC days, the same day number as CraftWise/Market.lua). Item keys are split into item ID and
-- suffix ID (0 = no random suffix), so "2589" is (2589, 0) and "15210:1017" is (15210, 1017).
--
-- Write budget (D1 free plan: 100,000 rows written per day, every index entry counts as a row):
-- price tables are WITHOUT ROWID with no secondary index, so one upsert is one row written.

-- Auction houses as CraftWise names them: "<realm>|H", "<realm>|A", "<realm>|N:BootyBay".
CREATE TABLE houses (
	id INTEGER PRIMARY KEY,
	key TEXT NOT NULL UNIQUE,
	realm TEXT NOT NULL,
	kind TEXT NOT NULL CHECK (kind IN ('faction', 'neutral')),
	faction TEXT CHECK (faction IN ('Horde', 'Alliance')),
	label TEXT NOT NULL,
	last_scan INTEGER,           -- latest scan of any kind
	last_full_scan INTEGER,
	last_full_scan_items INTEGER -- items stored by that full scan (with history + last only)
);

-- Item info from the client (CraftWise #92). A field the client didn't give is NULL.
CREATE TABLE items (
	id INTEGER PRIMARY KEY,
	name TEXT,
	quality INTEGER,
	icon INTEGER,  -- icon file ID
	class INTEGER,
	subclass INTEGER,
	updated INTEGER NOT NULL
);

-- Search index: lower-case words of item names; search is by word prefix.
CREATE TABLE item_words (
	word TEXT NOT NULL,
	item INTEGER NOT NULL,
	PRIMARY KEY (word, item)
) WITHOUT ROWID;

-- Latest observation per item and house (CraftWise `last`) and the latest price depth.
CREATE TABLE prices (
	house INTEGER NOT NULL,
	item INTEGER NOT NULL,
	suffix INTEGER NOT NULL,
	t INTEGER NOT NULL,
	min INTEGER,         -- lowest unit price
	qty INTEGER,         -- units listed
	listings INTEGER,    -- listings (price levels for commodities); NULL when the client didn't say
	off INTEGER,         -- a later full scan at this house didn't list it (time of that scan)
	depth_t INTEGER,     -- time of the latest raw point (scope items only)
	depth_total INTEGER, -- units in that point
	depth TEXT,          -- its cheapest price tiers, JSON [price, qty, price, qty, ...]
	PRIMARY KEY (house, item, suffix)
) WITHOUT ROWID;

-- Raw price points of scope items (CraftWise `raw`): kept RAW_DAYS (src/limits.ts).
CREATE TABLE points (
	house INTEGER NOT NULL,
	item INTEGER NOT NULL,
	suffix INTEGER NOT NULL,
	t INTEGER NOT NULL,
	total INTEGER NOT NULL,
	listings INTEGER,
	m INTEGER,           -- median of the cheapest 15% when the tiers don't hold all units
	tiers TEXT NOT NULL, -- JSON [price, qty, ...], cheapest first, at most 8 levels
	PRIMARY KEY (house, item, suffix, t)
) WITHOUT ROWID;

-- Daily aggregates, kept forever.
-- src 1: CraftWise's own aggregate of a scope item (lo, typ, hi, qty_max, list_max, n, gone).
-- src 0: built here from `last` observations of an item outside the scope: lo/hi are the lowest
--        and highest minimum price seen that day, qty_max/list_max the most units/listings seen;
--        typ, n and gone are NULL (unknown without tiers). A src 1 row always replaces a src 0 row.
CREATE TABLE daily (
	house INTEGER NOT NULL,
	item INTEGER NOT NULL,
	suffix INTEGER NOT NULL,
	day INTEGER NOT NULL,
	src INTEGER NOT NULL,
	lo INTEGER,
	typ INTEGER,
	hi INTEGER,
	qty_max INTEGER,
	list_max INTEGER,
	n INTEGER,
	gone INTEGER,
	PRIMARY KEY (house, item, suffix, day)
) WITHOUT ROWID;
-- Top movers read the typical prices of one house's last 7 days; only src 1 rows have one.
CREATE INDEX daily_typ ON daily (house, day) WHERE typ IS NOT NULL;

-- Scan log (CraftWiseMarketDB.scans): kept SCANS_DAYS.
CREATE TABLE scans (
	house INTEGER NOT NULL,
	t INTEGER NOT NULL,
	kind TEXT NOT NULL,
	items INTEGER,     -- scope items recorded
	last_only INTEGER, -- other items recorded with `last` only
	source TEXT,
	PRIMARY KEY (house, t, kind)
) WITHOUT ROWID;

-- Computed results (top movers), recomputed when a house gets a new scan.
CREATE TABLE cache (
	key TEXT PRIMARY KEY,
	t INTEGER NOT NULL,
	data TEXT NOT NULL
) WITHOUT ROWID;

-- Upload tokens, created on the private page. Only the SHA-256 of a token is stored.
CREATE TABLE tokens (
	id INTEGER PRIMARY KEY,
	hash TEXT NOT NULL UNIQUE,
	prefix TEXT NOT NULL,    -- first characters, to tell tokens apart on the page
	name TEXT NOT NULL,
	scopes TEXT NOT NULL,    -- "public", "private" or "public private"
	created INTEGER NOT NULL,
	created_by TEXT,         -- Access e-mail
	last_used INTEGER,
	revoked INTEGER,
	rl_window INTEGER,       -- rate limit: current minute and requests in it
	rl_count INTEGER
);

-- Rows written per UTC day as D1 reports them, for the daily write budget.
CREATE TABLE usage (
	day INTEGER PRIMARY KEY,
	rows_written INTEGER NOT NULL DEFAULT 0,
	uploads INTEGER NOT NULL DEFAULT 0
);

-- Private data (only through /api/me/* behind Cloudflare Access).
-- Character key as CraftWise uses it: "<realm>-<name> <surname>" (#77).
CREATE TABLE characters (
	key TEXT PRIMARY KEY,
	realm TEXT,
	name TEXT,
	surname TEXT,
	faction TEXT,
	race TEXT,
	class TEXT,
	level INTEGER,
	updated INTEGER NOT NULL
) WITHOUT ROWID;

-- Latest document per character; an upload replaces it only when its `t` is newer.
CREATE TABLE snapshots (char TEXT PRIMARY KEY, t INTEGER NOT NULL, data TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE auctions (char TEXT PRIMARY KEY, t INTEGER NOT NULL, data TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE fishing (char TEXT PRIMARY KEY, t INTEGER NOT NULL, data TEXT NOT NULL) WITHOUT ROWID;

-- Purchase and sale log (CraftWiseMarketDB.ledger.entries). uid makes a re-upload a no-op.
CREATE TABLE ledger (
	uid TEXT PRIMARY KEY,
	char TEXT NOT NULL,
	t INTEGER NOT NULL,
	kind TEXT NOT NULL,
	item INTEGER,
	qty INTEGER,
	money INTEGER,
	place TEXT,
	name TEXT
) WITHOUT ROWID;
CREATE INDEX ledger_by_char ON ledger (char, t);
