-- The addon's item watch list (#165): CraftWiseDB.watch = { [itemID] = addedAt }, uploaded by the
-- companion with the private upload. One list for the site's owner (every Access login is the owner, as
-- for characters and the ledger). An upload that carries the list replaces it as a whole: items no longer
-- in it are deleted, changed times updated, unchanged rows are not written.
CREATE TABLE watch (
	item INTEGER PRIMARY KEY,
	added INTEGER NOT NULL
) WITHOUT ROWID;
