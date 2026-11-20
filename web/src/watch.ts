// The watch list (#165, two-way since #244): one row per item with the time of its newest change
// and whether that change was a removal (a tombstone). Changes from the addon (through the
// companion), from the other machine and from the site's favourites all go through mergeWatch, so
// they converge whatever the order they arrive in:
//   - per item the newest change time wins;
//   - on the same second, "watched" wins (an item is never lost to a tie);
//   - a change that doesn't win writes nothing.
import type { Env } from "./env";

export interface WatchChange {
	item: number;
	t: number; // when the item was watched or unwatched
	removed: boolean;
}

// The statements that merge `changes` (at most one per item) into the table. The WHERE of the upsert is
// the whole rule: the incoming change is newer than the stored state, or equally new and a "watched"
// replacing a removal.
export function mergeWatchStatements(env: Env, changes: WatchChange[]): D1PreparedStatement[] {
	if (!changes.length) return [];
	const rows = JSON.stringify(changes.map((c) => [c.item, c.t, c.removed ? 1 : 0]));
	return [
		env.DB.prepare(
			`INSERT INTO watch (item, added, removed, updated)
			SELECT value->>0, CASE WHEN value->>2 = 1 THEN 0 ELSE value->>1 END, CASE WHEN value->>2 = 1 THEN value->>1 END,
				CAST(strftime('%s', 'now') AS INTEGER)
			FROM json_each(?1) WHERE true
			ON CONFLICT (item) DO UPDATE SET
				added = CASE WHEN excluded.removed IS NULL THEN excluded.added ELSE watch.added END,
				removed = excluded.removed,
				updated = excluded.updated
			WHERE COALESCE(excluded.removed, excluded.added) > COALESCE(watch.removed, watch.added)
				OR (COALESCE(excluded.removed, excluded.added) = COALESCE(watch.removed, watch.added)
					AND excluded.removed IS NULL AND watch.removed IS NOT NULL)`,
		).bind(rows),
	];
}

// Keeps one change per item: the newest, a tie to "watched".
export function newestPerItem(changes: WatchChange[]): WatchChange[] {
	const by = new Map<number, WatchChange>();
	for (const c of changes) {
		const old = by.get(c.item);
		if (!old || c.t > old.t || (c.t === old.t && old.removed && !c.removed)) by.set(c.item, c);
	}
	return [...by.values()];
}
