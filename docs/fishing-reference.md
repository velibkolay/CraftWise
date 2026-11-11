# Local fishing reference (#88)

CraftWise's **Fishing** tab ranks zones by value per catch. It uses two sources and labels every row with the one it shows:

- **Own catches**: the fishing log (`/craftwise fishing`, #69/#86). Used once a zone has `fishingOwnMin` catches (default 50, `/craftwise fishing ownmin <n>`), and for zones the reference doesn't have.
- **Local reference**: a separate addon, `CraftWise_FishingRef`, that only exists on your PC. You save the web pages yourself and `tools/fishing_ref.py` turns them into the addon's data. It is never part of CraftWise or this repository (the repository is public; `.gitignore` lists the folder in case it ends up in a checkout).

## Build it

1. Create `World of Warcraft/_forever_/Interface/AddOns/CraftWise_FishingRef/pages/`.
2. Save pages into `pages/` with the browser's "Save page as" (HTML only, or complete: the `..._files` folders are ignored). Use the site language that matches your game client: zones are matched by name.
   - **Zone pages** (WoW: Forever zone pages with a *Fishing* tab): what was fished there, how often, out of how many recorded fishing loots, and the stack size range.
   - **Container item pages** with a *Contains* tab (trunks, crates, clams): what one opening gives. Without one, a container is valued by your own openings, else by its sell value.
   - **Fishing pool object pages** (optional): kept by object ID for later use; the ranking does not use them yet.
3. Run the converter (Python 3.10+, no extra packages) from the CraftWise checkout:
   ```
   python tools/fishing_ref.py "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\CraftWise_FishingRef"
   ```
   It writes `Data.lua` and `CraftWise_FishingRef.toc` into that folder and lists what it read and skipped (pages without a fishing or contains table, data it could not read, the same zone saved twice: the page with more recorded loots wins).
4. The first time, restart the game fully (a new addon is only found at start). After adding pages later, run the converter again and `/reload`.
5. `/craftwise` > **Fishing**, or `/craftwise fishing zones [name]` in chat.

## What the numbers mean

- **Chance** (reference): how often the item was recorded / recorded fishing loots in the zone (an item's own `outof` when the page gives one). Own catches: items caught per catch.
- **Units per catch** = chance x stack. The pages give a stack range, not a mean, so a range gives a low and a high value (`12s - 15s`); the ranking uses the low one. A row without a stack counts 1 and says so.
- **Unit value**: containers by the mean value of their contents (own openings first once there are 5, or any number when the reference doesn't have the container; else the reference's contents table), everything else by the best sell value at the profit house (AH typical or current after the cut, else vendor), as set in Settings. Items without any price are left out of the sums and counted (`+?`).
- **Per hour**: your own catches per hour in that zone (timed catches, sessions as in `/craftwise fishing`) x the value per catch shown. Empty until you have fished there.

The reference describes what other players recorded on that site; it is not client data and can differ from WoW: Forever as it is now. Own catches take over as soon as they are large enough.
