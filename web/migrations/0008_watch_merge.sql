-- The watch list becomes two-way (#244, two machines #237): the addon of each machine, the companion
-- and the site's favourites all change it, and the changes are merged per item instead of one upload
-- replacing the list.
--
-- Per item the newest change wins (a tie keeps the item watched). A removal is kept as a tombstone, or
-- the machine that didn't see it would add the item back:
--   added    Unix time the item was watched (0 = never watched here, only a tombstone is stored)
--   removed  Unix time it was unwatched; NULL = watched. The item's state time is COALESCE(removed, added).
--   updated  Unix seconds (the database clock) of the last change, so the companion downloads only what
--            changed (`GET /api/sync/watch?since=`)
-- Existing rows stay as they are (watched, removed NULL) and count as changed now, so the first
-- download of every companion carries the whole list once. One row per item, at most a few thousand
-- (an upload carries at most 1,000 changes); no index.
ALTER TABLE watch ADD COLUMN removed INTEGER;
ALTER TABLE watch ADD COLUMN updated INTEGER;
UPDATE watch SET updated = CAST(strftime('%s', 'now') AS INTEGER);
