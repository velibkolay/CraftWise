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
- AH rule: Bags view top right "AH rule: +20%, min 10c" opens a panel: "At least this % more" (5% steps) and "And at least this much more" (0, 1c, 2c, 5c, 10c ... 1g); example line updates; "Defaults" resets. Items under the rule show "Vendor  AH +Xc, too little". Also `/craftwise ahmin <percent> [copper]`. Since #157 the panel is gone: Settings › AH rule (gear in the main window header), same steps, example and Defaults; `/craftwise ahmin` opens it.
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
- Gear button (top right of the CraftWise window) or `/craftwise settings`: on/off, Always / Only with Shift (tooltip redraws when Shift is pressed), each line on/off. Since #157: Settings › Tooltips (the gear in the main window header).
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

Settings (gear button or `/craftwise settings`), "Profit prices": Since #157: Settings › Prices on the Settings page.
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
- [ ] AH rule panel: change the percent or copper, then compare two items near the threshold: the advice flips on the profit house's net price, not Auctionator's. Since #157: Settings › AH rule.
- [ ] Learn view, a recipe sold on the AH (no trainer or vendor): "To learn" shows the AH price and a second line with its label ("typical · Horde AH"); "Where to get it" lists "AH: ..." with the same label instead of "Auctionator". Switch house or basis: the price follows.
- [ ] Profit row tooltip "Sells for" and the Level view sale line show "5% cut (confirmed)" in grey, no orange.
- [ ] Disenchant value: still hidden until the disenchant data exists (#11); when it does, the Bags row tooltip lists each material's price label and cut text.
- [ ] Phase 3 (#26) once a cut is measured: "N% cut measured (n sales)" replaces "(confirmed)"; a measurement that differs from 5% shows both ("..., differs from 5% confirmed") in orange.

## Baganator
- (#318) AH sell frame, Keep warning: mark an item Keep, open the AH, Sell tab, pick it (bag click or drag): "Marked Keep" in teal shows at the top left of the sell frame, for a single item (Item sell frame) and for a stack item (Commodities sell frame). Pick an unmarked item or clear the slot: it goes. The post button and the post itself work as before (post one unmarked item to check nothing is blocked; no taint error in chat). Toggle Keep while the item sits in the frame: the label follows. Settings › Bag slot marks off: no label. Auctionator Selling tab: not hooked on purpose (no public API for its item); check the item's tooltip still shows "Marked: Keep".
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
- [ ] Settings (gear), "Reagent cost": switch Profit to "Paid cost". The summary line says `reagents: paid cost, else AH (N rows with reagents at AH)`; the reagent tooltip header says the same. Buy a reagent at a vendor: its line now shows `paid cost, <n> held` and the row updates without reopening the window. Reagents you never bought show their AH/vendor price with `no paid cost`. Since #157: Settings › Prices, "Reagent cost · Craft / Learn / Level up / Upgrades".
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
- [ ] Item tooltip (bags or link): "Sold by" with up to 2 merchants and "+N more: /craftwise where". Settings: the "Sold by (merchants you opened)" checkbox turns it off; the Settings panel still fits. Since #157: Settings › Tooltips.
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
Since #156 the Fishing view is Gather › Fishing in the main window (`UI\ProfitFrame\Fishing.lua` is gone): the items below about the profit window's Fishing button and tab are checked in "Gather: Farm, Fishing, Crates (#156)"; the reference and slash command items still hold.
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

## Fishing page on the site (#128)
`/reload` is enough (no new file, no TOC change). Then rebuild and restart the companion (its snapshot structs carry the new fields; an old companion drops them and the page shows the snapshot's figures).
- [ ] `/craftwise snapshot`, `/reload`, open `CraftWise.lua`: `snapshots[...].fishing.spots[1].items`, `.waters` and `.pools[1].items` look like `"<itemID> <count> <value> v<vendor>; ..."`; `fishingZones.zones[1].items` holds units per catch; `fishingZones.compare` has your fished zones with `own` (`"<itemID> <hits> <units> <value> ..."`) and, where the reference has the zone, `ref`/`refN`.
- [ ] A container you caught (trunk, crate) ends in ` c` in the lists; an item vendors don't buy ends in ` v0`.
- [ ] After the next upload, `/me/fishing`: values say "with today's Horde AH prices"; a zone with 50+ own catches ranks by your catches with the reference under Compared; the Catch pane lists your share of each item with its interval next to the reference's.

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

## Class names and vendor sell prices (#120)
`/reload` is enough (no new file, no TOC change). The first full scan or login after the update loads every priced item the client hasn't cached, 100 every 0.2 s (about 35 s for 18,000 items) to read its sell price.
- [ ] After a full scan, about a minute and a `/reload`: in `CraftWise.lua` (copy it with the game closed) `CraftWiseMarketDB.itemInfoV = 2` and the `itemInfo` strings have 6 fields (`q,i,c,s,t,p`). Report how many still end in a comma (sell price unknown).
- [ ] Pick three items and compare `p` (base 36) with the sell price in the game tooltip at a vendor, and with `/dump select(11, C_Item.GetItemInfo(<id>))`. An item the vendor doesn't buy (quest item, some bind-on-pickup items) has `p` = `0`.
- [ ] `CraftWiseMarketDB.classNames` and `subclassNames` hold the names the auction house's category list shows (Trade Goods / Herb, Cloth, ...), the same as `/dump C_Item.GetItemClassInfo(7)` and `/dump C_Item.GetItemSubClassInfo(7, 9)`. No empty names.
- [ ] No stutter after the scan beyond what #92 had; BugSack shows no CraftWise error.
- [ ] After the companion uploaded (rebuilt with #120): wow.velikopter.com's category tree shows those names instead of "Tradegoods" / "Subclass 9"; the list has a Vendor column, "Better sold to a vendor" filters it; an item page shows "Sell Price" in the tooltip and the "Auction House or Vendor" block, in both skins.

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
- [ ] `/craftwise loottoast unlock`: the white handle and outline appear (#159); drag the handle, `/craftwise loottoast lock` hides them. `/craftwise loottoast test` shows two bag items and a coin line there, each labelled "test". `/reload` (and a relog) keeps the position. `/craftwise loottoast reset` puts it back.
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
- [ ] (Since #156 the loot log is on Gather › Farm, see that section.) Loot panel: the "Log" button switches to the loot log: one line per drop, newest on top, time (your clock, HH:MM:SS), icon, count, name in quality colour, value (`?` for unknown), zone; coin drops are their own lines with a coin icon; catches and their coin have the fishing icon. Hover a line: time, zone, count, value, "From a fishing catch.". Scroll with the mouse wheel. "List" switches back; `/reload` keeps the chosen view.
- [ ] `/reload` mid-session: the log is still there. x on a list row removes that item's lines from the log too.
- [ ] Profit window (`/craftwise`): a "Farm" button left of "Profit" opens and closes the farm window; it doesn't overlap the subtitle.
- [ ] Esc > Options > Key Bindings > AddOns > CraftWise: "Toggle CraftWise farm tracker" is listed under the CraftWise header next to Party; bind a key, it opens and closes the farm window (also in combat).
- [ ] Settings (gear) > Farm tracker: the "Farm window" button opens and closes it. Since #157 that button is gone: Gather › Farm "Open tracker", the minimap right-click and the key binding open it.

## Containers opened from the bags (#135)
`/reload` is enough (no new file, no TOC change). Turn on the chat's loot messages (the "Loot" filter of the General tab is on by default).
- [ ] **Note the exact chat lines** when you open each of these from the bags: a bloated fish (e.g. Bloated Redgill), a crate, a trunk, a junkbox (or lockbox). Write on #135, per container: the line for each item (copy the wording, e.g. "You receive loot: [Star Ruby]." or "You receive item: [Star Ruby]." or no line at all), and the coin line if it had coin ("You loot 1 Silver ..." or none). CraftWise counts the contents without any of these lines, but the wording tells which path counted them.
- [ ] Open a container that dropped this farm session (a mob's crate or junkbox): in the Farm window the container's row goes down by one and the contents appear (and the toast shows them), each once. Hover the totals: Items went up by the contents' value minus the container's (if it had one). The loot log still has the container's line plus a line per item it gave.
- [ ] Fish up a bloated fish or a crate, then open it (Veli's case: Bloated Redgill with a Star Ruby): the list and the Fishing panel both lose the container and gain the contents; Containers goes to 1; the contents' log lines have the fishing icon. `/dump CraftWiseDB.fishing["<realm>-<name> <surname>"].opened` has the opening.
- [ ] Open a container you already had before the session (Reset first): the contents count as loot of the session, nothing else in the list changes, Containers stays 0.
- [ ] Open a container with full bags: what stays in the window is not counted. Free a slot and open it again: the rest counts, and the container isn't taken off the list a second time.
- [ ] Hand in a quest that rewards an item ("You receive item: ..."): it is not counted and not toasted, also right after opening a container.
- [ ] Loot a mob right after opening a container that gave the same item (e.g. a fish): both count.
- [ ] Fast auto-loot on and off (Settings, "Fast auto-loot"), and opening by hand clicking each item: the same counts.
- [ ] If the contents of a container never count: `/dump C_Container.GetContainerItemInfo(<bag>, <slot>)` on an unopened container shows `hasLoot = true`, and report whether the Farm window's container row went down (then only the contents were missed) on #135.

## Farm tracker: your catch rate (#136)
`/reload` is enough (no new file).
- [ ] Fish with a farm session running: the Fishing panel has a "Your rate" line under Catches. With fewer timed catches in the fishing log than `/craftwise fishing zones` uses as its own-data minimum (50): grey "N timed catches, too few (50)". From 50 on: "141/h", then in grey the water types with 50 timed catches each ("open 163 · pools 88"). The line fits the panel (no overlap with the Zones column, nothing below the panel's edge).
- [ ] Hover it: the explanation, then "All water", "Open water", "Pools" (and "Water not known yet" when there is such a catch) with the rate or "too few", the timed catches and minutes. `/craftwise fishing ownmin 10` lowers the minimum and the line shows a rate at once; set it back with `ownmin 50`.

## Every feature in the UI: Records window, Settings, farm history (#137)
Since #157 (part 2) the Records window and the old Settings panel are gone: Snapshot is Settings › Snapshot, every switch below is on the Settings page, the item views are on Look up › Items. The farm history and slash items still hold.
Needs a **full game restart**: ten new files in the TOC (`UI/Records/*.lua`, `UI/FarmHistory.lua`); `/reload` is not enough.
- [ ] Profit window (`/craftwise`): a "Records" button left of "Farm"; the subtitle now sits under the title; nothing overlaps (title, subtitle, Records, Farm, Profit ... Music, gear, x). Records opens and closes the Records window.
- [ ] Records window: title row, three tabs (Market, Where to buy, Snapshot; Ledger and Auctions moved to Sell in #155, Crates and Fishing log to Gather in #156), toolbar, two summary lines, column headers, rows with icon, name (quality colour) and second line, scroll bar, footer. Drag it by a free spot; Esc closes it; it opens on the tab last used (also after `/reload`).
- [ ] Ledger: the same numbers as `/craftwise ledger` for Since reset, Today and Since login (each button sets what `/craftwise ledger` shows next). Per day matches the "per day" lines of `/craftwise ledger today`. Reset: the first click turns the button orange "Click again"; after 5 s it goes back by itself; two clicks within 5 s reset ("since reset" is empty, Today keeps its rows).
- [ ] Auctions: post 2 items, let one sell: rows "listed" (buyout each, ends in ...), "sold, awaiting mail" (expected gold); the summary's On its way and If all listed sell match `/craftwise auctions`. Hover a row: item tooltip plus posted time, deposit, expected note.
- [ ] (Moved to Gather › Crates in #156.) Crates: opening the tab with a Waylaid crate in the bags lists it like `/craftwise crates` (per Favor, crate price, cheapest fill, reward, held); best to buy and fill marked green; your Favor balance in the summary. Hover: every bundle with its price.
- [ ] (Moved to Gather › Fishing › Log in #156.) Fishing log: rows match `/craftwise fishing` (zone · subzone, water type on the second line, catches, per catch, per hour, top catches); Pools / Open water filter like `/craftwise fishing pools|open`; typing a zone in the box filters like `/craftwise fishing <zone>`; Pool visits lists the pool lines of the slash command; Find Fish state in the summary.
- [ ] Market: without a search the reagents/products of your recipes; typing "linen" finds every recorded item with that name (also items outside the scope: "latest only"); an item ID works. Columns: house, latest lowest, typical (days), units/listings on the AH, seen. Hover: cheapest tiers, 7-day range, disappeared units, as `/craftwise market <id>` prints. Summary: last full scan per house. With hundreds of recorded items, typing stays smooth (no hitch per key); report a hitch on #137.
- [ ] Where to buy: typing "nightcrawler" lists the merchants you opened that sell it, cheapest first, with zone and coordinates, price per character standing, stock, seen; restocks in the tooltip, base price in the summary. Same as `/craftwise where nightcrawler`.
- [ ] Snapshot: "Save snapshot" shows "Snapshot saved." and every section as saved/skipped/error with the time of the save; "Reload UI" reloads the interface (then `CraftWise.lua` on disk has the new `t`).
- [ ] Click an item row in Ledger, Auctions or Market: the item menu opens at the cursor (#159). Item menu (middle-click an item in the bags): "Where to buy" and "Price history" open the Records window on that item. Since #157 the Records window is gone: Look up › Items (see #157 below).
- [ ] Settings (gear): two columns, fits the screen (clamped), nothing overlaps. Right column: Loot toast "Show what you loot", "With value", Move (unlocks: drag the white handle; the button says Lock, click to lock), Test (three sample lines labelled "test"), Reset position, Lines stay - / + (1-30 s). Farm tracker: on/off, Start on first loot, Lock window (the window stops moving, "locked" shown), Pause when idle - / + (never at 0), Window scale - / + (0.5-2.0, the window scales at once), Farm window, Farm history (opens Gather › Farm since #156). Fishing: Session gap - / + (Gather › Fishing › Log's per hour changes), Own catches count from - / + (Gather › Fishing › Spots switches zones between own and reference). Other: Minimap button (hides and shows it), Records. Since #157 the panel is gone: every switch is on the Settings page (Loot toast, Farm tracker, Fishing groups; Minimap button under Look); the Records button went with the Records window.
- [ ] (Since #156 History opens Gather › Farm; see that section.) Farm window: a "History" button left of List/Log. It lays the history over the whole window: one line per finished session (started, time, zone with "+n" for more zones, coin, items, gold per hour, fishing catches); mouse wheel scrolls. Click a session: its stats, zones, top items and fishing on the left, its loot log on the right (newest first, hover for time and zone); a session older than the newest 10 says its log wasn't kept. Back returns to the list; "Session" returns to the live session. The panel (360 px high) is not cut off at the bottom and covers the list completely.
- [ ] All slash commands still do what they did (`ledger`, `auctions`, `crates`, `fishing ...`, `market <item>`, `where <item>`, `snapshot`, `loottoast ...`, `farm ...`, `ahmin`, `minimap`, `party`, `settings`, `debug`).

## Style and Media (#151)
Needs a **full game restart**: new files under `CraftWise/Media/` (fonts and textures) are only found after a restart; no TOC change, no new Lua file. `/craftwise debug style` opens a sample sheet with every font, shape and control (debug only; again to close, or Esc).
- [ ] The sheet has a folded top-right corner (22) in the flap colour with a hard 3 px shadow to the lower right, no soft edge; the card below has its own 14 corner. Nothing is round.
- [ ] Header: gold key block in two tones with a diagonal right edge, two dark planes, the top-right corner left open so the sheet's corner shows; the W key (30) sharp on the gold; "CraftWise" in ExtraBold, dark.
- [ ] Twelve font lines, each in its own face: Brand/Hero ExtraBold, Section/BodyBold/Label Bold, Body/Small/Caption Regular, the Figure lines in the monospaced cut (digits line up). None falls back to the client's default font (that would mean a path or a file is wrong). Glyph line: ▲ red, ▼ turkuaz, → grey drawn as small shapes in line with the digits; · − × come from the font; coin digits gold, silver, copper.
- [ ] Line button and chip: 1 px border; hover turns border and text white. The chip toggles on click. Segmented: "Window" filled white with dark text, the borders between the three buttons are single lines (not doubled). Checkbox: 14 square, filled white with a dark tick. Slider: thin track, white part up to a 12 x 14 thumb, drags in steps.
- [ ] End session (red): the corner lifts from 10 to 14 on hover and settles back; pressing moves it 2 down and back, quickly (80 ms), no fade. Start (white) with a white corner.
- [ ] Rails: four rows on one scale, the first fills its rail to the right end; the loss (Barbaric Shoulders) runs left of the zero line in red; the zero line is a short vertical line, the axis a hairline. Click a row: the nokta hops to it (grows from its middle in about 0.16 s), the bar of the clicked row turns white. Hover a row: the light tooltip with dark text, corner 6 and a hard shadow, under the row.
- [ ] 1 px lines at other scales: `/console uiScale 0.64` (and back to your own), `/reload`, `/craftwise debug style`: borders, hairlines, the axis and the zero line are still exactly one screen pixel, not blurred into two or gone. Change the UI scale in the options with the sheet open: they stay one pixel.
- [ ] W key at 20 (right column) and the gold W key as a whole: edges clean, no dark fringe around the gold sheet or the shapes (texture edges).
- [ ] Report `/dump UIParent:GetEffectiveScale()` on #150 if not done yet.

## Marks on Blizzard frames (#160)
No new Lua file, no TOC change. The corner and key textures are from #151, so a full game restart is only needed if you have not restarted since that one.
- [ ] Item tooltip: a blank line, then the small gold W key and "CraftWise" in gold. Labels grey, values white. "Sell" (or "Sell ×20" for a stack) shows "AH …" and "Vendor …" with the better way white and the other grey. The "AH price" line shows the price source, then the age ("3h old", "today", "2d old"), then the cut. An age over 24 hours is red-orange (a scan older than a day, or Auctionator more than a day old). The W key is sharp at 12 px; if it looks muddy, report on #150 (the 64 px texture is used, see the W key size question in #168).
- [ ] Setting "Only with Shift": nothing of CraftWise (not even the header) until Shift is held; pressing and releasing Shift over an open tooltip adds and removes the section.
- [ ] Profession window: one figure at the right end of each recipe row, 4 units from the edge, in the monospaced font. Measured chances are white ("58%"), formula estimates grey with "~" ("~41%"). Grey (trivial) recipes show nothing. No green and no orange anywhere; the figure does not collide with the recipe name, the skill-up count or the crafts count. Hovering a recipe still adds the "CraftWise: skill-up chance" source line.
- [ ] Merchant frame with marked junk in the bags: a red "Sell junk · 35s" button (folded corner, 28 tall) at the bottom left of the merchant frame, above the tabs. Check it does not cover Blizzard's own buttons (repair, sell all junk) or the buyback slot; if it does, say where it should sit on #160. It lifts its corner on hover. The amount is at most two units (12g 40s). With nothing marked the button is not there.
- [ ] Click Sell junk: the stacks are sold one by one, an orange diamond and "Selling 3 of 5" show to the right of the button, the button waits and is dimmed until done; the chat line gives the total.
- [ ] Combat: with the merchant open, get into combat (a training dummy works): the button is dimmed and does not react; hovering it shows the light tooltip with "Unavailable in combat. It works again when combat ends." Leaving combat re-enables it. Starting a sale and then entering combat stops the sale; what is left stays marked.
- [ ] Bag slots, game bags (combined and single): a mark in Sell on AH shows a gold folded corner (13) on the slot's top right; a junk mark shows a grey corner and the item icon greyed and dimmed to about half. Unmarked items show nothing. (#318) Items marked Keep show a teal (nokta) corner, icon not dimmed; quest items and unmarked items none; off with Settings › Bags and loot › Bag slot marks. Same in Bagnon and Baganator (Baganator: the "CraftWise: marks" corner widget). Marking and unmarking from the item menu updates the slot at once; closing and reopening the bags keeps it. The old red X and the auctioneer icon are gone. Check the corner does not hide the item level or quality border.
- [ ] Baganator (if installed): Settings > Icons lists the corner widget "CraftWise: marks" (new id, so an earlier placement of "CraftWise: sell on AH" is gone): put it in the top right. Gold corner for Sell on AH, grey corner and a dimmed icon for junk. Baganator still draws its own junk coin on junk while the "CraftWise" junk plugin is selected; report whether the coin and the corner together look wrong (#160 question).
- [ ] Bagnon (if installed): same marks as the game bags.

## Loot toast, item menu, minimap button, compartment, W key icon (#159, #166)
Needs a **full game restart**: the TOC's `IconTexture` changed (no new Lua file). Use a character with a few items in the bags and an AH price for at least one of them. Report your UI scale with any finding.
- [ ] Addon list (character select › AddOns) and the addon compartment (the button next to the minimap): CraftWise shows the gold W key, not the gold coin. Clicking the compartment entry opens the CraftWise window (again closes it).
- [ ] Minimap button: a round button of the same size as the client's tracking button, the client's ring, the W key centred inside the ring with nothing cut off or spilling over the ring. Hover: the light tooltip with dark text, "CraftWise", then "Click: open", "Right-click: farm tracker", "Drag: move" (no Shift-click line until the docked layout, #161). Click: the CraftWise window opens on the page it was on. Right-click: the farm tracker shows; again: it hides. Shift-click: same as a click for now. Drag: it moves around the minimap rim and stays there after `/reload`. Settings › "Minimap button" and `/craftwise minimap` hide and show it.
- [ ] With MinimapButtonButton (or a similar collector) installed: the CraftWise button is collected and all clicks still work there.
- [ ] Loot toast: loot three different things (one with an AH price, one vendor-only, some coin). Each line is a dark strip 28 tall with a small folded corner and a hard shadow to the lower right; 6 apart; newest on top. Only the newest line's corner is turkuaz, the older ones grey. The second line is a bit faded (75 %), the third and older ones more (50 %); the dark fill shows the world behind it (70 %), while icon and text of the newest line are fully solid. Each strip is as wide as its text plus a little room at the right for the corner.
- [ ] Line content: 18 icon, the item name in its quality colour (grey, white, green, blue, purple; no brackets), "×count" in grey monospaced digits, the value in gold/silver/copper digits with at most two units and a small grey "AH" or "vendor". The coin line reads "Coin" and the coins. Settings "With value" off: no value and no source word.
- [ ] Lines leave after "Lines stay" (Settings) with the short fade-out; looting the same item while its line is fully shown adds to that line, which moves to the top and becomes the turkuaz one.
- [ ] Settings › Loot toast › Move: a white handle "Loot toast · drag to move" with a thin white outline below it where three lines go; drag the handle, Lock hides both. Test: two bag items and a coin line, each with a grey "test" at the end. Reset position puts it back.
- [ ] Item menu (middle-click an item in the bags, or click a row in the Bags view or a Records row): opens at the mouse cursor; a dark sheet 200 wide with a folded corner and hard shadow; the item name in bold; Keep, Junk, Sell on AH, Normal; the current mark has the turkuaz diamond and a lighter row behind it and is bold. A hairline, then Where to buy, Price history, Recipes using this. Hover a row: it lights and the light tooltip explains it. A choice closes the menu; so do Escape and a click elsewhere. Since #157 there are no Records rows: any row of the main window.
- [ ] Item menu on a quest item: "Quest items can't be sold" (grey, not clickable) in place of Junk and Sell on AH; Keep has the diamond.
- [ ] Item menu › Where to buy and Price history open the Records window on the item (Look up › Items replaces this with #157). Done in #157: Look up › Items.

## Farm tracker in the Origami look (#158)
No new Lua file and no TOC change: `/reload` is enough. The tracker uses #151's fonts and textures, so a game that hasn't been restarted since #151 needs that restart first. Compare with the board "Farm tracker states, mini mode, loot toast" (canvas page Screens).
- [ ] No session (`/craftwise farm reset`, then `/craftwise farm show`): a 260 wide sheet with a dark grey dog-ear (22) and a hard shadow; "Farm" in ExtraBold, "no session" in grey; "Press Start, then loot." and, with Start on first loot on, the grey line under it; buttons Start (white, folded) and History (line). Nothing overlaps; the bottom padding equals the sides roughly (14).
- [ ] Start: the dog-ear turns orange, "running" orange, the timer at the top right counts "0:00:01", "0:00:02" … once a second and stays clear of the dog-ear. Gold per hour shows "—" for the first minute, then big monospaced digits in coin colours (gold and silver only, never three units). Caption: "per hour · total … · <zone>".
- [ ] Loot a few mobs: the split bar (6 tall) shows coin gold, white (items at AH) and grey (vendor only) parts with 2 unit gaps, as wide as their shares; the three figures under it line up with their labels. With AH prices over a day old the "Items at AH" label is red. Hover each column, the gold per hour and a loot row: our cells show the light tooltip under them, a loot row the item tooltip with the session lines.
- [ ] Loot list: at most 5 rows of 24, icon 16 with trimmed edges, name in its quality colour (grey, white, green, blue, purple), "×N" grey, value in coin colours; an unpriced item says "no price". With more items or unpriced ones the footer says "+ N more · M unpriced"; Log · History sit right. The tracker's height follows its content (no empty band at the bottom, nothing cut off).
- [ ] Pause: the dog-ear turns grey (rule-strong), "paused" and the timer grey, the timer stops; buttons Resume (white) and End session (line). Resume goes on. Stop looting 5 minutes: "paused · idle 5 min", caption "per hour · resumes with your next loot"; the next loot resumes.
- [ ] End session (red, its corner lifts on hover): the session goes to the history; the tracker shows "no session".
- [ ] Fish with a session running: the Fishing card (folded card, corner 14) appears under the split bar with Catches, Per catch, Per hour (catches per hour) and "Best catch: <name in quality colour> · your usual rate N/h" (or "your usual rate: N of M timed catches" below the minimum); long lines wrap inside the card and the card grows with them. Hover the card: the light tooltip with gold per hour of fishing, zones and your rate per water type. Not shown without catches.
- [ ] Log, "+ N more" and History open Gather › Farm in the main window (#156; the loot panel and the history beside the tracker are gone): see "Gather: Farm, Fishing, Crates (#156)".
- [ ] Drag the tracker by any free spot, its rows, hero or split: it moves (unless locked in Settings › Farm tracker); `/reload` keeps the position. Settings scale 0.5 to 2: it scales at once and its hairlines stay one pixel.
- [ ] The tracker hides with the profit window's Farm button, the key binding, Settings › "Farm window" or `/craftwise farm hide` (it has no close button of its own, as on the board). Since #157: the key binding, the minimap right-click, Gather › Farm or `/craftwise farm hide`.

## Farm tracker: mini mode and fade (#164, #163)
No new Lua file and no TOC change: `/reload` is enough. Compare with the board "Farm tracker states, mini mode, loot toast" (canvas page Screens).
- [ ] Full tracker: the – button (a short grey bar, white on hover with the light tip "Mini mode") sits between the timer and the dog-ear. With "paused · idle 5 min" showing, the state word and the timer don't touch, and the timer stays clear of the – button.
- [ ] Click –: the tracker becomes a strip 30 tall with a 12 corner in the state colour (orange running) and the hard shadow; its top left corner stays where the full tracker's was. Running: timer grey, gold per hour in coin colours (mono SemiBold), "/ h" grey; padding 12 left, 26 right, 12 between the parts; the strip is as wide as its text and the text is centred vertically.
- [ ] Right-click the strip: grey corner, "Paused" and the session total; right-click again resumes (orange, timer counts on). Stop looting 5 minutes: "Paused" as well. `/craftwise farm reset`: "no session" in grey with the dark corner; right-click does nothing.
- [ ] Hover the strip: the light tip "Farm" with Click / Right-click / Drag lines. Drag the strip: it moves and does not open the full tracker on release (unless locked in Settings, then it doesn't move). Click without dragging: the full tracker opens at the strip's top left corner, at full width.
- [ ] In mini mode, Settings › "Farm window" hides and shows the strip.
- [ ] `/reload` in mini mode: the strip comes back where it was. Settings › Farm tracker › "Mini mode" switches both ways and shows the current mode. Scale 0.5 and 2 in Settings scale the strip too.
- [ ] Settings › Farm tracker › "Fade farm tracker to 40 % away from the mouse" is off on a fresh install. Turn it on and move the mouse away: the whole tracker (sheet and text) fades to 40 % in about 0.14 s; move onto it: back to 100 % as fast. Moving between rows, buttons, the hero and the split never flickers; leaving through a row or a button at the edge fades it.
- [ ] The same with the mini strip. Hide the tracker and show it again with the mouse elsewhere: it appears at 40 % without a flash at 100 %. Turn the setting off: 100 % at once and it stays there.

## Main window shell (#153)
Needs a **full game restart**: five new files in the TOC (`UI/Main/Shell.lua`, `States.lua`, `List.lua`, `Frame.lua`, `Pages/Bridges.lua`) and three new textures (`cw-gear`, `cw-dock`, `cw-close`); `/reload` is not enough. Until the pages move (#154–#157) every sub-page is a "bridge": it says it has not moved yet and its button opens the old window there.
- [ ] `/craftwise`, the minimap button, the addon compartment and the new key binding (Key Bindings › AddOns › CraftWise › "Toggle CraftWise", listed beside "Toggle CraftWise farm tracker") all open and close the same window. Fresh profile (or `/run CraftWiseDB.settings.ui = nil` + `/reload`): it opens as a window, centred 40 above the middle of the screen, on Make › Craft.
- [ ] Window: 880 × 600, folded top-right corner (22) with the hard shadow; header 56 tall: the gold key block with the W key (30) and "CraftWise" sharp, five tabs (Make, Sell, Gather, Look up, Music) starting right of the key block, the active one white with a 3 unit bar under it. Right side, 30 from the edge: gear and × (no dock button yet: it appears with #161). Hover each: the light tooltip ("Settings", "Close").
- [ ] Sub bar 46 tall under a hairline: the sub-pages in Bold 13, the active one white with the turkuaz nokta before it. Click another: the nokta hops to it (grows in about 0.16 s, no fade). Music has no sub bar.
- [ ] Gear: Settings shows, the gear is filled white with a dark icon and no tab is active; the gear again goes back to the section you came from.
- [ ] No sub-page is a bridge any more (Make since #154, Sell #155, Gather #156, Look up, Music and Settings #157): none says "has not moved here yet".
- [ ] Drag the window by the header: it moves; close and reopen (and `/reload`): same place, same section and sub-page. Esc closes it. The window works in combat (open, switch tabs, close).
- [ ] UI scale 0.64 (`/console uiScale 0.64`, `/reload`): hairlines under the sub bar stay one pixel; nothing overlaps in the header. Report `/dump UIParent:GetEffectiveScale()` on #150 if not done yet.
- [ ] Texture edges: gear, dock (once shown) and × are crisp at 14 / 11 units, no dark fringe.
- [ ] AH status, Scanning, Stale, the list, hero card and the other states only show on pages that use them; they are checked with the first real page (#154).

## Sell: Bags, Auctions, Ledger (#155)
Needs a **full game restart**: four new files in the TOC (`UI/Main/Pages/Sell.lua`, `Bags.lua`, `Auctions.lua`, `Ledger.lua`); `/reload` is not enough. The profit window has no Bags button any more, the Records window no Ledger or Auctions tab.
- [ ] Sell › Bags with a mix of items (something to auction, something for a vendor, a grey you marked Junk, an item marked Keep, a quest item): groups in this order: Sell at the AH, Sell to a vendor, (No price), Keep, Junk. Each group row: Bold title, "N items · reason" in grey, the group total right, a 2 unit white rule under it; no column header row. Item rows 36 tall: icon 22, name in its quality colour, "×count", the grey note line ("22s each · vendor 1s 50c · used in 9 of your recipes"), your mark as a small outlined tag (Keep / Junk / AH), the value in coin colours on the right.
- [ ] Hero "What your bags would bring": the total in big mono digits under the label, the three parts on the right (AH after cut with a white square, vendor gold, junk grey) and the 6 unit split bar along the bottom of the card, parts in the same order. With an item without any price: "1 item without a price not counted" under the total. The bar's widths look right against the figures.
- [ ] Chips in the sub bar: My crafting materials and Show kept turn white when on and filter the list (the footer right counts what is hidden); Sort bags sorts the bags and reads "Sorting" in orange while it runs. Hover Sort bags: the light tooltip.
- [ ] Click an item: the item menu at the cursor (Keep, Junk, Sell on AH, Normal, Where to buy, Price history); choosing Junk moves the row to Junk with a Junk tag at once. Right-click and middle-click open the menu too; Shift-click puts the link into chat; hover shows the item tooltip with the CraftWise lines. Footer: "Click an item: … In your bags: middle-click." (or Alt + right-click, as set in Settings).
- [ ] An item with no price: value "—", hover it for the reason; note "no price" in grey. After `/run CraftWiseMarketDB.scans = {}` (or a fresh house): the No prices state with Show vendor-only profits. With the newest scan over 24 h old: the Stale card, and the AH figures in the notes carry "3 d" in red.
- [ ] Sell › Auctions with something listed, sold and expired (post with Blizzard's auction house): three folded cards side by side (no card behind them): "On its way · in the mail" (sold, after cut and deposit back), "If all listed sell" ("N listed · 1 without a buyout not counted" with a bid-only listing), "Returning" ("1 item", "expired, deposit lost 15s"). Sub bar right: "<name> · owned list read 12 min ago" (open the Auctions tab of the auction house once to read it).
- [ ] The list: Sold first (newest sale first), then Listed (ending soonest first) with an orange diamond before "Listed", then Returning in grey. When: "ends in 11 h", "sold 19 min ago", "expired · 2 min ago". You get: buyout less the cut plus the deposit back; compare it with the sale mail's money (`received` in `CraftWiseMarketDB.auctions`). Hover a "—": why it is not counted.
- [ ] Mail delay for #155: note how long after "A buyer has been found" the sale mail arrives, and how long after expiry the returned item arrives. With those verified the When column can say "mail in 41 min" as the board shows.
- [ ] Sell › Ledger opens on Per day: one row per recorded day, newest first, Today with the turkuaz nokta and the selected background; Start, Spent (−), Received (+), the money change rail (zero at 30 %, losses red to the left, all rows on one scale, today's bar white) and the signed figure. Hero "Last N days": the money change over those days, Spent, Received, Not from logged trades ("loot, quests, mail").
- [ ] Chips Since reset, Today, Since login: the item list (Item, Bought at, Bought, Sold, Net) and that period's hero; the chip you pick stays after a `/reload`. `/craftwise ledger today` opens the page on Today (and still prints to chat); `/craftwise auctions` opens Sell › Auctions.
- [ ] Reset ledger (footer, right): the first click turns it red "Click again"; wait 3 s: back to "Reset ledger", nothing reset. Click twice quickly: the page switches to Since reset and its list is empty.

## Gather: Farm, Fishing, Crates (#156)
Needs a **full game restart**: three new files in the TOC (`UI/Main/Pages/Farm.lua`, `Fishing.lua`, `Crates.lua`), and three left it (`UI/ProfitFrame/Fishing.lua`, `UI/Records/Crates.lua`, `UI/Records/FishingLog.lua`); `/reload` is not enough. Compare with the boards "Gather › Farm", "Gather › Fishing" and "Gather › Crates" (canvas page Screens).
- [ ] Gather has three real pages (Farm, Fishing, Crates); none says "has not moved here yet". The profit window has no Fishing button any more and its view buttons don't overlap; the Records window has three tabs (Market, Where to buy, Snapshot).
- [ ] Farm, no session: the hero card reads "Farm tracker" / "No session running" with the hint under it and a white Start button right; no Coin / Items at AH / Vendor only columns. Start: the session starts, the card's dog-ear and label turn orange ("Running now · 0:00:01"), the timer counts once a second while the page shows, and gold per hour appears in big mono digits after the first minute. The three columns line up under their labels, "Open tracker" (line button) and "Pause · End in the tracker" sit right and don't touch the columns. Pause in the tracker: label "Paused · …" grey, grey dog-ear.
- [ ] Farm list: "Finished sessions" + note; the open session on top (Started and Time orange while it runs), then finished sessions newest first: Started "Wed 11 · 21:04", Zone (+N more zones, "· fishing"), Time "1:48", the gold-per-hour rail (all bars on one scale, the opened row's bar white), Total, Per hour (bold). Headers sort; the open session stays on top. Empty history: the grey line "No finished session yet. End one in the farm tracker and it shows here."
- [ ] Click a finished session: the card opens under it (nokta on the row): Top items (quality colours, ×N), Zones (time), Split (coin, AH · vendor, unpriced, stale AH part in red, fishing line), "N loot lines kept" and Loot log right. Hover lines: item tooltip, or the light tooltip for zones and the split. Loot log: the log in the same place, newest first (time, icon, name ×N, value with AH/vendor, zone; catches with the fishing icon), "Show 50 more" for long logs, Summary goes back. A session older than the newest 10: "loot log not kept" with the reason on hover. The card's height fits its content (nothing cut off, no empty band) at UI scale 1 and 0.64.
- [ ] Click the open session: Zones, Split, Loot log, then "Items · N" with every looted item, its value and ×. Hover ×: the light tip "Remove from this session". Click ×: the item leaves the list, the tracker and the log; it is ignored until the session ends. Right-click an item line: the item menu; Shift-click: the link in chat.
- [ ] Farm tracker: Log opens the main window on Gather › Farm with the open session's loot log; "+ N more" with its items; History (link, and the no-session button) on Gather › Farm. Settings › Farm history does the same.
- [ ] Fishing › Spots: chips Spots / Log | All water / Pools / Open water at the sub bar's right, the chosen ones white; no hero card. "Where to fish" with the rate line: "gold per hour = value per catch × your catch rate (N catches/h, your last 90 days) · Fishing <skill>"; below the own-catch minimum "~N catches/h from n of m timed catches" and the Per hour figures carry "~"; without any timed catch "no catch rate yet". Zone, Your data (grey under the minimum; hover says which side the zone shows), Gold per hour as a tick with a thin grey range line (stack range), Per catch ("no price" when nothing is priced; hover: source, range, unpriced), Per hour (bold). Footer: the minimum and "reference: loaded (date)".
- [ ] Click a zone: "Reference · n = …" or "Own catches · n = …", then per fish: icon, name in quality colour, Share of catches (grey bar + %), Share of money (gold bar + %), Each (coin colours with AH/vendor/contents); junk (grey items) as one line "Junk: …" with "vendor". "Show own catches" / "Show reference" switches the side when the zone has both. Items the client hadn't loaded get their name and icon by themselves.
- [ ] Pools / Open water: Your data counts only that water's own catches and the rate line names that water's rate ("in pools"); the choice stays after `/reload`.
- [ ] Fishing › Log: "Fishing log · last 90 days · N catches · sessions: …"; one row per zone · subzone and water (open water, pool name, not known yet) with catches, per catch, per hour (bold, "not timed" grey); pools only seen have a row with "—". Click a pool row: "Visits: …" and the items caught there with share and value. Footer: the Find Fish state. Same numbers as `/craftwise fishing`, `/craftwise fishing pools|open`.
- [ ] Crates: the sub bar says "Merchant's Favor on this character: N". Two folded cards side by side (Best of the crates you hold / Best to buy and fill) with name and the line under it; "None priced" when there is none. Rows: icon, crate name with "10 Favor · measured" (or "· tooltip", or "reward not seen yet") under it in grey, Crate, Fill ("no price" grey when no bundle has a price), the cost-per-Favor rail (shorter = cheaper), You hold, Per Favor (bold). Carry a crate and open the page: it shows up within a few seconds. Click a row: crate price, every bundle with its price (cheapest marked), the reward and how it was measured, what is missing in red.
- [ ] Every Gather page in combat: open, switch chips and rows, no error. Hairlines and rails stay one pixel at UI scale 0.64.

## Crate Favor guide (#176)
Needs a **full game restart**: `Data/CrateFavorGuide.lua` is a new file in the TOC; `/reload` is not enough.
- [ ] Gather › Crates: a crate you never turned in and whose tooltip states no reward (Apprentice/Journeyman/Expert, not Artisan) shows "5 Favor · guide" (value by rank and kind) under its name, and is ranked by cost per Favor. Opened, the Reward line says "guide (Forever Mastery, Forever Changes), not measured". An Artisan crate still says "reward not seen yet".
- [ ] After one turn-in of that crate the note changes to "N Favor · measured" and the guide value is no longer used; a crate whose tooltip states the reward says "· tooltip".

## Look up, Music, Settings (#157, part 1)
Needs a **full game restart**: four new files in the TOC (`UI/Main/Pages/Items.lua`, `Upgrades.lua`, `Music.lua`, `Settings.lua`), and three left it (`UI/ProfitFrame/SongPicker.lua`, `UI/Records/Market.lua`, `UI/Records/Where.lua`); `/reload` is not enough. Compare with the boards "Look up · Items", "Look up · Upgrades", "Music" and "Settings" (canvas page Screens).
- [ ] Look up, Music and the gear open real pages; none says "has not moved here yet". The profit window has no Upgrades or Music button and its view buttons don't overlap; the Records window has only Snapshot left.
- [ ] Items: the search box (300 wide, white border) sits right in the sub bar with its grey hint. Type a name: the left list shows recorded items (AH and merchants), exact name first; an item ID or a link works too. Click into the box, then Shift-click an item in the bags: its link lands in the box (not in chat) and the list shows it. Enter picks the first row.
- [ ] Items left list: chips Your recipes / Recent (Watched only once #165 is in). Rows: icon, name in quality colour, "214 listed" / "3 listed · thin" / "vendor only" under it, typical price in coin colours, the 7-day change under it (▲ +4 % red, ▼ −12 % turkuaz, "latest only", "vendor"). The chosen row is on the selected tint. Right-click: item menu; Shift-click: link in chat; hover: item tooltip. Recent keeps the last items you looked at across `/reload`.
- [ ] Items card: 40 icon, name (quality colour), "Trade Goods · stacks of 20 · you have 6 in bags, 40 in the bank" (hover: which places were counted); the four figures (Typical big, Lowest now, On the AH, 7 days) line up; hover each: its reason (median of n days, cheapest tiers, 7-day range, disappeared units, other houses, Auctionator).
- [ ] Items chart (**Line objects**): the typical price is a solid white line, the lowest a dashed grey one, the nokta sits on today's point, the top and bottom prices and "Thu 6" / "Today" read clearly; lines are crisp at UI scale 1 and 0.64. If `CreateLine` fails in this client the page errors on drawing the chart: report it (the fallback, seven 4 unit bars, is covered by the specs only).
- [ ] An item outside the market scope (e.g. a grey item seen in a full scan): "latest only" on the row and the Typical figure, no chart, the line saying why.
- [ ] Items "Used in" (profession · recipes · known, then the known recipes ×N) and "Where to buy" (merchants with prices, hover: the full `/craftwise where` lines), vendor sell price, your last purchase from the ledger.
- [ ] Item menu (bags, any row): Where to buy and Price history open Look up › Items on that item. On gear: "Don't suggest as upgrade" / "Suggest as upgrade again"; not on other items.
- [ ] Upgrades: no column header row; group rows "You can craft" (your professions and skill) and "From the auction house" (when you last searched) with the 2 unit white rule. Rows 40 tall: icon, name in quality colour with "known · reagents in bags" / "learn: trainer 45s" / "4 listed · 2 h ago" under it, Slot, "replaces …", Gain ("+6 AGI +4 STA · +31 armor"), Cost (coin colours; "~" when a reagent has no price). Hover Gain: every stat difference; Cost: reagents and what you hold / the listing.
- [ ] Upgrades AH group: with the AH closed, "open the auction house to search" right in the group row and the "Search AH for these" chip grey and not clickable. Open the AH: the chip works; click it: it reads "Searching 3 of 15 · Shoulder" in orange while it runs, rows appear as slots answer. Dismiss a row from the item menu: it goes; Settings › Bags and loot › Show dismissed upgrades lists it again, desaturated with "dismissed".
- [ ] Music: rows for Party and every profession: name and skill, Song and Video dropdowns (white border on hover, ▾), Next cast Resume / From start (Party has none), the volume slider. Song dropdown: "No song" and every song; Play previews, Stop stops, a song added by name has ×; choosing closes it; a click elsewhere or Escape closes it and stops a preview. Same for Video.
- [ ] Music: cast a profession with a song: the orange Playing card appears within a second ("Playing · while you cast Leatherworking", song, "chunk 7 of 22 · resumes here next cast", the time bar moving), with Music on and Party! on the card; they move back to the list bar when nothing plays. Party! starts the party (card "Playing · Party", button "Stop party"). Add a song by file name under the rows: message under the box.
- [ ] Settings: gear filled; group list 170 wide on the darker ground, the nokta on the open group; rows label left, control right, hairlines between. Every group: Look, Prices, Tooltips, Bags and loot, Loot toast, Farm tracker, Fishing, AH rule, Snapshot. Each control changes what it says (see the spec in `tests/settings_page_spec.lua`); nothing overlaps at UI scale 1 and 0.64, the Snapshot grid (18 sections, two columns) fits.
- [ ] Settings › Look: Scale slider applies when you let go (70–130 %), the window resizes in place; Lock position stops dragging the header; Close with Escape off: Escape no longer closes the window; Minimap button hides/shows it; Reset window positions puts the main window, the farm tracker and the loot toast back in their default places.
- [ ] Settings › Bags and loot › Bag slot marks off: the gold and grey corners leave the bag slots (open bags refresh), on brings them back.
- [ ] `/craftwise settings` opens the Settings page. Every page above in combat: no error.

## Background alpha per window (#162)
No new file in the TOC, so `/reload` is enough. Compare with the Colours paragraph of #150.
- [ ] Settings › Look: three sliders, Background · Main window / Farm tracker / Loot toast, 20–100 %, defaults 96 / 86 / 70 %. Drag the main one: the window's sheet, its cards (hero card, list cards, Crates, Auctions) and the header planes get see-through while you drag; text, icons, rails and the nokta stay fully opaque. Compare the shadow: it fades with the sheet.
- [ ] The header's baked planes carry the gold key block too (one texture): check that it fading with the planes looks right at 20 % (open question in the PR).
- [ ] Farm tracker slider: the tracker's sheet and its fishing card follow while dragging, also in mini mode. With "Fade to 40 %" on, away from the mouse it ends at about alpha x 0.4 (the two multiply); hovering brings it back to the slider's value, not to 100 %.
- [ ] Loot toast slider (Look and Settings › Loot toast, same value): with no toast on screen the three test lines appear and follow the slider; with real loot on screen those strips follow. The newest line's turkuaz flap stays solid.
- [ ] The values survive `/reload`. Item menu, the Music dropdown and tooltips are not affected (always solid).
- [ ] Every window at UI scale 1 and 0.64: sliders do not overlap other rows.

## Items watch list (#165, part 1)
Needs a **full game restart**: new file `ItemWatch.lua` in the TOC (before `UI/Style.lua`); `/reload` is not enough.
- [ ] Item menu (right/middle click in the bags, any row): a "Watch" line after Price history; click it and the menu closes. Open the menu again: the line reads "Stop watching"; click it and the item is no longer watched. Quest items can be watched too.
- [ ] Look up › Items: chips Watched / Your recipes / Recent (a fresh install opens on Your recipes). The Watched chip lists the watched items by name; empty it says "Watch an item from its card and it shows here."
- [ ] Items card: the Watched toggle (top right) is white when on. Click it: the item joins or leaves the Watched chip at once. Watch an item from the item menu while the Items page is open on it: the card's toggle follows without reopening the page.
- [ ] `/reload`: the watched items are still there. `SavedVariables/CraftWise.lua` has `["watch"] = { [itemID] = <Unix time>, ... }` (account wide, the same file for every character).

## Make: Craft, Learn, Level up (#154)
Needs a **full game restart**: five new files in the TOC (`UI/Main/Pages/Make.lua`, `MakeTooltips.lua`, `Craft.lua`, `Learn.lua`, `LevelUp.lua`), and nine left it (the whole `UI/ProfitFrame/` and `UI/Main/Pages/Bridges.lua`); `/reload` is not enough. The old profit window is gone: Profit, Learn and Level were its last views. Compare with the boards "Window layout · Make › Craft" (page One design), "Make › Learn", "Make › Level up" and "States" (page Screens).
- [ ] Make has three real pages (Craft, Learn, Level up); no page anywhere says "has not moved here yet". The Records window's "Main window" button (it said "Profit window") opens the main window. Since #157 the Records window is gone, and with it that button.
- [ ] Sub bar right: the profession chip "Leatherworking 191 ▾" (name white, skill grey, caret) left of the 160 wide filter box ("Filter recipes" in grey until you type), 18 apart. Click the chip: a folded menu under it with your crafting professions (no gathering ones), the current one with the nokta and the dark background; pick another: all three pages switch, and it is still chosen after `/reload`. Click elsewhere or Esc closes the menu; the chip again closes it too.
- [ ] Type in the filter: the rows filter by recipe or reagent name ("light leather" lists the recipes using it) on all three pages; Esc / Enter leave the box. Raise a skill (or `SKILL_LINES_CHANGED`): the chip shows the new skill without reopening.
- [ ] Craft: hero "Best craft right now": name, "Yellow · skill-up 58% · short 4 Heavy Leather" (colour word in the skill colour; "~41%" for the formula; nothing short: no short part), the bar in the middle (grey cost, then the white profit, 6 tall, along the sale) with "cost …" / "sells … · AH" under it, the profit in big mono coin digits on the right. No priced recipe: "—" and the reason.
- [ ] Craft list: "N recipes" + "by profit"; chips Unlearned and Hide unpriced right, white when on. Rows 38: output icon, name in the profession window's colour (unlearned: white), the profit rail (zero line at 18 % of the column, all bars on one scale, losses red to the left, the opened row's bar white), "1g 50s → 2g 70s AH" grey (the → is a small texture in line with the digits; "vendor", "AH gross", "· thin", stale "3 d" in red), the profit bold right ("+" coin colours, "−…" red, "—" grey without a price; hover the "—" for the reason). Footer: "Prices: typical · Horde AH · reagents: AH" left; hidden and cut-unverified counts right.
- [ ] Click a Craft row: the folded card under it (nokta on the row): up to four reagents per line, each "10 Heavy Leather", the total in coin colours, "AH · have 6" grey; Price history (line button) right opens Records › Market on the crafted item (Look up › Items once #157 lands). Hover a reagent: its item tooltip; right-click: its item menu. Click again closes; one row open at a time.
- [ ] Hover a Craft row: the crafted item's tooltip, then one CraftWise section (W key header): skill-up thresholds, reagents with their source, the buy list, Sells for with Vendor / AH net (used one marked), auction houses. The item tooltip's own CraftWise lines do not appear a second time. Right-click: the item menu of the crafted item; Shift-click: its link in chat.
- [ ] Learn: hero "Best recipe to learn": name, "Trainer · <name> · you meet skill 190", "Learn cost" with the fee in the middle, "Pays off after" over "3 crafts" right. List "N recipes you don't know" by profit; columns Recipe (white), Skill (orange above yours, "unknown" grey), Where to get it (grey, "+N" more), To learn ("unknown" grey), Profit/craft, Pays off ("8 crafts", "—"). Chips Fits my skill and Hide unpriced; the footer right counts what they hide. Click a row: where to get it (up to six lines) above the reagents.
- [ ] Level up: hero "Best skill-up right now": "Yellow · earns +1g 20s per craft after selling it", "Skill-up chance" with "58%" and an 8 tall bar, "measured · 12 of your crafts" (or "estimate · community formula"), "Per skill-up" over the figure. List "Known recipes that still give skill" + "best value per skill-up first: earning, then cheapest", right "Sale: AH after cut …". Chance: 60 unit bar (white measured, grey estimate) and the percent ("~41%" grey). Net/craft and Per skill-up: "+" earns, "−" red costs. Footer: "Chance: … Grey recipes are left out." and the reagent basis and crafts recorded. Hover: the chance maths.
- [ ] States on each Make page: a profession whose window you never opened: the W key, "Open your <profession> window once." (the chip stays to pick another). Fresh market data (`/run CraftWiseMarketDB.scans = {}`): "No auction house visited yet." and Show vendor-only profits. A scan running at the AH: orange header status and progress line, rows keep their figures, rows without a profit show a skeleton bar stepping between two greys. Newest scan over 24 h old: the Stale card, "3 d" in red after AH figures.
- [ ] Item menu › Recipes using this (on a reagent in your bags): the main window on Make › Craft with that profession, Unlearned on and the reagent's name in the filter box.
- [ ] All three pages in combat: switch pages, chips and rows, no error. Hairlines and rails stay one pixel at UI scale 0.64; long recipe and reagent names are cut, not overlapping.

## Old windows retired, gaps closed (#157 part 2)
Needs a **full game restart**: five files left the TOC (`UI/Records/State.lua`, `Snapshot.lua`, `Frame.lua`, `UI/Settings.lua`, `UI/AHRule.lua`); `/reload` is not enough.
- [ ] No old window is left: no Records window, no old Settings or AH rule panel. The gear in the main window header opens the Settings page; nothing else opens a separate settings panel.
- [ ] Header AH status (on Make, Sell › Bags and the other price pages): hover it. A light tooltip "Auction houses" lists every house CraftWise recorded at, your faction's first, the profit house marked "(profit)": "Horde AH (profit): full scan 2 h ago · 1 240 items, 980 with history", a neutral house you only browsed "no full scan"; then "Auctionator (house unknown): N items read" when CraftWise read Auctionator prices. Compare the counts with what Records › Market's summary line showed before.
- [ ] With Auctionator installed and its prices loaded, on a character or house where CraftWise has recorded nothing (e.g. set Auction house for profit to your faction on a fresh character): Make › Craft shows the list, not "No auction house visited yet."; the header says "Horde AH · Auctionator prices"; AH figures say "Auctionator (house unknown)" on hover. Disable Auctionator and `/reload`: the page says "No auction house visited yet." again.
- [ ] Make › Craft, Learn and Level up: open a row. Right of the reagents: Price history, and under it "Open in profession window". Click it: the profession window opens on that recipe (with the profession window closed, and with it open on another recipe). On Learn, for a recipe you don't know yet: report what the client does (opens it greyed, or nothing). Nothing overlaps the reagents with four reagents on a line or with where-lines on Learn.
- [ ] Slash commands open their page: `/craftwise market <link>` and `/craftwise where <link>` (Shift-click an item into the chat box) open Look up › Items on that item; `/craftwise where <name>` puts the name in the search box as typed (capitals kept); `/craftwise ledger`, `auctions` (Sell); `crates`, `fishing`, `fishing pools`, `fishing zones`, `farm history` (Gather); `settings`, `snapshot`, `ahmin`, `loottoast …`, `minimap`, `farm lock`, `fishing gap 5` (the matching Settings group). `/craftwise farm` still only toggles the tracker, `/craftwise party` (the party key's macro) only toggles the party, `/craftwise debug` only prints.
- [ ] The video clip window (Music, a profession with a video): a dark sheet with a thin rule round the clip (the old flat panel is gone); it still drags and remembers its place.
- [ ] Recipe tooltips with reagents you hold ("Your reagents", "Crafts possible", "To buy for N crafts"): the same colours as before (grey notes, yellow warnings, green crafts possible).
- [ ] An old `CraftWise.lua` from before this change: after login the saved `settings` no longer has `view`, `sortKey`, `bagSortKey`, `recordsTab` and the other keys only the old windows used; everything else (AH rule, prices, costs) is unchanged.

## Docked layout (#161)
Needs a **full game restart**: new file `UI/Main/Docked.lua` in the TOC (after `UI/Main/Frame.lua`) and a new texture `Media/cw-undock.tga`; `/reload` is not enough. Compare with the board "Docked layout, on your screen" (canvas page One design). Items, Settings, Music and the multi-card heroes have no docked board yet: what they do docked is provisional (#161 Q1–Q4 in the PR) and may change.
- [ ] Fresh profile (`/run CraftWiseDB.settings.ui = nil` + `/reload`): the window opens as Window. The dock button (left of ×) docks it to the left edge; with `/run CraftWiseDB.settings.ui.lastDocked = "dockRight"` it docks right. The sheet slides in from its edge in about 0.2 s, without fading or bouncing. The undock button (frame with a title bar line, tooltip "Undock to a window") puts the window back where it was.
- [ ] Docked: 380 wide, 20 from the screen edge, 20 from the top and the bottom of the screen at UI scale 1 and 0.64 (resize the game window too: the sheet follows the screen height). Not draggable; Lock position makes no difference. Background alpha (Settings › Look) applies to the sheet as in the window.
- [ ] Shift-click on the minimap button docks and undocks; with the window closed it opens docked. Its tooltip lists "Shift-click: dock / undock". Settings › Look › Layout: Window / Docked left / Docked right swaps in place from either layout (the docked Settings page has the same control across the row).
- [ ] Docked header 64: the narrow gold key block with the W key (34) sharp, "CraftWise" white on the dark plane at x 128 with the AH status under it (Scanning orange with the nokta before it, Stale red bold), gear, undock, × right; the five section tabs on their own row under it (gap 20, active white with its 3 unit bar on the hairline). The tabs, gear and buttons click; the status never runs under the gear.
- [ ] Sub bar 40, padding 18. Make, Sell and Gather: the page tools (profession chip and filter box, Bags chips, Ledger periods, Fishing chips, the Crates / Auctions / Upgrades / Farm lines) sit in their own row above the list, the list title over its note in the list header with the chips right. Nothing overlaps at UI scale 0.64 (Fishing's five chips are the widest).
- [ ] Hero cards stacked: label, name left and the figure right on one line, the rail or bar under, the sub-line last (Craft: cost and sells under the bar; Learn: "Pays off after" top right; Level up: the chance bar and how it was found). Bags: the total, the three-part bar, one line per part with its square; Ledger: the change, then Spent / Received / Not from logged trades; Farm: gold per hour, Coin / Items at AH / Vendor only, Open tracker (Start without a session). Auctions and Crates: their cards one under the other (provisional Q4).
- [ ] Rows 44 in two lines: icon, the name over its rail (or a grey note line), the result right in bold with the sub-figure under it; all rails of a list on one axis. Bags and Upgrades group headers with the 2 unit rule; the Bags mark as a small tag under the value; Auctions' orange diamond before "Listed"; Ledger's today with the nokta and the selected tint. Click opens a row in place (card 18 from both edges; Make: two reagents per line, Price history and Open in profession window side by side under them; Farm: Top items, Zones and Split one under the other; Fishing: the share bars under each fish); right-click item menu, Shift-click link, hover tooltip and the "—" reasons work as in the window. Mouse wheel scrolls.
- [ ] Look up › Items docked (provisional Q1): the list across the sheet with the chips at its top and the search box (170) in the sub bar; click an item: its card across the sheet (figures two by two, the chart, Used in over Where to buy; wheel scrolls it) and Back in the sub bar in place of the search box; Back returns to the list. Item menu › Price history opens the card.
- [ ] Settings docked (provisional Q2): one list with every group under its header and 2 unit rule, each label over its control, segmented controls across the row; the wheel scrolls it; every control still writes its setting. Music docked (provisional Q3): the Playing card stacked (time bar across, Music on and Party! under it), each profession row with Song, Video, Next cast and Volume one under the other; the dropdown menus open next to them.
- [ ] States docked: First run (the profession chip stays above it), No prices, Stale card, Scanning skeletons in the result spot, Error with Reload UI and Show error text all fit 380 without running over the edge.
- [ ] Switch layouts on every page, with a row open: the same row stays open; nothing from one layout stays drawn in the other. In combat: dock, undock, switch pages, no error.

### Make › Craft › Vendor check (#185)

- Open Make › Craft on a profession with known recipes, turn on the Vendor check chip: the list holds only crafts with a vendor profit above 0, best first, each sale tagged "vendor"; with Unlearned on/off the list changes accordingly. Hero label reads "Best vendor craft right now".
- A craft whose reagents are all sold by vendors (thread, vials, flux, dyes; visit the merchants once so prices are recorded) and whose product a vendor buys for more than that shows "· loop" after the sale. Buy the reagents, craft once, sell to a vendor: the gold gained matches the vendor profit shown.
- Hover a row: the "Vendor check" section lists each reagent with AH price, vendor price and which was used, then the vendor sale and profit. A product no vendor buys never shows up with the chip on; a reagent without a vendor price shows "not sold by a vendor".
- Chip off: nothing changes except the loop tag on loop rows. After a client patch changing sell prices, the vendor sale follows the client's price.
- No new file: `/reload` is enough.

### Vendor loop alert and basket (#186)

- **New files (Loops.lua, Basket.lua, Pages/Basket.lua): restart the game completely, `/reload` is not enough.**
- Settings › Vendor loops: Loop alert on, Smallest profit per craft at 0. Visit the AH with a full scan (or a merchant once) while a known craft has a vendor profit: one toast "N vendor loops / M vendor profits" with the best craft and its profit per craft, about 10 s. Browsing more AH pages right after gives no second toast; a new or clearly better (+50 %) find does. Click the toast: Make › Craft opens with Vendor check on. Shift-click: the best craft goes into the basket and Make › Basket opens.
- Raise Smallest profit per craft above the best find: no toast. Loop alert off: no toast.
- Make › Craft, open a row: "− +" and "Add N to basket" under the reagents. Make › Basket lists the crafts (open one: − + +10 Remove), then AH lines, vendor lines, items without a price, and what is already in the bags; the hero shows the AH and vendor totals and the expected vendor profit.
- Put some of the reagents into your bags: those lines move to "in bags" (BAGS_CHANGED), no reload.
- With Auctionator: the Auctionator list chip creates/replaces the shopping list "CraftWise basket" (check it in Auctionator\x27s Shopping tab: exact names with quantities). Without Auctionator: an AH line opens to a search string to copy.
- Open a merchant that sells a vendor line (plain gold, sold one at a time): open the line, Buy N is enabled; one click buys exactly that quantity (more than a stack = several BuyMerchantItem calls in that click, check the bags). Sold in lots, with a currency cost, sold out, or not enough gold: the button stays off and says why. Closing the merchant disables it. Nothing is bought without the click.
- Item menu: Open basket opens Make › Basket. Clear basket empties it.

### Disenchant values and Disenchant check (#190)

- **TOC changed (OptionalDeps: Disenchantry, new Data/DisenchantGuide.lua and Disenchant.lua): restart the game completely.**
- Without Disenchantry, or before any disenchant: Make › Craft › Disenchant check lists crafts of uncommon or better armour and weapons with the sale tag "disenchant · guide"; the tooltip says "Classic table (guide)" and "not measured on Forever". Settings › Disenchant says the guide is used.
- With Disenchantry loaded: disenchant an uncommon or better armour or weapon (Enchanting open), `/reload`. The same item now shows "disenchant · N samples" (or "few samples" below Settings › Disenchant › Few samples below), the tooltip lists the materials with chance, quantity, unit price and "measured, N disenchants". Another item of the same quality, type and item-level bracket shows "pooled N".
- Check the sample key in `WTF/Account/<account>/SavedVariables/Disenchantry.lua` (`disenchantSamples`): `<version>:<build>:<itemID>:<quality>:<baseItemLevel>:<classID>:<normal|salvager>`; CraftWise reads it as is and never writes it. After a client patch (new build) the old samples are ignored until new ones exist.
- With the Arcane Salvager buff (1283701) active the tooltip says so and only salvager samples count; without the buff the normal ones. Without salvager samples the guide answers.
- Sell › Bags: a disenchantable item with a value shows in the Disenchant group when that pays most; its value matches the Craft tooltip per item. Vendor check and Disenchant check cannot both be on (turning one on turns the other off).
- Enchanter wands (Lesser Magic Wand etc.) get no value.

## Performance recorder: stutter when opening bags or a vendor (#194)

- **TOC changed (new Perf.lua): restart the game completely.**
- Settings › Debug. Press **Record**, then do the thing that stutters: open the bags (all of them, or the combined bag), close, open a vendor, close it. Press **Stop**. The report appears under the buttons; **Copy report** opens it in a box with the text selected (Ctrl+C, paste it into the issue).
- While Record is on the button says Stop and is lit. With Record off CraftWise times nothing (the recorder is a single `nil` check in the event dispatch).
- Report, top to bottom: frame count and worst frame; the slowest frames with how much of each was CraftWise handlers and which handler was slowest; CraftWise events, handlers (`EVENT File.lua:line`), module callbacks and the BagIcons hooks, each with total ms, count and longest run; the other addons' slow ticks (over 5 / 10 / 50 / 100 ms) during the recording from `C_AddOnProfiler`, and the top addons by recent average and by peak since login.
- Check that a slow frame (over 30 ms) shows up in the list when you open the bags, and that "CraftWise inside it" tells whether CraftWise or another addon (Auctionator, Bagnon, Disenchantry, ShortestPathForever) holds the time. If every handler shows ~0 ms while the frame is long, the cost is outside CraftWise handlers: read the addon table.
- If the handler labels read `#12` instead of `Bags.lua:40`, `debugstack` returned an unexpected format: report the line.
- No Lua error from `C_AddOnProfiler` calls (all wrapped; a missing function only leaves its lines out).

### After the first recording: vendor price news and item loads (#194)

- Open the same vendor twice, and flip its pages: with unchanged prices CraftWise does no price work after the first visit (`PRICES_CHANGED` fires only for a vendor price that is new or different, and Crates no longer rescan the auction house items for it). Record once more: `MERCHANT_SHOW` should be a few ms at most and `Crates.lua` should not show under Module callbacks. The bag-frame and vendor hitches that remain are listed in the report under "Addons".
- The report now ends its CraftWise section with "CraftWise asked the client to load N items (M more skipped)" and the callers. Every load the client answers is an event that every addon with a `GET_ITEM_INFO_RECEIVED` handler runs; compare N with the event counts (`GET_ITEM_INFO_RECEIVED`, `ITEM_DATA_LOAD_RESULT`) of the same recording.
- **Hitches from Baganator or Syndicator are outside CraftWise.** If the slowest frames show "CraftWise inside it" at a few ms and the Addons table lists Baganator / Syndicator (or GearQuestForever, ShortestPathForever) with ticks over 50 or 100 ms, the time is in those addons. CraftWise cannot fix it; report it to them, or try bags with only one of them enabled.


## Make › Craft: sort by profit % (#197)

- No TOC change; `/reload` is enough.
- Make › Craft: the new **Return** column (profit / cost to craft) shows next to Profit; click its header to sort. The list bar note reads "by profit %". Check a 1g-cost craft with 10s profit (10 %) sits below a 10s-cost craft with 15s profit (150 %). Rows with no price or a free craft (no cost) stay at the bottom, also when the sort is reversed.
- The hero card "Best craft right now" follows the chosen sort and shows the % in its line. Switch back to Profit and it returns to the highest absolute profit.
- `/reload`: the chosen sort is still there (saved in `settings.ui.sort`).
- Vendor check and Disenchant check: the % uses that mode's profit over the same cost.
- Hover a craft: **Return** section with the %, then either "N units disappeared in 7 days at prices up to the typical (sold or expired)", "No units seen disappearing in 7 days", or "No market history for the product at this house". It is a measured count from CraftWiseMarketDB, never a speed.
- Vendor loop toast and Make › Basket: the best return per gold is first (toast text names the top find; the basket lists crafts by %).

## Look up › Items opens cheap, Price history goes to the site (#202)

- No TOC change; `/reload` is enough.
- Veli's market DB (the one that froze the game): open Look up › Items (Look up tab, or `/craftwise market`). It opens without a freeze and the list shows at once, whatever the size of `CraftWiseMarketDB`. Turn on Settings › Debug › Record first, open the page, then Copy report: the hook "Look up › Items: Refresh" should be a few ms (before: seconds on a large DB, see the PR).
- Make › Craft: open Goblin Deviled Clams (or any row) and click **Price history**: no freeze. A small popup shows `https://wow.velikopter.com/item/<itemID>` selected in a box, with a "Ctrl+C to copy" line. Ctrl+C then paste it in a browser: the item's page opens. Escape closes the popup; so does Close. Typing in the box does not change the address.
- Item menu (middle-click an item in the bags, or a row of the main window) › Price history: the same popup for that item. Where to buy still opens Look up › Items on the item.
- Hover Price history in the opened Make row and in the item menu: the tooltip says it shows the item's page on the site.
- Look up › Items: type in the search box (also one letter): the list answers without a hitch. Click the "Your recipes", "Recent" chips and scroll: rows fill in as they scroll into view.


## Merchant window: buy a typed quantity, basket lines at the vendor (#201)

- **TOC changed (new UI/MerchantBuy.lua): restart the game completely.**
- **Several `BuyMerchantItem` calls in one click (not verified yet).** Forever caps one purchase at 20 (seen in game). At a merchant that sells Hot Spices (Naal Mistrunner, Thunder Bluff): Alt+click the item, type 45, press Buy. Expect 45 in the bags after the one click (calls of 20, 20, 5), no error, one "Bought 45 × ..." line in chat. If only 20 arrive, the later calls were dropped: report how many arrived and whether a second click gets the rest, then the purchase has to wait for an event between calls.
- Alt+click on a merchant item (page 1 and after flipping to page 2): the panel on the right of the merchant window shows that item's name. A plain click and Shift+click do what Blizzard does and leave the panel alone. If Alt+click picks nothing, the `MerchantItemNItemButton` names or IDs differ in Forever: report it.
- Type a quantity: the line under the box shows the total (`45 for 1g 12s`) without buying. Empty box: "Type a quantity." and Buy is grey.
- Refusals buy nothing and say why: more than you can pay ("Not enough gold"), more than a limited item has ("Only N left at this merchant"), more than fits in the bags ("Bags have room for N", free slots of ordinary bags plus room in partial stacks), a merchant that sells in lots or for a token or currency ("Sold in lots of N" / "Costs more than gold").
- Close the merchant window with the quantity typed, open it again: the panel is empty (nothing is remembered, nothing buys on open).
- Basket (Make › Basket): add a craft whose reagent this vendor sells, open the vendor: under "Basket: sold here" each such line shows `453 × Hot Spices` with its Buy button; one click buys the line's quantity (the same stack-sized calls). After the purchase the line drops out when the bags hold enough (Basket recomputes from the bags).
- Opening the vendor with an empty basket does no basket work; with a basket and several bag changes the vendor window should not stutter (record it with Settings › Debug if it does, `MerchantBuy: item click` and `BAGS_CHANGED` show there).
- **Merchant slot read (fix, #201):** Forever has no `GetMerchantItemInfo` global; `ns.MerchantItemInfo` (Merchant.lua) reads `C_MerchantFrame.GetItemInfo` for Basket, Prices and SourceRecorder. With a merchant open, Make › Basket must draw without "Basket could not be built", and a vendor line's Buy shows "Buy N" (not greyed) for a gold-only item.
- **Count box and Max (Make › Craft opened row, Make › Basket craft row):** type a number into the box next to − / +: Enter or clicking elsewhere applies it (the "Add N to basket" label / the basket count follow), Escape puts the old number back, 0 or empty puts it back, above 9999 becomes 9999. **Max** sets the count to what the reagents you already hold allow, ignoring reagents a vendor sells (Goblin Deviled Clams with 597 Tangy Clam Meat: 597, Hot Spices not counted). It is hidden when every reagent has a vendor source and greyed when a held reagent is missing.

- Opening a vendor is quick (#201 follow-up): with a basket of a few crafts (Make > Basket) open Naal Mistrunner
  (about 20 items) and a big vendor (about 100). No stutter. Settings > Debug > Record, open the vendor, Stop: no
  `MERCHANT_SHOW` handler over a few ms; "MerchantBuy: basket plan" and "Merchant: record" show up as separate hook
  lines, each once per open. Buy a stack: bag events do not re-plan per event (one "MerchantBuy: basket plan" a
  moment later), typing in the quantity box runs no plan.

- Items sold in lots (#217): Mild Spices (lot of 5) from a spice vendor. Type 10: the panel says "10 for <2 lots' price>" and Buy buys 10 (two lots). Type 7: "Type a multiple of 5", Buy greyed. A basket line of 7 shows "10 x Mild Spices (2 lots of 5)" and its Buy buys 10. **Unverified, check these:** (1) a merchant's stock number on a lot item (numAvailable) is read as lots, so 2 left = 10 items; (2) a call above the merchant's GetMerchantItemMaxStack is never made: with a max of 20 and lots of 5, calls are at most 20 items; (3) gold spent equals price per lot x lots.

## Look up › Items: first open in slices (#202 follow-up)

- No TOC change; `/reload` is enough.
- Log in and wait about 20 s before opening anything: the index and the "Your recipes" list build in small slices after login (Settings › Debug › Record shows "Look up › Items: prebuild" and many short "build slice" and "used-in slice" hooks, none over a few ms). Then open Look up › Items: it appears without a hitch and the list is already there.
- Open Look up › Items right after login (before the 20 s): the list says "Loading…" for a moment, then fills in by itself. The game doesn't hitch. Click a recent item meanwhile: its card opens, "Used in" says "Loading…" and fills in.
- At the auction house, scan, then open Look up › Items: no hitch (the older list stays while a new one builds).
- `/craftwise market <part of a name>` on a fresh login still works (it waits for the whole build once, in one frame; a visible hitch there is expected).

## Craft log (#205)

- **Craft log (#205, new file Pages/Crafted.lua: restart the game completely, `/reload` is not enough):** craft something with Create All (say 5 of a recipe with a yield of 1): Make › Crafted lists the recipe with today = 5 and the total up by 5; hover the row, or the row in Make › Craft: "Crafted N · today 5", a line for this character with today / 7 days / total, and (when the recipe had crafts before this version) "Before the log (undated): N". The old total, e.g. Goblin Deviled Clams 1532 in `skillups`, is in the undated line and in N, never in today. A craft that gives no skill-up (grey) and a craft at skill unknown still count. A recipe that makes 2 or more per craft (e.g. a stack of bandages or potions): check `CraftWiseDB.crafted.chars[<char>][<recipeID>].days[<YYYYMMDD>]` in the SavedVariables after /reload: `{crafts, items}`, items = crafts × yield. A recipe with a yield range adds crafts only (items stay 0); note the recipe so the received quantity (TRADE_SKILL_ITEM_CRAFTED_RESULT) can be read once its payload is verified. Log in on a second character and craft: the tooltip shows both, each with its own today. Make › Crafted works in the docked layouts too. "Profit of all crafts at today's prices (approx.)" shows in the Make › Craft tooltip only for rows with a profit and is crafts × today's profit per craft, not what was earned.
- **Make › Crafted: search, filters, sorting (#205 follow-up, no TOC change, `/reload` is enough):** open Make › Crafted with no crafts today: the list starts with the largest totals (Goblin Deviled Clams above Barbaric Harness), not the alphabet. Click Today / 7 days / Total / Recipe: the list sorts, the same header again flips it, the arrow and the list note follow; `/reload` keeps the choice. Type part of a name in the filter box: only matching recipes stay (the box is the one of Make › Craft). The profession chip offers All professions and the professions that have logged recipes; the character chip (list bar) offers All characters and each character in the log. With one character chosen the undated counts drop out and the footer says so. The hero and the list count follow the filters.
- **Craft speed (#209, no TOC change, `/reload` is enough):** craft 25 of one recipe with Create All. In the Make tooltip of that recipe (Craft or Crafted row): under the log lines "Speed  N sec per craft · M per hour", "Profit per hour at today's prices" (a dash when the row has no profit) and "measured over N crafts". Nothing shows before 5 gaps have been measured. The gap should be about one cast (a few seconds); stopping for more than 30 s and crafting again must not raise the figure (a break is not counted: after Create All, wait a minute, craft again, check the number stays near one cast). Crafting two recipes alternately still measures each recipe's own gaps. Make › Crafted: columns Sec/craft, Crafts/h, Profit/h sort like the others, recipes without a measurement show a dash and stay last. Profit per hour follows Settings › Prices › Profit cost basis: with "Paid cost" the line says "Profit per hour at paid cost" and uses what you paid for the reagents (a note when only part of the units have a paid price or a reagent is at AH, and a `*` after the figure in Make › Crafted); with AH it says "at today's AH prices". Switch the basis and compare with the profit of the same row in Make › Craft: the per-craft profit there times crafts/hour is the figure here. In the SavedVariables `crafted.chars[<char>][<recipeID>].speed` is `{ n, sum, gaps }` with at most 50 gaps.
- **Make › Craft: All professions (#211, no TOC change, `/reload` is enough):** open the profession dropdown on Make › Craft: the first entry is "All professions" (Learn and Level up don't have it). Choose it: one list with the recipes of every profession you have (not gathering), each row with its profession name in grey after the recipe name; sorted by profit (or Return %) across professions; the hero "Best craft right now" is the best of all. The Unlearned, Hide unpriced, Vendor check and Disenchant check chips and the filter box act on the whole list. Open a row: "Open in profession window" opens the right profession; "Add to basket" puts the craft in the basket under its own profession. A recipe two professions can make shows twice. `/reload`: the choice stays; pick one profession and it leaves All. Switching to Learn or Level up shows a single profession. Open and close Make › Craft a few times with All on: no hitch (Settings › Debug performance recorder lists "Make: all professions rows").
- **Item mark "Sell to vendor" (#214, no TOC change, `/reload` is enough):** open the item menu on a craft's row in Make › Craft or Make › Crafted (right or middle click), e.g. Kaldorei Spider Kabob: the new line "Sell to vendor" sits after Sell on AH (quest items don't have it). Choose it: the row's sale shows "vendor (marked)" instead of AH, the profit, Return % and, in Make › Crafted, profit/h drop to the vendor value; the Make tooltip still lists the AH price. Pick Normal: back to the AH. An item with no known vendor price shows a dash, never the AH value. Hover the item in the bags: "Marked: Sell to vendor". Sell › Bags advises Vendor for it and still shows the AH value. The farm tracker and loot toast value it at the vendor price. At a merchant, "Sell junk" counts and sells items with this mark too (its tooltip says so), but not items you Keep. Marks exclude each other (Junk, Sell on AH, Keep, Sell to vendor).
- **Craft log profit and recipe payback (#215, no TOC change, `/reload` is enough):** craft 10 of a recipe that has prices (reagents and sale). Make › Crafted: the new columns Profit today / Profit 7 days / Profit total show the sum, each craft valued when it was made (reagents at the Profit view's cost basis, the sale with a "Sell to vendor" mark respected); the hero card shows "Estimated profit today" and the 7 days in its line. Change the AH prices or the basis and craft again: the earlier crafts keep their old profit. Hover the figures: "Estimated profit at craft time ... Not money received" and "Profit known for K of N crafts"; a `*` after the figure means some crafts had no price. A recipe crafted only before this version, or with no prices, shows a dash. The tooltip (Make › Craft or Crafted row) lists "Profit at craft time (est.)", the split per character, and for a recipe whose item you bought (vendor or AH, in the ledger, or a recorded vendor price) "Recipe cost 50s: 32s to go" and, once the total profit covers it, "paid back". A recipe without a known cost shows no payback line. `/reload`: the figures stay. SavedVariables `crafted.chars[<char>][<recipeID>].days[<day>]` is `{ crafts, items, profit, known }`.
- **"Sell to vendor" mark drops when the item sells on the AH (#222, no TOC change, `/reload` is enough):** mark an item "Sell to vendor", list it at the auction house and let it sell. Nothing happens while it is listed, when you cancel it or when it expires, and not at the "sold" message alone. When you take the sale mail's money, one chat line says "[item] sold on the AH: 'Sell to vendor' mark removed", and the item is valued at the AH again (Make rows, Make › Crafted, Sell › Bags refresh; the item menu shows Normal). An item without the mark prints nothing.
- **Junk and Sell to vendor are one mark (#227, no TOC change, `/reload` is enough; this supersedes the Sell to vendor checks above):** the item menu has no "Sell to vendor" line any more; "Junk" says it is valued at its vendor price everywhere (the AH price still shown) and sold with Sell junk. An item you had marked Sell to vendor before this update shows as Junk after it (menu, bag tooltip, Sell › Bags), valued at its vendor price in Make rows (tag "vendor (junk)"), Make › Crafted profit/h, farm and loot values; Sell junk at a merchant sells it. A Junk item with no vendor price shows a dash. When a Junk item sells on the AH (the sale mail's money taken), one chat line says "... sold on the AH: Junk mark removed" and it is valued at the AH again.
- **Make › Crafted fits (#228, no TOC change, `/reload` is enough):** open Make › Crafted at the default window width: eight columns (Recipe, Today, 7 days, Total, Speed, Profit/h, Profit today, Profit total), the last one ends before the scrollbar, nothing is clipped and no stray "+" sits at the row ends. Speed reads "3.1 s · 1,168/h" and sorts by crafts per hour. Profit 7 days is in the hero card and the tooltip, no longer a column. Switch to the docked layout (dock button): the hero line ("7 days ... · profit 7 days ...") and the footer fit on one line without "..."; each row shows the total on the right and "today N · profit" under the name.

## Market history for every profession (#232)

- No TOC change; `/reload` is enough. The market scope now holds the reagents and outputs (and the recipe items) of **every** profession in the bundled recipe data, whether a character of this account knows it or not: Alchemy, Blacksmithing, Enchanting, Tailoring as well as Cooking, Leatherworking, First Aid, Engineering, Mining and the gathering ones. About 2,700 items instead of about 1,400 (headless count of Data/Recipes.lua).
- Log in on a character without Alchemy and run a full scan at an auction house. Then `/craftwise market` with a shift-clicked Elixir of Strength link (or any other Alchemy potion or herb): the house line, "cheapest: ..." and "typical: ..." (or "too little history" in the first days) show, and the line "history: none (outside the market scope, latest price only)" does not. Scan again some hours later: "disappeared in 7 days: N units (sold or expired)" appears once units went. The same for a Tailoring, Blacksmithing or Enchanting item. An item no recipe uses (a quest item, gear) still says "history: none".
- Look up › Items: the Elixir has a card with a chart of at least two points after the second scan.
- Scan time: Settings › Debug › Record, run a full scan at a house that already has history, Stop. The longest frame of the commit hooks stays in the same few-milliseconds range as before this change (headless: 8 to 10 ms before and after); the scan lasts about 16 % more frames (227 instead of 196 for 18,900 rows). No hitch while it stores.
- Login: no `PLAYER_LOGIN` handler over a few ms in the recorder. The sell prices of the added items are read in the background, 10 every 0.1 s, so the client loads about 2,300 more items over about half a minute; no stutter in that time.
- File size: after a few weeks the SavedVariables file of `CraftWiseMarketDB` is about 1.6 times what it was (headless, one house: 3.70 MB before, 6.04 MB after 30 days of two scans a day; four houses: about 11 MB). Note the size before and after the first weeks here if it looks larger.
- **Make › Craft: Per day (#231, no TOC change, `/reload` is enough):** the new column "Per day" (sortable) between Return and Profit = profit per craft × the crafts a day the AH takes, from the units that disappeared at the profit house over the last 7 days at prices up to the typical, divided by the days with market data and by the items per craft. Hover it or the row: "N units disappeared in D days of history ... = X a day = Y crafts a day" (the word is always "disappeared", never "sold"). Items you sell to a vendor or marked Junk show "no limit" and sort after the rows with a figure; recipes without a price show a dash with the reason; with fewer than 3 days of market data the dash says "Market history too short: 2 of 3 days". Turn on the Unlearned chip: unlearned recipes get the figure too, and their tooltip adds "Learning costs ...: about N days to pay back at this rate" next to "Where to get it". Works with All professions. Compare a figure with the Items page of the product: its "disappeared in 7 days" is the same number.

## Sale alert (#235)

- **New file `AuctionAlert.lua` is in the TOC: restart the game, `/reload` is not enough.**
- List an item with a buyout at the AH (one that you can have bought by an alt or a friend), then leave the AH and wait for it to sell. One line appears in the loot toast's place: "Sold: [item]" with the amount after the cut in coin digits and "you get", and the coin sound plays. The chat line "A buyer has been found for your auction of ..." comes as before, but the toast must show **once** per sale, not twice (event and chat both arrive). Sell › Auctions, if open, moves the row from Listed to Sold at the same moment, without reopening.
- Stay at the AH while it sells: the same single line. Close and reopen the AH afterwards (the owned list is read again): no second line.
- Log out with a sale unseen (sold while offline), log in and open the AH: one line for it when the owned list reads it. Log out and in again: nothing for sales already known.
- A commodity stack where only part was bought: "×5" when the owned list showed the quantity drop, "some of 20" when only the sold message came. With "some of N" there is no amount, never a guess.
- Several sales close together stack as lines, newest on top; clicking a line opens Sell › Auctions. Lines stay 8 seconds.
- The sound: is the coin sound (SOUNDKIT.LOOT_WINDOW_COIN_SOUND, the one Blizzard's AH buy dialog plays) audible and not harsh? Note here if you want a different one.
- Settings › Sale alert: "Auction sold" off = no line and no sound (the record still moves on the page); "Sale sound" off = line only; "Auction expired" on = a line "Expired: [item]", "×5 · returning by mail", no sound. Let an auction expire to see it (default off).

## Two machines: the market sync file (#241, part of #237)

- **No TOC change in CraftWise.** The companion (#239) writes the data addon `CraftWise_Sync` (its own folder in `Interface/AddOns/`, `## Dependencies: CraftWise`); it sets the global `CraftWiseSync` (`v`, `written`, `machine`, `market`). The folder is new the first time the companion writes it, so **restart the game completely once** after that (the game only finds new addon folders at start). After that `/reload` picks up a rewritten file. CraftWise reads the global at login (a `/reload` counts) and merges it into `CraftWiseMarketDB` **while the loading screen is up**, never in world; what is left after 2 seconds of that (only a first file of tens of thousands of entries we have never seen) is merged at logout, before the saved file is written.
- No file (companion not installed or never downloaded): nothing changes, no error in chat or in the Lua error display, `/craftwise debug` prints as before. Let the companion write the file, restart the game once: the merge runs during the next loading screen. A later download is picked up by `/reload`.
- Loading screen: log in (and `/reload`) on a machine whose file holds a full market (tens of thousands of entries) and time the loading screen with and without the file (disable the `CraftWise_Sync` addon in the list to compare). Note the difference here (headless: about 0.1 s when the file equals the saved market, 0.3 s when our entries are newer, about 2 s once for 40,000 entries we had never seen). Settings › Debug › Record (turn it on, then `/reload`) lists "Market: sync merge (login)" once. Nothing of the merge runs in world: no "Market: sync" hook after the world shows, no stutter.
- Prices cross over: on the PC scan the Horde AH, let the companion upload and wait for the Mac companion to download. Restart the Mac game: Look up › Items shows the items scanned on the PC with their prices, tooltips and profit use them, `/craftwise market <item link>` shows "cheapest" and, for a profession item, "typical", "disappeared in 7 days" from the PC's history. The other way round after a Mac scan. A price recorded on both machines shows the newer recording.
- History from both: an item with history on both machines shows days from both (check "typical" or the Items chart: the days of the other machine's scans appear, no gaps where only one machine scanned). A day both machines recorded keeps the one with more points.
- Not a scan of this machine: on a machine that never scanned the Horde AH, the header status says "Horde AH · synced 3 h ago" (never "scanned ... ago"), and the AH tooltip in the header adds "synced ... ago" to the house line. After a scan on this machine the header shows this machine's scan again. With the other machine's name in the file's scans the line says "synced from <machine>".
- Same file again: `/reload` (or restart) without a newer download: the merge costs nothing (`CraftWiseMarketDB.sync.written` equals the file's). A second download with the same market changes no price; the file size of `CraftWiseMarketDB.lua` does not grow from reloads.
- File size: after the first merge the SavedVariables file holds the other machine's history too (the market of two machines, the same as one machine that scanned twice as much). Note the size before and after here.
- Companion upload after a merge: the next upload must not send the other machine's data back as new (the companion's no-echo rule, #239); the site's `/me` counts do not double.

## Make › Crafted: active crafting time (#251)
- Craft the same recipe 10 times in a row (queue or repeated clicks), then check the summary card on Make › Crafted: "today N · X min active" is about the time those crafts took (the first craft of the run adds nothing).
- Wait over 30 s (stand at a vendor, tab out) and craft again: the break is not in the time. Craft a different recipe in between: the gaps are not counted twice.
- The 7-day time is in brackets on the second line in the window layout; the docked layout shows today's time only.
- A character filter and the profession chip change the time with the counts. Days logged before this version show no time (no figure at all, not 0).
- The card also shows gold per active hour next to the time (estimated profit today / active time today). It is absent without active time or a recorded profit.
- **Merge cost (#241):** after the first login with a full file, walk around in a busy place for a minute: no stutter. `CraftWiseMarketDB.sync` in the saved file says what the merge was: `same` (identical text), `skipped` (nothing to take, read from the text without building it), `decoded` (had to be built), `changed`, `ms` of work, `atLogout` (true when the loading screen's 2 s were not enough and the rest was merged at logout). For a file that mostly equals the saved market `decoded` should be a small number and `ms` a few hundred at most; note the figures here.

## Class trainer: record, planner, Train all (#259)

- **New files `ClassSpells.lua`, `UI/TrainAll.lua` and `UI/Main/Pages/Train.lua` are in the TOC: restart the game, `/reload` is not enough.**
- **Record (the level and the spell id are the open questions).** Open your class trainer. Then `/craftwise train` (Make › Train): every service the trainer lists is there with its level, rank, cost and the right state. The required level comes from `GetTrainerServiceInfo`'s fourth return, which Blizzard's Forever trainer window reads as `reqLevel`; not yet seen in game. If the Level column shows dashes for everything, the client doesn't give it: note it here. The spell id comes from the service tooltip (`C_TooltipInfo.GetTrainerService`); if it is hidden, known spells are told by what the trainer showed on the last visit ("known as of the last visit") instead of `C_SpellBook.IsSpellKnown`. Check in SavedVariables (`CraftWiseDB.classSpells.<CLASS>.services`) whether `id` is set. A weapon trainer (type General too) is recorded under the same class; check that it doesn't mix up the list (its services have no level).
- The trainer lists only a band of your level: visit again after a few levels and the list grows, spells from earlier visits stay. A spell you learned moves to Known on the next `/reload` or visit.
- **Cost and reputation:** the price shown is the trainer's own (reputation discount included); the base price isn't readable. Compare one spell's recorded cost before and after you gain a reputation level with that trainer's faction: it should drop, and the page says "with your reputation discount".
- **Train all (the purchase is the open question).** At a class trainer with spells you can learn: a "Train all" button at the top right of the trainer window. Click: a panel lists the spells and the total, nothing is bought. Cancel closes it. Click Train: one purchase per spell, a chat line "Training N spells for X", the services turn to learned. Check that all of them are bought from the one click (Blizzard's own button buys one at a time) and the order is last to first without skipping any; after it, any spell that needed an earlier one (rank 2) is now available and a second Train all lists it. At a profession trainer and at a pet trainer the button is not there. With less money than the list needs, the panel leaves out what doesn't fit and says how many. Settings › Class trainer › Train all turns the button off.
- **Cross-check with What's Training?** (answers whether its data was ever wrong): with What's Training? loaded, `/craftwise trainercheck` after a trainer visit prints how many of your recorded spells match its list, where cost or level differ, which of its spells up to the level you visited with aren't in the record (quest spells and tomes are left out) and which recorded ones it doesn't have. Note the output here; costs that match neither its price nor its base price are the interesting ones.

## Make › Craft: max AH price per reagent (#261)
- Hover a Cooking recipe with one AH reagent and one vendor reagent (e.g. Curiously Tasty Omelet): under the AH reagent a line "max X each (now Y)", X = the sale after the cut minus the vendor reagent's cost. Check X by hand.
- Y above X: the line is red. A recipe whose other reagents cost more than the sale says "loses money at any price".
- Vendor reagents and crafted reagents show no line. Mark the product Junk: the sale side switches to the vendor price and X follows.
- Unknown prices (a reagent never seen on the AH): no line at all, never a guess.

## Make › Crafted: Profit/h shows the figures behind it (#265)
- Hover a Profit/h cell: the tooltip ends with "One craft now: sale X (AH after the 5% cut | vendor price, no AH cut | vendor price (Junk mark), no AH cut) - reagents Y = +Z". Compare Z with Make › Craft's profit for the same recipe: they are the same figure.
- A Junk-marked product (Cooked Crab Claw sold to a vendor): the sale is the vendor price with no cut. The footer says "vendor/Junk sales: no cut".
- If Profit/h is negative while Profit today is positive, the line shows why (prices or the paid-cost basis now against craft time).

## Sell › Auctions: click a card (#269)

- No TOC change; `/reload` is enough. Open Sell › Auctions. Click "On its way · in the mail": the list shows only the sold auctions waiting in the mail, newest first, each with item, quantity, how long ago it sold, buyout and "You get" (after the cut, deposit back included); the card gets a white outline, the list bar says "N sold, waiting in the mail". The figure on the card equals the sum of the "You get" column (rows with a dash have no counted payout, as the card says). Click it again, or the All chip in the list bar: the whole list is back.
- "If all listed sell" shows the listings (time left, buyout); "Returning" shows expired and cancelled auctions coming back by mail. Auctions marked Uncertain stay in the list under every filter. The cards keep their totals while a filter is on. Hover a card: "Click to show these". Dock the window: the cards stack as before; the All chip still clears the filter.

## Make › Crafted: timed crafts and gold per active hour (#273)
- After a long Create All on a day that already had crafts from before this version, the card says "· N min active (X of Y crafts timed)": X is the crafts since the update. Once every craft of the day was recorded by this version, the parenthesis is gone.
- Gold per active hour is the profit of the timed crafts over the active time: check it against Profit today / crafts today x crafts per hour (about the same per-craft figure).
- Hover the Today cell of a row: "Active time: the time between crafts up to 30 s; longer pauses don't count."
- Active time per craft is about the Speed column's seconds (e.g. 3.1 s); a day recorded by the first #251 build shows no time until a craft is made (its old seconds are dropped).
- The window card also shows "+ ≈ X est. for N untimed crafts" (untimed crafts x that recipe median gap, only with 5+ gaps), kept apart from the measured time, and a "≈ .../h est." figure. The docked card leaves it out.

## Where to buy a reagent (#276)

- No TOC change; `/reload` is enough. Hover a Make › Craft or Make › Level up row whose recipe has a reagent that a merchant you opened sells (e.g. First Aid's Bottle of Dalaran Noir after visiting Barkeep Morag): under that reagent, "Buy at: Barkeep Morag, Orgrimmar · Valley of Strength 54, 68 · 50c". The coordinates are the ones recorded when you opened the merchant (a decimal rounded to whole numbers); stand next to him and compare with the map.
- A reagent you hold fewer of than one craft needs (bags, bank and mail as counted for the tooltip) has the line in the danger colour and "you hold 0 of 1". Several vendors: the one in the zone you stand in first, then the cheapest, at most two lines and "+N more: /craftwise where". Vendors of the other faction are left out; a vendor that sells to both shows for both.
- A limited-stock item says "limited stock, N seen" (the count at your last visit). A reagent no merchant was recorded for, but the bundled data says a vendor sells, shows "Sold by vendors, location not recorded yet" only when you are short of it; nothing else is claimed.
- **New file `UI/BuyAtPanel.lua` is in the TOC: restart the game, `/reload` is not enough.** Open a Make › Craft or Make › Level up row and click a reagent that a recorded vendor sells (its tooltip now ends with "Click: Where to buy it"): a panel lists every recorded vendor for your faction, one row each, the nearest marked with a "›" and a word: "nearest on this map" (same map, ranked by the distance between the recorded and your current position), else "in this zone", else "on this continent". A vendor on another continent has no word: no distance is claimed, and when none is on your continent the panel says there is no nearest. Walk to the other end of Orgrimmar and reopen it: the order follows you. Shift-click on the reagent still links it, right-click the item menu.
- **Waypoints (click-started):** "Waypoint to nearest" and each row's "Waypoint" button set a map waypoint at the recorded position (`C_Map.SetUserWaypoint` with `UiMapPoint.CreateFromCoordinates`, then it is tracked): open the world map and check the pin is at the vendor, and the arrow points there. A vendor recorded without a position has its button greyed. With TomTom loaded the same click adds its waypoint. Opening the panel sets nothing. Not yet seen in game: `UiMapPoint.CreateFromCoordinates` (Blizzard's Forever map code calls it, `WaypointLocationDataProvider.lua`).
## Sell › Auctions cards: highlight and filter bar (#270 follow-up)

- No TOC change; `/reload` is enough. Click "On its way · in the mail": the card gets a double orange outline and a brighter fill, and the bar above the list reads "Showing: On its way · N auctions · <what they pay>". With no filter the bar reads "All auctions · N sold · N listed · N returning". Click the card again or "All": back to the full list (a Status column names each row's group). If the click still does nothing in game, note whether the tooltip "Click to show these" shows and whether the bar changes.

## "On its way" only counts what is still pending (#278)

- No TOC change; `/reload` is enough. At the auction house, open Blizzard's Auctions tab and CraftWise's Sell › Auctions side by side (the owned list is read when you open the AH). The "On its way · in the mail" count should equal the number of Sold rows with an "Incoming Amount" in Blizzard's list (auctions of the same item sold in one batch may show as several rows on either side, the count of auctions is what must agree). Sold auctions whose money you already took are gone from the card, and from the list when you filter it.
- Records with no confirmation for three hours that Blizzard still lists them read "Probably collected" in the list, are not counted on the card and are not claimed as collected. The three hours are a label heuristic, not the mail delay (not verified for Forever): note here the real delay between a sale message and its mail.
- Take the money of several sale mails of one item at once (e.g. Cooked Crab Claw sold in 4 auctions): after taking them, none of those auctions stays "Sold". A sale mail's count is the sum of its auctions' quantities (Hot Spices ×200 for several 20-unit sales).

## Main window: drag to resize, tables reflow (#280)

- No TOC change; `/reload` is enough. **Window layout:** a grip of six dots sits in the bottom right corner of the window. Drag it: the window grows to any size up to the screen (never under 880 × 600). While you drag, the page is drawn again about every 0.1 s (slower on a heavy page such as Look up › Items: the gap is four times what a redraw takes) and once more when you let go; if the page stutters while dragging, note which one. After the drag the window must stay where its top left was (the client re-anchors a frame it sizes; CraftWise saves the place when you let go), `/reload` brings it back at the same size and place, and Escape / close / reopen keeps the size.
- **Does `StartSizing("BOTTOMRIGHT")` on the window (anchored at its centre by default) grow it from the top left?** Check on a fresh window, and with Settings › Look › Scale at 0.7 and at 1.3: the grip must follow the cursor, and the size must not jump when you press it. The bounds are given to `SetResizeBounds` in the frame's own units (screen width and height divided by the scale): check that at scale 1.3 you can't drag the window off the screen.
- **Columns:** open Make › Crafted and drag the window wider. At 880 the Speed column still reads "3.1 s · 1,…" as before; dragged about 40 units wider it shows the whole "3.1 s · 1,168/h", Profit/h, Profit today and Profit total get their room next, and the recipe name takes everything wider than that. The rows must not flicker or lose their scroll position while you drag. Other pages: the name column of Sell › Auctions, Bags, Crates and Make › Craft's recipe column (up to 300, then the profit rail) grow with the window; note any other column that is still cut with "…" when there is room, with the page and the text (it needs a `grow` width in its column definition).
- **Taller:** more rows show; the footer and the hero card stay at their height.
- **Docked:** the sheet has a thin dotted handle on its inner edge (the right edge of the left sheet, the left edge of the right one). Drag it: the sheet follows the cursor at once, the page is drawn again every 0.1 s and when you let go; it never gets under 380 or over half the screen. The left and right sheets and the window each keep their own size (Settings › Look › Layout, or the dock button, swaps between them). Check the header's AH status line still fits when the sheet is wide.
- **Settings › Look:** "Reset window size" (next to "Reset window positions") puts the window and both sheets back to their own size at once. Hold Ctrl and turn the mouse wheel over the title bar: the Scale setting moves one step (5 %) per notch, between 70 and 130 %, and the window is clamped to the screen at the new scale; without Ctrl the wheel does nothing there.

## Own full AH scan: "Scan AH" (#6)

- No TOC change; `/reload` is enough. At an auction house the header of the main window shows a "Scan AH" button (left of the AH status; docked: in the header's bottom right corner). It does nothing until you click it; it is greyed with "Scan AH · 15:00" counting down while the cooldown runs. The 15 minutes come from #6 and Auctionator's code, **not verified on Forever**; they count from the click, and also from any full list that arrives (an Auctionator or Mastercraft scan restarts them).
- **First run, first ever replicate scan on this account.** Write the numbers in a comment on #6. After the scan, `CraftWiseMarketDB.ownScan.last` in the saved file has most of them (`/reload` or log out to write it): `rows` (the row count of the list on this realm, one per auction), `waited` (seconds from the click to the list), `readMs` / `readFrames` / `readWorstMs` and `storeMs` / `storeFrames` / `storeWorstMs` (CraftWise's own time per phase, the number of frames and the longest frame; the budget per frame is 6 ms plus one step), `items` (entries stored with history), `lastOnly`, `unread` (items whose link wasn't in the client's cache).
- **Unknown, to be measured, nothing is assumed:**
  - How many rows the list has. Memory while reading: rows are added up per item, so it grows with items, not auctions.
  - How long the list takes to arrive (the button counts "Waiting for the list · N s"). The 120 s timeout (`Market.OWN_WAIT_SECONDS`) is a placeholder: if the list takes longer on a busy realm, the scan fails with "No list arrived within 120 s" while the list may still come; note the time.
  - Whether the game stutters or lags when the list arrives (before CraftWise reads anything), and while it is read and stored (`readWorstMs`, `storeWorstMs`; frame time with the slow-frame recorder in Settings › Debug).
  - Whether the client disconnects on the request or the list.
  - What the server does with a request inside the 15 minutes: nothing, an error, or the old list again. Test it once with the CraftWise cooldown out of the way (edit `ownScan.requested` and `ownScan.list` in the saved file, or ask after an Auctionator scan): does the button wait, does a list come, does the client print an error? The message "No list arrived ..." is the answer CraftWise gives when nothing comes.
  - Whether `ReplicateItems` needs a click (a hardware event) on Forever: the button calls it from its click, so it works either way; Blizzard's docs do not mark it restricted.
  - Whether a failed or timed-out request still uses up the 15 minutes. CraftWise keeps the countdown after a timeout; note whether a second click earlier works.
- **After the scan:** the AH status in the header reads "scanned 0 min ago", Sell › Auctions, Make and the Bags prices use the new data, and scope items have history from the one list (look at Look up › Items › Price history for an item you track). The scan is logged `kind = "full"`, `source = "own"` in `CraftWiseMarketDB.scans` for the house.
- **Failures:** close the auction house while the button says "Waiting": a chat line says the house closed and nothing was stored. Close it while it reads: the same. Close it while "Storing": the scan finishes.

## Own AH scan: progress shown per phase (#285)

- No TOC change; `/reload` is enough. Click "Scan AH" and watch the header (a Make or Sell page, where the AH status shows) and the bar CraftWise draws under Blizzard's auction house window:
  - **Waiting:** "Waiting for the server · 0:23 / 2:00" with a bar that fills towards the timeout; the button reads "Waiting · 0:23 / 2:00". Note how long the list really takes (the 120 s is a placeholder).
  - **Reading:** "Reading the list · N of TOTAL · NN %", hint "Keep the auction house open." After a few seconds the tooltip and the bar add "≈ m:ss left", worked out from the rows read so far (nothing else): compare it with the real time.
  - **Storing:** "Storing prices · N of M · NN %" (items stored of items to store, not rows) with the hint "Closing the auction house is safe now." Close the house here: the scan must finish. Check that the bar keeps moving, that the game doesn't stutter (the frames are cut at 6 ms), and that the percentage reaches 100 %.
  - **Done:** "Scan done · ROWS rows · ITEMS items · m:ss" in bold white in the header and on the bar for 10 s, plus a chat line. Then the button reads "Next scan in 14:52", counting down.
  - **Failed:** the reason in red ("Scan failed · no list within 2:00", "the auction house was closed", ...), until the next click.
- **Where the bar sits:** it is anchored 4 units under `AuctionHouseFrame`, outside its art. Check that it is visible and doesn't sit on the screen's bottom edge or on top of another window (the Forever AH layout has not been read). If it is off screen, say so: it needs another anchor.
- **The countdown:** hover the button while it says "Next scan in ...": the tooltip says the server allows one list per account every 15 minutes, counted from the request, so it runs after a failed scan, a closed house or another addon's scan too. Close the auction house while "Waiting" or "Reading": the countdown must still run after reopening.

## Own AH scan: item data for the unread items (#286)

- No TOC change; `/reload` is enough. Veli's first own scan (208,029 rows) left 3,901 items unread: gear whose link the client couldn't give yet. CraftWise tried every such row again every half second for 5 s. Now, after the list is read, a **"Loading item data · N of M · NN %"** phase asks for each of those items once (in a window of `Market.LOAD_WINDOW` = 300 requests that wait for an answer, an item again after 10 s) and reads its rows once its data is there. The button reads "Loading · NN %", the bar under the auction house the same, with "Keep the auction house open." (the list must stay the one that was read).
- **Unknown, to measure on the next scan** (all placeholders, nothing is known about how fast Forever loads item data): how many items need the load (`ownScan.last.needed`), how many arrive (`loaded`) and in how many seconds (`loadSeconds`), the longest frame of the phase (`loadWorstMs`), whether the game stutters while 300 requests are out, whether a window of 300 is too small or too big (if `loadSeconds` is long with few frames busy, try a bigger `M.LOAD_WINDOW`), and whether `LOAD_STALL_SECONDS` = 20 / `LOAD_MAX_SECONDS` = 180 end the phase too early or too late. `stalled = true` means it gave up on what was still missing.
- **What stays unread, by reason and category** (counts in `ownScan.last`, and "N items not read" in the done line): `unreadFailed` (the client says there is no such item), `unreadTimeout` (nothing arrived in time), `unreadNoLink` (the data is cached but the replicate list still has no link: the "never store under a wrong key" case), and `unreadWeapon` / `unreadArmor` / `unreadOther` by item class. Compare with the 3,901 of the first scan: write the new counts on #286. An item left unread keeps its older price and is not marked as gone.
- Check that the scan keeps its frames short in this phase (`loadWorstMs`, the slow-frame recorder in Settings › Debug), and that closing the auction house during it fails the scan with the "closed" message and stores nothing.

## Vendor restock reminders and learned restock times (#289)

- **TOC change:** a new file, `Restock.lua` (after `Merchant.lua`). It needs a full game restart, `/reload` is not enough.
- **Set one:** open a reagent's vendor panel (Make, click the reagent; #277). Each vendor row has **Remind**: it shows the times (the learned one first, when the stock log has one, then 1 h, 2 h, 6 h, 12 h). One click sets it, a chat line says so, and the reminder is listed under the vendors with a delete button (×). From chat: `/craftwise remind <hours> <item link | id | name>` (at the open merchant, else the nearest recorded vendor of the item), `/craftwise remind` lists, `/craftwise remind remove <n>`.
- **Tunkk's case (Pattern: Raptor Hide Harness):** open Tunkk once (a full, unfiltered merchant window), close it, open him again: `/craftwise remind 6 <shift-click the pattern in chat>` while his window is open. It must say "Tunkk: not sold here (seen 2 visits)" if he never listed it. Check that this is true to what the window showed and that a filtered window (merchant filter not "All") does not make the claim.
- **Due:** a toast line "<item> may be back at <vendor> (<zone>)" with "Waypoint", a chat line, the sale sound (Settings › Sale alert) when on. Clicking the line sets the waypoint. Log out with a reminder due in 5 minutes, log in after: it must fire within seconds of login. It fires once.
- **Unknown, to measure:** whether sold-out limited items stay in the window with a count of 0 in Forever or vanish (a vanished one is only "not listed now, last seen ..." and gives no learned time), whether stock is per Forever layer (a different count may be another layer, see #73), and the real restock intervals: `/craftwise where <item>` shows "restocked within ..., seen N times" once a 0 and a later higher count were both recorded. Write what you find on #289.
- Tooltip and panel wording to read: "not sold here (seen N visits)" only after N complete views that never showed it; "out of stock" only for a count of 0; "not listed now, last seen ..." for an item an earlier complete view showed.

## Own AH scan: the client's request throttle (#291)

- No TOC change; `/reload` is enough. Veli's click at 18:36 got no list in 120 s although the previous scan was 4 h earlier and none of his addons runs a replicate scan: the suspect is the auction house throttle, because Auctionator, Mastercraft and CraftWise's own browse recording all query the house when it opens. **Not verified**: whether `ReplicateItems` goes through the throttle on Forever, and which of the four events fire for it.
- What CraftWise does now: the click waits until `C_AuctionHouse.IsThrottledMessageSystemReady()` is true (or `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` fires, with a half second poll in case it doesn't): the button reads "Getting ready · 0:07" and the bar "Waiting for the auction house to be ready", nothing is sent and **no cooldown is used**; after 30 s (`Market.OWN_READY_SECONDS`, a placeholder) it fails with "wasn't ready" and a click can try again at once. Then the request is sent and the events are counted: `AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED` shows "Queued by the game, not sent yet" (the wait for the server starts at `_SENT`), `_DROPPED` before any `_SENT` is taken as the server never having got it ("the game dropped the request": the cooldown is given back, click again), a `_DROPPED` after `_SENT` is ignored (somebody else's message). The events carry no message id as far as CraftWise knows, so that attribution is a guess: it is the reason the numbers are recorded.
- **Read from the saved file after each click** (`/reload` or log out to write it): `CraftWiseMarketDB.ownScan.lastRequest` = `{ t, house, outcome ("list", "timeout", "dropped", "notready", "closed", "changed", "error"), readyAtClick, readyWait (seconds the click waited for the throttle), sent, queued, dropped, response }`, and the same fields as `thrSent`, `thrQueued`, `thrDropped`, `thrResponse`, `readyAtClick`, `readyWait` in `ownScan.last` for a finished scan. Write them on #291 after the next clicks: Does `readyAtClick` come out false right after opening the house (and for how long)? Which events fire for a successful scan, in which order, and do `_SENT` and `_RESPONSE_RECEIVED` fire for it at all? If a click times out: how many `queued` / `dropped` / `sent` did it see?
- Try: open the auction house and click "Scan AH" at once, with Auctionator and Mastercraft loaded; again 30 s later; again with them disabled. A timeout message now ends with "Throttle events after the request: sent N, queued N, dropped N." and says the throttle may have held the request back.
- **After a timeout (Veli's saturated connection at 18:36, #291):** the 274k-row list may simply have taken longer than 120 s. A timed out request no longer locks the button for the full 15 minutes: the header offers **Try again anyway** next to "Next scan in …" (its tooltip: the server may send nothing if it counted the first request), and a list that still arrives after the timeout, while the house is open and within 15 minutes of the request, is read and stored as our own (`ownScan.last.late = true`, `waited` = the real wait in seconds). Check on a slow connection (or with a big download running): how long the list really takes to arrive, whether it comes after the 120 s timeout, whether Try again anyway gets a second list, nothing, or the first one. The timeout message names a slow connection as one possible cause.

## Item tooltip: max price to pay for a reagent (#292)
- Hover a reagent of a recipe you know (e.g. Crispy Lizard Tail) in the bags, in Blizzard's AH, in Auctionator's Shopping lists and on an item link: the CraftWise section has "Max to pay | 1s 5c for <recipe> (now 1s 32c)", red when the price now is above it. Compare with the same reagent's line in Make › Craft's row tooltip.
- Several recipes use it: the highest maximum first, a second line, then "+N more recipes".
- A vendor-sold reagent (Mild Spices) shows no line. "loses money at any price" when the recipe's other reagents cost more than the sale.
- Settings › Tooltips › "Max price to pay for a reagent" turns it off. Change the cost basis (Settings › Prices): the figure follows, and the line says "paid cost" with the Paid basis.

## Make › Crafted: long casts are timed (#295)
- Craft Barbaric Leggings (about a minute per cast) five times, one after another or with pauses: after the fifth the row shows Speed "≈ 60 s · 60/h" and a Profit/h. Before this, nothing showed.
- A pause of several minutes between two crafts is still a break: it doesn't add to the active time beyond the craft's own cast.
- Cancel a cast (move or press Esc) and craft again: the cancelled cast doesn't count.
- Short recipes (3 s) show the same Speed as before.

## Own AH scan: the bar no longer covers the tabs (#297)

- No TOC change; `/reload` is enough. The scan bar moved from under the auction house window (where it sat over the tabs Alış / Satış / … and the tabs other addons add) to **4 units above the window's top edge**, taking no mouse input at all. Check with Auctionator, Mastercraft and Disenchantry loaded: during a scan every AH tab is clickable, and clicks go through the bar even if it overlaps something. If the AH window sits so high that the bar can't fit above it, the screen clamp pushes the bar down over the window's title strip (visual only, no clicks): note where the AH window sits, and whether the bar is then readable.
- The done or failed line leaves the bar after 6 s (`Main.AH_BAR_LINGER`); the header keeps the summary 10 s and a failure until the next click. Settings › Look has "Scan bar" to switch the bar off.

## Trade window: fill up to 6 slots from a send list (#299)

- **TOC change:** two new files, `SendList.lua` (after `Basket.lua`) and `UI/TradeFill.lua` (after `UI/MerchantBuy.lua`). A full game restart is needed, `/reload` is not enough.
- **Open a trade** with any player: the panel "To send" sits to the right of the trade window with "Trading with <name>". Add items: type part of a bag item's name (and a quantity, empty = all stacks) and press Enter or Add; or Basket (the basket's materials) or Sell on AH (marked items in the bags). Save list stores the working list under a name; click a saved name to load it, right-click to delete; "Use for this partner" loads that list by itself when that character opens a trade.
- **Fill 6 (one click):** the stacks go into the empty slots of your side. CraftWise picks the stack up (`C_Container.PickupContainerItem`, or `SplitContainerItem` for a part of a stack) and drops it with `ClickTradeButton(slot)`, the call Blizzard's own TradeFrame makes for a drag. **To verify, none of this is known from the client docs:**
  - that all of up to 6 pickups and drops work inside one click. If the client keeps an item on the cursor after a drop, the fill stops with "the trade window did not take it: one slot per click", the cursor is cleared, and the next click places the next stack. Check which of the two happens, and write it on #299;
  - that `SplitContainerItem` followed by `ClickTradeButton` sends exactly the typed quantity (list an item with a quantity below its stack size and check the number in the trade slot);
  - that `GetTradePlayerItemInfo(slot)` is filled by the time the next click happens (occupied slots are skipped; CraftWise also remembers what it just placed).
- **Accepting is yours:** the addon never calls `AcceptTrade` or `C_SecureTransfer.AcceptTrade` (a spec checks the source). Press Trade yourself.
- **After the trade:** the line reads "sent N of M stacks"; the stacks that left the bags count as sent (it looks at the bag slots that were placed, again a few seconds after the window closed). Quantities on the list shrink by what went out, and the button reads "Fill next 6". Cancel a trade: nothing counts as sent and the same stacks are offered again. Check both, and that a soulbound stack is skipped with "Nothing left to send (N bound stacks can't be traded)" when only those remain.
- Send lists are stored in `CraftWiseDB.send` (`work`, `lists`, `partners`) and are meant to be reused for mail (#300).

## Make › Learn: where to buy a recipe, from What's Training?'s data (#302)
- Needs a full game restart (new data file in the TOC). Open Make › Learn on Cooking with Hot Wolf Ribs unlearned and never opened its vendor: the row and the tooltip show "Vendor: NPC 8145 (Feralas)" and "NPC 12246 (Desolace)" labelled "source: What's Training?, not seen in game"; the Alliance vendor (NPC 7947) is not listed for a Horde character.
- Walk to a listed vendor and open its window: the line gets the NPC's name and the recorded price, and the "not seen in game" label goes. No coordinates or waypoint appear for a vendor only What's Training? knows.
- Check a few NPC ids and zones from the list against the game (Wowhead/in game); report wrong ones on #302.

## Learn vendors: names and coordinates from an installed QuestieDB (#304)
- With QuestieDB loaded: Make › Learn, Hot Wolf Ribs (Cooking, Horde): "Vendor: Sheendra Tallgrass (Feralas 74.4, 42.8)" labelled "source: Questie/What's Training?, not seen in game". Check the name and the coordinates in game. A vendor Questie doesn't know stays "NPC <id> (zone)".
- Without QuestieDB (disable it, `/reload`): the same vendors show as "NPC 8145 (Feralas)" again, no error.
- Walk to the vendor and open it: our own recorded name, price and "seen by you" replace the line.
- The line carries a map and position, so Merchant.Waypoint works for it; there is no button for it on the Learn page yet.

## Key bindings: one header (#306)
- `/console scriptErrors 1`, then log in or `/reload`: no "Binding header CRAFTWISE was attempted to be loaded more than once" warning.
- Game menu › Options › Key Bindings: the three bindings (party, main window, farm) are still listed together under CraftWise.

## Icons: junk is one symbol (#308)
- Mark a poor-quality (grey) item as junk with the middle mouse button. Check in Blizzard's bags (combined and single), Bagnon and Baganator: each shows the grey folded corner (top right) and the dimmed icon, and **no coin**. Open Baganator's Settings > Icons and make sure "CraftWise: marks" sits in a corner and the "Junk" widget too: the coin still must not show on the marked item.
- Visit a merchant: the marked grey item shows the fold only; an unmarked grey item shows the client's coin (Blizzard bags and Baganator with the CraftWise junk plugin selected).
- Unmark the item: the fold and dim go, the coin returns on a grey item at a merchant. Mark a non-grey item (white): fold and dim, no coin.
- Make > Bags: a junk row has its icon grey and dimmed like the slot; docked layout the same.
- Baganator: the dim also shows on marked items (the corner widget no longer needs the button as its parent).

## Companion: W key logo (#310)
- [ ] Tray at 100 % and at 150 % display scale: the gold W key shows crisp (not blurry, not cut off); at 100 % the 16 px drawing with the angular pixel W, at 150 % the 24 px one.
- [ ] Light and dark taskbar: the key is readable on both (the gold border holds it against either).
- [ ] The exe (`craftwise-companion.exe`, built with `-H=windowsgui`) shows the key in Explorer (small, medium and large icons views), in the taskbar while the settings run and in Settings > Apps > Startup.
- [ ] The tray icon still comes back after restarting Explorer.


## AH → vendor flips (#312)
- [ ] Run a full AH scan at your profit house (Make > Basket, Settings > Prices to see which). In the minute after, if any item is listed below the price a vendor pays for it, one toast "N AH → vendor flip(s)" shows with the best item, its units and the profit (gold toast, source word "AH → vendor"). Click opens Make > Basket.
- [ ] Make > Basket has the section "AH → vendor": item, units ("×12+" when every stored tier is below the vendor price), "≤ <max per unit>", and the expected profit. Pick one flip by hand at the AH: is its cheapest buyout per unit really below the vendor price in the item's tooltip? Does the number of units match the AH's own list?
- [ ] A second scan with the same flips gives no second toast; a flip that was bought out (or relisted higher) leaves the section.
- [ ] Dismiss a line (open it, Dismiss): it stays away on the next scans until its profit is 1.5 times the dismissed one.
- [ ] With Auctionator loaded: after a scan with flips, Auctionator has the shopping list "CraftWise vendor flips" with one line per flip. Open it at the AH: does the max price (the line shows it in gold, `0.0099` = 99 copper) filter by the buyout **per unit** for stackable items and commodities? Does it still show the cheapest listings? Making the list while the AH is open starts its search right away (Auctionator's own behaviour); nothing is bought.
- [ ] Without Auctionator: opening a flip line shows a search string to copy; paste it into Auctionator's Shopping tab (or an empty list) and check it parses with max price and quantity.
- [ ] Buy some of a flip item: the line shows "in bags" and dims when the bags hold the units.
- [ ] Settings > AH to vendor flips: "Flip alert" off stops the toast, the section and the list; "Smallest profit per item" steps like the loop alert (default 1s).
- [ ] A full scan of an Everlook-sized house: the check right after the scan does not freeze the client (it reads every recorded item once; note the time in Settings > Debug > performance, "Loops.lua check").

## Bought flips become junk (#314)
- [ ] With a flip on Make > Basket > "AH → vendor" (item not in your bags before): buy some at the AH. Where does the purchase arrive on Forever, straight into the bags or by mail? Note it. Once the items are in your bags (taken from the mail if it came by mail) the chat says "<item> is marked as junk: bought as an AH → vendor flip" and the item shows the fold and the dim. Merchant: "Sell junk" sells them.
- [ ] An item you already carry when it becomes a flip: buying more does not mark it. An item you marked Keep / Sell on AH or watch: not marked.
- [ ] Middle-click the marked item to take the mark off, buy another flip of it later: stays unmarked.
- [ ] If the purchase comes by mail: the next scan may drop the flip from the list before you open the mail; the item is still marked when you take it from the mail within a day.
- [ ] Settings > AH to vendor flips > "Mark bought flips as junk" off: nothing is marked.
- [ ] A flip with all eight stored tiers below the vendor price reads "8 or more" (not "×8+") in the line and the toast; hover the line: tooltip with the count, the max price per unit and the profit.

## Buying at the AH from CraftWise: panel, search, buy (#315, part 1)
Needs a full game restart (new files AHBuy.lua and UI/AHPanel.lua in the TOC). Try it first with something cheap.
- [ ] Open the AH: the CraftWise panel docks at the right of the AH window and lists the flips (Make > Basket) and the basket's AH lines. Opening the AH and the panel send **no** search by themselves (check with a slash `/etrace` or by watching the AH's own list).
- [ ] Click a flip line: one search goes out; results list "qty × price per unit". The Buy button reads "Buy N for X" with the exact total. Check it against the AH's own list: the cheapest N units up to the line's max price (a flip: vendor price minus 1c).
- [ ] Throttle: right after opening the AH (other addons query), click a line: the panel says "Wait: the auction house is busy" and sends nothing; click again when it is ready.
- [ ] Buy an **item** auction (non-stackable, one at a time): one click buys that auction; the button is off until the result; then "Bought. The list is old: search again." The Buy button stays off until you search again. Does Blizzard's own AH frame show anything odd while CraftWise searches by item ID (level 0 key)? Gear with an item level may need the specific level: note what is found.
- [ ] Buy a **commodity**: the first click starts the purchase and the button becomes "Confirm: buy N for X" once the server's price arrives (COMMODITY_PRICE_UPDATED); the second click confirms. Does Blizzard's AH window show its own buy dialog while this happens? Does the item land in the bags or the mail? (#314 notes where.)
- [ ] A price change in between: have a second character buy or post under the listing, or wait for the list to move, then click Buy: nothing is bought, the panel says the price changed and shows the live total. For a commodity: if the server's quote is above what the button showed the purchase is cancelled and says so.
- [ ] Not enough money: with less gold than the total the button says "Not enough gold" and is off. Auction gone: buy an auction another player just took: the panel or the client says so, nothing is retried.
- [ ] A total above the limit (Settings > Buying at the AH > Ask above, default 10g) shows the client's confirm dialog first; Cancel buys nothing, Accept buys once. Change the limit and try again.
- [ ] Hold the click / press fast: only one purchase per click; a second click while the result is pending does nothing.
- [ ] With Auctionator loaded: the "Auctionator list" button in Make > Basket still works; Settings > Buying at the AH > Auctionator list off stops the automatic "CraftWise vendor flips" list.

## Buying at the AH: keys and the snipe list (#315, part 2)
New files (`Snipe.lua`) and Bindings.xml: needs a full game restart once. Esc > Options > Key Bindings > AddOns > CraftWise: "AH: search next" and "AH: buy best" are listed under the one CraftWise header; bind two keys.
- [ ] Does the client give the binding body `keystate` ("down" then "up", the bindings are `runOnUp`)? Check: bind a key, hold it down for 3 seconds with the AH open and a line picked: exactly **one** search goes out (a second search needs a release and a new press). If the body is called without `keystate` or only once, note it.
- [ ] Search key: with a snipe, a flip and a basket line listed, each press searches the next line (snipes first), round to the first. With one line it searches that line again. A press while the server is busy ("wait" in the panel) sends nothing, and when the server is ready again nothing is sent by itself.
- [ ] Buy key, **item** auction at or below the max: one press buys it (PlaceBid works from the key press as the hardware event: no "action blocked" error). A held key does not buy a second one. After the result the next press searches the line again.
- [ ] Buy key, **commodity**: press 1 starts (the panel shows "Confirm: buy N for X" when the price arrives), press 2 confirms. The start key held down does not confirm. Is the key press accepted by `ConfirmCommoditiesPurchase` (it is not restricted)? Is a press between start and the quote harmless?
- [ ] Price above his max: the quote rises above the max between start and confirm (or move the max below the live price): the purchase is cancelled, nothing is bought, the panel says so. Not enough gold, auction gone: nothing is bought, no retry.
- [ ] Above the "Ask above" total (10g) a key press shows the client's confirm dialog first; Accept buys once.
- [ ] Speed: time search next, Buy best (item) and search next, Buy best, Buy best (commodity). Is it fast enough to compete with a macro? Note the time from first press to the item in the bags.
- [ ] Snipe list in the AH panel: type an item link (shift-click a link in chat, copy it, paste), an item ID or a name the game already knows into the first box, a max price per unit (`3g 40s 5c`, `40s`, `3.5g`; a bare number is gold), optional "up to"; Save. The line shows "snipe" and its max price; the × removes it. A click on any line fills the form with its item and max price. Item menu (middle click in the bags): "Add to snipe list" fills the form.
- [ ] His max wins: put a flip item or a basket item on the list with a lower max: the line shows his max and the Buy button never buys above it. Change the max while results are shown: the picked line is dropped and has to be searched again.
- [ ] Toast: after a scan or search with a snipe-list item listed at or below the max, the toast says "N snipes under your max" (with the flips if there are some); a click opens the panel when the AH is open. Nothing is bought or searched by the toast. A listing exactly at the max counts.
- [ ] Item level: a snipe of gear with an item level: does the search by item ID (level 0 key) list the gear? Note what is found.

## AH panel: lines with cost, vendor return and profit, totals on top (#328)
No new files. Display only: nothing here searches or buys by itself. Needs a flip list (a full scan, Make > Basket), a snipe-list item and a basket item with an AH line.
- [ ] The panel is 340 wide and docks to the right of the AH window without covering it. Is the text readable at the default UI scale; does the summary line fit on one line?
- [ ] Top: "Flips: cost X · vendor Y · profit +Z" and under it "from the scan N m ago; the live search may differ". The age matches the last full scan (Settings > Debug or the scan time shown elsewhere).
- [ ] Groups in order with small headings: "Snipes (n)", "Flips (n)", "Basket (n)". A group without lines has no heading.
- [ ] Each row is two lines: item and quantity, then "cost · vendor · profit" (flip), "max X each · up to N" (snipe), "cost about X (market price)" or "no market price" (basket). The × of a snipe still removes it; a click still picks and searches once.
- [ ] Flip with bags holding part of it: the cost is for the units still missing (the cheapest ones), not the whole list. Compare one line by hand with the tiers (`/craftwise market <id>`).
- [ ] A flip that reads "×≥N" (the list may hold more): cost, vendor and profit all read "≥".
- [ ] Totals add up to the lines by hand; with a line whose prices aren't stored the profit total shows "?".
- [ ] After a click or search, "Listed now (units × price = row total)" heads the live results, each row "12 × 3s 40c = 40s 80c" with the right total.
- [ ] Item names: after opening the AH no row shows "item 1234"; an uncached item shows "…" and its name replaces it within a moment, without clicking.
- [ ] Buy button: with no line picked it looks clearly off (faded, grey text), its text is what AHBuy says, and the line under the buttons reads "Click a line to search it first".
- [ ] Click a gear item (not a commodity, e.g. Barbaric Shoulders): the status line says "Searching...", then either the listed rows or "Nothing is listed"/"Nothing is listed at or below the max price". If it stays on "Searching..." the client sent no item results for a search by item ID with item level 0: note what the Blizzard frame shows for the same item.
- [ ] With 12+ lines the "+N more" note still shows and the panel stays on screen (the headings take room: does the panel grow past the bottom of the screen?).

## Interface › Minimap (#321, part 1)
New file `MinimapStyle.lua` in the TOC: needs a full game restart once. Settings > Interface has three switches, all off by default.
- [ ] All three off: the minimap, its buttons and the addon compartment look exactly as before; `/reload` with Leatrix Plus and MinimapButtonButton loaded changes nothing.
- [ ] Square minimap on: the minimap is square (white mask), Blizzard's round frame art is gone and a thin Origami border sits on the edge. Do the map, the quest and POI blips, the player arrow and the ping stay inside and line up with the map? Is the border straight and the right size (Minimap is 198 units)? Zoom buttons, the clock, the zone text, mail and queue icons: do they still sit sensibly? Note anything that floats off the square.
- [ ] Square: toggle Esc > Options > "Rotate Minimap" (the `rotateMinimap` CVar). The square must stay (the hook on `MinimapCluster:UpdateMinimapConfig` re-applies it); in rotate mode the compass pointer is hidden, which is expected.
- [ ] Square off again (no reload): the round mask and Blizzard's frame art are back.
- [ ] Is the white texture `Interface\Buttons\WHITE8x8` accepted as a mask (a solid square, not an empty minimap)? If the minimap goes blank, the mask path is wrong: note it.
- [ ] Minimap buttons on: the addon buttons (LibDBIcon ones, CraftWise's own) fade out; Blizzard's own (zoom, tracking, mail, calendar, landing page button) stay. Moving the mouse onto the minimap shows them, moving onto one of them keeps them, leaving hides them again. Buttons made late (after `/reload`, a few seconds in) are caught too.
- [ ] Minimap buttons with MinimapButtonButton loaded: its own button and its bar work as before; a button it has collected is no longer faded; no Lua errors. Switching the option off again gives every faded button back at full alpha.
- [ ] Addon compartment on: the compartment button is gone and stays gone after `/reload`, zoning and the next addon registration. Off: it is back.
- [ ] Leatrix Plus loaded: Settings > Interface shows the note that both act on the same things.

## Interface › Flight map (#321, part 2)
New file `FlightTimes.lua` in the TOC: needs a full game restart once. Settings > Interface: Flight times, Flight bar, Bigger flight map (+ size); all off by default.
- [ ] All off: the flight map, its tooltips and flights are exactly as before; no Lua errors.
- [ ] Which frame does Forever open: `TaxiFrame` (`/dump TaxiFrame:IsShown()` with the map open) or `FlightMapFrame`? Both are hooked; note which one shows the tooltip line.
- [ ] Flight times on, open a flight master: hover a reachable node: a grey line "Flight time: not recorded". Fly there. After landing, `/dump CraftWiseDB.flights` has `[start][destination] = { secs, n = 1, t }` and the hover line reads "Flight time: m:ss". Nothing is shown on the current or an unreachable node. Hover several times: the line is there once.
- [ ] Is the time right? Compare with a stopwatch from the takeoff to the landing (within a second or two). Fly the same route again: n = 2, the time updates.
- [ ] A route with a stop on the way (destination reached over two or more legs): does the flight land at the stop (PLAYER_CONTROL_GAINED fires) or fly through? If it lands at the stop, the first landing is **not** a whole route: check that it is not recorded under the final destination (a flight is recorded only when control comes back after the last leg; note what happens).
- [ ] Cut short: take a new destination in the air, or use the "Request stop" button; after landing nothing new is recorded. Choose a destination and close the map without flying: nothing is recorded.
- [ ] `UnitOnTaxi("player")` is true when `PLAYER_CONTROL_LOST` fires at takeoff? (If not, the second check one second later should catch it; note if the bar then starts late.)
- [ ] Flight bar on: at takeoff a bar appears at the top ("To <destination>"); a route flown before shows the time left counting down, then "arriving"; a route never flown says "Time not recorded". With a multi-leg route the "next stop" is the first leg's stop and stays so for the whole flight (the client gives no progress): is that acceptable, or does the flight land there?
- [ ] Bigger flight map on: the flight map opens at the chosen size (1.0 to 1.5); does it stay on screen and keep clicking correctly? Turn it off: back to normal size without a reload.
- [ ] #333, landing: does `UnitOnTaxi("player")` turn false before or after `PLAYER_CONTROL_GAINED` in Forever? Fly with the bar on and after landing `/dump UnitOnTaxi("player")` at once and again a second later; note which. Either way the bar must be gone within about two seconds of landing and the flight recorded (`/dump CraftWiseDB.flights`), with a time from takeoff to the moment control came back (stopwatch to the landing, within a second or two).
- [ ] #333, walking out of the flight master with a pet out right after landing: the bar does not stay on screen.
## Interface › Tooltips (#321, part 3)
New file `UnitTooltip.lua` in the TOC: needs a full game restart once. Settings > Interface: "Unit tooltip: target" and "Unit tooltip: guild rank", both off by default.
- [ ] Both off: unit tooltips look as before.
- [ ] Target on: hover a player or mob that is targeting something: a line "Target: <name>" under the tooltip, the name in the class colour for players; "you" when it targets you. A unit with no target: no line. Hover for a while: the line follows the target and is never doubled.
- [ ] Guild rank on: hover a guilded player: the "<Guild>" line reads "<Guild> - Rank"; hover a player without a guild and an NPC: unchanged. Is the guild name on the second line (the module looks in lines 2 to 4)? Does the rank show for players who are not in your group (GetGuildInfo(unit) needs the unit inspected/in range)?
- [ ] In combat and in a raid with secret values: no Lua errors from hovering units.
- [ ] CraftWise's item tooltip lines are unchanged (item post call is separate).
- Left out on purpose: "hold Shift to see a tooltip hidden in combat": CraftWise hides no tooltips in combat.
## Interface › Dressing room (#321, part 4)
New file `DressingRoom.lua` in the TOC: needs a full game restart once. Settings > Interface: "Dressing room: undress" and "Dressing room: animation", both off by default.
- [ ] Both off: the dressing room has no extra buttons.
- [ ] Undress on: open the dressing room (try on an item from the bags or a link). "Undress" and "Try-ons only" sit at the top left of the model. Do they overlap anything of Blizzard's frame? Undress strips everything, weapons too.
- [ ] Try on two items (shift-click links, Ctrl-click bag items): "Try-ons only" strips the model and puts back just those two. Click Blizzard's Reset: "Try-ons only" has nothing to show until you try on something new. Close and reopen the room: the list starts empty.
- [ ] Items tried on from the wardrobe or a set are **not** tracked (they do not come through `DressUpVisualLink`): note whether they are kept or dropped by "Try-ons only".
- [ ] Animation on: a "Pause" button; it freezes the model's animation and reads "Play"; Play resumes. Does the pause stay when you try on another item or zoom? Does it also pause the character frame's model (`SetPaused(paused, false)` should not touch the global pause)?
- [ ] Off again: the buttons disappear without a reload.
## Interface › small ones: volume and Wowhead link (#321, part 5)
New file `InterfaceExtras.lua` in the TOC: needs a full game restart once. Settings > Interface: "Master volume" and "Wowhead link", both off by default. (Keep audio synced is not built yet: it waits for evidence of a sound-restart function, #321.)
- [ ] Both off: nothing new on the minimap, no box, the item menu has no Wowhead entry.
- [ ] Master volume on: a thin slider at the bottom inside the minimap (110 wide). Does it fit under the zone text/coordinates without covering anything useful? Drag it: Esc > Options > Audio > Master Volume follows; change the option there: the slider follows (CVAR_UPDATE). Mouse wheel on the slider moves it by 5 %. Square minimap on too: still inside the border?
- [ ] Wowhead link on: hovering items opens nothing. Middle-click an item in the bags: the item menu has a "Wowhead link" entry (after Price history); click it: a box at the bottom of the screen shows `https://www.wowhead.com/forever/item=<id>`. Click the box: the text is selected; Ctrl+C, paste into the browser: does the page open? Typing in the box does not change the text; "x" hides it.
- [ ] Open the quest log (map) and a quest's details: a small "Wowhead" button at the top right of the details. Is it where it should be (does it cover the back button or the title)? Click it: the box shows `.../forever/quest=<id>` with the quest title. Close the quest log: the box for a quest goes; one for an item stays. Does the details frame exist in Forever as `QuestMapFrame.DetailsFrame` (if no button appears, it does not)?
- [ ] Is the `forever/` path right for items and quests, and does a localized client need another prefix?
## Auctions: expired before warning (#327)
No new file, `/reload` is enough. Settings > Sale alert > "Expired before" (on by default) and Settings > Tooltip > "Expired unsold before" (on by default).
- [ ] Let an auction of one item expire (12 hours), or use an item that expired earlier (records go back 30 days; `/craftwise auctions` lists them). Open the AH, Sell tab, put that item into Blizzard's sell frame: a red "Expired before:" line with date and time, duration, unit price and (x quantity) sits at the top left, under "Marked Keep" if the item is also marked Keep. Does it overlap the item slot or the frame's title? Does it fit on one line for a long price? Check both the item sell frame (gear) and the commodities one (stack item).
- [ ] The date follows your client's date format (`%x`), the duration is the client's own text.
- [ ] Two expired posts of the same item: "and 1 more" at the end, the newest one is shown. A cancelled auction, a sold one, and an expiry at the other faction's house do not count.
- [ ] Pick another item or clear the slot: the line goes. Settings off: no line. Posting works as before, no taint error in chat.
- [ ] Hover the item with the AH open: a "Expired before" row in the CraftWise tooltip section. With the AH closed: no row (the house is unknown). Auctionator's Selling tab is not hooked: the tooltip row is the cue there.
- [ ] Does `GetItem()` of Blizzard's sell frame return the picked item after `SetItem` in Forever, so the label appears?


## Sell › Flips (#330)
New files `Flips.lua` and `UI/Main/Pages/Flips.lua` in the TOC: needs a full game restart once. No setting; the page is Sell › Flips.
- [ ] Buy 10 of an item at the AH (commodity), take them from the mail/AH delivery, sell all to a vendor (right-click). Sell › Flips shows one row: when, the item name, 10 units, AH cost, what the vendor paid, the profit (red when negative). The hero shows the same profit, the flip and unit count, and "best: <item> +X".
- [ ] Sell part of a stack: the row covers only those units, cost is their share of the average AH price. Buy a second batch at another price: the average of both applies.
- [ ] Sell units you looted or bought from a vendor: no row. Sell a stack where some units came from the AH and some from loot: one row for the AH units, tooltip on the name says how many units were left out.
- [ ] Buy the sale back from the vendor's buyback tab: the row goes, the profit goes down. Sell the units again: the old AH cost is used again.
- [ ] Chips Today / 7 days / 30 days / All change hero and list. After /reload the history is still there. Docked layouts (left, right) draw the page too.
- [ ] Does the hero caption with the best items fit on one line in the window and in the dock?

## Ledger: AH item purchases (#337)
- Buy one item auction (not a commodity) at the AH with Blizzard's own Buy tab, then one from CraftWise's buy panel. Each gives one `ahbuy` entry in `/craftwise ledger` with the row's buyout (stack of 1 or more).
- `/craftwise debug` prints the AH purchase trace: `PlaceBid <id> bid <copper>`, `auction <id> in <source> ... found`, `pending: item ... from <source>`, then `AUCTION_HOUSE_PURCHASE_COMPLETED ... logged ahbuy`. Which line is missing tells which step failed. `/craftwise debug ledger` echoes lines live.
- Sell the bought units to a vendor: Sell › Flips shows one flip with cost, vendor paid and profit.
- A bid below the buyout, or a buyout the server refuses, logs nothing.

## AH buy: the next profitable auction on each press, no search in between (#335)
No new files. Item auctions only (gear, recipes); commodities buy their quantity in one purchase as before. Try it with cheap items first, a flip or snipe line with several auctions under the max price.
- [ ] **Does the client resend item results after a purchase?** Blizzard's UI code does not send a new query after PlaceBid (it only redraws on ITEM_SEARCH_RESULTS_UPDATED / _ADDED), so this comes from the client: buy one auction of an item with several listed (Toughened Leather Armor), then `/etrace` or watch the panel. Note: does ITEM_SEARCH_RESULTS_UPDATED arrive, before or after AUCTION_HOUSE_PURCHASE_COMPLETED, and with the bought auction already gone from the list?
- [ ] If it arrives: the status line says "Bought 1 for X", the button shows the next one ("Buy 1 for X (N more under max)") with no search. Press again: the next auction is bought. Each press is one purchase; a held key buys one.
- [ ] If it does not arrive: the status says "Bought 1 for X. The list is old: search again." and the button stays off, as before.
- [ ] After three buys the status reads "Bought 3 for <total>". Picking another line or closing the AH starts a new count.
- [ ] A price above the max or a vanished auction: nothing is bought, the panel says why. The auction you just bought is never offered again, even if the list still shows it.
- [ ] An error ("Internal auction error"): the status line names it ("... (error N). Search again."), nothing is retried, and a list that arrives afterwards does not re-enable Buy. Note the error number and what you were doing.

## AH item buys that answer with error 10 (#340)
- Buy one item auction from the CraftWise panel. The server may send "Internal auction error (error 10)" and still complete the purchase. The panel then reads "Bought 1 for X (the server also sent error 10). Search again.", never "failed"; the auction is not offered again.
- `/craftwise ledger` has the `ahbuy` entry; `/craftwise debug` shows `AUCTION_HOUSE_SHOW_ERROR error 10 (pending bids kept)` and `logged ahbuy`.
- Sell the units to a vendor: Sell › Flips shows the flip.
- An error with no completion logs nothing; closing the AH or waiting 60 s drops a pending bid.

## Flips: profit per purchase (#339)
No new files. Display and selection only; the buy path is untouched. Needs a scan with a one-at-a-time item (gear that does not stack) and a commodity below the vendor price.
- [ ] A gear item that does not stack, listed a few copper under its vendor price (e.g. Toughened Leather Armor): it is no flip at the default 10c minimum. Settings > AH to vendor flips > "Smallest profit per purchase" down to 0 or 1c brings it back.
- [ ] Mixed: a gear item with a few auctions well under the vendor price and many a few copper under: only the good auctions count; the line's max price is the vendor price minus the minimum (not minus 1c); the Auctionator list search has that max.
- [ ] Order: panel, toast, Make > Basket and the Auctionator list all list the flips by profit per purchase (an item's best margin, a commodity's total), not by total profit.
- [ ] The AH panel's flip lines show "+3c each · N buys" (items) or "1 buy" (commodities) at the right of the name; the summary's second line starts with the number of purchases. Does it fit at 340 wide?
- [ ] The client's stack size: does C_Item.GetItemInfo return 1 for gear, a larger number for cloth/herbs? A line that says "buys not known" means the item was not cached at the scan; it fills in on the next scan. Are there stackable items that are not commodities (one purchase per auction)? Note them: they are counted as one purchase now.

## Ledger: one unit per item PlaceBid, repair of #338 data (#343)
- On login after this build, chat prints "Ledger repair (#343): ..." once (only if the old data had inflated item buys). `/craftwise ledger` then shows those AH purchases as x1, and Sell › Flips shows the real profit (about +1c for the 12s 49c plans sold for 12s 50c).
- Buy a plan from a grouped row (row quantity above 1) with one press: the ledger logs x1 at the row's buyout. A stackable item bought this way is not logged (`/craftwise debug` says "units of one purchase unknown").

## Loops: the check after a full scan, and "Check now" (#345)
- [ ] Put an item up at the auction house (sell frame search, post): no toast, no CPU spike in Settings > Debug > Record under "Loops.lua check".
- [ ] Run our own full scan (the header button) with a vendor loop, flip or snipe available: the check runs about 4 seconds after the scan is stored and one toast shows what is new; "Loops.lua check" is in the recorder.
- [ ] Settings > Vendor loops > "Check now": prints "Check done: N new." or "nothing new" at once; a toast only for what is new since the last notice. The window layout of that row is provisional (docked and normal).
- [ ] After the companion's merged market is synced in at login with new prices: one check runs, not one per item.
- [ ] Everything off (Loop alert, Flip alert, Snipe alert): a full scan runs no check.
## Flips: commodities first, one by one after (#344)
- [ ] A scan with a commodity flip (small total) and a one-at-a-time item flip (bigger margin per purchase): panel, toast detail, Make > Basket and the Auctionator list all show the commodity first. The AH panel has two headings, "Flips · bulk" and "Flips · one by one". Do the headings read well at 340 wide?

## AH buy: grouped item rows are one purchase (#343)
- [ ] Find an item search row with quantity above 1 (several identical auctions, e.g. a plan or pattern listed by many sellers). The panel's "Listed now" shows "1 × price · N listed, one per purchase" and the Buy button says "Buy 1 for <the buyout>", never the quantity.
- [ ] With the line's max under that buyout nothing is bought, whatever N is. At or above it one press buys one item and the amount taken is exactly the buyout (check the gold). Compare with Blizzard's own AH list: quantity column = N, buyout column = the same price.

## Bags full: suggest the cheapest Junk slot, or a stack (#352)
No new files. Needs bags with no free slot and a few items marked Junk (item menu). Settings > Bags and loot > "Suggest a junk item to delete when bags are full" is on by default (provisional; Veli's call).
- [ ] Fill every plain bag slot (the reagent bag may stay empty), mark a cheap item Junk, loot a mob with fast auto-loot: ONE chat line "Bags are full. Left in the loot window: ... Delete <item> xN (worth ...)." and the small panel "Bags are full" appears. Nothing is deleted or moved by itself.
- [ ] Is the cheapest slot really the lowest vendor price x count? Compare two stacks of the same Junk item (a partial one and a full one): the partial one is offered.
- [ ] The panel's "Delete..." button opens CraftWise's confirm dialog naming the item, the count and the value; "Cancel" and Escape delete nothing. "Accept" deletes exactly that one stack (check DeleteCursorItem is allowed from the dialog's button: restricted function, needs the click). Then the panel closes.
- [ ] Loot something cheap while the cheapest Junk slot is worth more: the line ends with "not worth it, the loot is worth less".
- [ ] A Junk item with no vendor price (sell price 0) is offered first and says "no vendor price, worth nothing".
- [ ] Two partial stacks of one item (e.g. 8 and 5 Linen Cloth): the panel offers "Stack Linen Cloth: 2 slots -> 1" and the button moves one stack per click.
- [ ] Not offered, ever: Keep items, quest items, unmarked items, anything in the reagent bag, a profession bag, the bank.
- [ ] Buy something at a vendor or take mail with full bags: which error does the client send? Only ERR_INV_FULL is handled; if the client sends another text for vendor or mail, note it here (no guessed strings).
- [ ] CraftWise > Sell > Bags with no free slot: footer starts with the suggestion and a "Free a slot" (or "Stack") chip sits next to "My crafting materials". Does the tools row still fit in the docked layout?
