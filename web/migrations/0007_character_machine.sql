-- Which machine uploaded a character, and when (#242, two machines #237). The download of the
-- characters (`GET /api/sync/characters`) gives every character to the companion of the other
-- machine, labelled with these two columns, and walks them in `uploaded` order.
--
-- machine   the uploading companion's machine name (header X-CraftWise-Machine), else the name of the
--           token it uploaded with; NULL for a character last uploaded before this migration. Written
--           by the private upload only when it differs.
-- uploaded  Unix seconds (the database clock) of the last change of the character's stored data: a
--           newer snapshot, auctions or fishing document, a new ledger entry, a new or changed craft
--           day. The triggers below set it, so an upload that changes nothing still writes nothing.
--
-- Cost: one more row written per character and change (at most one per second). No index:
-- `characters` has one row per character (a few dozen at most).
ALTER TABLE characters ADD COLUMN machine TEXT;
ALTER TABLE characters ADD COLUMN uploaded INTEGER;

-- Existing characters count as uploaded when their snapshot says so (a one-time write per character).
UPDATE characters SET uploaded = updated WHERE updated > 0;

-- The WHERE keeps a second change in the same second from rewriting the row again.
CREATE TRIGGER snapshots_touch_insert AFTER INSERT ON snapshots
BEGIN
	UPDATE characters SET uploaded = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE key = new.char AND uploaded IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;
CREATE TRIGGER snapshots_touch_update AFTER UPDATE ON snapshots
BEGIN
	UPDATE characters SET uploaded = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE key = new.char AND uploaded IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;
CREATE TRIGGER auctions_touch_insert AFTER INSERT ON auctions
BEGIN
	UPDATE characters SET uploaded = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE key = new.char AND uploaded IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;
CREATE TRIGGER auctions_touch_update AFTER UPDATE ON auctions
BEGIN
	UPDATE characters SET uploaded = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE key = new.char AND uploaded IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;
CREATE TRIGGER fishing_touch_insert AFTER INSERT ON fishing
BEGIN
	UPDATE characters SET uploaded = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE key = new.char AND uploaded IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;
CREATE TRIGGER fishing_touch_update AFTER UPDATE ON fishing
BEGIN
	UPDATE characters SET uploaded = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE key = new.char AND uploaded IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;
CREATE TRIGGER ledger_touch AFTER INSERT ON ledger
BEGIN
	UPDATE characters SET uploaded = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE key = new.char AND uploaded IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;
CREATE TRIGGER crafted_touch_insert AFTER INSERT ON crafted
BEGIN
	UPDATE characters SET uploaded = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE key = new.char AND uploaded IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;
CREATE TRIGGER crafted_touch_update AFTER UPDATE ON crafted
BEGIN
	UPDATE characters SET uploaded = CAST(strftime('%s', 'now') AS INTEGER)
	WHERE key = new.char AND uploaded IS NOT CAST(strftime('%s', 'now') AS INTEGER);
END;
