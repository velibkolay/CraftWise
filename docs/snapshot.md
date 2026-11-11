# Character snapshot (#63)

A per-character state snapshot that a Claude session reads from disk to answer questions about the character (quests, gear, professions, money). CraftWise doesn't talk to Claude; it only writes this table.

## Where it is
- File: `WTF/Account/<account>/SavedVariables/CraftWise.lua` (account-wide, so a session that can read the account SavedVariables folder sees every character).
- Key: `CraftWiseDB.snapshots["<realm>-<name>"]`, e.g. `CraftWiseDB.snapshots["Forever-EU-Veli"]`. One entry per character, overwritten each time; no history.
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
| `name`, `realm` | Character name and realm. |
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
| `zone`, `subzone` | Zone and subzone text (`GetRealZoneText`, `GetSubZoneText`); `subzone` missing when there is none. |
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

## Size
A full character (18 worn items, 80 bag items, 100 bank items, 16 mail items, 25 quests with two objectives each, 50 reputations) is about 44 KB in the SavedVariables file (measured headless, `tests/snapshot_spec.lua`). Most of it is the file's indentation; quests, reputations and holdings are roughly 12-13 KB each.
