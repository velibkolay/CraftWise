# Working on CraftWise

Instructions for anyone (human or AI agent) picking up this project.

## Where things are tracked
- **All planned work, decisions and open questions live in GitHub issues.** No roadmap or TODO files in the repo.
- **Milestones** group issues by phase: `Beta` (before the WoW: Forever launch, Nov 4 2026), `Market data`, `Later`.
- **Labels**: `mvp` (needed for the first usable version), `later`, `spike` (verify an assumption in game), `data` (game data we need).
- Decisions made in conversation are written as a comment on the issue they affect. Commits reference issues (`#12`).
- Before starting, read the open issues of the current milestone and the latest comments on the one you pick.

## Project rules
- **No guessed data.** Only first-hand client data, data recorded in game, and verified datasets. Anything unverified stays out and is listed in #11.
- Addon stays free (Blizzard add-on policy). Paid features, if any, live on velikopter.com.
- No anti-AFK or input automation. The companion app (#7) only reads SavedVariables.
- Supabase: no service keys in clients, uploads through an Edge Function, RLS on every table.
- License GPL-3.0. Bundled data files under `CraftWise/Data/` keep their source header.

## Code
- WoW: Forever client (interface 16001, Mainline 12.x API, Lua 5.1 sandbox, no `require`). Files load in `CraftWise/CraftWise.toc` order, each gets `local addonName, ns = ...`. A new file must be added to the TOC; adding files needs a full game restart, `/reload` is not enough.
- Modules: `Core.lua` (events, DB, slash), `Prices.lua`, `Profit.lua` (pure maths), `Recipes.lua` (recipe cache, status, sources), `Trainer.lua`, `Bags.lua`, `UI/`.
- Tests: `lua5.1 tests/run.lua` (headless, stubbed client in `tests/wowstub.lua`). Run before every commit. What the stub can't cover goes in `docs/ingame-checks.md`.
- API audit (part of the tests): every client function and event the addon uses must be in `tests/forever_api.lua`, generated from Blizzard's API docs for the Forever client (`lua5.1 tools/gen_api_index.lua <wow-ui-source checkout, branch forever> > tests/forever_api.lua`; regenerate after client patches). Undocumented legacy functions go in `tests/api_allowlist.lua` with evidence (Blizzard's Forever UI calls it, or seen working in game). Don't use deprecation fallbacks (`DoEmote`, `IsPlayerSpell`, global `GetItemInfo`/`GetSpellInfo`): they only exist when the `loadDeprecationFallbacks` CVar is on. Functions marked restricted (e.g. `C_ChatInfo.PerformEmote`) need a hardware event (key binding, click, slash command).

## Install for testing
Copy `CraftWise/` into `World of Warcraft/_classic_beta_/Interface/AddOns/`, then `/reload` (or restart after TOC changes). `/cw debug` prints what is cached. Saved data is in `WTF/Account/<account>/SavedVariables/CraftWise.lua` and per character under `WTF/Account/<account>/<realm>/<character>/SavedVariables/`.
