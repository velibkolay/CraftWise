// GET /api/sync/watch (#244): the changes of the watch list since a time, for the companion of every
// machine (#237). Token auth with the `private` scope. One entry per item that changed at or after
// `since` (server time): `{ i, t, d? }`, the same shape the upload takes (t = when the item was watched
// or unwatched, d: true = unwatched, a tombstone). The companion merges them into its own list by the
// same rule (newest wins, a tie keeps the item), so repeating an answer is harmless. Reads only.
import { uploadAuth } from "./auth";
import type { Env } from "./env";
import { HttpError } from "./http";
import { MIN_TIME, SYNC_SAFETY } from "./limits";

export async function syncWatch(request: Request, env: Env, url: URL, now: number): Promise<Response> {
	await uploadAuth(request, env, "private", now);
	const raw = url.searchParams.get("since");
	if (raw !== null && raw !== "" && !/^\d{1,12}$/.test(raw)) throw new HttpError(400, "bad_query", "since: expected Unix seconds");
	const since = raw ? Number(raw) : 0;
	const { results } = await env.DB.prepare(
		"SELECT item, added, removed FROM watch WHERE COALESCE(updated, 0) >= ?1 ORDER BY COALESCE(updated, 0), item",
	)
		.bind(since)
		.all<{ item: number; added: number; removed: number | null }>();
	const watch = results.map((r) => (r.removed === null ? { i: r.item, t: r.added } : { i: r.item, t: r.removed, d: true }));
	// what to send as `since` next time: a margin behind now, so a change that was still being written
	// when this was read is returned again
	const until = Math.max(MIN_TIME, now - SYNC_SAFETY);
	return new Response(JSON.stringify({ v: 1, watch, until }), {
		status: 200,
		headers: { "content-type": "application/json; charset=utf-8", "cache-control": "private, no-store" },
	});
}
