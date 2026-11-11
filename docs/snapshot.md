# Character snapshot (#63)

A per-character state snapshot that a Claude session reads from disk to answer questions about the character (quests, gear, professions, money). CraftWise doesn't talk to Claude; it only writes this table.

## Where it is
- File: `WTF/Account/<account>/SavedVariables/CraftWise.lua` (account-wide, so a session that can read the account SavedVariables folder sees every character).
- Key: `CraftWiseDB.snapshots["<realm>-<name> <surname>"]` (#77; Forever characters have a surname), e.g. `CraftWiseDB.snapshots["CAMWOW EU4 Realm 8 PvP-Velikopter Tanner"]`; `"<realm>-<name>"` for a character without a surname. One entry per character, overwritten each time; no history.
- Before #77 the key had no surname, so characters with the same first name shared one entry. At login such an old entry moves to the current character only if its `char.class` and `char.race` match; otherwise it stays under the old key with `legacy = true` (its owner is unknown) and CraftWise prints once what it could not assign. The ledger and the fishing log move with it.
- Written by `/craftwise snapshot` (prints "snapshot saved, /reload to write it to disk") and automatically on `PLAYER_LOGOUT` (logout, `/reload`, quit).
- **The file is only current after `/reload`, logout or quit.** The game writes SavedVariables to disk only then; `/craftwise snapshot` alone updates the table in memory. Check `t` against the current time before trusting it.

## Rules
- Only data the client gives about this character. No chat, whispers, other players' names, item tooltips or estimates. A value the client doesn't give is missing (nil), never filled in.
- Reading never changes the UI: quest log and reputation headers are not expanded, collapsed or selected. The client does not list rows under collapsed headers, so those quests and factions are missing; the headers are named in `collapsedHeaders`.
- Every section is read on its own. A section whose API the client lacks is missing and named in `skipped` with the reason; a section that raised an error is missing and named in `errors`.

## Fields
Times (`t`, `scanned`, `since`) are Unix seconds (`time()`). Money is in copper (1g = 10000).

| Field | Meaning |
|---|---|
| `v` | Format version, currently `1`. |
| `t` | When the snapshot was taken. |
| `skipped` | `{ [section] = reason }` for sections not in this snapshot (API missing, or e.g. `pet = "no hunter pet out"`). Missing when nothing was skipped. |
| `errors` | `{ [section] = error text }` for sections that failed. Missing when none failed. |

### `char`
| Field | Meaning |
|---|---|
| `name`, `surname`, `realm` | First name, Forever surname (missing for a character without one) and realm. |
| `faction` | `"Horde"` / `"Alliance"` (`UnitFactionGroup`). |
| `race`, `class` | Localized race and class (`UnitRace`, `UnitClass`). |
| `level` | Character level. |
| `xp`, `xpMax` | XP in the current level and XP needed for the next (`UnitXP`, `UnitXPMax`). |
| `rested` | Rested XP bonus pool (`GetXPExhaustion`); `0` = no rested XP. |
| `money` | Money carried, copper. |
| `guild` | Guild name; `false` = not in a guild; missing = in a guild but the client hasn't sent its name yet. |

### `location`
| Field | Meaning |
|---|---|
| `zone`, `subzone` | Zone and subzone text (`GetRealZoneText`, `GetSubZoneText`); `subzone = ""` where the client names no subzone (#78). |
| `minimapZone` | The text over the minimap (`GetMinimapZoneText`, as Blizzard's Minimap_Update shows it): the subzone, else the zone. |
| `mapID`, `map` | UI map the player is on (`C_Map.GetBestMapForUnit`) and its name. |
| `x`, `y` | Position on that map, 0..1 from the top left, 4 decimals (multiply by 100 for the usual map coordinates). Missing where the client gives no position (instances). |
| `resting` | In a city or inn (`IsResting`). |

### `equipment`
`items` is a list in paper-doll order, one entry per worn item; `empty` lists the slot names with nothing worn.

| Field | Meaning |
|---|---|
| `slot` | Head, Neck, Shoulder, Back, Chest, Shirt, Tabard, Wrist, Hands, Waist, Legs, Feet, Ring 1, Ring 2, Trinket 1, Trinket 2, Main hand, Off hand, Ranged. A slot the client doesn't have is left out. |
| `id`, `link` | Item ID and the item link (includes enchant/suffix). |
| `ilvl` | Item level. |
| `armor` | Armour from the item's stats; `0` = the item has none. Missing when the client hadn't loaded the item's stats. |
| `stats` | Main stats as text, the same as the Upgrades view (#16): `"+5 AGI +4 STA"` (STR, AGI, INT, SPI, STA). Missing when the item has none of them or its stats weren't loaded. |
| `dur`, `durMax` | Durability now / maximum. Missing for items without durability. |

### `professions`
A list, primary professions first. Built from the profession cache and the client's profession list (`GetProfessions`/`GetProfessionInfo`, read without opening anything), so gathering professions and Fishing appear without a window. Recipes are cached whenever a profession window is opened; skill, max skill, name and icon of every profession are refreshed from the client's list at login and whenever the client's skill lines change (#65), so a new cap (Expert learned) or a Fishing skill-up shows without opening anything.

| Field | Meaning |
|---|---|
| `name` | Profession name. |
| `kind` | `"primary"` or `"secondary"` (Cooking, First Aid, Fishing). |
| `skill`, `max` | Skill and current maximum (from the client's list when it has the profession, else from the cache). |
| `line` | Parent skill line ID (e.g. 165 Leatherworking). |
| `recipesKnown` | Learned recipes in the cache. Missing when `cached = false`. |
| `scanned` | When the recipe cache was last filled from the profession window. |
| `cached` | `false` when no profession window has been read for it (Fishing, gathering professions, or a window never opened): skill and max are known, recipes are not. Missing otherwise. |

### `quests`
| Field | Meaning |
|---|---|
| `list` | One entry per quest the quest log lists (see below). |
| `inLog` | Quests the client says are in the log. |
| `read` | Quests in `list`. Lower than `inLog` when headers are collapsed (their quests aren't listed) or the client counts hidden quests. |
| `collapsedHeaders` | Zone headers that were collapsed: their quests are missing from `list`. Expand them in the quest log and snapshot again to include them. |
| `hidden` | Hidden quests skipped. |

Per quest: `id` (quest ID), `title`, `level`, `zone` (the header it sits under), `group` (suggested group size, missing for solo quests), `complete` (ready to turn in), `failed`, `objectives` = list of `{ text, have, need, done }` (`text` as the quest log shows it, `have`/`need` the counts, `done` finished).

### `reputations`
| Field | Meaning |
|---|---|
| `list` | One entry per faction the reputation list shows (headers that carry their own reputation included). |
| `collapsedHeaders` | Collapsed headers; their factions are missing from `list`. |

Per faction: `id` (faction ID), `name`, `header` (the header above it), `reaction` (1 Hated .. 8 Exalted), `standing` (the client's label for it, e.g. "Honored"), `value` (raw reputation), `min` / `max` (raw values where this standing starts and the next one begins; progress = `value - min` of `max - min`), `atWar` (true when at war, else missing).

Also read by the merchant lookup (#75): for a character that never opened a merchant, `/craftwise where` and the "Sold by" tooltip line show the price another character saw at the same standing with that merchant's faction, marked "seen at <standing>". A faction missing from `list` (collapsed header, no snapshot yet) gives no such line. The character logged in uses its live standing instead; a snapshot marked `legacy` (old key without surname, #77) is not used.

### `pet`
Only while a hunter pet is summoned (dismissed, dead or stabled: missing, `skipped.pet` says why).

| Field | Meaning |
|---|---|
| `name`, `level`, `family` | Pet name, level, creature family (e.g. "Wolf"). |
| `happiness`, `happinessText` | `C_PetInfo.GetPetHappiness`: 1 unhappy, 2 content, 3 happy. |
| `loyalty` | Loyalty text as the client gives it (`C_PetInfo.GetPetLoyalty`). |

### `holdings`
What CraftWise's holdings count (#49) sees. Item counts are `{ [itemID] = count }`.

| Field | Meaning |
|---|---|
| `bags` | Backpack, bags and reagent bag, read at snapshot time. |
| `bank` | `{ t, items }`: character bank as last seen while the bank was open (`t` = when). Missing until the bank was opened once. |
| `mail` | `{ t, mails, items }`: mailbox attachments as last seen (`mails` = number of mails). Missing until the mailbox was opened once. |
| `names` | `{ [itemID] = name }` for the items above whose name the client had cached. |
| `notCounted` | Places not in the counts (bank or mail never seen, account bank not read). |

### `ledger`
Totals from the purchase and sale log (#46), no individual entries: `today` and `reset` (since the last `/craftwise ledger reset`), each `{ since, startMoney, money, change, spent, received, net, other }`. `spent`/`received`/`net` are logged AH and vendor trades; `other` is the money change they don't explain (loot, quests, repairs, fees, AH sales by mail). `startMoney`/`change`/`other` are missing when the start money wasn't seen.

### `flightPaths`
Known flight paths (#68), per character. Recorded when a flight master's map opens (`TAXIMAP_OPENED`): the nodes the flight master lists (`C_TaxiMap.GetAllTaxiNodes` on the taxi map the client opened, `GetTaxiMapID`). Each opening overwrites that map's entry; other maps stay as last seen, so `t` says how current each one is. Missing (`skipped.flightPaths = "no flight master map opened yet"`) until a flight master was used once with this version.

`maps` is a list sorted by map ID, one entry per taxi map (continent):

| Field | Meaning |
|---|---|
| `mapID`, `map` | Taxi map ID (e.g. 1414 Kalimdor) and its name (`C_Map.GetMapInfo`). |
| `t` | When that flight master map was last opened. |
| `nodes` | Flight points listed there, sorted by name (see below). |

Per node:

| Field | Meaning |
|---|---|
| `id` | Taxi node ID (`nodeID`). |
| `name` | Name as the flight master shows it, e.g. `"Crossroads, The Barrens"`. |
| `x`, `y` | Position on that taxi map, 0..1 from the top left, 4 decimals. |
| `state` | From where it was read: `"current"` (this flight master), `"reachable"` (a route exists), `"unreachable"` (listed, no route from there). |
| `current` | `true` for the flight master the map was opened at; missing otherwise. |
| `known` | Discovered flag from the map's own node list (`C_TaxiMap.GetTaxiNodesForMap`, `isUndiscovered`): `true` = discovered. Missing when that list didn't have the node. |
| `transition` | `true` for map-layer transition points (Blizzard's flight map shows them only on other map layers); missing otherwise. |

### `fishing`
Fishing log ranking (#69, #86), this character, last 90 days: `{ days, catches, containersOpened, sessionGapMinutes, findFish, spots, moreSpots, pools, morePools }`. Values are copper. The full tables are in `/craftwise fishing`; raw catches are in `CraftWiseDB.fishing[<character key>]` (see `CraftWise/Fishing.lua` and `CraftWise/FishingTables.lua`).

| Field | Meaning |
|---|---|
| `spots` | The best 8 rows of zone, subzone and water type, ranked by `perHour` (rows with timed catches first), then `perCatch`. `moreSpots` = rows left out. |
| spot `zone`, `sub` | Zone and subzone (`""` = none). |
| spot `water` | `"open"` (open water), `"pool"` (one pool object, `obj` = its GameObject ID, `pool` = the name the client showed, missing if never shown), or `"?"` (water type not known yet; `obj`/`pool` as far as known). How the type is worked out: `CraftWise/Fishing.lua`. |
| spot `n` | Catches (one per loot window). Small numbers are small samples: no drop rates. |
| spot `perCatch` | Value per catch: each item at its best sell value (AH after cut at the profit house and basis, else vendor incl. remembered sell prices; containers by their logged contents). `unpriced` = item units without any price, left out (missing when 0). |
| spot `perHour`, `timed`, `minutes` | Value per hour over the `timed` catches: catches less than `sessionGapMinutes` apart are one session, a catch's time is the time since the previous catch of its session, a session's first catch is untimed. `minutes` = their time. Missing without timed catches. |
| spot `top` | Up to 3 items, most first: `"<itemID> <name> <count>/<all items caught in this row>"`, separated by `; `. |
| `pools` | Up to 5 pool objects with the most ended visits (`morePools` = rest): `{ obj, name, visits, perVisit = "<min>-<max>, avg <avg>", going, seen, notFished }`. A visit = catches from one pool spawn; it has ended once a later catch came from elsewhere or the session gap passed (`going` = visits not ended). Its catch count is what the pool gave until it vanished **or the player left** (the client doesn't tell the two apart). `seen` = sightings without fishing (tooltip, interact target), `notFished` = sighted spawns never fished. |
| `findFish` | `{ spellID = 43308, known, tracking }`: whether this character knows Find Fish and whether its tracking is on, missing when the client didn't say. |

### `fishingZones`
Fishing zones by value per catch (#88), the same ranking as the Fishing tab: `{ reference, ownMin, zones, more }`. `reference` = whether the local reference addon `CraftWise_FishingRef` is loaded (see `docs/fishing-reference.md`). Values are copper.

| Field | Meaning |
|---|---|
| `zones` | Up to 5 zones, best value per catch first (`more` = zones left out): `{ zone, source, n, perCatch, perCatchHigh, perHour, unpriced }`. |
| zone `source`, `n` | `"own"`: this character's catches, `n` = catches (used from `ownMin` catches on, or when the reference lacks the zone). `"ref"`: the local reference, `n` = fishing loots it recorded in the zone. |
| zone `perCatch`, `perCatchHigh` | Value per catch: chance x units x unit value, summed. Unit value: containers by the mean of their contents (own openings, else the reference's contents table), else AH after cut at the profit house and basis, else vendor. The reference gives stacks as min-max, so `perCatch` uses the minimum and `perCatchHigh` the maximum (missing when equal). `unpriced` = items without any price, left out (missing when 0). |
| zone `perHour` | Own catches per hour in this zone (timed catches, see `fishing`) x `perCatch`. Missing without own timed catches there. |

### `auctions`
Auction tracker (#81), this character: `{ active, sold, returning, uncertain, expectedTotal, expectedMissing, ownedListAt, ownedListHouse }`. Each list holds rows (fields below). Money is copper.

| Field | Meaning |
|---|---|
| `active` | Listed auctions. |
| `sold` | Sold, money not collected from the mailbox yet. |
| `expectedTotal` | Sum of `expected` over `sold`: gold on its way. Sales without an expected payout are left out and counted in `expectedMissing`. |
| `returning` | Expired or cancelled: the item is on its way back by mail. |
| `uncertain` | Missing from the owned list before its expiry with no message seen: sold or cancelled, which is unknown. |
| `ownedListAt`, `ownedListHouse` | When the client's owned-auctions list (AH "Auctions" tab) was last read, and at which house. CraftWise never asks for that list itself. |

Row fields:

| Field | Meaning |
|---|---|
| `id` | Auction ID; missing until the client named it. |
| `item`, `name`, `q` | Item ID, name (from the link, so random suffixes are kept), units in this auction. |
| `house`, `houseLabel` | House key and label (#26), e.g. `"<realm>|H"`, `"Horde AH"`. Missing when the house couldn't be told (non-English client). |
| `status`, `statusText` | `active` "listed", `sold` "sold, awaiting mail", `gone` "sold or cancelled (uncertain)", `expired` / `cancelled` "... returned via mail". |
| `posted`, `expires`, `durText` | Post time, expiry time (from the owned list's time left, else the duration's hours on an English client), the duration as the client names it. Missing for auctions listed before tracking (`untracked = true`). |
| `overdue` | `true` when a listed auction's time is up but no outcome was seen yet. |
| `unitBuyout`, `unitBid`, `deposit` | Prices per unit as posted, and the deposit the client calculated for that post. |
| `soldAt`, `soldVia` | When the sale was seen and how: `"message"`, `"owned list"`, `"owned list (quantity dropped)"`. |
| `unitsSold` | `"some or all"`: a sold message for a commodity auction doesn't say how many units sold. |
| `expected`, `expectedNote`, `salePrice` | What the sale mail should bring: sale price minus the house cut, only where the cut is confirmed or measured (`expectedNote`, e.g. `"5% cut (confirmed)"`). Missing with the reason in `expectedNote`: `"cut unverified"` (neutral houses), `"bid and buyout: sale price unknown"`, `"units sold unknown"`, `"price not recorded (listed before tracking)"`. The deposit, if the mail refunds it, is not included. |
| `uncertain` | Matched by item name among several open auctions of the item (`"matched by name among 2 auctions of this item"`); the outcome may belong to the other one. |
| `why` | How an inferred status was reached. |

Full records (also settled sales with `received`, `sale`, `cut`, `saleDeposit`) are in `CraftWiseMarketDB.auctions.chars[<character key>]`, kept 30 days after they finish.

### `market`
Where the AH price data is (#90). The prices themselves are not copied into the snapshot: they are account-wide in `CraftWiseMarketDB` (same file, see below), and a full scan holds thousands of items.

| Field | Meaning |
|---|---|
| `where` | `"CraftWiseMarketDB"`. |
| `houses[<house key>]` | Per auction house seen (`"<realm>|H"`, `"<realm>|N:BootyBay"`, ...): `label`, `kind` (`faction`/`neutral`), `items` (items with a price there), `withHistory` (of those, items in the market scope with history), `lastRecorded` (last scan, search or browse), `lastFullScan`, `lastFullScanSource`, `lastFullScanItems` (scope items stored), `lastFullScanLastOnly` (items outside the scope stored with `last` only). |
| `auctionator` | `label` ("Auctionator (house unknown)"), `house = "unknown"`, `items` (prices exported, see below). |
| `names` | How many item names `CraftWiseMarketDB.names` holds. |
| `itemInfo` | How many items `CraftWiseMarketDB.itemInfo` describes (#92). |

### `crates`
Waylaid crates (#91): every crate this account has seen (bags, auction house items, merchants), cheapest Merchant's Favor first. `{ list, best, bestHeld }`; `best` = item ID of the cheapest crate to buy and fill, `bestHeld` = the cheapest to fill among the crates this character carries. Money is copper, rounded to whole copper.

| Field | Meaning |
|---|---|
| `id`, `name`, `tier` | Crate item, its name, the first word after the colon ("Apprentice"). |
| `held` | Crates in this character's bags (missing when 0). |
| `crate`, `crateFrom` | Price of one crate: the cheapest of vendor and AH, with the price label (house and basis, #26). Missing when there is none. |
| `options` | The bundles the crate takes, any one of them, as its tooltip lists them: `{ n, name, id, cost, how, best }`. `id` missing = the name matched no item CraftWise knows; `cost` missing = no price; `how` = price label ("crafted" when a recipe this character knows makes it cheaper, #47); `best = true` on the cheapest. |
| `fillCost` | Cost of the cheapest bundle. |
| `reward`, `rewardFrom`, `observed` | Merchant's Favor per crate. `"tooltip"`: a line of the crate's tooltip states it. `"seen"`: measured when a Favor gain came with one such crate leaving the bags (the value seen most; `observed` = turn-ins measured). Missing until one of them was seen. |
| `total`, `perFavor` | Crate + cheapest bundle, and that per Favor point. |
| `fillPerFavor` | Cheapest bundle per Favor point (for a crate you already have). |
| `missing` | What keeps a figure out: "fill list not read", "no price for any bundle", "reward not seen", "no crate price". |

Raw tooltip lines, fill options and measured rewards are in `CraftWiseDB.crates[<itemID>]` (`lines`, `fill`, `reward`, `got`).

### `favor`
Merchant's Favor (currency 3402) and the merchants that take it (#91): `{ id, name, balance, max, earned, vendors }`. `balance` = this character's amount (`C_CurrencyInfo`), `max` missing when the client reports no cap, `earned` = total earned when the client reports it.

`vendors`: each merchant this account opened that sells something for Favor (e.g. Pawani, Durotar Supply and Logistics, The Barrens), from the merchant recorder (#66): `{ npc, name, zone, sub, map, x, y, t, faction, factionID, standing, standingNow, rep, full, items }`. `standing` = this account's standing when the list was recorded, `standingNow` and `rep = { value, min, max }` = this character's standing now. `full = true` when the merchant window showed all items (its filter was "All"); otherwise the list may miss items.

| Item field | Meaning |
|---|---|
| `id`, `name` | Item. |
| `favor` | Favor cost. `p` = copper on top (missing when none), `other` = other currencies or items asked, `s` = stack bought (missing when 1). |
| `req` | Reputation requirement as the item's tooltip states it: the standing alone ("Honored") when it is with the merchant's own faction, else the whole line. Missing when the tooltip has none (or the list was recorded before #91). |
| `known`, `unusable`, `n` | "Already known" on the tooltip, shown in red, limited stock (missing when unlimited). |

## Market data (`CraftWiseMarketDB`, #26, #90)
Account-wide, in the same `CraftWise.lua` file. Written to disk at logout, `/reload` or quit, like the snapshot. Money is copper, times are Unix seconds.

- `items[<item key>][<house key>]`: one string per item and house. The item key is the item ID, or `"<itemID>:<suffixID>"` for random-suffix gear. Decoding is in `Market.lua` (`DecodeEntry`): numbers are base 36, `"last|raw|days"`.
  - `last` = `t,min,qty,listings[,off]`: the latest observation: when, lowest unit price, units listed, listings (price levels for commodities). `off` = time of a later full scan at that house that didn't list it.
  - Items in the market scope (own professions' reagents, products and recipes, items you interacted with) also keep `raw` (48 h of scans with the cheapest 8 price levels) and `days` (30 days of daily low, typical, high, ...).
  - Every other item of a full scan or browse list has `last` only: the string ends in `||` (#90).
- `names[<itemID>]`: the item's name as the client gave it, in the client's language (full-scan rows, else the client cache after a scan, on AH close, after login and at logout). Missing when the client hadn't loaded the item; not part of any price record. A plain string, unchanged since #90.
- `itemInfo[<itemID>]` (#92): `"q,i,c,s,t"`, numbers in base 36 like the price records, for every item ID that has a record in `items` (suffix variants share their item ID's entry) or in `auctionator.items`. Dropped together with the last of those records.
  - `q` quality (`Enum.ItemQuality`: 0 poor, 1 common, 2 uncommon, 3 rare, 4 epic, 5 legendary, ...), `i` icon file ID, `c` class ID and `s` subclass ID (`Enum.ItemClass` and its subclass enums), all as the client returns them (`C_Item.GetItemInfoInstant`, `C_Item.GetItemInfo`, or the complete full-scan row for quality and icon). `t` = Unix time CraftWise read them.
  - An entry exists only once the client gave the quality; any other field the client didn't give is empty (e.g. `"1,,7,9,tmz8w0"` has no icon): missing, never a default.
  - The name is not repeated here: it is `names[<itemID>]` (one name store). Together they give `{ n, q, i, c, s, t }` as issue #92 lists it; `Market.ItemInfo(itemID)` in Lua returns exactly that.
  - Read again from the client when older than 30 days (after a scan, on AH close or after login); items the client cache doesn't hold are requested 100 at a time.
  - Example (made-up item): `itemInfo = { [12345] = "1,2vji,7,9,tmz8w0" }` with `names = { [12345] = "Some Herb" }` = `{ n = "Some Herb", q = 1 (common), i = 134190, c = 7 (Tradegoods), s = 9, t = 1792115136 }`.
- `auctionator`: `{ source = "auctionator", house = "unknown", label = "Auctionator (house unknown)", items = { [<itemID>] = "t,copper,age" } }`. Auctionator's price for items CraftWise had no price for at the profit house when it looked (`t` = when CraftWise read it, `age` = days since Auctionator saw it). Auctionator mixes houses (#26), so this is never mixed into `items` and never wins over CraftWise's own prices. Kept 30 days.
- `scans[<house key>]`: the last 30 recordings: `t`, `kind` (`full`, `search`, `gear`), `items` (scope items), `lastOnly` (other items), `source`.

## Size
`CraftWiseMarketDB.itemInfo` for 10,000 items is about 0.34 MB (measured headless, `tests/item_info_spec.lua`); it is per item, not per house. With the names map and one full scan of 10,000 items at one house, the market data is about 1.4 MB.

A full character (18 worn items, 80 bag items, 100 bank items, 16 mail items, 25 quests with two objectives each, 50 reputations, 30 flight paths on each of two continents, a heavy fishing log, 26 Waylaid crates with 5 bundles each and a Favor merchant with 82 items) is about 98 KB in the SavedVariables file (measured headless, `tests/snapshot_spec.lua`; the test allows 128 KB). Most of it is the file's indentation; `crates` and `favor` are about 37 KB of it, quests, reputations, holdings and flight paths roughly 12-13 KB each.
