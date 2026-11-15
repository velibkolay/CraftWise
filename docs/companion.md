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

The request format is `web/docs/api.md`. The companion only reads the game's files: no game
memory, no input, nothing written into the World of Warcraft folder.

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

  Changes apply at the next upload; a different `wowPath` or `account` switches the watched file.
- `state.json`: what was uploaded (per site and file). Delete it, or use `-once -full`, to send
  everything again; re-sending is harmless (the server ignores what it has).
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
