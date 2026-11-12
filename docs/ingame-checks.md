# In-game checks

Things the headless tests cannot prove. Run after installing to `World of Warcraft/_forever_/Interface/AddOns/`, on the live Forever client.

## Setup
1. Install CraftWise and Auctionator, `/reload`.
2. Auction house: Auctionator tab, **Full Scan**.

## Recipe capture (#1, #3)
- [ ] Open a profession window. `/craftwise debug` shows the profession with a recipe count that includes unlearned recipes.
- [ ] Count matches the window with the "Unlearned" filter on. If it only counts learned recipes, `GetAllRecipeIDs` respects the filter: report it.
- [ ] `/craftwise`: unlearned recipes show reagents (tooltip). If they show "Reagents unknown", `GetRecipeSchematic` returns nothing for unlearned recipes.

## Prices (#2)
- [ ] Rows show cost and sells-for after the Auctionator scan.
- [ ] Visit a trade goods vendor (thread, dye) and reopen `/craftwise`: those reagents show "vendor" in the tooltip.
- [ ] Without Auctionator and before any AH visit: orange "No auction prices yet" line, no Lua error. With CraftWise's own recorded prices it goes away even without Auctionator.

## Trainer (#3)
- [ ] Open the profession window first (recipe names are matched against it), then your profession trainer, then `/craftwise`: trainer recipes show Trainable / Trainable at N, a learn cost and break-even.

## UI (#5)
- [ ] Window drags, closes with Esc and the X button.
- [ ] Profession buttons switch tables; "Show unlearned" toggles rows.
- [ ] Header click sorts, second click flips direction.
- [ ] Mouse wheel scrolls; Shift+wheel scrolls a page.
- [ ] Row hover: reagent breakdown with source; clicking a row with the profession open selects the recipe.

Report Lua errors with BugSack + BugGrabber.

## Skill-up recorder (#15)
- Craft a few recipes (orange and yellow). `/craftwise debug` shows "skill-up log: N crafts recorded" = number of crafts.
- Recipe tooltip shows `Skill-ups  yellow X  grey Y` and `Your crafts  a skill-ups in b crafts`.
- Orange crafts must all count as skill-ups. After `/reload`, `CraftWiseDB.skillups[recipeID][skill]` holds `{ n, ups, d }`.
- Batch crafting (craft all): every craft counted once.

## Upgrades view (#16)
- Upgrades tab lists known recipes whose item has a higher item level (or same level, more armour) than what you wear, or fills an empty slot.
- Items you can't wear (red line in the item tooltip) or are too low level for are not listed.
- Tooltip: stat differences vs the equipped item, reagents with "have N". Right-click dismisses; "Show dismissed" shows them greyed at the bottom; right-click again restores.
- Equip something from the list: the row disappears (PLAYER_EQUIPMENT_CHANGED).
- Check: `C_Item.GetItemStats` returns armour under `RESISTANCE0_NAME` in the Forever client (else the armour gain shows 0).
- Check: ranged items (bow/gun) compare against the ranged slot.

### Craftable section: learnable recipes, total cost, main stats (#16 scope extension)
`/reload` is enough (no new file).
- Summary starts with "Craftable" and counts rows from known recipes and rows to "learn first".
- A recipe you don't know, whose item would upgrade a slot, shows with "learn first (Trainer)" / "(Vendor: Name (Zone) - price)" / "(Drop: ...)" / "(AH: price)" when its required skill is known and met. Recipes above your skill, with an unknown requirement, sold only by the other faction's vendor, quest-only, or without any source are not listed.
- TOTAL COST column = reagents + learn cost (trainer fee, vendor price or the recipe item's AH price at the profit house). A drop recipe without an AH price shows "+?". No profit anywhere in the view.
- Hover: "Main stats  +3 AGI +2 STA  vs  +1 STR", "Learn first (skill N)" with the sources, "Cost to obtain" with reagents, learn and total.
- Check: `C_Item.GetItemStats` uses the keys `ITEM_MOD_STRENGTH_SHORT`, `ITEM_MOD_AGILITY_SHORT`, `ITEM_MOD_INTELLECT_SHORT`, `ITEM_MOD_SPIRIT_SHORT`, `ITEM_MOD_STAMINA_SHORT` in the Forever client (else the inline stats stay empty). Spirit is shown because it is a base attribute in Forever; say if it should go.
- Check: `C_PlayerInfo.CanUseItem(itemID)` returns false for armour/weapon types the class can't use (e.g. plate on a hunter) and true otherwise, also for items not cached yet. If it returns false for usable items, every row disappears: report it.
- Items the client hasn't loaded are requested and appear about half a second later (GET_ITEM_INFO_RECEIVED).

### General / AH section (#50)
New file `UpgradeSearch.lua`: **full game restart** needed, `/reload` is not enough.
- Upgrades view: "Craftable" / "General / AH" buttons next to the search box. General / AH shows a "Search AH" button on the right (dimmed while the AH is closed; clicking it then only prints "Open the auction house first").
- At an auctioneer, click Search AH once. The summary counts "Searching the AH: n/15 <slot>..." through Head, Neck, Shoulder, Back, Chest (incl. robes), Wrist, Hands, Waist, Legs, Feet, Ring, Trinket, Off hand (shields, held in off-hand), Weapon (one-hand, two-hand, main/off hand), Ranged (bow, gun, crossbow, wand, thrown). It ends with "AH gear search done." Nothing more is sent after that, and nothing is sent without the click.
- Check: no error and no "action blocked" for the searches after the first (they are sent from AUCTION_HOUSE_BROWSE_RESULTS_UPDATED / AUCTION_HOUSE_THROTTLED_SYSTEM_READY, not from the click). If the client blocks them, report it: the search would have to become one click per slot.
- Check: the server honours `itemClassFilters` with `classID` + `inventoryType` and no `subClassID` (e.g. the Back search returns cloaks only). It doesn't matter for correctness, because rows are filtered by equip slot anyway, but without it the results are mostly other gear.
- Check: `maxLevel` = your level keeps out items you can't wear yet. Sort "Level" descending puts the highest item levels first. Up to 3 extra result pages per slot are requested (`RequestMoreBrowseResults`).
- Check: `itemKey.itemLevel` in browse results is the item level (rows show "ilvl N"), and random-enchant items ("of the Monkey") come with a non-zero `itemSuffix` (row says "random enchant"; its inline stats are left out because only the base item's stats are known).
- Rows: item, slot, ilvl, main stats, "N listed · 2h ago", REPLACES with the equipped item and its stats, gain, TOTAL COST = lowest buyout at the profit house. Plate on a class that can't wear it, or lower item level than what you wear, is not listed. Searched at a neutral house while the profit house is your faction's: "not seen at Horde AH".
- `/craftwise market <itemID>` on an AH gear item found this way shows only "last" (no cheapest tiers, no typical). In `CraftWiseMarketDB.scans` the run shows as kind "gear".
- Closing the AH mid-search stops it: "AH gear search stopped ... (n of 15 slots searched)", with the rows found so far kept. The summary says "(stopped)".
- Right-click dismisses / restores, as in Craftable. While our search runs, Blizzard's browse list shows our results; that is expected.

## Music (#17)
- `CraftWise_Music` made with `tools/music_split.py`, game restarted: Music tab shows the songs count.
- Click a profession: a picker lists "No music" and every song with Play/Stop preview, plus Resume / From the beginning. Escape or X closes it and stops the preview.
- Skinning: music starts with the cast and stops when the cast ends (also when interrupted by moving). Next skin continues from the same part (resume) or from the start (restart).
- Pressing another ability during a cast doesn't stop the music.
- Resume plays 1-2 s chunks (small gaps possible); start over and Party play `full.ogg` continuously and loop.
- Channel is Master: master volume applies, game music keeps playing underneath (turn it down in Sound settings if needed).

## Learning a recipe (#3)
- Buy a recipe at the trainer with the CraftWise window open: it leaves the Learn view right away (no profession reopen). Which event fired is not logged; if it does not update, report it.
- Song file by name: put `x.mp3` in `AddOns/CraftWise_Music/Songs/`, restart, picker -> type `x.mp3` -> Add. A wrong name says "Not found". Check that the existence probe is silent (it is stopped at once) and that PlaySoundFile returns false for a missing file in Forever.

## Video window (#19)
- After `tools/video_frames.py` and a restart: picker shows the video under "Video"; Play opens a small window that animates; Stop / closing the picker hides it.
- Choose it for a profession, cast: window shows and animates, hides when the cast ends, continues from the same frame next cast. Drag to move; position is kept.
- Check: TGA sheets load (no green/black squares), no stutter when switching sheets.
- Volume (picker, - / +): songs play on the Dialog channel; its volume is set while a song plays and put back after. Check Sound settings > Dialog volume is unchanged after fishing/skinning, and after /reload during a song. NPC voices play at the profession volume while a song plays.

## Party key (#20)
- Esc > Options > Key Bindings > AddOns > CraftWise: "Party: music, video and dance" listed; bind a key (needs a game restart once for Bindings.xml).
- Key / `/craftwise party` / "Party!" button: character dances, Party song + video start. Same key stops; walking stops. Check DoEmote works from an addon in Forever.

## Bag sort (#12)
- Bags view > "Sort bags": kept items, quest items and reagents first (by item type, then item ID - the same order every time), free slots, items to sell last (best value first, junk at the very end). Right after login it first loads item data ("Loading item info..."); a second click must say "already in order", also after a restart. Chat says "Bags sorted (N moves)". Click again: "already in order".
- Profession bags / quivers untouched. Stacks of the same item are not swapped (they would merge).
- Entering combat during the sort stops it; holding an item on the cursor stops it.
- Check: dropping onto an occupied slot swaps the two items (no item left on the cursor).

## Junk (#12)
- Bags view: click a row -> menu Keep / Junk / Normal (current one highlighted). Junk shows red "Junk".
- In the game bags / Bagnon / Baganator: middle-click an item (default) -> same menu at the cursor; nothing else happens (bag buttons only listen to left/right). Settings: Middle click / Alt + right / Off. Click elsewhere or Esc closes the menu.
- Merchant window: "Sell junk (N)" button left of Blizzard's sell-all-junk button. One click sells every marked stack, ~5 per second; chat prints count and money. Closing the merchant stops it.
- Loot the same item again: it is junk right away. Sort bags puts junk at the very end.
- Check: button position on the Forever merchant frame; UseContainerItem sells (doesn't equip/use) while the merchant is open.
- AH rule: Bags view top right "AH rule: +20%, min 10c" opens a panel: "At least this % more" (5% steps) and "And at least this much more" (0, 1c, 2c, 5c, 10c ... 1g); example line updates; "Defaults" resets. Items under the rule show "Vendor  AH +Xc, too little". Also `/craftwise ahmin <percent> [copper]`.
- First AH sale of a single cheap item: check the mail amount to learn how the 5% cut rounds (single 8c item -> 7c or 8c).

## Level view (#15)
- New file: full game restart. "Level" button between Learn and Upgrades; profession tabs at the top.
- Rows: known recipes that still give points (grey hidden), best "per skill-up" first. Chance shows % and where it comes from (orange: always / your crafts x/y / all your crafts of this profession x/y / ~% estimate from the community formula when fewer than 5 crafts are recorded for that stage).
- Hover: thresholds, chance source, reagents, sale (AH after cut or vendor), net, crafts per point, per skill-up.
- Craft a recipe: the view updates (skill and chances) without reopening.
- Check: the skill in the summary matches the profession window; soulbound outputs use vendor price.

## Chance in the profession window (#15)
- New file: full restart. Open a crafting profession: learned yellow/green/orange recipes show a % at the right of the row (green = measured / orange 100%, light orange "~" = formula estimate). Grey and unlearned rows show nothing.
- Hover a recipe: "CraftWise: skill-up chance" line with where it comes from.
- Craft: the % updates after the skill-up settles. Long recipe names don't run under the %.
- Check: no Lua errors / taint when crafting from the window, scrolling, switching professions.

## Sell on AH mark (#12)
- [ ] Middle-click an item in the bags > "Sell on AH": Bags view shows "Auction  marked", tooltip shows "Marked: Sell on AH".
- [ ] Junk shows a red X (not the coin), so it differs from the AH icon. Small auctioneer icon in the top-left corner of the item in Blizzard bags, Bagnon and Baganator (Baganator: Settings > Icons, if the corner is taken).
- [ ] Sort bags: AH-marked items come first in the selling part, junk last.
- [ ] Keep or Junk on the same item removes the AH mark; quest items can't be marked.

## Used in (crafting materials)
- Bags view: "USED IN" column (e.g. "Leatherworking 72 · Tailoring 6"): green = you know a recipe with it, white = your profession, grey = other profession. Disenchant column replaced (values still need #11; "can be disenchanted" stays in the row note).
- Tooltip: "Used in N recipes" grouped by profession: known / learn at X / other profession, up to 4 per profession.
- "My crafting materials" filter: only items used by your professions.
- Item menu > "Recipes using this": Profit view of that profession, unlearned shown, search = item name (search also matches reagent names now).
- Junk icon: items marked Junk show the coin icon in the Blizzard bags and in Bagnon (needs a restart once: BagIcons.lua). Unmarking removes it. With Scrap disabled, only CraftWise junk (and Bagnon's own grey-item coin, if "glowPoor" is on) shows it.

## Item tooltip section
- Any item tooltip (bags, Bagnon, links, merchant): a "CraftWise" header (blue) with: Marked (Junk/Keep), Sell xN (Vendor · AH · advice), Used in, Your crafts (skill-ups for items you craft). Not added twice inside the CraftWise window.
- Gear button (top right of the CraftWise window) or `/craftwise settings`: on/off, Always / Only with Shift (tooltip redraws when Shift is pressed), each line on/off.
- Check: TooltipDataProcessor post-call works for bag items in Forever; GameTooltip:RefreshData redraws on Shift.

## Market recorder (#26 phase 1)
New file and new SavedVariables: full game restart. Nothing changes in the profit numbers yet; `/craftwise market <itemID or link>` is the only output. Saved data is `CraftWiseMarketDB` in `WTF/Account/<account>/SavedVariables/CraftWise.lua` (copy it only with the game closed).

House detection:
- [ ] At the AH in Orgrimmar and Thunder Bluff, search an item you carry: `/craftwise market <id>` lists it under "Horde AH".
- [ ] Same at Booty Bay, Gadgetzan and Everlook: it lists under that town, and the Horde AH line is unchanged. If it lands under "Horde AH", the zone text differs from `NEUTRAL_ZONES` in `Market.lua`: run `/dump GetRealZoneText(), GetSubZoneText()` there and report it.
- [ ] `/dump GetRealmName()` still returns the ruleset name ("PvP"), and `CraftWiseMarketDB.houses` has `PvP|H` and `PvP|N:BootyBay` style keys.

What can be seen from other addons' scans:
- [ ] Auctionator Full Scan: `/craftwise market <id>` for a reagent shows "cheapest: 3 @ ... · 25 @ ..." and `CraftWiseMarketDB.scans[<house>]` ends with `kind = "full"`, `source = "auctionator"`. This proves a second addon receives `REPLICATE_ITEM_LIST_UPDATE` and can read the list.
- [ ] The game doesn't stutter during or after the scan. The scan log's `items` is about the number of scope items on sale.
- [ ] Close the AH during a full scan: no new `kind = "full"` entry and no "disappeared" count from it.
- [ ] One scan is one log entry (the event doesn't fire twice in a way that stores it twice).
- [ ] Auctionator shopping search and Blizzard's own search, for a commodity and for gear: one new point each, not one per event.
- [ ] Blizzard browse list: only `last` changes (no tiers line change) for items in scope.

Prices:
- [ ] A stack of gear or other non-commodity with quantity above 1: compare the Blizzard list with `/craftwise market`. `buyoutAmount` is treated as per unit in searches, and the full scan divides by stack. Both must give the same unit price. If not, report it: searches would then need dividing too.
- [ ] Random-suffix gear ("of the Bear"): `/craftwise market <link>` lists `item <id>:<suffix>`, and two suffixes of one item stay apart. Check the same key from a search and from a full scan.
- [ ] Gear not yet in the item cache right after login, full scan: it appears after the scan (links load within 5 s) or stays out, never under a wrong key.

Scope:
- [ ] Loot something new, buy from a vendor, take something from the bank: `CraftWiseMarketDB.scope.items[id]` is true after `/reload`.
- [ ] Bank: `Enum.BagIndex` covers the bank on this client (bank items enter the scope when the window opens).
- [ ] Items from your professions, known or not, are in scope after login. Engineering and Mining items too, without an alt logged in.
- [ ] Loot during combat raises no Lua error (chat payloads can be secret values on 12.x).

History and size:
- [ ] Three days after the first scan, `/craftwise market` shows `typical: ...` instead of "too little history". Today's scans count once the AH has closed.
- [ ] Check an item with many small listings (a popular herb): the typical is near where most units sit, not at the 8th tier.
- [ ] After a week of use: size of `CraftWise.lua`, and login and `/reload` time compared with before. The test budget is 5 MB at the expected load.
- [ ] Open and close the AH several times: no stutter on close. Right after login a prune runs over about 3 seconds (20 entries per frame).

## Market display (#26 phase 2)
`/reload` is enough (no new file). Needs a few recorded scans first (phase 1 above).

Settings (gear button or `/craftwise settings`), "Profit prices":
- [ ] Basis Typical / Current lowest and the four house buttons render without overlapping; the first house button says "Horde AH". Houses with nothing recorded are greyed, don't select, and are listed after "No data yet:".
- [ ] Switching basis or house updates the open CraftWise window at once; the second summary line says "Auction prices: typical · Horde AH, else Auctionator (house unknown)" with the chosen basis and house.

Profit view:
- [ ] Row tooltip, Reagents: each AH price is labelled "typical · Horde AH", "current lowest, too little history · Horde AH" (until 3 days of history) or "Auctionator (house unknown)" for items CraftWise hasn't recorded.
- [ ] Row tooltip, "Auction houses" section: one line per reagent at the profit house with "best for N" (N = one craft), then the crafted item with its figures, Best to sell and the other houses.
- [ ] Select Booty Bay: crafted items sold at the AH show "cut unverified" in the PROFIT column and "gross, cut unverified" in the tooltip; the summary counts them separately. Back on Horde AH, profit after 5% returns.
- [ ] "thin market" (orange) appears in a row's status line when a reagent or the crafted item has a thin cheapest tier at the profit house. Compare with the AH list: the cheapest tier holds under one stack or under 10% of the units within +10% of min.
- [ ] Level view: the sale line names the house and cut ("AH after 5% cut" plus the label); at Booty Bay it says the AH sale is not counted because the cut is unverified.

Item tooltip (bags, links):
- [ ] Line "Auction prices per house" (on by default, can be turned off in Settings): profit house with typical or "too little history (n of 3 days)", Current (min, units, price levels for commodities / listings for gear, seen ... ago), Cheapest tiers, Within +10% of min, Last 7 days, thin warning, Best to buy, Best to sell (gross, cut unverified) and each other house in one line.
- [ ] `C_Item.GetItemMaxStackSizeByID` returns the stack size for a reagent (e.g. Light Leather) so "price levels" and the stack part of the thin rule show. Right after login, items not cached yet show no count until hovered again.
- [ ] Items never seen at an AH add no market lines. Alliance AH data from an Alliance alt never shows on a Horde character.
- [ ] Memory: open the CraftWise window on a big profession, then `/run UpdateAddOnMemoryUsage() print(GetAddOnMemoryUsage("CraftWise"))` before and after. Reading prices unpacks the entries it touches until the next prune (AH close or login).

## Profit house for every AH value, cut source (#40)
`/reload` is enough (no new file). Needs recorded prices for a few items (see Market display above).

- [ ] Bags view, AUCTION column: with Settings "Auction house for profit" = Horde AH and basis Typical, the value matches the profit view's price for the same item after 5%. Switch basis to Current lowest: the column changes at once. Row tooltip: "Auction, after cut" and a line like "typical · Horde AH · 5% cut (confirmed)".
- [ ] Select Booty Bay: Bags items priced there show "cut ?" in the AUCTION column (not counted, vendor advised); the row tooltip says "<gross> gross, cut unverified". Items CraftWise never saw show the Auctionator value labelled "Auctionator (house unknown)" with "5% cut (house unknown)"; items with nothing show "-".
- [ ] Item tooltip (bags, links): "Sell: Vendor X · AH Y" is followed by a line "AH price | typical · Horde AH · 5% cut (confirmed)", or "no price data". At Booty Bay: "AH ?" with "gross ... · cut unverified". The advice (Vendor / Auction) follows the AH rule on the net price at that house.
- [ ] AH rule panel: change the percent or copper, then compare two items near the threshold: the advice flips on the profit house's net price, not Auctionator's.
- [ ] Learn view, a recipe sold on the AH (no trainer or vendor): "To learn" shows the AH price and a second line with its label ("typical · Horde AH"); "Where to get it" lists "AH: ..." with the same label instead of "Auctionator". Switch house or basis: the price follows.
- [ ] Profit row tooltip "Sells for" and the Level view sale line show "5% cut (confirmed)" in grey, no orange.
- [ ] Disenchant value: still hidden until the disenchant data exists (#11); when it does, the Bags row tooltip lists each material's price label and cut text.
- [ ] Phase 3 (#26) once a cut is measured: "N% cut measured (n sales)" replaces "(confirmed)"; a measurement that differs from 5% shows both ("..., differs from 5% confirmed") in orange.

## Baganator
- Baganator settings > junk: "CraftWise" listed (auto-selected if no other plugin is active); marked items show Baganator's junk coin; marking/unmarking refreshes at once.
- Baganator settings > sorting: "CraftWise" mode; Baganator's sort button sorts the backpack like Sort bags (bank untouched).

## Source recorder (#37)
Needs a full game restart after the update (new file in the TOC). Data is `CraftWiseDB.sources[<recipe item ID>]` in `CraftWise.lua`.
- [ ] Recipe vendor (e.g. a cooking or leatherworking supply vendor): open the merchant. `sources[<item>].vendors[<npcID>]` has the NPC name, zone, subzone, price and (if the item is limited) `limited`. The Learn view shows the line with "seen by you just now"; the "Source not known yet" status for that recipe is gone.
- [ ] Same vendor again with a changed price (or reopen): one entry, `t` updated, no duplicate.
- [ ] `faction` on the vendor and the quest NPC: set only when `UnitFactionGroup("npc")` / `("questnpc")` returns Horde or Alliance for an NPC. If it is nil for NPCs, that is fine; if it returns your own faction for a neutral NPC, report it (wrong data).
- [ ] Vendor selling for tokens/currency or items: `costs` lists name and amount.
- [ ] Looted recipe: kill a mob that drops a recipe, open the loot window. `loot["Creature:<id>"]` has `n = 1`, zone, and the name (target or mouseover). Close and reopen the same corpse: `n` stays 1. Another corpse: `n = 2`. No drop chance anywhere.
- [ ] **`GetLootSourceInfo` exists in Forever and returns the corpse GUID** (`/dump GetLootSourceInfo(1)` with a loot window open). If it is nil, nothing is recorded; report it.
- [ ] A recipe from a chest or object: `loot["GameObject:<id>"]` is recorded, name stays empty (no unit to read it from) and the Learn view shows "Drop: GameObject #<id>".
- [ ] Quest reward: open a quest (and then the turn-in) with a recipe as reward or choice. `quests[<questID>]` has the title, zone, `choice = true` for a choice; one entry for both dialogs.
- [ ] Looting during combat raises no Lua error (GUIDs can be secret values).
- [ ] Hover the recipe in the Learn view: every line in "Where to get it" ends with `[seen by you 2h ago]` or `[bundled data]`/`[QuestieDB]`.

## Profession filing (#44)
`/reload` is enough (no new file). Back up `WTF/.../CraftWise.lua` first if the "?" tab or Cooking-under-Leatherworking is currently there, to see the clean-up work on real data.
- [ ] After `/reload`: the "?" 0/0 tab is gone, and Leatherworking's Level, Profit and Learn views list no Cooking recipes (Roasted Kodo Meat, Coyote Steak, Longjaw Mud Snapper). `/craftwise debug` shows sane recipe counts per profession.
- [ ] Open Cooking, then Leatherworking, then switch back and forth a few times (also with the window open while switching): Leatherworking's Level view shows only Leatherworking recipes, Cooking's only Cooking recipes, and no "?" tab appears.
- [ ] First Aid (if learned): the tab keeps its recipes after opening and closing the window; nothing moves to another tab.
- [ ] Level view tooltip of a yellow/green recipe: "crafts of all recipes of this profession in the ..." counts only crafts from that profession (craft a few Cooking items and check a Leatherworking row's n does not change).

## Fast auto-loot (#41)
Needs a full game restart (new file in the TOC). Settings, "Fast auto-loot" (default on).
- [ ] Solo mob with auto-loot on in the game options: right-click the corpse, everything is taken at once, no loot window.
- [ ] Recipe drop: `sources[<item>].loot["Creature:<id>"]` is recorded even though the window never shows. `/dump GetLootSourceInfo(1)` at a hand-opened window tells whether the function exists (see Source recorder).
- [ ] Source fallback: if `GetLootSourceInfo` is nil, the same record appears with the corpse as source (dead mouseover or target at `LOOT_READY`). Report if the creature ID is wrong.
- [ ] Hold the auto-loot toggle key (Shift by default): the window stays open and nothing is taken. With auto-loot off in the options, the same key makes CraftWise loot.
- [ ] #57 (`/reload` is enough for this fix): Shift + right-click and let go of Shift right away (before the window would appear): the window still stays open and nothing is taken. CraftWise now follows the `autoloot` payload of `LOOT_READY` (the client's decision at click time). To see the payload: `/run local f=CreateFrame("Frame") f:RegisterEvent("LOOT_READY") f:SetScript("OnEvent",function(_,_,a) print("LOOT_READY autoloot", a) end)`, then loot with and without Shift: it prints `true`/`false`. Report if it prints `nil` (then the fallback below decides).
- [ ] `/dump C_CVar.GetCVarBool("autoLootDefault"), IsModifiedClick("AUTOLOOTTOGGLE")` return a boolean each (the fallback rule uses them when the payload is missing).
- [ ] Full bags: coins are taken, items stay in the window, one message "Bags are full. Left in the loot window: ...". Also try with only a partial stack of the dropped item left in the bags (CraftWise leaves it when no slot is free).
- [ ] A bind-on-pickup item asks Blizzard's confirmation; nothing is confirmed for you.
- [ ] Group (loot method group/need before greed): rolls and locked slots are untouched. Master loot: CraftWise does nothing. `Enum.LootMethod.Masterlooter` exists (UNVERIFIED name): `/dump Enum.LootMethod`.
- [ ] Fishing and chests loot too.
- [ ] SpeedyAutoLoot enabled: CraftWise prints its one-time note and does not loot; Settings shows the checkbox dimmed. Without it, no double looting.

## Sale options in the profit view (#48)
`/reload` is enough (no new file).
- Profit view: the "Sells for" cell shows the value plus `vendor` or `AH` (orange `AH gross` where the house's cut is unverified). Light Leather Pants with a vendor price above the AH net shows `5s 99c  vendor`.
- Hover a row: under "Sells for" two lines, "Vendor  5s 99c (no cut)" and "AH net  x (gross y, 5% cut (confirmed), typical · Horde AH)"; the one "Sells for" uses is green with "(used)". Items without AH data say "no price data"; items vendors don't buy say so.
- The cell fits in its column with gold amounts (e.g. `12g 34s 56c  AH`); if it is cut off, report the width.

## Reagent balance and buy list (#49)
New files (`Holdings.lua`, `Balance.lua`): **full game restart** needed, `/reload` is not enough.
- Profit view, hover Light Leather Pants with 60 Cured Light Hide and leather for 8 pants: "Your reagents" lists each reagent with "hold N  X crafts", "Crafts possible 8", the orange line "Light Leather limits you to 8 crafts; you hold Cured Light Hide for 60.", then "To buy for 60 crafts" with quantity, cost and vendor / AH (house) per reagent, and a total.
- Ruined Leather Scraps in the bags count toward Light Leather ("made from what you hold"), Light Hide + Salt toward Cured Light Hide, only when you know those recipes.
- Same section in the Level view tooltip.
- Track the recipe in the profession window, then hover Cured Light Hide or Light Leather in the bags: "Tracked  Light Leather Pants" with the same lines. Settings > tooltip lines has "Tracked recipe: reagents you hold" to turn it off.
- Counted places: open the bank once, then the mailbox; the tooltip line "Counted" lists bank and mail with their age. Check that the bank count matches what is in the bank: CraftWise reads the containers named `CharacterBankTab_N` (or `Bank` / `BankBag_N`) in `Enum.BagIndex`. If the bank shows up as counted but items in it are missing, report `/dump Enum.BagIndex`.
- Mail: items in letters count (`GetInboxItem`); taking an item out of a letter moves it to the bags count without doubling.
- Account bank tabs, when the client has them, show as "Not counted: account bank (not read)".
- The result is cached until the bags change (`BAG_UPDATE_DELAYED`), the bank or mailbox is scanned, or recipes change: loot an item while hovering, hover again, the counts follow. Hovering the same items repeatedly should not stutter.

## Ledger (#46)
Needs a full game restart (new file `Ledger.lua` in the TOC). Saved in `CraftWiseMarketDB.ledger` (`entries`, `chars["<realm>-<name>"]`).
- [ ] Vendor, right-click buy (e.g. 5 Salt): one `entries` row `k = "vbuy"`, `q = 5`, `m` = the merchant's price, `w` = the merchant's name. Same with a split stack (Shift-click, enter 3) and with a drag from the merchant onto a bag slot (that path calls no `BuyMerchantItem`).
- [ ] Vendor sale by right-click and by dragging an item onto the merchant: one `k = "vsell"` row each, `m` = the money received. "Sell junk" with several stacks: one row per item, and their sum equals the money change.
- [ ] Buyback: sell something, buy it back from the buyback tab: one `k = "buyback"` row; `/craftwise ledger` shows the item with sold 0 and received 0. `/dump GetNumBuybackItems()` returns a number at a merchant (legacy function, allowlisted from Blizzard's MerchantFrame.lua).
- [ ] Repair All (and repairing a single item): no row; `/craftwise ledger` lists the repair under "not from logged trades".
- [ ] A slow server: buy at a vendor with high latency; the row still appears (money and bag events are paired within 1.5 s). Report any purchase that was missed.
- [ ] AH commodity (e.g. 10 Light Hide): one `k = "ahbuy"` row, `q = 10`, `m` = the total shown in Blizzard's buy dialog, `w` = the house key (e.g. `<realm>|H`). Let a purchase fail (price changed): no row. Same with Auctionator's buy screen (it calls the same functions).
- [ ] AH item buyout (gear or a recipe): one row with `q` from the auction and `m` = the buyout. A bid without buyout: no row.
- [ ] Where AH purchases land (bags at once, or the mailbox): either way `/dump CraftWiseMarketDB.ledger.chars["<realm>-<name>"].pos[<itemID>]` shows `transit` back at 0 once the units are in the bags, and `known` = the units bought.
- [ ] `pos[<itemID>].held` matches bags + bank right after login, with the bank closed (`C_Item.GetItemCount(id, true, false, true)` must count the bank from the cache). If it drops at login and comes back when the bank opens, report it: the paid cost would turn partial (`N of M units`).
- [ ] `/craftwise ledger login`, `/craftwise ledger today` (per-day rows), `/craftwise ledger all` (since last reset), `/craftwise ledger reset`: start money, spent/received per item, net. With only trades in the session the line says "net matches the money change"; a quest reward or loot money shows as "not from logged trades". `/craftwise ledger` alone repeats the last view.
- [ ] `/reload` keeps "since login"; a relog starts it again. A session over midnight: the new day's start money is the money held at midnight (taken at the first money change after it).

## Reagent cost basis, craft or buy (#47)
`/reload` is enough on top of #46 (no new file; #46 itself needs a restart).
- [ ] Leatherworking with Cured Light Hide learned: hover Light Leather Pants in the Profit view. The Cured Light Hide line says `crafted` when Light Hide + Salt are cheaper than Cured Light Hide at the AH, and the line under it shows both values: `each: crafted 1s 55c · bought 2s typical · Horde AH`. When the AH is cheaper it says `bought: ...` with the same two values.
- [ ] The Cost column of rows using an intermediate drops accordingly; the Cured Light Hide row itself still prices Light Hide and Salt as bought.
- [ ] An intermediate whose recipe you have not learned (or that only an alt knows) is always bought.
- [ ] Settings (gear), "Reagent cost": switch Profit to "Paid cost". The summary line says `reagents: paid cost, else AH (N rows with reagents at AH)`; the reagent tooltip header says the same. Buy a reagent at a vendor: its line now shows `paid cost, <n> held` and the row updates without reopening the window. Reagents you never bought show their AH/vendor price with `no paid cost`.
- [ ] Partial paid cost: hold a few units of a reagent from before the log, buy more at a vendor. The line shows `paid cost, <bought> of <held> units` at the average of the bought units, and under it `average of the <n> units you bought; <m> held have no recorded price`.
- [ ] Intermediate with a paid cost (Paid cost basis): buy Cured Light Hide, then hover Light Leather Pants. Its line shows `paid cost, <n> held` even if crafting it would be cheaper, and no `each: crafted ... · bought ...` line. Without a paid cost it is craft-or-buy as above; a crafted line whose reagents partly lack a paid cost says `some of its reagents have no paid cost (AH)`.
- [ ] The other views (Learn, Level, Upgrades) keep their own setting.
- [ ] Opening the Profit view of a large profession (all recipes, "include unlearned") with craft-or-buy is not noticeably slower than before. Report a stutter.

## Item names in chat (#59)
`/reload` is enough (no new file).
- [ ] Buy and sell something at a vendor, then `/craftwise ledger login`: every item is a clickable link (click opens the item tooltip). `/dump CraftWiseMarketDB.ledger.entries[#CraftWiseMarketDB.ledger.entries]` shows `n` (name) and `l` (link).
- [ ] An item not in the client's cache (e.g. Salt or a grey sold in an earlier session, after a full restart, before hovering it anywhere): `/craftwise ledger` prints within a moment with the item's name or link, never `item <id>`. Old entries from before #59 (no `n`) get their name after the first such print.
- [ ] If the ledger takes noticeably long to print (it waits up to 2 s for item data), report it.
- [ ] `/craftwise market <itemID>` of an item you haven't seen this session: the header is the item's link; a suffix variant shows `<link> (item <id>:<suffix>)`.
- [ ] Item menu "Recipes using this" on an item none of your professions uses: "<item> is not used by your professions." shows the item as a link.

## Buy list: craft or buy for intermediates (#60)
No new files: `/reload` is enough.
- [ ] Profit view, Light Leather Pants with leather and thread for 2 crafts and no Cured Light Hide, Cured Light Hide on the AH above Light Hide + Salt (cost line says "crafted"): "To buy for 2 crafts" shows "Craft 2 × Cured Light Hide  each: crafted 1s50 · bought 1s80 ...", then "2 × Light Hide" (AH, house) and "2 × Salt" (vendor), no "2 × Cured Light Hide" line, and a total of 2 × the crafted cost (when the AH tiers match the price the cost line uses).
- [ ] Light Hide or Salt in the bags: the held units are used first, only the rest is on the list.
- [ ] Cured Light Hide cheaper on the AH than crafting (cost line "bought"), or the Cured Light Hide recipe not known: the list buys Cured Light Hide as before.
- [ ] Settings, cost basis "Paid cost" for a view, holding 1 Cured Light Hide with a recorded paid cost and short of 1: the cost line shows the paid cost, but the buy list still crafts the missing one at market prices (Scout decision on #60: the buy list always decides on the AH basis).
- [ ] Tracked recipe tooltip (hover a reagent in the bags): same buy list as the Profit view.

## Character snapshot for Claude (#63)
New file `Snapshot.lua` in the TOC: **full game restart** needed (not `/reload`). Field reference: `docs/snapshot.md`.
- [ ] `/craftwise snapshot` prints `snapshot saved, /reload to write it to disk` and no second line. A second line `not in this snapshot: ...` names sections the client didn't give: report which and why (`/dump CraftWiseDB.snapshots["<realm>-<name>"].skipped` and `.errors`).
- [ ] `/reload`, then open `WTF/Account/<account>/SavedVariables/CraftWise.lua`: `["snapshots"]` has `["<realm>-<name>"]` with `t` = now. Log out instead of `/reload`: `t` moves to the logout time (refresh on `PLAYER_LOGOUT`).
- [ ] `char`: level, XP, rested XP, money and guild match the character frame and XP bar tooltip. `guild` is `false` on a character without a guild.
- [ ] `location`: zone, subzone and map name are right; `x`/`y` × 100 match the world map coordinates (a coordinates addon, or `/dump C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player")`). In a dungeon `x`/`y` are missing, no error.
- [ ] `equipment`: every worn slot has `link`, `ilvl`, `armor`, `stats` like the item tooltip, `dur`/`durMax` like the tooltip's Durability line. Check whether Tabard and Ranged are listed (a slot the client doesn't know is skipped).
- [ ] `professions`: primary and secondary professions with the skill shown in the spellbook. A gathering profession without a window (Herbalism, Skinning) shows with `cached = false`.
- [ ] `quests`: every quest of the log with title, level, zone header, objectives and counts as in the quest log; a quest ready to turn in has `complete = true`. Collapse one zone header in the quest log, snapshot again: that zone's quests are missing, the header is in `collapsedHeaders`, `read` < `inLog`, and the header is still collapsed afterwards (the snapshot must not expand it).
- [ ] `reputations`: factions with the standing label and value as in the reputation pane; collapse a header: its factions are missing, the header is listed and stays collapsed.
- [ ] Hunter with pet out: `pet` has name, family, level, happiness (1-3, as the happiness icon) and loyalty text. Pet dismissed: `pet` missing, `skipped.pet = "no hunter pet out"`. Report if `C_PetInfo.GetPetLoyalty` returns nothing.
- [ ] `holdings`: bag counts match the bags; `bank`/`mail` appear after opening the bank/mailbox once, with their `t`.
- [ ] `ledger.today` / `ledger.reset` totals match `/craftwise ledger today` / `/craftwise ledger all`.
- [ ] Logout and `/reload` don't take noticeably longer than before; no Lua error on logout (BugSack keeps it for the next login).
- [ ] The file has nothing about other players (party members, whisper partners, guild members).

## Profession skill refresh without the window (#65)
No new file: `/reload` is enough.
- [ ] After `/reload`, without opening any profession window: `/craftwise debug` lists every profession of the spellbook, Fishing and gathering ones included, with the skill and max shown there (Fishing and gathering professions with 0 recipes cached).
- [ ] Learn Expert (or Journeyman) of a profession at a trainer, then open `/craftwise` without opening the profession window: the tab shows the new cap (e.g. `Cooking 150/225`). Same at once if the CraftWise window was already open.
- [ ] Catch a fish that gives a skill point: `/craftwise debug` shows the new Fishing skill; `/craftwise snapshot` then `/reload`: `professions` has Fishing with that skill, `cached = false`.
- [ ] Fishing, Herbalism, Mining and Skinning get no tab. A profession whose window was never opened (e.g. First Aid) gets its tab only after opening the window once, as before.
- [ ] Open a profession window afterwards: `/craftwise debug` lists that profession once, not twice, with its recipes.
- [ ] Weapon skill-ups in combat (they also send `SKILL_LINES_CHANGED`) cause no stutter.

## Merchant recorder and "who sells X" (#66)
New file `Merchant.lua` in the TOC: **full game restart** needed (not `/reload`).
- [ ] Open any vendor (e.g. a fishing supplier), then `/dump CraftWiseDB.merchants[<npcID>]` (NPC ID from the GUID, `/dump UnitGUID("npc")` while the window is open): `name`, `zone`, `sub`, `map`, `x`/`y` (match the world map coordinates within a few tenths), `group`, `t`, and `items` with every item of every page: `p` = price in copper as shown, `s` = stack size, `n` = -1 for unlimited items.
- [ ] **Faction (unverified):** at Sewa Mistrunner (Thunder Bluff) `faction` = `{ id, name = "Thunder Bluff" }` and `standing` = your standing (6 = Honored). This relies on the NPC's tooltip showing the faction name as a line; if `faction` is missing, hover the NPC and report the tooltip lines (`/dump C_TooltipInfo.GetUnit("npc")` while the window is open). `reaction` is `UnitReaction("npc", "player")`: report whether it equals your standing with the vendor's faction (e.g. 6 at Honored) or stays at 4/5.
- [ ] `items[<itemID>].ps` holds the price per standing: Nightcrawlers at Sewa should show `ps[6] = 90`. A vendor of a faction where you are Neutral (e.g. Orgrimmar at Neutral) selling Nightcrawlers for 1s: `/craftwise where nightcrawlers` ends with "base price seen at Neutral: 1s". If you see the same item at a Friendly vendor, report its price next to the Neutral one (a Friendly discount is not assumed).
- [ ] Limited stock (e.g. Strong Fishing Pole): `n` = the count on the button; `log` has `{ n, first, last, realm }`. Buy one: a new log entry with the lower count. Come back after it restocked: `/craftwise where strong fishing pole` shows "count rose 0 -> 1 between <time> and <time> (within ..., may be another layer)". Forever layers may have separate stock, so a rise is not proven to be a restock: report if counts jump between visits minutes apart.
- [ ] Merchant filter: the window opens on your class filter. `filter`/`full`: switch the filter dropdown to "All": `full = true`, and items hidden by the class filter appear. With the class filter, items not shown are kept (not deleted).
- [ ] A recipe you know: `known = true` (tooltip "Already known"). An item shown in red: `unusable = true`.
- [ ] A currency/token vendor: `c` lists the costs with `currency` or `item` IDs; `p = 0` when only currency is asked.
- [ ] `/craftwise where <shift-clicked item link>`, `/craftwise where 6530`, `/craftwise where nightcrawl`: vendors cheapest first with place, price, standing, stock and age. An unknown item: "no merchant you opened sells ...".
- [ ] Item tooltip (bags or link): "Sold by" with up to 2 merchants and "+N more: /craftwise where". Settings: the "Sold by (merchants you opened)" checkbox turns it off; the Settings panel still fits.
- [ ] Buying several items in a row at a vendor (each fires `MERCHANT_UPDATE`): no stutter.

## Merchant prices per character (#75)
No new file: `/reload` is enough. Needs two characters on the account with different standings with one merchant's faction (e.g. Thunder Bluff: Velikopter Tanner Honored, Velikopter Wright Neutral). Keys include the surname (#77): `"<realm>-Velikopter Tanner"`.
- [ ] On Tanner, open Sewa Mistrunner (Thunder Bluff). `/dump CraftWiseDB.merchants[3027].char` = `"<realm>-Velikopter Tanner"` (with the surname; if it is only `"<realm>-Velikopter"`, report it); `items[6530].pc["<realm>-Velikopter Tanner"]` = `{ p = 90, st = 6, t = ... }`; `items[6530].pk[6]` = the same key.
- [ ] Log Wright in, open the same merchant: `pc` now has both characters with their own price and standing; `char` is Wright's key. `/craftwise where nightcrawlers`: "90c with Velikopter Tanner (Honored), 1s with Velikopter Wright (Neutral) · faction Thunder Bluff", cheaper first. Item tooltip "Sold by": "Sewa Mistrunner · 90c Velikopter Tanner (Honored), 1s Velikopter Wright (Neutral) · ...". A character on another realm shows as "Name Surname-Realm".
- [ ] A third character that never opened Sewa: `/craftwise snapshot` on it (or log out once), then on any character `/craftwise where nightcrawlers`: it shows with "(seen at <its standing>)" only when a price at exactly that standing was seen at Sewa; otherwise it is not listed. Log that character in: its live standing is used (no new snapshot needed). A snapshot kept under an old key without surname (`legacy = true`, #77) is not used.
- [ ] Merchants recorded before this change (no `pc`): `/craftwise where` and the tooltip look as before until a character opens them again.

## Known flight paths in the snapshot (#68)
New file `FlightPaths.lua` in the TOC: **full game restart** needed (not `/reload`). Field reference: `docs/snapshot.md`, `flightPaths`.
- [ ] Talk to a flight master (e.g. Crossroads). Then `/dump CraftWiseDB.debug.taxi`: `nodes` = the number of flight points the map shows, no `why`. If `why` is set, report it (`no taxi map ID`, `flight master listed no nodes`: the client's flight map works differently than Blizzard's Forever UI code suggests).
- [ ] Note which window opened: the newer zoomable flight map or the old flat "Flight Map" frame. Both should record.
- [ ] `/craftwise snapshot`, `/reload`: `flightPaths.maps` has the continent (`mapID` 1414 Kalimdor / 1415 Eastern Kingdoms, `map` name) with `t` = now, and one node per flight point on the map with its name. The one you stand at has `state = "current"`, `current = true`.
- [ ] Compare with the map: are flight points you have **not** discovered missing from `nodes`? (Expected: the flight master lists only known ones.) Each listed node should have `known = true`; report any `known = false` or a missing `known`.
- [ ] `x`/`y` × 100 roughly match the flight point's place on the continent map.
- [ ] Discover a new flight point, open that flight master: the continent's entry has the new node and a new `t`; the other continent's entry is unchanged.
- [ ] Another character: its own `flightPaths` (per character), no mix-up.

## Market scope: recipe items and profession books (#67)
No new files: `/reload` is enough.
- [ ] Auctionator full scan at the Horde AH, then `/craftwise market <itemID>` of Recipe: Mithril Head Trout (link it from the AH or bags): it has a price at the Horde AH, not "not a recorded item".
- [ ] Same for the Expert Cookbook (and Expert First Aid, if listed). If it shows "not a recorded item" after a full scan: `/dump C_Item.GetItemInfoInstant(<itemID>)` and report the 6th and 7th values (class, subclass). CraftWise takes a book only when the client files it as Recipe (9) with the profession's subclass (Cooking 5, First Aid 7, Fishing 9); a "Book" (0) subclass is not recorded and the book IDs then need verified data.
- [ ] A Tailoring pattern (or any profession neither you nor the alt has) is still "not a recorded item" after the scan.
- [ ] Profit view, Learn: a not-yet-learned recipe taught by an item that was on the AH shows "To learn" with the AH price and its label (e.g. "typical · Horde AH", or "current lowest, too little history" in the first days).
- [ ] The full scan still finishes without a noticeable stall (each item outside the scope is checked once per session).

## Fishing log (#69)
New file `Fishing.lua` in the TOC: **full game restart** needed (not `/reload`).
- [ ] Fish a few times with fast auto-loot on (default), then `/craftwise fishing`: the zone and subzone are listed with the number of casts, each caught item with its count and value ("vendor", an AH label, or "no price data"). `/dump CraftWiseDB.fishing` shows one entry per cast with `t`, `zone`, `sub`, `map` and `items`.
- [ ] Same with Shift held (or fast auto-loot off in Settings, or the loot window open by hand): still recorded once per cast, nothing twice.
- [ ] Loot a mob or a chest: no catch is recorded (IsFishingLoot is false).
- [ ] Fish in a pool and in open water and compare `obj` in `/dump CraftWiseDB.fishing`: report whether `obj` is set and whether it differs between the two (the GameObject the client names as the loot source; CraftWise doesn't interpret it yet). If `obj` is always missing, `GetLootSourceInfo` gives nothing for fishing loot.
- [ ] Catch a container (trunk, crate, bloated fish), open it from the bags: `/dump CraftWiseDB.fishing["<realm>-<name>"].opened` has an entry with the container's item ID and its contents. `/craftwise fishing` then values the container by its contents ("contents of 1 opened") if it has no price itself. Coins from a container are not recorded.
- [ ] `/craftwise fishing <zone>` (zone or subzone name, any case) lists only that zone.
- [ ] `/craftwise snapshot`, `/reload`: the snapshot has `fishing` with the per-zone summary (`docs/snapshot.md`).

## Character key with surname (#77)
No new files: `/reload` is enough. Make a backup of `WTF/Account/<account>/SavedVariables/CraftWise.lua` first.
- [ ] Log in with Velikopter Tanner. If the old snapshot under `"<realm>-Velikopter"` is that character's class and race, chat says the ledger, snapshot and fishing log now belong to Velikopter Tanner. Otherwise it says they were kept under the old key, marked legacy (once; not again after `/reload`).
- [ ] `/reload`, then check the file: `CraftWiseDB.snapshots` has `"<realm>-Velikopter Tanner"` with `char.name = "Velikopter"`, `char.surname = "Tanner"`; `CraftWiseMarketDB.ledger.chars` and `CraftWiseDB.fishing` use the same key. Report the exact key (it shows which separator the client's `Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR` gives; expected a space).
- [ ] Log in with Velikopter Wright, buy something at a vendor, fish once, `/reload`: Wright has its own `"<realm>-Velikopter Wright"` entries; Tanner's ledger (`/craftwise ledger`) and `/craftwise fishing` are unchanged when you switch back.
- [ ] `/craftwise where <item>` (merchants, #75) shows the standing of the character you are on.

## Subzone text and the line-0 profession (#78)
No new files: `/reload` is enough.
- [ ] Stand in a named place (e.g. Razor Hill, The Crossroads): `/craftwise snapshot`, `/reload`. `location.subzone` is that name and `location.minimapZone` matches the text over the minimap.
- [ ] Stand in the open with no subzone over the minimap: `location.subzone = ""`, `minimapZone` = the zone. If `subzone` is `""` while the minimap shows a place name, report both texts: then `GetSubZoneText` and the minimap disagree on Forever.
- [ ] Fish at a named spot and in open water: `/dump CraftWiseDB.fishing` catches have `sub` with the name, or `sub = ""`; `/craftwise fishing` lists the open-water casts as "(no subzone)".
- [ ] After login the "? 0/0" profession tab is gone, and `/dump CraftWiseCharDB.professions[0]` is `nil`. Open and close every profession window: it does not come back.

## Auction tracker (#81)
New file `Auctions.lua` in the TOC: **full game restart** needed (not `/reload`). Saved in `CraftWiseMarketDB.auctions.chars["<realm>-<name> <surname>"].list`; `/craftwise auctions` prints it.
- [ ] Post a commodity (e.g. 20 Light Leather) with Blizzard's sell tab: one `list` row with `id`, `q = 20`, `unit` = the unit price entered, `kind = "commodity"`, `dep` = the deposit Blizzard showed, `h` = the house key, `durText` ("12 Hours" / "24 Hours" / "48 Hours", whatever the client calls them) and `exp`. If no row appears, `AUCTION_HOUSE_AUCTION_CREATED` didn't fire: report it (`/etrace`, filter AUCTION) — nothing is recorded without it.
- [ ] Post one item with bid and buyout (gear): `bid` and `unit` per item, `kind = "item"`. Post 3 non-stacking items at once (multisell): three rows of `q = 1`. Post a stack of a stackable non-commodity item, if Forever has one: one row, and check `unit` is per item (Blizzard's sell frame totals quantity × buyout).
- [ ] Post with Auctionator's Selling tab too: same rows (it calls the same client functions).
- [ ] Open the AH "Auctions" tab: `ownedAt` is set; rows have `exp` from the list's time left. An auction listed before this version appears with `untracked = true`, `ownedBuyout`: compare `ownedBuyout` with the tab's Buyout column for a stack of more than 1 — is it per unit or per stack? (Untracked rows get no expected payout until that's known.)
- [ ] A sale while online: chat says "A buyer has been found for your auction of X."; the row turns `st = "sold"`, `soldVia = "message"`, and `/craftwise auctions` shows "expected ... after 5% cut (confirmed)" at the Horde AH. Note whether the auction ID came with it (`/etrace`: `AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION` third value) and whether `CHAT_MSG_SYSTEM` fired as well; the row must turn sold once, not twice.
- [ ] Two auctions of one item, one sells: the older one is marked, with `uncertain = true` unless the notification carried the auction ID.
- [ ] A commodity auction partly bought: open the Auctions tab; the bought units split off as `sold` ("owned list (quantity dropped)"), the rest stays listed with the lower `q`. Report whether the tab shows a separate "Sold" entry for them.
- [ ] Cancel an auction: `st = "cancelled"`. Let one expire: `st = "expired"` from "Your auction of X has expired."
- [ ] With the AH open on the Auctions tab, an auction that sold while you were offline (or was cancelled elsewhere) and is gone from the list turns `gone` ("sold or cancelled (uncertain)"); one past its expiry turns `expired` with `why` saying it was inferred.
- [ ] Mailbox: take the money of a sale mail (click, Shift-click, Open All): the row turns `settled` with `received` = the money, `sale`, `cut` (house cut), `saleDeposit` as the invoice shows them; `/craftwise ledger` lists it as sold (kind `ahsell`, `w` = the house). `/dump CraftWiseMarketDB.cutSamples[#CraftWiseMarketDB.cutSamples]` has `house`, `listed`, `received`, `cut`, `deposit`. Check `received = listed + deposit - cut` (Blizzard's invoice maths), and report the cut ÷ listed you see.
- [ ] Take a returned item from an "Auction expired: X" mail and from an "Auction cancelled: X" mail: the row turns `returned`. If not, report the mail subjects exactly: the patterns come from `AUCTION_EXPIRED_MAIL_SUBJECT` and `AUCTION_REMOVED_MAIL_SUBJECT`, which Blizzard's Forever UI code doesn't use (`/dump AUCTION_EXPIRED_MAIL_SUBJECT`).
- [ ] `/craftwise snapshot`, `/reload`: `snapshots[...].auctions` has `active`, `sold` with `expectedTotal`, `returning`, `uncertain`, matching `/craftwise auctions`.
- [ ] Nothing in `CraftWiseMarketDB.auctions` names a buyer.
- [ ] #116: with auctions listed at the Horde AH, `/craftwise auctions` prints "if all listed sell: ... after 5% cut (confirmed)" right after "on its way"; the amount is the sum of the Auctions tab's buyouts minus 5% each. A bid-only listing shows as "not counted: 1 without buyout", one at Booty Bay as "1 with cut unverified". The snapshot has the same numbers in `listedTotal`, `listedNoBuyout`, `listedUnknownCut`.

## Trainer recipes and vendor floor (#83)
No new files: `/reload` is enough.
- [ ] Open the Leatherworking window once, then the Expert Leatherworking trainer (Tarn, Thunder Bluff). `/craftwise debug`: "last trainer: N services, M recorded (K with output and reagents)". K = 0 means `C_TradeSkillUI.GetRecipeSchematic` returns nothing for trainer recipes with the profession window closed: report it with `/dump C_TradeSkillUI.GetRecipeSchematic(1255075, false)` (Mender's Leather Belt).
- [ ] `/reload`, then check `CraftWiseDB.trainer[1255075]`: `fee` (18s = 1800), `required = 150`, `skill = "Leatherworking"`, `line = 165`, `output.itemID` one of 252459-252461 / 252520-252523, `reagents` with counts matching the trainer's recipe tooltip, `at`. Same for the other belts (1255076-1255081). If an entry is missing, `CraftWiseDB.debug.trainer.samples` shows the tooltip ID of the first services.
- [ ] `/craftwise`, Learn view: the seven belts are listed with Trainable at 150 and the fee; the tooltip ends with "Recorded in game at a trainer" and shows "Skill-ups: thresholds unknown" (never yellow/grey numbers).
- [ ] At the AH, run a full scan or search a belt: its price is recorded (`/craftwise market <belt link>` shows data, not "(not a recorded item)").
- [ ] Vendor floor: `/dump CraftWiseDB.sellPrices` has entries after login (scope items). Log out, log back in and hover a scope item in the Bags view before its tooltip loaded: the vendor value shows at once.

## Fishing loot tables (#86)
New file `FishingTables.lua` in the TOC: **full game restart** needed (not `/reload`). Report `/dump` output where asked; everything below depends on what the client shows, nothing is filled in from lists.
- [ ] Loot source: fish once in open water and once from a pool. `/dump CraftWiseDB.fishing["<key>"].catches[#CraftWiseDB.fishing["<key>"].catches]` after each: `obj` and `spawn` set (else `GetLootSourceInfo` gives nothing for fishing loot), and `obj` differs between pool and open water. Report both `obj` values.
- [ ] Clicked object: the same catches have `clk`, and `same = true` for the open-water one (the bobber was both clicked and the loot source). If `clk` is missing with a mouse click: report `/dump UnitGUID("mouseover")` while the cursor is on the bobber, and `/dump C_TooltipInfo.GetWorldCursor()` (does it have a `guid` field?). Repeat with the interact key if you use one (`softinteract`).
- [ ] After one open-water catch with `same = true`, fish a pool: `/craftwise fishing` lists the pool row as "<name> (pool)" or "pool object N (name not seen)", the open-water casts as "open water", and nothing as "water type not known" except catches without a loot source.
- [ ] Pool name: hover a pool before fishing it; after the first catch from it `/dump CraftWiseDB.fishObjects` has its object ID with the name as the tooltip showed it. If the pool stays "name not seen", report the `C_TooltipInfo.GetWorldCursor()` dump while hovering it. Hovering a mailbox or herb stores nothing there.
- [ ] Position: catches have `x`/`y` matching the world map coordinates (percent) within a few tenths.
- [ ] Pool visits: fish one pool until it vanishes, then fish elsewhere: `/craftwise fishing pools` ends with "<pool>: 1 visits ended, N catches per visit (n = 1, ...)", N = the casts that pool gave. Leaving a pool early counts as a short visit (the client doesn't say why a pool is gone).
- [ ] Sightings: after fishing a pool type once, hover another pool of that type without fishing it: `/dump CraftWiseDB.fishing["<key>"].seen` gets an entry with `obj`, `spawn`, `name`, `zone`, `x`/`y`, `how = "tooltip"` (once per pool per 10 minutes). `/craftwise fishing pools` shows "seen N times, K not fished".
- [ ] Find Fish: `/craftwise fishing` second line. Not learned: "not known by this character". Learned (report where it is learned on Forever) and tracking switched on in the minimap tracking menu: "known, tracking on"; off: "tracking off" (updates on `MINIMAP_UPDATE_TRACKING`). Catches made while it is on have `ff = true`.
- [ ] Value per hour: fish for a few minutes; `/craftwise fishing` shows "... per hour (n = <timed>, <minutes> min)" per row. `/craftwise fishing gap 10` changes the session gap (catches further apart start a new session; the first catch of a session is untimed).
- [ ] Filters: `/craftwise fishing pools`, `/craftwise fishing open`, `/craftwise fishing pools <zone or subzone>`, `/craftwise fishing <zone>`.
- [ ] `/craftwise snapshot`, `/reload`: `snapshots[...].fishing` has `spots` (ranked, with `perCatch`, `perHour`, `top`), `pools` and `findFish` (`docs/snapshot.md`). The per-zone item lists of #69 are gone from the snapshot.

## Fishing tab with the local reference (#88)
New files `FishingZones.lua` and `UI\ProfitFrame\Fishing.lua` in the TOC: **full game restart** needed (not `/reload`). Build the reference first (`docs/fishing-reference.md`); the new addon also needs a restart the first time.
- [ ] Character select > AddOns lists "CraftWise Fishing Reference (local)", enabled, no "missing dependency" or "out of date" warning.
- [ ] `/craftwise`: the header has a **Fishing** button; the view buttons don't overlap the subtitle "Profit, gear, loot, fishing".
- [ ] Fishing: one row per zone (fishing icon), best value per catch first, each with "reference · n = ..." or "own catches · n = ...". The summary says "reference: loaded (<date>)". Zone names from the pages match the client's names (a reference zone and your own catches in the same zone are **one** row; two rows with the same zone in different spelling or language means the pages don't match the client language).
- [ ] Items only in the reference show their name and icon once the client has loaded them (the list refreshes by itself); report items that stay "item <id>" or without icon.
- [ ] Values: a fish sold at the AH shows the AH value at the profit house after the cut, others the vendor value; containers (Iron Bound Trunk etc.) show "contents" and the contents per opening in the row tooltip. Stack ranges show "low - high".
- [ ] Click a zone: its loot table (chance, count / recorded, unit value, per catch). "All zones" and right-click on a row go back; "Show own catches" / "Show reference" switches the source when the zone has both. Headers sort in both lists.
- [ ] After fishing a few minutes in a zone: its row gets a value per hour (own catches per hour x value per catch).
- [ ] `/craftwise fishing zones`, `/craftwise fishing zones <part of a zone name>`, `/craftwise fishing ownmin 20` (the zone's row switches to own catches once it has 20); `/craftwise fishing` still prints the #86 tables.
- [ ] Without the reference addon (disable it, restart): the tab shows own zones only and "reference: not loaded", no Lua error.
- [ ] `/craftwise snapshot`, `/reload`: `snapshots[...].fishingZones` has up to 5 zones (`docs/snapshot.md`).

## Every item of a full scan, Auctionator export (#90)
`/reload` is enough (no new file, no TOC change).
- [ ] Auctionator Full Scan at the Horde AH, wait until it says it finished, then wait about 10 seconds more: no stutter while CraftWise stores it. `/dump CraftWiseMarketDB.scans["<realm>|H"][#CraftWiseMarketDB.scans["<realm>|H"]]` shows `kind = "full"` with `items` (scope items) and `lastOnly` (all other items) roughly adding up to the number of items Auctionator reports.
- [ ] An item outside your professions that was on sale (e.g. Silverleaf, a Glimmering Shard, a Waylaid Crate): `/craftwise market <id>` shows "Horde AH: last ..." and "history: none (outside the market scope, latest price only)".
- [ ] `/reload`, then open `WTF/Account/<account>/SavedVariables/CraftWise.lua` (copy it with the game closed): `CraftWiseMarketDB.names` has names for most scanned items (the client names a row only once it has loaded the item). Report how many items have no name.
- [ ] Size of `CraftWise.lua` before and after the first full scan, and `/reload` time. Headless: 10,000 items at one house are about 1 MB, at four houses about 2.6 MB.
- [ ] Run a second full scan an hour later: an item sold out in between shows ", none in the latest full scan" in `/craftwise market`.
- [ ] With Auctionator loaded, hover a reagent CraftWise has no AH price for at the profit house: its tooltip says "Auctionator (house unknown)" and `/craftwise market <id>` ends with "Auctionator (house unknown): <price>, read ... ago". `CraftWiseMarketDB.auctionator.items` fills with the scope items about 5 seconds after login.
- [ ] `/craftwise snapshot`, `/reload`: `snapshots[...].market.houses` lists each house with `lastFullScan` and counts.

## Waylaid crates and Merchant's Favor (#91)
New file `Crates.lua` in the TOC: **full game restart** needed (not `/reload`). Crates are recognised by the name prefix "Waylaid " (English client).
- [ ] Carry a Waylaid crate: `/dump CraftWiseDB.crates` has it with `name`, `tier`, `lines` (the tooltip lines as the client gave them) and `fill` (one entry per "- <count> <item>" line). Report the `lines` of one crate: does any line state the Favor reward? If yes, `reward` and `rewardText` are set; if no, report what the tooltip shows besides the bundle list.
- [ ] Fill a crate (Use, pick a bundle) and report what happens to the item: same item ID, a new "filled" item (`/dump` its link), or does it go away? If a filled item appears, `/dump CraftWiseDB.crates` should list it too when its name starts with "Waylaid ".
- [ ] Turn a filled crate in at Dokimi (Durotar Supply and Logistics, The Barrens). Afterwards the crate that left your bags has `got = { { n = <Favor gained>, t } }`. Report if `got` stays empty: then the crate and the Favor gain were more than 3 seconds apart, or several crate types left the bags at once, or the item turned in is not one CraftWise recognised as a crate.
- [ ] `/craftwise crates`: first line "Merchant's Favor: <n> on this character" (matches the currency tab), then one line per crate: price per Favor (once crate price, a bundle price and the reward are known), crate price with its label, the cheapest bundle with its label ("crafted" when a recipe you know makes it cheaper), the reward with "(tooltip)" or "(seen at N turn-ins)", "you hold N: fill only ... per Favor". Ends with "best to buy and fill" / "best of the crates you hold" when there is one.
- [ ] After an AH full scan (with #90 storing every scanned item): crates on the AH appear in `/craftwise crates` with a crate price, also ones you never carried (their names must be in the client cache; report crates that are on the AH but missing).
- [ ] Bundle names that match no item: shown as "(item not identified)". Report any (e.g. "Handful of Copper Bolts", "Copper Modulator"); they resolve once the item is in the client cache (bags, AH, merchant).
- [ ] Open Pawani (Durotar Supply and Logistics vendor) with the filter on "All": `/dump CraftWiseDB.merchants[248201].items[<itemID>].req` for an item that shows "Requires Durotar Supply and Logistics - <standing>" on its tooltip has `faction`, `standing` (1..8) and `text`; items without that line have no `req`.
- [ ] `/craftwise snapshot`, `/reload`: `snapshots[...].crates` and `.favor` as in `docs/snapshot.md`; `favor.balance` matches the currency tab, `favor.vendors` lists Pawani with all items, Favor costs and requirements.

## Item info for every priced item (#92)
`/reload` is enough (no new file, no TOC change).
- [ ] After a full scan and about 10 seconds more: no extra stutter. `/reload`, then in `CraftWise.lua` (copy it with the game closed) `CraftWiseMarketDB.itemInfo` has an entry for (nearly) every item with a record. Report how many records have no `itemInfo` entry.
- [ ] Pick three entries and compare with the game: `/dump C_Item.GetItemInfoInstant(<id>)` (icon is the 5th value, class 6th, subclass 7th) and `/dump C_Item.GetItemQualityByID(<id>)` must match the decoded `q,i,c,s` (base 36: in Lua `tonumber("2vji", 36)` = 134190).
- [ ] An item searched or browsed only (no full scan) has an entry after closing the AH.
- [ ] A Waylaid Crate or an item you never saw before the scan: present after the scan or after the next login (the client loads it on request).
- [ ] With a non-English client (if available): `names` are in that language; `itemInfo` is the same numbers.

## Market entries packed at logout (#105)
`/reload` is enough (no new file, no TOC change).
- [ ] Have a fishing log with catches that have an AH price at the profit house (the snapshot values them at logout), then `/reload`. In `CraftWise.lua` (copy it with the game closed) every value under `CraftWiseMarketDB.items[<id>]["<realm>|H"]` is a string; report any `{ ["days"] = ..., ["last"] = ..., ["raw"] = ... }` table.
- [ ] Logout and `/reload` take no longer than before, and BugSack shows no CraftWise error at logout.

## Companion app (#94)
Not part of the addon: build `companion/` (see `docs/companion.md`), create an upload token on wow.velikopter.com/me. Headless tests cover the delta, the request shapes (also checked against the Worker's validator), the watcher and retries; the tray and the real file system are untested.
- [ ] Windows: start `craftwise-companion.exe` (built with `-H=windowsgui`): a gold coin appears in the notification area, no console window. Right and left click open the menu; "Open settings" opens `config.json` in Notepad. Put the token in, save, then "Upload now": the first menu line says "Checked HH:MM: sent ..." and wow.velikopter.com shows the houses and prices.
- [ ] Auto-detect: with WoW in `C:\Program Files (x86)\World of Warcraft`, `craftwise-companion -status` (console build) prints the right `CraftWise.lua` without setting `wowPath`. With several account folders it picks the one written last; `account` in the settings overrides it.
- [ ] In game `/reload`: within about 10 seconds the log (`Open log`) shows "upload (file changed)" and only the new data (a few prices, not the whole file). Logout: the same.
- [ ] While the game is writing (logout with a large market DB) the log never shows a parse error that stays; "still being written" is followed by a successful read.
- [ ] Nothing is created or changed in the `_forever_` folder by the companion (the game's own `CraftWise.lua.bak` is from WoW).
- [ ] A second start says "another CraftWise Companion is already running" in the log and exits.
- [ ] Explorer restart (Task Manager > Windows Explorer > Restart): the icon comes back.
- [ ] Quit from the menu removes the icon; no process left in Task Manager.
- [ ] macOS (MacBook): `./craftwise-companion-macos -once` uploads from `/Applications/World of Warcraft/_forever_`; without `-once` it keeps running in the terminal and uploads after `/reload`.

## Recently learned recipes and known recipe IDs (#107)
`/reload` is enough (no new file, no TOC change).
- [ ] Learn a recipe from a pattern (e.g. a Pawani pattern) with the profession window closed: `/dump CraftWiseCharDB.learned` ends with `{ id = <recipe>, how = "event", t = <now>, line = 165 }`. If the entry is missing, Forever doesn't fire `NEW_RECIPE_LEARNED` for patterns: open the profession window, the next scan adds it with `how = "scan"` and `after` = the previous scan's time. Report which of the two happened.
- [ ] Same at a trainer: buy a recipe, check `CraftWiseCharDB.learned` the same way and report `how`.
- [ ] The profit window shows the newly learned recipe as learned right away (before opening the profession window).
- [ ] `/craftwise snapshot`, `/reload`: in `snapshots[...]`, each scanned profession has `known` (ascending recipe IDs, comma-separated; the count equals `recipesKnown`), and `recipesLearned` lists the recipe with name, profession and time.

## Loot toast (#114)
Needs a full game restart (new file `LootToast.lua` in the TOC). On by default; Settings, "Loot toast".
- [ ] Autoloot a mob: one line per item (icon, name in its quality colour, `xN` for stacks) appears at the anchor, stays about 4 s, then fades over 1 s. Same with a hand-opened loot window (Shift + right-click), clicking the items.
- [ ] A mob with several items and coin: one line per item plus one coin line with the exact amount. Each line fades on its own timer (loot a second mob 2 s later: the first lines go first).
- [ ] Area loot of several corpses (or two kills of the same mob quickly): the same item adds to its line (`x` count goes up) instead of a second line; coins add to one coin line.
- [ ] Value text: an item with an AH price (Auctionator or a CraftWise scan) shows `<money> AH`, a vendor-only item `<money> vendor`, both for the whole stack and matching the item tooltip's "Sells for" times the count. An item without any price shows no value. `/craftwise loottoast value off` hides it.
- [ ] Coin: selling to a vendor, taking money from mail and a quest reward do **not** show a coin line. In a group, "Your share of the loot is ..." shows the coin line with your share. If looted coin never shows, `CHAT_MSG_MONEY` and `PLAYER_MONEY` are more than 2 s apart (or the first never fires) on Forever: report it.
- [ ] Another player's loot in a group never shows; quest reward items (pushed, "You receive item:") don't either.
- [ ] Inside a dungeon in combat: if `CHAT_MSG_LOOT` text is a secret value there, lines are skipped without a Lua error. Report whether loot during combat in an instance shows.
- [ ] `/craftwise loottoast unlock`: a blue bar appears; drag it, `/craftwise loottoast lock` hides the bar. `/craftwise loottoast test` shows up to three bag items and a coin line there. `/reload` (and a relog) keeps the position. `/craftwise loottoast reset` puts it back.
- [ ] `/craftwise loottoast duration 8`: lines stay 8 s. `duration 0` and `duration 50` are refused with a usage line. `/craftwise loottoast off`: nothing shows on loot; `on` again.
- [ ] Non-English client (if available): lines still appear (the client's own `LOOT_ITEM_SELF` / `LOOT_ITEM_SELF_MULTIPLE` strings are used).
- [ ] Fast auto-loot (#41) on and off, and with another loot addon: the toast shows the same either way (it reads what arrived, not who looted).

## Money and XP in the logout snapshot (#123)
`/reload` is enough (no new file, no TOC change). Read the snapshot in `CraftWise.lua` (copy it with the game closed, or read it after logging out) under `CraftWiseDB.snapshots["<realm>-<name> <surname>"]`.
- [ ] Note gold, XP (`xp / xpMax` on the XP bar tooltip), rested XP and level, then `/reload`. `char.money`, `char.xp`, `char.xpMax`, `char.rested` and `char.level` match what you noted (not 0), and `ledger.today.money` equals `char.money`.
- [ ] Earn or spend some copper and gain some XP (kill a mob), then log out to the character screen. The snapshot has the new money and XP. Do the same with a quit (`/quit`).
- [ ] `/craftwise snapshot` then `/reload`: the values are the live ones as well (the manual snapshot is overwritten by the logout one, which must agree).
- [ ] Level up, then `/reload`: `char.level` is the new level and `xp`/`xpMax` are the new level's.
- [ ] `ledger.today.change` and `other` are plausible: `money - startMoney`, not `-startMoney`. `/craftwise ledger today` after logging back in shows no day starting at 0.
- [ ] While there, compare `holdings.bags` and `favor.balance` in the logout snapshot with the bags and the Favor shown in game. If either is empty or 0 at logout, the client clears more than money and XP by then: report it on #123.

## Farm tracker (#126)
Needs a **full game restart**: three new files in the TOC (`LootFeed.lua`, `Farm.lua`, `UI/FarmFrame.lua`). Compare with MoneyLooter side by side before uninstalling it.
- [ ] Kill and loot a mob: the CraftWise Farm window opens on its own (Start on first loot is on), state "running", Time counts up once a second. The loot toast still shows the same loot (both read one feed now).
- [ ] Coin equals MoneyLooter's Gold to the copper after a few mobs. Selling to a vendor, taking mail money or a quest reward does **not** add coin.
- [ ] Item list: count, name in quality colour, stack value with `AH` or `vendor` (`AH!` in orange = AH price over a day old). Hover a row: item tooltip plus "Looted this session", value, each, price source. A bind-on-pickup drop says "vendor only" and is valued at vendor. An item without any price shows `?` and is counted under Unpriced, not in Items.
- [ ] Items / Vendor only / AH part (with "stale" part) add up as the hover texts say; Items is at least Vendor only. Gold / hour and Coin / hour appear after the first minute and match (coin + items) and coin per hour of Time.
- [ ] Priciest names the drop with the highest value per unit (hover shows its unit value).
- [ ] x on a row removes it from the totals; looting that item again in the same session doesn't bring it back; after Reset it counts again.
- [ ] Pause: state "paused", Time stops, loot is not counted; Resume goes on. `/craftwise farm pause` does the same.
- [ ] Stop looting for 5 minutes: state "paused (idle)", Time stays at the last loot (the idle minutes don't count); the next loot resumes. `/craftwise farm idle 2` makes it 2 minutes, `idle 0` never pauses.
- [ ] Ride into another zone and loot there: the Zones lines show both zones with their time and gold per hour, the time split at the zone border (`ZONE_CHANGED_NEW_AREA`).
- [ ] `/reload` mid-session: same session, Time continues from where it was (the loading screen is not counted). Log out for a few minutes and back in: Time didn't count the time offline.
- [ ] Reset: the session goes to the history; `/craftwise farm history` lists it (start, time, zone, coin, items, gold per hour, best item). Then `/reload` and read `CraftWiseDB.snapshots[...].farm` in `CraftWise.lua`: `current` / `sessions` as in `docs/snapshot.md`.
- [ ] Drag the window by its title or a free spot; `/reload` keeps the position. `/craftwise farm lock`: it no longer moves ("locked" shown at the top right); `unlock` again. `/craftwise farm scale 0.8` shrinks it, `scale 3` is refused.
- [ ] X button or `/craftwise farm hide`: the window hides, loot is still counted; `/craftwise farm` (or `show`) brings it back with the totals.
- [ ] Settings: "Farm tracker" off pauses the session, hides the window and nothing is counted; on again and Resume. "Start on first loot" off: loot doesn't open a session until Start.
- [ ] In a group: your share of the coin counts, other players' loot doesn't. In a dungeon in combat, if loot lines are secret values they are skipped without a Lua error (same as the loot toast).

## Farm tracker: fishing, loot log, Farm button, key binding (#130)
No new files in the TOC; `Bindings.xml` changed (it is not in the TOC, the client reads it from the addon folder). Restart the game once for this update: whether `/reload` re-reads `Bindings.xml` is not verified.
- [ ] Before fishing: farm a few mobs. The window has no Fishing panel.
- [ ] Fish 10+ casts in a row (pool and open water). A Fishing panel appears under the window with the first catch. Catches = the number of catches (compare `/craftwise fishing`, same count for this stretch); after a minute of fishing `x/h` appears and is plausible (a catch every 15-25 s = 140-240/h).
- [ ] Per catch = (fishing coin + caught items) / catches; caught items valued as in the loot list (hover a fish row there for its value). A catch with coin adds its coin to fishing (hover Per catch: "Coin from fishing"); coin from a mob looted right after does not. An item without a price shows `+N ?` next to Per catch and is not in it.
- [ ] Gold / hour is per hour of fishing time: stand still for 3+ minutes between two casts, the next catch adds no time (the gap is over 2 minutes).
- [ ] Best catch names the caught item with the highest value per unit.
- [ ] Open a container you caught this session (crate, chest): Containers goes to 1, the container leaves the fishing value and its contents (and coin) join it. A container caught in an earlier session is not counted.
- [ ] Fish in a second zone: the right side lists both zones with catches, per catch and gold per hour.
- [ ] Reset: `/craftwise farm history` prints a "fishing:" line under that session; `/reload`, then `CraftWiseDB.snapshots[...].farm.sessions[1].fish` has the block (`docs/snapshot.md`).
- [ ] Loot panel: the "Log" button switches to the loot log: one line per drop, newest on top, time (your clock, HH:MM:SS), icon, count, name in quality colour, value (`?` for unknown), zone; coin drops are their own lines with a coin icon; catches and their coin have the fishing icon. Hover a line: time, zone, count, value, "From a fishing catch.". Scroll with the mouse wheel. "List" switches back; `/reload` keeps the chosen view.
- [ ] `/reload` mid-session: the log is still there. x on a list row removes that item's lines from the log too.
- [ ] Profit window (`/craftwise`): a "Farm" button left of "Profit" opens and closes the farm window; it doesn't overlap the subtitle.
- [ ] Esc > Options > Key Bindings > AddOns > CraftWise: "Toggle CraftWise farm tracker" is listed under the CraftWise header next to Party; bind a key, it opens and closes the farm window (also in combat).
- [ ] Settings (gear) > Farm tracker: the "Farm window" button opens and closes it.
