-- Connected realms (#366). Two realms that share an auction house, proved in game: a linked character of
-- the player answered a whisper from the other realm (the addon records the pair, the companion uploads
-- it as `connected`). One row per pair, stored once in a fixed order (a < b by plain string comparison),
-- `t` is the earliest time any upload reported it. Rows only ever come from uploads: no list of realms
-- is built in, and nothing here changes the stored prices, which stay per house key. The read API
-- groups the houses of connected realms at read time (src/groups.ts); deleting rows undoes the grouping.
CREATE TABLE connected (
	a TEXT NOT NULL,
	b TEXT NOT NULL,
	t INTEGER NOT NULL,
	PRIMARY KEY (a, b),
	CHECK (a < b)
) WITHOUT ROWID;
