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

## Size
A full character (18 worn items, 80 bag items, 100 bank items, 16 mail items, 25 quests with two objectives each, 50 reputations, 30 flight paths on each of two continents) is about 57 KB in the SavedVariables file (measured headless, `tests/snapshot_spec.lua`). Most of it is the file's indentation; quests, reputations, holdings and flight paths are roughly 12-13 KB each.
