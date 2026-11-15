#!/usr/bin/env bash
# Updates CraftWise on the Mac after a merge (#249): pulls main, replaces the addon, rebuilds and
# restarts the companion. Run it from the repo checkout:  tools/update-mac.sh   (-n: only print)
#
# Env: CRAFTWISE_WOW  the `_forever_` folder (default /Applications/World of Warcraft/_forever_)
#      CRAFTWISE_BIN  where the companion binary lives (default ~/Applications/CraftWise/craftwise-companion)
# Never touches WTF/ (SavedVariables), AddOns/CraftWise_Sync or the companion's config.json (token).
set -euo pipefail

dry=0
case "${1:-}" in
  -n|--dry-run) dry=1 ;;
  "") ;;
  *) echo "usage: tools/update-mac.sh [-n]" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
wow="${CRAFTWISE_WOW:-/Applications/World of Warcraft/_forever_}"
addons="$wow/Interface/AddOns"
bin="${CRAFTWISE_BIN:-$HOME/Applications/CraftWise/craftwise-companion}"
label="com.velikopter.craftwise-companion"
plist="$HOME/Library/LaunchAgents/$label.plist"

die() { echo "update-mac: $*" >&2; exit 1; }
# step prints what it does; with -n that is all it does.
step() { echo "+ $*"; if [ "$dry" = 0 ]; then "$@"; fi; }
[ "$dry" = 1 ] && echo "dry run: nothing is changed"

# 1. The game must be closed: it holds the addon files and writes SavedVariables on exit.
if pgrep -f "World of Warcraft" >/dev/null 2>&1; then
  die "World of Warcraft is running. Quit the game first, then run this again."
fi

# 2. Up to date main, nothing local.
cd "$root"
branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = main ] || die "the checkout is on '$branch', not main"
[ -z "$(git status --porcelain)" ] || die "the checkout has local changes; commit or discard them first"
step git pull --ff-only
commit="$(git rev-parse --short HEAD)"

# 3. Addon: move the old folder aside (never rm), copy, verify.
[ -f "$root/CraftWise/CraftWise.toc" ] || die "CraftWise/CraftWise.toc not found in $root"
[ -d "$addons" ] || die "no AddOns folder at $addons (set CRAFTWISE_WOW to the _forever_ folder)"
old="none (first install)"
if [ -d "$addons/CraftWise" ]; then
  old="_to_delete/CraftWise-old-$(date +%Y%m%d-%H%M%S)"
  step mkdir -p "$addons/_to_delete"
  step mv "$addons/CraftWise" "$addons/$old"
fi
step cp -R "$root/CraftWise" "$addons/CraftWise"
step diff -rq "$root/CraftWise" "$addons/CraftWise"

# 4. Companion: build next to the old binary, then replace it, then restart through launchd.
tmpbin="$bin.new"
step mkdir -p "$(dirname "$bin")"
echo "+ (cd companion && go build -o $tmpbin ./cmd/craftwise-companion)"
if [ "$dry" = 0 ]; then (cd "$root/companion" && go build -o "$tmpbin" ./cmd/craftwise-companion); fi
step mv "$tmpbin" "$bin"

uid="$(id -u)"
restarted="no"
stopped="no"
if [ ! -f "$plist" ]; then
  restarted="no: start at login is off, run '$bin -autostart on' once"
  if pgrep -f "$bin" >/dev/null 2>&1; then
    restarted="no: a manually started companion still runs the old binary; stop and start it by hand"
  fi
else
  # A companion started by hand (nohup ...) is not the launchd job: a second copy would not
  # replace it, so stop it first. The launchd job's own pid is left to kickstart -k.
  job="$(launchctl print "gui/$uid/$label" 2>/dev/null | awk '$1 == "pid" && $2 == "=" {print $3}' || true)"
  manual=""
  for pid in $(pgrep -f "$bin" 2>/dev/null || true); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$job" ]; then manual="$manual $pid"; fi
  done
  for pid in $manual; do step kill -TERM "$pid"; done
  if [ -n "$manual" ]; then
    stopped="yes (pid$manual)"
    if [ "$dry" = 0 ]; then
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        alive=""
        for pid in $manual; do if kill -0 "$pid" 2>/dev/null; then alive=1; fi; done
        [ -z "$alive" ] && break
        sleep 0.5
      done
      [ -z "$alive" ] || die "the manually started companion (pid$manual) did not stop; stop it, then run this again"
    fi
  fi
  if [ -n "$job" ] || launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
    step launchctl kickstart -k "gui/$uid/$label"
    restarted="yes (kickstart)"
  else
    step launchctl bootstrap "gui/$uid" "$plist"
    restarted="yes (bootstrap)"
  fi
fi

# 5. Summary.
echo
echo "CraftWise updated to $commit$([ "$dry" = 1 ] && echo " (dry run, nothing changed)")"
echo "  old addon folder: $old"
echo "  companion restarted: $restarted"
echo "  stopped a manually started companion: $stopped"
