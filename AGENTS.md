# Working on CraftWise

Instructions for anyone (human or AI agent) picking up this project.

## Where things are tracked
- **All planned work, decisions and open questions live in GitHub issues.** No roadmap or TODO files in the repo.
- **Milestones** group issues by phase: `Live` (current; WoW: Forever launched Nov 4 2026, `Beta` is closed), `Market data`, `Later`.
- **Labels**: `mvp` (needed for the first usable version), `later`, `spike` (verify an assumption in game), `data` (game data we need).
- Decisions made in conversation are written as a comment on the issue they affect. Commits reference issues (`#12`).
- Before starting, read the open issues of the current milestone and the latest comments on the one you pick.

## Project rules
- **No guessed data.** Only first-hand client data, data recorded in game, and verified datasets. Anything unverified stays out and is listed in #11.
- Addon stays free (Blizzard add-on policy). Paid features, if any, live on velikopter.com.
- No anti-AFK or input automation. The companion app (#7) only reads SavedVariables.
- Supabase: no service keys in clients, uploads through an Edge Function, RLS on every table.
- License GPL-3.0. Bundled data files under `CraftWise/Data/` keep their source header.

## Merge rule
- PRs may be squash-merged by the Worker or the Scout once CI (`test`) is green and the Scout posted "Scout review: approved" with no open `needs:owner`.
- Release-relevant, these need Veli's go:
  - `.github/workflows/**`
  - `CraftWise/CraftWise.toc`
  - `tools/package.sh`, `tools/changelog.py`, `CHANGELOG.md`
  - version bumps and tags
  - every release

## Code
- WoW: Forever client (interface 16001, Mainline 12.x API, Lua 5.1 sandbox, no `require`). Files load in `CraftWise/CraftWise.toc` order, each gets `local addonName, ns = ...`. A new file must be added to the TOC; adding files needs a full game restart, `/reload` is not enough.
- Modules: `Core.lua` (events, DB, slash), `Prices.lua`, `Market.lua` (price history per auction house, own SavedVariables `CraftWiseMarketDB`, #26), `Profit.lua` (pure maths), `Recipes.lua` (recipe cache, status, sources), `Trainer.lua`, `Bags.lua`, `UI/`. The profit window is `UI/ProfitFrame/`, one file per responsibility (State, Fishing, Data, Rows, Tooltips, SongPicker, Layout, Refresh, Frame, Events); they share internals through `ns.PF`, and each file only uses what the files before it in the TOC export.
- Tests: `lua5.1 tests/run.lua` (headless, stubbed client in `tests/wowstub.lua`). Run before every commit. What the stub can't cover goes in `docs/ingame-checks.md`.
- API audit (part of the tests): every client function and event the addon uses must be in `tests/forever_api.lua`, generated from Blizzard's API docs for the Forever client (`lua5.1 tools/gen_api_index.lua <wow-ui-source checkout, branch forever> > tests/forever_api.lua`; regenerate after client patches). Undocumented legacy functions go in `tests/api_allowlist.lua` with evidence (Blizzard's Forever UI calls it, or seen working in game). Don't use deprecation fallbacks (`DoEmote`, `IsPlayerSpell`, global `GetItemInfo`/`GetSpellInfo`): they only exist when the `loadDeprecationFallbacks` CVar is on. Functions marked restricted (e.g. `C_ChatInfo.PerformEmote`) need a hardware event (key binding, click, slash command).
- Companion (Go, `companion/`, module `github.com/velibkolay/CraftWise/companion`, stdlib only): `svparse` parses SavedVariables, `market` ports Market.lua's packed formats (entries, item info, Auctionator prices), `savedvars` reads CraftWiseMarketDB and the snapshots into typed values; the app (#94, `docs/companion.md`): `upload` (delta since the last upload, requests per `web/docs/api.md`, retries), `watch` (file watcher), `app` (settings, run, loop), `tray` (Windows tray via the Win32 API, no cgo), `autostart` ("Start with Windows": the Run registry value behind a small Store interface, decisions tested with a fake), `cmd/craftwise-companion`. Run `go test ./...` in `companion/`; CI also cross-compiles windows/amd64 and darwin/arm64. Its fixtures are written by the Lua code: after changing a packed format or a table the companion reads, run `lua5.1 tests/companion_fixtures.lua` and commit both files (the Lua spec fails while the golden file is out of date).
- Web (`web/`, wow.velikopter.com, #100): Cloudflare Worker (TypeScript) + D1, static pages in `web/public/`, their scripts in `web/site/` (plain TypeScript, no framework; `npm run build` bundles them with esbuild into the ignored `public/assets/`, and wrangler runs it before every deploy and dev run). Skin values only in `public/css/tokens.css`; the Velikopter skin maps the brand kit (velibkolay/velikopter-brand) onto them: its `tokens/velikopter-tokens.css` is copied unchanged to `public/css/velikopter-tokens.css` (header names the commit) and its fonts to `public/fonts/`, so re-copy both when the kit changes; item class and quality names come from `site/lib/enums.ts` (`lua5.1 tools/gen_item_enums.lua <wow-ui-source checkout> > web/site/lib/enums.ts`). API and upload contract: `web/docs/api.md`; deploy steps: `docs/web-deploy.md`. Tests: `cd web && npm ci && npm test` (vitest in the Workers runtime), plus `npm run typecheck`; CI job `web`. Schema changes are new files in `web/migrations/`, never edits of applied ones. Free plans only.
- Bundled data: `CraftWise/Data/Thresholds.lua`, `Recipes.lua`, `Vendor.lua` and `Sources.lua` are generated from the client's DB2 tables on wago.tools. Move `BUILD` and `SOURCE_DATE` in `tools/gen_thresholds.py`, then run `python3 tools/gen_thresholds.py`, `tools/gen_recipes.py`, `tools/gen_vendor.py` and `tools/gen_sources.py` in that order (Python 3.10+, stdlib only; downloads are cached in the ignored `tools/.cache/`). The generators are adapted from cjber/skillup-forever (GPL-3.0); their headers say what changed. Then run `lua5.1 tools/gen_site_recipes.lua`: it writes the site's recipe data `web/public/data/recipes.json` (#143: recipe item -> spell and required skill, spell -> reagents and output, vendor buy and sell prices, with each data file's source header) from those files; commit it with them (`tests/site_recipes_spec.lua` fails while it is out of date).

## Install for testing
Copy `CraftWise/` into `World of Warcraft/_forever_/Interface/AddOns/`, then `/reload` (or restart after TOC changes). `/craftwise debug` prints what is cached. Saved data is in `WTF/Account/<account>/SavedVariables/CraftWise.lua` and per character under `WTF/Account/<account>/<realm>/<character>/SavedVariables/`.
