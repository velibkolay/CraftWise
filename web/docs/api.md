# wow.velikopter.com API (#95)

The Worker in `web/` serves the public price API, takes uploads from the companion app (#94) and
serves the private API behind Cloudflare Access. Money is copper, times are Unix seconds, `day` is
`floor(t / 86400)` (UTC days, the same day number as `CraftWise/Market.lua`). JSON everywhere.

Errors are `{ "error": "<code>", "message": "<text>" }` with the HTTP status:

| Status | `error` | When |
|---|---|---|
| 400 | `bad_json`, `bad_shape`, `bad_query` | `bad_shape` names the field: `prices[3].last.min: expected a non-negative integer` |
| 401 | `unauthorized` | bearer token missing, malformed, unknown or revoked |
| 403 | `forbidden`, `access_denied`, `bad_origin` | token lacks the scope; no valid Access login; cross-site change on `/api/me/*` |
| 404 | `not_found` | |
| 405 / 415 | `method_not_allowed` / `unsupported_media_type` | uploads need `POST` and `Content-Type: application/json` |
| 413 | `too_large` | body over the limit: split it |
| 429 | `rate_limited`, `write_budget` | wait `Retry-After` seconds |
| 503 | `access_not_configured`, `access_keys` | `ACCESS_AUD` not set; Access keys unreachable |

## Uploads (companion app)

`Authorization: Bearer cw_...` with a token created on the private page (`/me`, see "Tokens").
A token has the scopes `public` (`POST /api/upload`) and/or `private` (`POST /api/private/upload`).
Only the token's SHA-256 is stored.

Rules for the companion:
- **Body at most 500,000 bytes** and 2,000 price entries (5,000 item infos). Split larger uploads
  into several requests; each request is stored on its own (one D1 transaction).
- **Re-sending is safe.** Every write is idempotent: the same body again changes nothing. A failed
  request can simply be retried.
- **Send what changed.** Keep the last uploaded packed string per item and house (the entry strings in
  `CraftWiseMarketDB.items` change whenever the addon records something) and send only entries whose
  string changed since the last successful upload. Unchanged entries cost upload time and CPU.
- **429:** wait `Retry-After` seconds. `rate_limited`: at most 30 requests a minute per token.
  `write_budget`: today's D1 write budget is used up (see "Budget"); resume after 00:00 UTC.
- **413:** split the body and retry.
- Never upload `CraftWiseMarketDB.auctionator` (#90: Auctionator mixes houses; the site shows no
  prices of unknown houses).
- Leave out what the addon doesn't have (or send `null`). Nothing is filled in on the server.

### `POST /api/upload`: public market data

```json
{
  "v": 1,
  "houses": {
    "CAMWOW EU4 Realm 8 PvP|H": { "realm": "CAMWOW EU4 Realm 8 PvP", "kind": "faction", "faction": "Horde", "label": "Horde AH" },
    "CAMWOW EU4 Realm 8 PvP|N:BootyBay": { "realm": "CAMWOW EU4 Realm 8 PvP", "kind": "neutral", "label": "Booty Bay" }
  },
  "scans": [
    { "house": "CAMWOW EU4 Realm 8 PvP|H", "t": 1794400000, "kind": "full", "items": 1480, "lastOnly": 8520, "source": "auctionator" }
  ],
  "items": {
    "2589": { "n": "Linen Cloth", "q": 1, "i": 132889, "c": 7, "s": 5 }
  },
  "prices": [
    {
      "item": "2589",
      "house": "CAMWOW EU4 Realm 8 PvP|H",
      "last": { "t": 1794400000, "min": 95, "qty": 400, "listings": 6 },
      "raw": [ { "t": 1794400000, "total": 400, "listings": 6, "m": 120, "tiers": [95, 10, 100, 40, 120, 150] } ],
      "days": [ { "day": 20768, "lo": 90, "typ": 100, "hi": 140, "qtyMax": 500, "listMax": 7, "n": 4, "gone": 20 } ]
    },
    { "item": "15210:1017", "house": "CAMWOW EU4 Realm 8 PvP|N:BootyBay", "last": { "t": 1794399400, "min": 25000, "qty": 1 } }
  ]
}
```

| Field | Source in the SavedVariables | Rules |
|---|---|---|
| `v` | | `1` |
| `houses` | `CraftWiseMarketDB.houses[<house key>]`: `realm`, `kind`, `faction`, `label` | Every house used in `scans` or `prices` must be listed. Key `<realm>\|H`, `<realm>\|A` or `<realm>\|N:<Name>`; `realm` must match the key; faction houses carry `faction` (`H` = Horde, `A` = Alliance), neutral houses none. At most 20. |
| `scans[]` | `CraftWiseMarketDB.scans[<house key>][]`: `t`, `kind`, `items`, `lastOnly`, `source` | `kind` lower-case letters (`full`, `search`, `gear`). Optional; drives "last scanned" per house. |
| `items` | item info per item ID (#92: `n` name, `q` quality, `i` icon file ID, `c` class, `s` subclass) | Optional. A field left out keeps the value stored before; only changed items are written. Names as the client gave them. |
| `prices[].item` | item key of `CraftWiseMarketDB.items` | `"<itemID>"` or `"<itemID>:<suffixID>"` |
| `prices[].house` | house key | |
| `prices[].last` | `DecodeEntry(s).last`: `t`, `min`, `qty`, `listings`, `off` | `t`, `min`, `qty` required; `listings` (browse results have none) and `off` optional. |
| `prices[].raw[]` | `DecodeEntry(s).raw[]`: `t`, `total`, `listings`, `m`, `tiers` | Scope items only. `tiers` = `[price, qty, ...]`, at most 8 levels, prices rising. At most 500 points. |
| `prices[].days[]` | `DecodeEntry(s).days`: the map `{ [day] = {...} }` as a list with the key in `day` | Scope items only. At most 400 days. |

An entry needs at least one of `last`, `raw`, `days`. One item and house appear once per request.
Times must lie between 2020-09-13 and now + 1 day.

How it is stored (schema: `web/migrations/0001_init.sql`):
- `prices`: one row per item and house: the latest `last` (an older one never replaces a newer one)
  and the cheapest tiers of the latest raw point.
- `points`: the raw points, kept 30 days.
- `daily`: one row per item, house and day, kept forever. Scope items: CraftWise's own aggregate
  (`src` 1). Items outside the scope: built from `last` (`src` 0): lowest and highest minimum seen
  that day, most units and listings; no typical, no counts. A CraftWise aggregate always replaces a
  `src` 0 row, never the other way round, and replaces an older aggregate only when it covers at
  least as many points (`n`).

Response: `{ "ok": true, "received": { "houses", "scans", "items", "prices", "points", "days" }, "itemsChanged", "rowsWritten" }`.

### `POST /api/private/upload`: private data

```json
{
  "v": 1,
  "snapshots": { "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner": { "t": 1794400000, "data": { "v": 1, "t": 1794400000, "char": { "name": "Velikopter" } } } },
  "auctions":  { "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner": { "t": 1794400000, "data": { "active": [], "sold": [] } } },
  "fishing":   { "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner": { "t": 1794400000, "data": { "days": 90, "catches": 12 } } },
  "ledger": [ { "t": 1794399000, "c": "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner", "k": "ahbuy", "i": 2589, "q": 20, "m": 2000, "w": "CAMWOW EU4 Realm 8 PvP|H", "n": "Linen Cloth" } ]
}
```

| Field | Source | Rules |
|---|---|---|
| `snapshots[<char key>]` | `CraftWiseDB.snapshots[<char key>]` (`docs/snapshot.md`) as `data`, its `t` as `t` | |
| `auctions[<char key>]` | `CraftWiseMarketDB.auctions.chars[<char key>]` as `data`; `t` = when the companion read the file | |
| `fishing[<char key>]` | the fishing summary (`snapshot.fishing` and `snapshot.fishingZones`) as `data` | |
| `ledger[]` | `CraftWiseMarketDB.ledger.entries[]` as they are (`t`, `c`, `k`, `i`, `q`, `m`, `w`, `n`) | At most 5,000 per request. |

- Character key `"<realm>-<name> <surname>"` (or `"<realm>-<name>"`, #77). At most 50 per section.
- Each document (`data`, an object) at most 450,000 bytes as JSON. A document replaces the stored
  one only when its `t` is newer. The characters list takes name, realm, faction, race, class and
  level from `snapshot.char`.
- Ledger entries are stored once: identical entries (same second, character, kind, item, quantity,
  money and place) are numbered in list order, so both of two identical vendor sales are kept and
  sending the log again adds nothing. Kept forever.

Response: `{ "ok": true, "received": { "snapshots", "auctions", "fishing", "ledger" }, "rowsWritten" }`.

## Public read API

`GET` only, `Cache-Control: public, max-age=60`. House keys in URLs are URL-encoded.

| Endpoint | Returns |
|---|---|
| `/api/houses` | `{ houses: [{ key, realm, kind, faction, label, lastScan, lastFullScan, lastFullScanItems }] }`, faction houses first |
| `/api/scans?limit=20&house=<key>` | `{ scans: [{ house, label, t, kind, items, lastOnly, source }] }`, newest first (limit 1..100, kept 90 days) |
| `/api/items?q=<text or item ID>&limit=20` | `{ query, items: [{ id, name, quality, icon, class, subclass, prices: [{ house, label, suffix, t, min, qty, listings, off, listed }] }] }`. Every word of `q` matches the start of a word of the name (`lot` finds Purple Lotus); "of", "the" and the like are ignored; at least 2 letters. |
| `/api/items/<id>?days=90&hours=48` | `{ id, item, markets: [...] }`, one market per house (and random suffix), see below |
| `/api/movers?house=<key>&limit=10` | `{ house, label, computedAt, up: [...], down: [...] }`, see below |

A market of `/api/items/<id>`:

```json
{
  "house": "CAMWOW EU4 Realm 8 PvP|H", "label": "Horde AH", "kind": "faction", "lastScan": 1794400000, "suffix": 0,
  "current": { "t": 1794400000, "min": 150, "qty": 300, "listings": 4, "off": null, "listed": true },
  "depth": { "t": 1794400000, "total": 300, "tiers": [{ "price": 150, "qty": 20 }, { "price": 160, "qty": 280 }] },
  "typical": { "status": "ok", "price": 100, "days": 5 },
  "days": [{ "day": 20764, "src": "craftwise", "lo": 95, "typ": 100, "hi": 120, "qtyMax": 100, "listMax": 5, "n": 2, "gone": null }],
  "raw": [{ "t": 1794400000, "total": 300, "listings": 4, "m": null, "tiers": [{ "price": 150, "qty": 20 }] }]
}
```

- `current`: the latest observation; `listed` false when a later full scan didn't list the item or
  the latest raw point had no units (`Market.lua` `M.Current`).
- `depth`: cheapest tiers of the latest raw point (scope items only, else `null`).
- `typical`: as `Market.lua` `M.Typical`: median of the daily typical of the last 7 days, rounded
  down; `too_little_history` below 3 such days, `no_data` without any data. Items outside the scope
  have no daily typical, so their typical is always `too_little_history`.
- `days`: the last `days` days (7..3650), `src` `craftwise` (the addon's aggregate) or `last` (built
  from observations, see above). `raw`: points of the last `hours` hours (0..720).

Top movers (`up` / `down`, at most 25 each, `limit` 1..25): items of one house whose current lowest
price is furthest above / below their typical price, as
`{ item, suffix, name, quality, icon, t, min, qty, listings, typical, typicalDays, change }` with
`change = (min - typical) / typical`. Only items with a typical price (at least 3 of the last 7 days
of CraftWise history) and a listed price seen in the last 2 days. `qty` and `listings` come with
every price: a jump at a thin market is no trend. Cached in D1 until the house's next scan or the
next UTC day.

## Private API (`/api/me/*`, Cloudflare Access)

Behind the Access app for `/me*` and `/api/me/*`. The Worker also checks the Access token
(`Cf-Access-Jwt-Assertion`: RS256 signature against
`https://velikopter.cloudflareaccess.com/cdn-cgi/access/certs`, issuer, audience `ACCESS_AUD`,
expiry), so the private data stays closed if the Access app is missing or misconfigured. `POST` and
`DELETE` need an `Origin` header of the site itself. `Cache-Control: private, no-store`.

| Endpoint | |
|---|---|
| `GET /api/me` | `{ email }` of the Access login |
| `GET /api/me/characters` | `{ characters: [{ key, realm, name, surname, faction, race, class, level, snapshotT, auctionsT, fishingT }] }` |
| `GET /api/me/characters/<char key>` | `{ key, snapshot, auctions, fishing }`, each `{ t, data }` or `null` |
| `GET /api/me/ledger?char=<key>&since=<t>&limit=500` | `{ entries: [{ char, t, kind, item, qty, money, place, name }] }`, newest first (limit 1..5000) |
| `GET /api/me/usage` | `{ day, rowsWritten, uploads, budget, dbBytes }`: today's D1 writes and the database size |
| `GET /api/me/tokens` | `{ tokens: [{ id, prefix, name, scopes, created, createdBy, lastUsed, revoked }] }` |
| `POST /api/me/tokens` | body `{ "name": "Companion PC", "scopes": ["public", "private"] }` (scopes default to both) → `201 { id, token, prefix, name, scopes, created }`. The token is shown only here. At most 20 active tokens. |
| `DELETE /api/me/tokens/<id>` | revokes it at once |

`GET /me` and `/me/*` serve the private page (placeholder until #98) after the same check.

## Budget (free plans) and retention

Limits that shape the design: Workers Free 10 ms CPU per request; D1 Free 100,000 rows written and
5 million rows read per day (every index entry counts as a row), 500 MB per database, 50 queries
per request (a batch counts as one), 100 bound parameters per statement.

- Bulk writes bind the rows as one JSON text and expand them in SQLite (`json_each`), so an upload
  is a few statements in one batch whatever its size, and the Worker's CPU time is parsing,
  checking and re-serializing the body.
- Price tables are `WITHOUT ROWID` without secondary indexes (one upsert = one row written), houses
  are integer IDs.
- **CPU** (`npm run bench`, Node on the dev container): a 470 KB body of scope items (7 days, 7 raw
  points of 8 tiers each) 4.5 to 6 ms median, 8 to 9 ms at the 90th percentile; 2,000 entries with
  `last` only (310 KB) about 4 ms. Hence the 500 KB body limit.
- **Rows written**, measured (`test/budget.test.ts`, 10,000 items at one house, 1,500 of them scope
  items, bodies of at most 450 KB):

  | Upload | Requests | Rows written | Database size after |
  |---|---|---|---|
  | First sync (item info, search words, 7 days of history, 6 raw points per scope item) | 13 | 81,996 | 2.9 MB |
  | Another full scan the same day (half the prices moved) | 14 | 18,767 | 3.0 MB |
  | The next day's first full scan | 14 | 27,517 | 3.4 MB |

  So a day holds about 3 to 4 full scans of 10,000 items. Uploads stop with `429 write_budget` when
  the next request could take the day over 90,000 rows (an upper bound per request: an upsert that
  changes a row is counted twice); the remaining 10,000 cover the cron job, token checks and the
  movers cache. The first sync of a full history may take two days.
- **Retention (decision):** raw points 30 days (as the issue proposed; they cost a write each to add
  and to delete), scan log 90 days, daily rows, prices, items and private data forever. Measured
  growth: about 0.46 MB per 10,000 items per house and day, so about 165 MB a year for one house
  scanned daily, 330 MB for two. `GET /api/me/usage` shows the database size; when it passes
  400 MB, thin out the `src` 0 daily rows older than a year (items outside the scope, where only the
  minimum is known):

  ```sql
  DELETE FROM daily WHERE src = 0 AND day < (strftime('%s', 'now') / 86400) - 365;
  ```

- **Reads:** a search reads the matching words plus 1 row per item and house; an item page about
  100 rows per house; top movers about 10 rows per item with history, once per scan and day.
- Daily cron (03:17 UTC) deletes expired raw points, scans, usage and cache rows.

## Development

```sh
cd web
npm ci            # npm 11 (Node 24); npm 10.9 fails to resolve vitest 4's peer dependencies
npm test          # vitest in the Workers runtime (Miniflare), D1 migrations applied per test file
npm run typecheck
npm run bench     # CPU time of an upload
npm run db:migrate:local && npm run dev   # local Worker with a local D1 on http://localhost:8787
```

Local private API: put `ACCESS_AUD=...` in `web/.dev.vars` (ignored by git); requests need a real
Access token, so the tests cover it with a test signing key.
