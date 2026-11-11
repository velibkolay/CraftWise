-- Random-suffix variants packed per item (#118). A full browse of the auction house is mostly gear
-- with a random suffix ("<item>:<suffix>", e.g. 16,465 of 21,117 entries over 1,333 items in the
-- first real upload), and one row per variant cost a `prices` and a `daily` row each. Their `last`
-- observations now go into one row per item and house (current) and per item, house and day
-- (history): a full browse writes about one row per item instead of one per variant.
--
-- Which variant goes where (src/upload.ts): a record with raw points, and every later `last` of a
-- variant whose `prices` row has a depth (scope items, CraftWise keeps their history), stays in
-- `prices` / `daily` / `points` as before. Everything else with a suffix goes here. Rows written
-- before this migration stay where they are; the read API merges both (newer `t` wins for the
-- current price, a CraftWise aggregate wins a day, two `last` days are combined).

-- Latest `last` per variant: {"<suffix>": [t, min, qty, listings, off], ...}
CREATE TABLE variants (
	house INTEGER NOT NULL,
	item INTEGER NOT NULL,
	data TEXT NOT NULL,
	PRIMARY KEY (house, item)
) WITHOUT ROWID;

-- Daily rows built from `last` (as `daily` src 0): {"<suffix>": [lo, hi, qtyMax, listMax], ...}
CREATE TABLE variant_days (
	house INTEGER NOT NULL,
	item INTEGER NOT NULL,
	day INTEGER NOT NULL,
	data TEXT NOT NULL,
	PRIMARY KEY (house, item, day)
) WITHOUT ROWID;
