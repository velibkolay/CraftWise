-- Download of the merged market for the companion (#238, two machines #237).
-- `GET /api/sync/market?since=` returns the item/house entries that changed at or after `since`, so
-- every entry needs the server time of its last change.
--
-- `prices.updated` / `variants.updated`: Unix seconds (the database clock) of the last write that
-- changed the row, or that changed a part of the entry stored elsewhere: a new raw point (`points`)
-- or a changed CraftWise day aggregate (`daily` src 1). The triggers below set it, so an upload
-- that changes nothing still writes nothing.
--
-- Cost: one more index entry per `prices` row written (`variants` has no index: one row per item
-- and house, a few thousand rows, read whole by the download). Existing rows get `updated = t` once
-- (a one-time write of every `prices` and `variants` row plus the index entries).

ALTER TABLE prices ADD COLUMN updated INTEGER;
ALTER TABLE variants ADD COLUMN updated INTEGER;

UPDATE prices SET updated = t;
UPDATE variants SET updated = (SELECT max(CAST(value->>0 AS INTEGER)) FROM json_each(variants.data));

-- The download walks `prices` in (updated, house, item, suffix) order, the index order.
CREATE INDEX prices_updated ON prices (updated);

-- A new raw point or a changed CraftWise aggregate marks its price row. The WHERE keeps a second
-- change in the same second from rewriting the row (and its index entry) again.
CREATE TRIGGER points_touch AFTER INSERT ON points
BEGIN
	UPDATE prices SET updated = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE house = new.house AND item = new.item AND suffix = new.suffix
		AND updated IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;

CREATE TRIGGER daily_touch_insert AFTER INSERT ON daily WHEN new.src = 1
BEGIN
	UPDATE prices SET updated = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE house = new.house AND item = new.item AND suffix = new.suffix
		AND updated IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;

CREATE TRIGGER daily_touch_update AFTER UPDATE ON daily WHEN new.src = 1
BEGIN
	UPDATE prices SET updated = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE house = new.house AND item = new.item AND suffix = new.suffix
		AND updated IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;
