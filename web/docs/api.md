# wow.velikopter.com API (#95)

The Worker in `web/` serves the public price API, takes uploads from the companion app (#94) and
serves the private API behind Cloudflare Access. Money is copper, times are Unix seconds, `day` is
`floor(t / 86400)` (UTC days, the same day number as `CraftWise/Market.lua`). JSON everywhere.

Errors are `{ "error": "<code>", "message": "<text>" }` with the HTTP status:

| Status | `error` | When |
|---|---|---|
| 400 | `bad_json`, `bad_shape`, `bad_query` | `bad_shape` names the field: `items["2589"]["<house>"].last.min: expected a non-negative integer` |
| 401 | `unauthorized` | bearer token missing, malformed, unknown or revoked |
| 403 | `forbidden`, `access_denied`, `bad_origin` | token lacks the scope; no valid Access login; cross-site change on `/api/me/*` |
| 404 | `not_found` | |
| 405 / 415 | `method_not_allowed` / `unsupported_media_type` | uploads need `POST` and `Content-Type: application/json` |
| 413 | `too_large` | body over the limit: split it |
| 429 | `rate_limited`, `write_budget` | wait `Retry-After` seconds |
| 503 | `access_not_configured`, `access_keys` | `ACCESS_AUD` not set; Access keys unreachable |

## Uploads (companion app)

`Authorization: Bearer cw_...` with a token created on the private page (`/me`, see "Private API").
A token has the scopes `public` (`POST /api/upload`) and/or `private` (`POST /api/private/upload`).
Only the token's SHA-256 is stored.

Rules for the companion:
- **Body at most 500,000 bytes**, 2,000 item/house entries and 5,000 item IDs in `names` +
  `itemInfo`. Split larger uploads into several requests (by items); each request is stored on its
  own (one D1 transaction). `houses` goes into every request.
- **Re-sending is safe.** Every write is idempotent: the same body again changes nothing. A failed
  request can simply be retried.
- **Send what changed.** Keep the last uploaded packed string per item and house (the entry strings in
  `CraftWiseMarketDB.items` change whenever the addon records something) and send only entries whose
  string changed since the last successful upload. Unchanged entries cost upload time and CPU.
- **429:** wait `Retry-After` seconds. `rate_limited`: at most 30 requests a minute per token.
  `write_budget`: today's D1 write budget is used up, or above 80% of it a request carries item
  info, names, sell prices or class names (see "Budget"); resume after 00:00 UTC.
- **Prices before item info.** Above 80% of the budget a request with item info or class names is
  refused as a whole, prices in it too. Send scans and prices first and `names`, `itemInfo`,
  `classNames` and `subclassNames` in requests of their own after them, so a refusal holds back
  only those.
- **413:** split the body and retry.
- Never upload `CraftWiseMarketDB.auctionator` (#90: Auctionator mixes houses; the site shows no
  prices of unknown houses).
- Leave out what the addon doesn't have (or send `null`). Nothing is filled in on the server.

### `POST /api/upload`: public market data

The body is a subset of `CraftWiseMarketDB` as the companion's Go readers (#93,
`companion/savedvars.MarketDB` with the decoded `market.Entry` values) marshal it to JSON, plus `v`:
`houses`, `scans`, `items`, `names`, `itemInfo`, `classNames`, `subclassNames`. Other fields (`cut`, `auctionator`, `ledger`, ...)
are ignored on this endpoint.

```json
{
  "v": 1,
  "houses": {
    "CAMWOW EU4 Realm 8 PvP|H": { "realm": "CAMWOW EU4 Realm 8 PvP", "kind": "faction", "faction": "Horde", "label": "Horde AH" },
    "CAMWOW EU4 Realm 8 PvP|N:BootyBay": { "realm": "CAMWOW EU4 Realm 8 PvP", "kind": "neutral", "label": "Booty Bay" }
  },
  "scans": {
    "CAMWOW EU4 Realm 8 PvP|H": [ { "t": 1794400000, "kind": "full", "items": 1480, "lastOnly": 8520, "source": "auctionator" } ]
  },
  "names": { "2589": "Linen Cloth" },
  "itemInfo": { "2589": { "q": 1, "i": 132889, "c": 7, "s": 5, "t": 1794400000, "p": 13 } },
  "classNames": { "7": "Trade Goods" },
  "subclassNames": { "7": { "5": "Cloth", "9": "Herb" } },
  "items": {
    "2589": {
      "CAMWOW EU4 Realm 8 PvP|H": {
        "last": { "t": 1794400000, "min": 95, "qty": 400, "listings": 6 },
        "raw": [ { "t": 1794400000, "total": 400, "listings": 6, "m": 120, "tiers": [ { "price": 95, "qty": 10 }, { "price": 100, "qty": 40 } ] } ],
        "days": { "20768": { "lo": 90, "typ": 100, "hi": 140, "qtyMax": 500, "listMax": 7, "n": 4, "gone": 20 } }
      }
    },
    "15210:1017": {
      "CAMWOW EU4 Realm 8 PvP|N:BootyBay": { "last": { "t": 1794399400, "min": 25000, "qty": 1 } }
    }
  }
}
```

| Field | Source in the SavedVariables | Rules |
|---|---|---|
| `v` | | `1` |
| `houses` | `CraftWiseMarketDB.houses`: `realm`, `kind`, `faction`, `label` | Every house used in `scans` or `items` must be listed. Key `<realm>\|H`, `<realm>\|A` or `<realm>\|N:<Name>`; `realm` must match the key; faction houses carry `faction` (`H` = Horde, `A` = Alliance), neutral houses none. At most 20. |
| `scans` | `CraftWiseMarketDB.scans`: per house `t`, `kind`, `items`, `lastOnly`, `source` | `t` and `kind` (lower-case letters: `full`, `search`, `gear`) required. At most 200. Optional; drives "last scanned" per house. |
| `names` | `CraftWiseMarketDB.names` | Optional. Names as the client gave them. |
| `itemInfo` | `CraftWiseMarketDB.itemInfo` decoded (#92): `q` quality, `i` icon file ID, `c` class, `s` subclass, `t`, `p` vendor sell price per unit (#120, format 2; `0` = vendors don't buy it) | Optional. `t` is checked, not stored. `p` is missing in format 1 strings (older addon) and for items the client hasn't loaded yet. |
| `classNames` | `CraftWiseMarketDB.classNames` (#120): `{ "<classID>": name }`, the client's own (localized) names | Optional. IDs 0 to 65535, names 1 to 64 characters, no control characters. |
| `subclassNames` | `CraftWiseMarketDB.subclassNames` (#120): `{ "<classID>": { "<subclassID>": name } }` | Optional, as `classNames`; together at most 1,000 names per request. |
| `items[<item key>][<house key>]` | `CraftWiseMarketDB.items` decoded (`Market.lua` `DecodeEntry`) | Item key `"<itemID>"` or `"<itemID>:<suffixID>"`. At most 2,000 item/house entries per request. |
| … `.last` | `t`, `min`, `qty`, `listings`, `off` | `t`, `min`, `qty` required; `listings` (browse results have none) and `off` optional. |
| … `.raw[]` | `t`, `total`, `listings`, `m`, `tiers: [{ price, qty }]` | Scope items only. `t`, `total` required; at most 8 tiers, prices rising; at most 500 points. |
| … `.days` | `{ "<day>": { lo, typ, hi, qtyMax, listMax, n, gone } }` | Scope items only. At most 400 days. |

`names` and `itemInfo` together at most 5,000 item IDs per request. A field left out keeps the value
stored before; only items whose info changed are written (a sell price arriving for a known item is
such a change). A class or subclass name is written only when it differs from the stored one. An entry needs at least one of `last`,
`raw`, `days`. Times must lie between 2020-09-13 and now + 1 day.

How it is stored (schema: `web/migrations/`):
- `items`: one row per item: name, quality, icon, class, subclass and `sell_price` (#120,
  `0003_names_sell_price.sql`); `item_words` its search words. `item_classes` / `item_subclasses`: the
  client's class and subclass names, one row each.
- `prices`: one row per item and house: the latest `last` (an older one never replaces a newer one)
  and the cheapest tiers of the latest raw point.
- Random-suffix variants (`"<itemID>:<suffixID>"`) without raw points (#118, `0002_variants.sql`):
  packed per item, `variants` (one row per item and house, the latest `last` of every variant) and
  `variant_days` (one row per item, house and day, the `src` 0 day of every variant). A variant
  stays in `prices` / `daily` when its record has raw points or its stored `prices` row has a depth
  (a scope item). The read API merges both, so this is invisible to readers: per variant the newer
  `t` is current, a CraftWise aggregate wins a day, two `last` days are combined.
- `points`: the raw points, kept 30 days.
- `daily`: one row per item, house and day, kept forever. Scope items: CraftWise's own aggregate
  (`src` 1). Items outside the scope: built from `last` (`src` 0): lowest and highest minimum seen
  that day, most units and listings; no typical, no counts. A CraftWise aggregate always replaces a
  `src` 0 row, never the other way round, and replaces an older aggregate only when it covers at
  least as many points (`n`).

Response: `{ "ok": true, "received": { "houses", "scans", "items" (item IDs with names or info), "classNames" (class and subclass names), "prices" (item/house entries), "points", "days" }, "itemsChanged", "rowsWritten" }`.

The companion keeps what it sent (state file) and sends a class or subclass name only when it is new
or changed, and an item's name and info only when one of them changed (the read time `t` alone is no
change), so after the first upload names and sell prices cost no writes.

### `POST /api/private/upload`: private data

```json
{
  "v": 1,
  "snapshots": { "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner": { "t": 1794400000, "data": { "v": 1, "t": 1794400000, "char": { "name": "Velikopter" } } } },
  "auctions":  { "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner": { "t": 1794400000, "data": { "active": [], "sold": [] } } },
  "fishing":   { "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner": { "t": 1794400000, "data": { "days": 90, "catches": 12 } } },
  "ledger": [ { "t": 1794399000, "c": "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner", "k": "ahbuy", "i": 2589, "q": 20, "m": 2000, "w": "CAMWOW EU4 Realm 8 PvP|H", "n": "Linen Cloth" } ],
  "watch": [ { "i": 2589, "t": 1794399000 } ]
}
```

| Field | Source | Rules |
|---|---|---|
| `snapshots[<char key>]` | `CraftWiseDB.snapshots[<char key>]` (`docs/snapshot.md`) as `data`, its `t` as `t` | |
| `auctions[<char key>]` | `CraftWiseMarketDB.auctions.chars[<char key>]` as `data`; `t` = when the companion read the file | |
| `fishing[<char key>]` | the fishing summary (`snapshot.fishing` and `snapshot.fishingZones`) as `data` | |
| `ledger[]` | `CraftWiseMarketDB.ledger.entries[]` as they are (`t`, `c`, `k`, `i`, `q`, `m`, `w`, `n`, `l`) | `t`, `c`, `k` required. At most 5,000 per request. The link `l` is checked, not stored. |
| `watch[]` | `CraftWiseDB.watch` (#165, the addon's item watch list, `{ [itemID] = Unix time it was watched }`) as `{ "i": itemID, "t": time }` | The **whole list**: it replaces the stored one. Absent or `null` = leave the stored list alone; `[]` = the player emptied it. `i` an item ID of 1 or more, `t` a time (as everywhere), at most 1,000, a repeated `i` counts once. |

- Character key `"<realm>-<name> <surname>"` (or `"<realm>-<name>"`, #77). At most 50 per section.
- Each document (`data`, an object) at most 450,000 bytes as JSON. A document replaces the stored
  one only when its `t` is newer. The characters list takes name, realm, faction, race, class and
  level from `snapshot.char`.
- Ledger entries are stored once: identical entries (same second, character, kind, item, quantity,
  money and place) are numbered in list order, so both of two identical vendor sales are kept and
  sending the log again adds nothing. Kept forever.

Watch list (#165): the companion sends it when it differs from the list it sent last (a hash in its state
file), in the same request as the other private data. The Worker stores it in `watch` (one row per item,
`0004_watch.sql`; one list for the site's owner, like the characters and the ledger): items no longer in the
upload are deleted, changed times updated, unchanged rows aren't written, so re-sending costs no writes.
It goes one way only, addon to site; the site never writes it back (the companion only reads SavedVariables).

Response: `{ "ok": true, "received": { "snapshots", "auctions", "fishing", "ledger", "watch" }, "rowsWritten" }`.

## Public read API

`GET` only, `Cache-Control: public, max-age=60`. House keys in URLs are URL-encoded.

| Endpoint | Returns |
|---|---|
| `/api/houses` | `{ houses: [{ key, realm, kind, faction, label, lastScan, lastFullScan, lastFullScanItems }] }`, faction houses first |
| `/api/scans?limit=20&house=<key>` | `{ scans: [{ house, label, t, kind, items, lastOnly, source }] }`, newest first (limit 1..100, kept 90 days) |
| `/api/items?q=<text or item ID>&limit=20` | `{ query, items: [{ id, name, quality, icon, class, subclass, className, subclassName, sellPrice, prices: [{ house, label, suffix, t, min, qty, listings, off, listed }] }] }`. Every word of `q` matches the start of a word of the name (`lot` finds Purple Lotus); "of", "the" and the like are ignored; at least 2 letters. |
| `/api/items/<id>?days=90&hours=48` | `{ id, item, markets: [...] }`, one market per house (and random suffix), see below; `item` as in `/api/items` without `prices` |
| `/api/movers?house=<key>&limit=10` | `{ house, label, computedAt, up: [...], down: [...] }`, see below |
| `/api/categories?house=<key>` | `{ house, label, lastScan, computedAt, categories: [{ class, subclass, className, subclassName, items }] }`: items priced at the house (no random suffix) per item class and subclass; `class` and `subclass` are `null` for items without item info yet |
| `/api/browse?house=<key>&class=<id>[&subclass=<id>]`, `...&q=<text>`, `...&ids=<id>,<id>` | `{ house, label, lastScan, today, more, items: [...] }`, the site's item list (#97), see below |

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

`/api/browse` takes exactly one of `class` (an item class ID, or `none` for items without info; optionally
`subclass`), `q` (as `/api/items`, at most 50 items) or `ids` (at most 100 item IDs, the site's favourites: the browser's own plus, behind Access, the addon's watch list from `/api/me/watch`, #165; the site marks the addon's ones "Watched in the addon" and can't remove them). Each
item: `{ id, name, quality, icon, class, subclass, className, subclassName, sellPrice, current, typical, days }` with `current` and `typical` as on
`/api/items/<id>` (house of the request, suffix 0; `current` `null` when the house has no price) and `days` the
daily rows of the last 9 days (`{ day, src, lo, typ, hi, qtyMax }`), enough for a 24 h and a 7 day change and a
7 day sparkline. At most 500 items (`more: true` beyond). The class index behind `/api/categories` and
`class=` reads one row per priced item and its info, so it is cached in D1 like the top movers (until the house's
next scan or the next UTC day); a browse then reads about 10 rows per item.

Names and sell prices (#120): `className` / `subclassName` are the client's own names as the addon
recorded them (`C_Item.GetItemClassInfo` / `GetItemSubClassInfo`), `null` where none was uploaded yet (the site
then shows Blizzard's enum identifier from `site/lib/enums.ts`, or "Subclass N"). `sellPrice` is what a vendor pays
for one unit (`C_Item.GetItemInfo`'s sellPrice), `0` when vendors don't buy the item, `null` when not known yet. The
names are read on every request (a few dozen rows), not cached with the class index.

### Recipe data and crafting profit (#143)

`GET /data/recipes.json` is a static asset (no Worker, no D1): the addon's bundled recipe data, written by
`tools/gen_site_recipes.lua` from `CraftWise/Data/Recipes.lua`, `Sources.lua` and `Vendor.lua` (format in the tool's
header; each file's source and licence header is carried in `sources`). The list page loads it when a list holds
recipe items (item class 9, or an item `teach` knows) and the item page always; both then price the products and
reagents through `/api/browse?ids=` (100 IDs per request, at most three at a time, each item fetched once per page
view). The maths is `site/lib/recipes.ts` (tested in `test/recipes.test.ts`):

- Reagent: per unit the Horde AH's typical price, else its lowest listing while listed, or the bundled vendor buy
  price when that is cheaper (or the only one).
- Product: one unit on the Horde AH (typical, else lowest) after the 5% cut, or what a vendor pays when that is
  more (`sellPrice`, else the bundled sell price), times the output quantity (mean yield), rounded down. Without a
  Horde AH price the product has no value ("no AH price", sorted with the unknowns), even when a vendor buys it: the
  breakdown shows the vendor price only as a floor ("a vendor pays X: at worst a loss of Y").
- Thin market: a price from the lowest listing (no typical price yet) shows the units and listings behind it in the
  breakdown; when the product's price rests on 1 or 2 listings or fewer than 5 units the profit carries a "thin"
  marker. The maths is the same.
- Profit per craft = product - reagents; unknown when any reagent or the product has no price (nothing is filled
  in); none for spells that make no item (enchants). Pays back = the recipe's AH price (typical, else lowest) /
  profit, rounded up, only when the profit is positive.
- Recipe items missing from `Sources.lua` (no usable required skill in the client, see its header) show "no data".

#### Crafts view and vendor check (#185)

`/crafts` (static page `public/crafts/index.html`, script `site/crafts.ts`, logic `site/lib/crafts.ts`) lists every
spell of `recipes.json` that makes an item, with the product, profession, reagent cost, AH sale, vendor sale, profit
and vendor profit. Same definitions as the addon (`vendorCheck` in `site/lib/recipes.ts`):

- Vendor sale = the product's vendor sell price (`sellPrice` from the API, else the bundled `sell`) x output
  quantity, rounded down; no price (vendors don't buy it, or not known) gives no value.
- Vendor profit = vendor sale - reagent cost (each reagent where it is cheaper, AH or vendor). Needs no AH price for
  the product; unknown when a reagent has no price.
- Loop: every reagent has a bundled vendor buy price and vendor sale - cost at vendor prices > 0. Needs no AH price.

Filters: profession, product name, "Profit when sold to a vendor" (vendor profit > 0), "Loops only" and, when
`/api/me/characters` answers (Access login), "My crafts": the recipe spell IDs in `professions[].known` of the
characters' snapshots (docs/snapshot.md). Only the prices of the filtered crafts are fetched (`/api/browse?ids=`).
URL: `?prof=<skill line>&q=&vendor=1&loops=1&mine=1&sort=&dir=&p=`.

A Recipe list of 158 items needs about 300 more item IDs, so 3 to 4 browse requests (about 10 rows read per item).

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
| `GET /api/me/watch` | `{ watch: [{ item, added }] }`, the addon's watch list (#165), newest first (`added` = when it was watched). Empty before the first upload or when nothing is watched. |
| `GET /api/me/ledger?char=<key>&since=<t>&limit=500` | `{ entries: [{ char, t, kind, item, qty, money, place, name }] }`, newest first (limit 1..5000) |
| `GET /api/me/usage` | `{ day, rowsWritten, uploads, budget, softBudget, dbBytes }`: today's D1 writes against the budget (`WRITE_BUDGET`) and its soft limit (80%), and the database size |
| `GET /api/me/tokens` | `{ tokens: [{ id, prefix, name, scopes, created, createdBy, lastUsed, revoked }] }` |
| `POST /api/me/tokens` | body `{ "name": "Companion PC", "scopes": ["public", "private"] }` (scopes default to both) → `201 { id, token, prefix, name, scopes, created }`. The token is shown only here. At most 20 active tokens. |
| `DELETE /api/me/tokens/<id>` | revokes it at once |

`GET /me` (also `/me/` and `/me/index.html`) serves the private page (#98, `public/me/index.html` with
`site/me.ts`) after the same check, with the pages' security headers and `Cache-Control: private, no-store`;
`/me/<page>` (also with `/` or `/index.html`) serves `public/me/<page>/index.html` the same way when that
page exists, e.g. `/me/crates` (#129, Waylaid crates and Merchant's Favor, `site/crates.ts`) and `/me/fishing`
(#128, where to fish, `site/fishing.ts`); other paths under `/me/` answer 404. The pages hold no data: they
read everything above from `/api/me/*` and item names, qualities and prices from `/api/browse?ids=`.

The fishing page works in the browser (`site/lib/fishing.ts`, tested in `test/fishing.test.ts`) from the
character's fishing document and the Horde AH's prices; the Worker only serves both:
- Values a catch again from the snapshot's item lists (docs/snapshot.md "Item lists"): per item the Horde AH's
  typical price, else its lowest listing while listed, after the 5% cut, unless the vendor price in the list is
  more (as `ns.GetSellValue`); containers by the contents value in the list; an item without a Horde AH price
  today at the value the snapshot used. Without item lists (older addon or companion) it shows the snapshot's
  figures.
- Measured per hour = own timed catches per hour in that row (`timed`, `minutes`) x the value per catch now,
  only from `fishingZones.ownMin` timed catches on (default 50); below that "too few timed".
- Expected per hour (#136, the default ranking) = the value per catch now x the character's catch rate: timed
  catches per hour over the whole log from `fishing.waters` (an older upload without it: the spots, when
  `moreSpots` is missing), per water type from `ownMin` timed catches on, else the overall rate. A zone takes
  the water mix of its own catches (`compare[].waters`, else open water when the log has no catch of unknown
  water), mixed by time per catch (n / Σ nᵢ / rateᵢ); a zone without own catches takes the overall rate. Below
  `ownMin` timed catches overall there is no rate and the ranking falls back to value per catch.
- Own catches against the reference (`fishingZones.compare`): each item's share of own catches (hits / n) with
  its 95% Wilson interval, the reference's share (count / loots), the difference, marked when the reference's
  share lies outside the interval; value per catch from both, priced the same way. Own data is the primary
  number from `ownMin` catches on (or without a reference), the reference otherwise; the other is shown as
  comparison. Fewer than `ownMin` catches is a small sample: marked, and ranked after the others.

## Budget (free plans) and retention

Limits that shape the design: Workers Free 10 ms CPU per request; D1 Free 100,000 rows written and
5 million rows read per day (every index entry counts as a row), 500 MB per database, 50 queries
per request (a batch counts as one), 100 bound parameters per statement. The design still fits
Free, although the account is on Workers Paid since 2026-11-12 (#145).

**Write budget (#145).** The Worker var `WRITE_BUDGET` (`wrangler.jsonc` `vars`) caps the rows
CraftWise writes a day; a missing or invalid value (not a whole number from 1 to 1,000,000) means
1,000,000. `GET /api/me/usage` reports it.

| Plan | D1 writes | `WRITE_BUDGET` |
|---|---|---|
| Workers Paid (current) | no daily limit; 50 million rows a month included, then $1 per million | `1000000` (default): effectively no limit, at most 30 million a month, so it never costs extra |
| Workers Free | 100,000 rows a day for the whole Cloudflare **account**, shared by every D1 database on it: Hivemind uses D1 on the same account | `30000`, leaving 70,000 for the others |

On Free, when the account reaches 100,000, every D1 database on it (Hivemind's too) refuses writes
until 00:00 UTC; on 2026-11-12 CraftWise's old fixed cap of 90,000 did exactly that.

Two levels, both `429 write_budget` with `Retry-After` until 00:00 UTC:
- **Soft limit, 80% of the budget:** a public upload that would write item info, names, sell prices
  or search words (only items whose stored values change count; unchanged ones write nothing and pass)
  or that carries class names is refused when today's rows plus its estimate would pass 80%. Price
  data (scans, prices, points, daily rows) and all private data (snapshots, auctions, fishing,
  ledger) still go through. This spreads big one-time uploads (#120's ~18,000 sell prices) over days.
- **Hard limit, the budget:** every upload is refused when the request could take the day over it.

- Bulk writes bind the rows as one JSON text and expand them in SQLite (`json_each`), so an upload
  is a few statements in one batch whatever its size, and the Worker's CPU time is parsing,
  checking and re-serializing the body.
- Price tables are `WITHOUT ROWID` without secondary indexes (one upsert = one row written), houses
  are integer IDs. Upserts carry a `WHERE` that skips rows that would not change (D1 counts an
  updated row even when its values stay the same, measured locally), so re-sending costs nothing.
- Random-suffix variants are packed per item (see "How it is stored"): a full browse is mostly gear
  with a random suffix (the first real upload: 16,465 of 21,117 entries, over 1,333 items), and
  packing them turns one `prices` and one `daily` row per variant into about one of each per item.
  The merge runs in SQLite (`json_each`), the Worker only groups the variants of a request.
- **CPU** (`npm run bench`, Node on the dev container, 101 runs): a 475 KB body of scope items
  (7 days, 7 raw points of 8 tiers each) 4 to 6 ms median, 6 to 9 ms at the 90th percentile; 2,000
  entries with `last` only (324 KB) 4.5 to 5 ms median, 7 to 8 ms at the 90th; 2,000 random-suffix
  variants (183 KB) 4.5 to 5.5 ms median. Hence the 500 KB body limit. A cold isolate (first
  request after a deploy or idle time) is slower.
- **Rows written** (#118), measured on Veli's first real upload (a dry-run dump of the companion:
  21,117 entries at one house, 4,652 without a suffix of which 155 scope items, 16,465 random-suffix
  variants of 1,333 items; uploaded locally, D1's `meta.rows_written` per statement; the later rows
  replay the same entries with newer times, a third of them with a new price):

  | Upload | Requests | Before #118 | Now |
  |---|---|---|---|
  | First upload (5,651 item infos, 14,463 search words, prices, history) | 14 | 63,451 | 33,212 |
  | A /reload while browsing: 1,000 entries, a third changed | 2 to 11 | 1,321 to 1,427 | 523 to 1,372 |
  | A second full browse the same day | 11 | 27,490 | 8,520 |
  | The next day's first full browse | 11 | 42,251 | 12,014 |
  | Private: snapshot, auctions, fishing, the ledger | 1 | 823 | 823 |

  So a day with a full browse, a second one and half a dozen reloads in between takes about
  24,000 to 29,000 rows (before: about 78,000). The first upload of a fresh install is the largest
  (item info and search words are written once). `test/budget.test.ts` checks the same shape with
  invented data (5,000 items, 500 of them scope items, plus 15,000 variants of 1,250 items):
  42,131 / 11,295 / 15,055 rows for the first upload, a second browse and the next day's (before
  #118: 69,611 / 31,275 / 42,525).

  Class names and sell prices (#120, `test/names-budget.test.ts`, invented data: 18,000 items already
  stored with names and info, 18 classes with 10 subclasses each, 11 requests as the companion splits
  them): the first upload after the update writes **18,209 rows** (one `items` row per item for its sell
  price, 198 name rows, 11 rate-limit rows), once; the same upload again 11 (the rate-limit rows only).
  On a fresh install the sell price comes with the item's first info and costs nothing extra (57,570
  rows without, 57,768 with, the difference being the 198 names). After that a sell price costs a write
  only when the client reports a new one, a name only when it changes (another client language).

  What a row costs: an insert or an update of a `prices`, `points`, `variants` or `variant_days`
  row and of a `daily` row built from `last` 1 (no secondary index); a CraftWise daily aggregate 2
  (the row and `daily_typ`, which the top movers need); an item 1 plus one per search word (2.6
  words per item on average); a ledger entry 2 (the row and `ledger_by_char`); a house 2 (`key` is
  unique); a class or subclass name 1. The two indexes stay: without them the top movers and the ledger page would read every
  row of a house's history or of the ledger. Uploads stop with `429 write_budget` when the next
  request could take the day over the budget (`WRITE_BUDGET`, see above; an upper bound per request:
  every upserted row is counted twice, a packed row too, so a variant never counts more than the
  companion's estimate of 4 rows per `last`-only entry). The cron job, token checks and the movers
  cache write outside the check, so on Free leave room below the account's 100,000.
- **Retention (decision):** raw points 30 days (as the issue proposed; they cost a write each to add
  and to delete), scan log 90 days, daily rows, prices, items and private data forever. Measured
  growth: about 0.43 MB per 10,000 items per house and day, so about 155 MB a year for one house
  scanned daily, 310 MB for two. With random-suffix variants (`test/budget.test.ts`, 20,000 entries)
  about 0.56 MB per house and day, about 200 MB a year for one house browsed daily.
  `GET /api/me/usage` shows the database size; when it passes 400 MB, thin out the `src` 0 daily
  rows older than a year (items outside the scope, where only the minimum is known):

  ```sql
  DELETE FROM daily WHERE src = 0 AND day < (strftime('%s', 'now') / 86400) - 365;
  DELETE FROM variant_days WHERE day < (strftime('%s', 'now') / 86400) - 365;
  ```

- **Reads:** a search reads the matching words plus 1 row per item and house (and variant), plus its
  classes' names; an
  item page about 100 rows per house (plus one `variant_days` row per day with variants); top movers about 10 rows per item with history, once per scan and day; the
  category index 2 rows per priced item, once per scan and day, plus the names of its classes (a few dozen
  rows) per request; a browse about 10 rows per item listed, plus its classes' names.
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
