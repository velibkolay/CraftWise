# CraftWise Companion (#94)

A small app that uploads CraftWise's saved data to wow.velikopter.com. It watches
`World of Warcraft/_forever_/WTF/Account/<account>/SavedVariables/CraftWise.lua` (the game writes it
on `/reload` and logout) and, after each change, sends what is new since the last upload:

- **Public** (`POST /api/upload`): auction houses, scans, item names and info with the vendor sell
  price, the client's class and subclass names (#120; only new or changed ones), prices (only new raw
  points, changed daily aggregates and newer `last` values per item and house). Never the
  Auctionator fallback prices.
- **Private** (`POST /api/private/upload`, can be turned off): each character's snapshot, the
  auction tracker's records, the fishing summary, new ledger entries and the item watch list (#165,
  `CraftWiseDB.watch`, sent whole when it changed; the site shows it as favourites, one way, never written back).

The request format is `web/docs/api.md`. The companion reads the game's files (never SavedVariables for
writing: no game memory, no input) and writes exactly one thing into the World of Warcraft folder:
the sync add-on `CraftWise_Sync` (see "Sync with the other machine"). Everything else it keeps in its own
folder.

## Build

Go 1.22 or newer, no other dependencies, no cgo:

```sh
cd companion
# Windows tray app (no console window)
GOOS=windows GOARCH=amd64 go build -ldflags "-H=windowsgui -X main.version=dev" -o craftwise-companion.exe ./cmd/craftwise-companion
# Windows console build, for -once / -status / -dry-run in a terminal
GOOS=windows GOARCH=amd64 go build -o craftwise-companion-cli.exe ./cmd/craftwise-companion
# macOS (Apple silicon)
GOOS=darwin GOARCH=arm64 go build -o craftwise-companion ./cmd/craftwise-companion
```

## Icon (#310)

The tray icon and the exe's icon are the W key brand mark (the site's app key, `web/public/img/key-wow-32.svg`).
`python3 tools/gen_companion_icon.py` (stdlib only) writes, all committed:

- `companion/tray/craftwise.ico`: 16, 20, 24, 32, 40, 48, 64 and 256 px. 24 px and up are the key rendered with
  the rasteriser of `tools/gen_addon_textures.py`; 16 and 20 px are drawn for their pixel grid (no nokta, a
  pixel-art W). Embedded with `go:embed`; the tray takes the smallest image at least as big as the system's small
  icon size (`GetSystemMetricsForDpi(SM_CXSMICON)`), so it is only ever scaled down. The old drawn coin is the
  fallback if loading fails.
- `companion/cmd/craftwise-companion/rsrc_windows_amd64.syso`: the same images as Windows resources
  (RT_ICON, RT_GROUP_ICON), linked by `go build` for windows/amd64 with no extra step. Explorer, the taskbar and
  Startup apps show it.
- `companion/tray/icon-preview.png`: every size on a light and a dark ground, 1x and 8x.

Rerun the script after changing the key or the pixel W, and commit the three files. macOS: the companion has no
menu bar icon and is no app bundle (a plain binary run in the terminal), so there is nothing to put an icon on;
a `.app` bundle with an `.icns` is a later step if one is ever wanted.

## Use

1. Start it once: it creates the settings file and looks for WoW.
2. On wow.velikopter.com/me create an upload token (scopes `public` and `private`) and put it into
   the settings ("Open settings" in the tray menu, or `-open config`).
3. "Upload now", or `/reload` in game.

On Windows it runs in the notification area. The menu shows the last check and its result, and has
Upload now, Open wow.velikopter.com, Open my page, Open settings, Open log, Start with Windows and
Quit. On macOS (and with `-no-tray`) it runs in the terminal and logs there; there is no menu bar
icon (a tray on macOS needs cgo and would stop the cross-compiled build).

Autostart on Windows: tick "Start with Windows" in the menu (or `-autostart on`). It writes the value
`CraftWise Companion` under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` with the quoted
path of the running exe; unticking removes it. The tick shows only when that value starts this exe:
after moving the exe it shows unticked, and ticking it again writes the new path. A shortcut to the
exe in `shell:startup` works too (then leave the menu item unticked, or it starts twice; the second
one exits because one is already running).

Autostart on macOS: `./craftwise-companion -autostart on` writes
`~/Library/LaunchAgents/com.velikopter.craftwise-companion.plist` (runs the binary at login, no
`KeepAlive`, so quitting it keeps it down); `-autostart off` deletes it. launchd picks it up at the
next login; it does not start a second copy now. `-status` shows `Start at login: on` only when the
plist starts this exact binary, so after moving the binary run `-autostart on` again.

Command line:

| Flag | |
|---|---|
| `-once` | upload once and exit (exit code 1 on failure) |
| `-dry-run` | build the requests and log their size, send nothing, change no state |
| `-dump <dir>` | dry run, and write the request bodies as JSON into `<dir>` |
| `-full` | with `-once`: send everything again |
| `-status` | print the file locations, the last upload and (Windows, macOS) whether it starts at login |
| `-autostart on\|off` | Windows: start with Windows or not (same as the menu item); macOS: start at login (LaunchAgent); then exit. Elsewhere it prints "only on Windows and macOS" and exits with 1 |
| `-open site\|me\|config\|log` | open one of them and exit |
| `-no-tray` | run in the foreground (Windows) |
| `-dir <dir>` | settings, state and log directory |

## Install on a Mac (Apple silicon)

1. Build it (needs Go 1.22+) or copy the `craftwise-companion` binary from the PC:
   `cd companion && GOOS=darwin GOARCH=arm64 go build -o craftwise-companion ./cmd/craftwise-companion`
2. Put it where it stays, e.g. `~/Applications/CraftWise/`, and make it runnable:
   `chmod +x ~/Applications/CraftWise/craftwise-companion`. If macOS blocks a copied binary:
   `xattr -d com.apple.quarantine ~/Applications/CraftWise/craftwise-companion`.
3. Run `~/Applications/CraftWise/craftwise-companion -open config`. It creates the settings file
   (`~/Library/Application Support/CraftWise Companion/config.json`) and opens it.
4. On wow.velikopter.com/me (signed in) create an upload token with scopes `public` and `private`
   and paste it as `token` in `config.json`. Leave `wowPath` empty if WoW is in
   `/Applications/World of Warcraft`, else set it to the `_forever_` folder.
5. Check: `~/Applications/CraftWise/craftwise-companion -once`, then `/me` shows this Mac's
   characters (log in and `/reload` in game first, so `CraftWise.lua` exists).
6. Start at login: `~/Applications/CraftWise/craftwise-companion -autostart on`. Log out and in
   (or reboot); `companion.log` in the settings folder shows "CraftWise Companion ... started".
   Turn it off with `-autostart off`.

## Sync with the other machine (#237, #239)

With two machines on one account, both upload their market scans and each gets the other's back, so the
price history is one market. After every successful upload, and at start, the companion downloads what
changed on the site and writes it into a small data add-on that CraftWise loads at login or `/reload`:

1. `GET /api/sync/market?since=<t>` (`web/docs/api.md`, #238; the token needs the `public` scope, the same token as the upload). The answer has
   the shape of the `POST /api/upload` body (`houses`, `scans`, `names`, `itemInfo`, `classNames`,
   `subclassNames`, `items[item key][house key] = { last, raw, days }`) plus `until` (the server time to ask
   from next time) and, for a long first download, `next` (a cursor; the companion follows the pages).
   The first run asks `since=0` and gets everything. Each entry is complete (merged from both machines),
   so a download replaces entries in `market-cache.json`.
2. The cache holds everything downloaded; the add-on file is always written from the whole cache.
3. `CraftWise_Sync` is written into `<wowPath>/Interface/AddOns/CraftWise_Sync/` (the folder and the TOC are
   created if missing). The companion writes only these two files, atomically (a temporary file next to it,
   then a rename, so a game that is loading never reads half a file), and rewrites the Lua file only when the
   data or the machine name changed. It never writes SavedVariables or anything else in the game folder.

`CraftWise_Sync.toc`: interface 16001, Title, `## Dependencies: CraftWise`, no SavedVariables.

`CraftWise_Sync.lua` sets one global (format version 1; the addon ignores a higher `v`):

```lua
CraftWiseSync = {
  v = 1,
  written = 1763200000,        -- unix time the companion wrote it
  machine = "PC",              -- this machine's name (setting `machine`, default host name)
  market = {                   -- all of the merged market, not a delta
    houses = { ["Realm|H"] = { realm = "Realm", kind = "faction", faction = "Horde", label = "Realm Horde" } },
    scans = { ["Realm|H"] = { { t = 1763000000, kind = "full", items = 1200, lastOnly = 300, source = "..." } } },
    names = { [2589] = "Linen Cloth" },
    itemInfo = { [2589] = "q,i,c,s,t,p" },      -- Market.lua's packed item info
    classNames = { [7] = "Trade Goods" },
    subclassNames = { [7] = { [5] = "Cloth" } },
    items = {
      [2589] = { ["Realm|H"] = "last|raw|days" },       -- Market.lua's packed entry (`market.Encode`)
      ["2589:123"] = { ["Realm|H"] = "..." },           -- a suffix variant: string key
    },
  },
}
```

Entries are Market.lua's packed strings, so the addon decodes them with its own code and merges them into
`CraftWiseMarketDB` per house and item. Strings are Lua-escaped; item keys are numbers, or `"<id>:<suffix>"`
for variants; table order is not defined.

**No echo.** The addon merges downloaded entries into `CraftWiseMarketDB`, so the next upload would find
them in SavedVariables and send the other machine's data back as new. Before the file is written, the
companion marks everything it downloaded in `state.json`: the newest scan time per house, the hashes of
names and item info, class names, the newest `last` time per item and house, the days' hashes and the
times of the downloaded raw points (`got`, kept 3 days, the addon keeps raw points 48 h). A recording made
on this machine has its own time, so it is still sent, even when it is older than a downloaded one. A day
that the merge changed differs from what was marked and is sent again; the server keeps the better one.

A failed download (network, 5xx, 429) retries like an upload; a refusal (401, 403)
is logged and tried again after the next upload. Nothing changes on a failure: the cache, `since`, the marks
and the add-on file stay as they were. Turn it off with `"sync": false`.

The machine name goes into the file and every request (header `X-CraftWise-Machine`) so the site can label
data later (#237 phase 2).

## Update on the Mac

After a merge, quit WoW and run, in the repo checkout on the Mac (on `main`, no local changes):

```sh
tools/update-mac.sh
```

`-n` only prints what it would do. It stops at the first failure and:

1. refuses while World of Warcraft is running;
2. `git pull --ff-only` (refuses on another branch or with local changes);
3. moves `AddOns/CraftWise` to `AddOns/_to_delete/CraftWise-old-<date-time>` (nothing is deleted),
   copies the repo's `CraftWise/` there and checks it with `diff -rq`;
4. builds the companion to `~/Applications/CraftWise/craftwise-companion` (temp name first, then
   moved over the old binary), stops a companion you started by hand (`nohup ...`; TERM, waits a
   few seconds) and restarts it through its LaunchAgent (`launchctl kickstart`, or `bootstrap` if
   it isn't loaded). Without the plist it says to run `-autostart on` once and
   skips the restart;
5. prints the commit, the old addon folder's new name and whether the companion was restarted and whether a manually started one was stopped.

It never touches `WTF/` (SavedVariables), `AddOns/CraftWise_Sync` or the companion's `config.json`.
Other places: `CRAFTWISE_WOW` (the `_forever_` folder) and `CRAFTWISE_BIN` (the binary). Needs Go.

## Files

In `%AppData%\CraftWise Companion` (Windows) or `~/Library/Application Support/CraftWise Companion`
(macOS):

- `config.json`: the settings (only the user can read it; it holds the token).

  | Key | Default | |
  |---|---|---|
  | `site` | `https://wow.velikopter.com` | |
  | `token` | | upload token from /me |
  | `wowPath` | (found) | the `_forever_` folder; empty = `C:\Program Files (x86)\World of Warcraft\_forever_` and the same on drives C to G, `/Applications/World of Warcraft/_forever_` |
  | `account` | (newest) | folder under `WTF/Account`; empty = the account whose `CraftWise.lua` was written last |
  | `private` | `true` | also upload the private data |
  | `pollSeconds` | `5` | how often the file is checked |
  | `settleSeconds` | `3` | how long it must stay unchanged before it is read |
  | `sync` | `true` | download the merged market and write the `CraftWise_Sync` add-on (the upload token, `public` scope) |
  | `machine` | (host name) | this machine's name, sent with every request and written into the sync file |

  Changes apply at the next upload; a different `wowPath` or `account` switches the watched file.
- `state.json`: what was uploaded (per site and file). Delete it, or use `-once -full`, to send
  everything again; re-sending is harmless (the server ignores what it has).
- `market-cache.json`: the market downloaded so far and the time to ask `since` next. Delete it to download everything again.
- `companion.log`: what happened; kept at about 1 MB (the previous one is `companion.log.1`).

## Uploads

- A change is read once the file's size and time stayed the same for `settleSeconds`; a file that
  is still being written (cut off in the middle) is read again a little later.
- Requests stay below the server's limits: at most about 400 KB, 2,000 item/house entries, 5,000
  item IDs and an estimated 8,000 rows written each. A large first upload is split into many
  requests; each one is recorded as soon as the server accepted it, so an interrupted upload goes on
  where it stopped.
- Order: scans and prices first, then item info, names and class names in requests of their own
  (#145). Above 80% of the server's daily write budget those are refused until 00:00 UTC while prices
  are still taken, so a refusal holds back only them. A refused request stops the rest of its
  endpoint (public or private); the other endpoint is still sent.
- Retries: network errors and 5xx up to 5 tries (2 s, 4 s, 8 s ... at most 60 s apart); `429` waits
  `Retry-After` (up to 2 minutes in place; longer, e.g. the daily write budget, until that time); a
  `413` builds smaller requests. `400`, `401` and `403` are not retried: the log says why.
- A value the server would refuse (a price without a minimum, a time out of range, more than 8
  tiers) is left out and counted in the log; nothing is filled in.
- Documents: `snapshots` is the snapshot as `docs/snapshot.md` describes it; `auctions` is
  `CraftWiseMarketDB.auctions.chars[<character>]` with the time the file was read; `fishing` is the
  snapshot's `fishing` summary with its `fishingZones` ranking under that key. A document is sent
  again only when its content changed.
