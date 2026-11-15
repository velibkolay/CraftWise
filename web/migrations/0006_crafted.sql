-- The craft log (#266): CraftWiseDB.crafted of the addon (Crafts.lua, #205), uploaded by the companion with the
-- private upload. One row per character, recipe (spell ID) and local day (YYYYMMDD, the player's day). The
-- addon keeps 90 days; the site keeps every day it received, forever.
--   n      crafts that day
--   items  items made (null when the recipe's yield isn't one exact number, or the day predates it)
--   profit copper, the estimate recorded at craft time summed over the crafts that had a price (may be negative);
--          null for days before profit was recorded
--   known  how many of the n crafts had a profit (profit covers only those)
--   active seconds of active crafting (#251); null for days before it was recorded
-- An upload writes a row only when it brings more crafts than the stored one (a day's craft count only grows),
-- so re-sending a day writes nothing. No secondary index: one row written per changed day.
CREATE TABLE crafted (
	char TEXT NOT NULL,
	recipe INTEGER NOT NULL,
	day INTEGER NOT NULL,
	n INTEGER NOT NULL,
	items INTEGER,
	profit INTEGER,
	known INTEGER,
	active REAL,
	PRIMARY KEY (char, recipe, day)
) WITHOUT ROWID;
