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
