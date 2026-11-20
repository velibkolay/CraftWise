package syncdata

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/velibkolay/CraftWise/companion/market"
	"github.com/velibkolay/CraftWise/companion/upload"
)

// The one add-on the companion writes (#239): a data add-on next to CraftWise. These are the only
// files it ever writes into the game folder.
const (
	AddonName = "CraftWise_Sync"
	TocName   = AddonName + ".toc"
	LuaName   = AddonName + ".lua"
	// FormatVersion is `v` in the file; the addon ignores a higher one.
	FormatVersion = 1
)

// Toc is CraftWise_Sync.toc. No SavedVariables: the file is data only.
const Toc = `## Interface: 16001
## Title: CraftWise Sync
## Notes: Market data from your other machine, written by the CraftWise companion app. Do not edit.
## Author: velibkolay
## X-License: GPL-3.0
## Dependencies: CraftWise
## LoadOnDemand: 0
` + LuaName + "\n"

// File is what goes into CraftWise_Sync.lua.
type File struct {
	Written int64  // unix time
	Machine string // this machine's name
	Market  *upload.PublicPayload
	// Chars are the other machine's characters (#242), without this machine's own: Cache.OtherChars.
	Chars map[string]Char
	// Watch is the merged watch list (#244): Cache.Watch. Nil = not written (private data off), so the addon
	// leaves its own list alone; an empty map writes empty tables.
	Watch map[int64]WatchState
}

// Dir is the add-on folder inside the game's AddOns folder; wow is the _forever_ folder.
func Dir(wow string) string { return filepath.Join(wow, "Interface", "AddOns", AddonName) }

// luaString quotes s as a Lua string: backslash, quote and control characters escaped (\ddd, as
// Lua 5.1 reads it), UTF-8 bytes left as they are.
func luaString(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == 0x5c || c == 0x22:
			b.WriteByte(0x5c)
			b.WriteByte(c)
		case c < 0x20 || c == 0x7f:
			fmt.Fprintf(&b, "%c%03d", 0x5c, c)
		default:
			b.WriteByte(c)
		}
	}
	b.WriteByte('"')
	return b.String()
}

var plainID = regexp.MustCompile(`^[1-9][0-9]*$`)

// itemKey writes an item key the way CraftWiseMarketDB keys it: a number for a plain item ID, a
// string "<id>:<suffix>" for a variant.
func itemKey(k string) string {
	if plainID.MatchString(k) {
		return "[" + k + "]"
	}
	return "[" + luaString(k) + "]"
}

func sortedStrings[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func sortedInts[V any](m map[int64]V) []int64 {
	keys := make([]int64, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })
	return keys
}

// itemKeys sorts item keys by item ID, then suffix.
func itemKeys(m map[string]map[string]market.Entry) []string {
	keys := sortedStrings(m)
	sort.SliceStable(keys, func(i, j int) bool {
		a, errA := market.ParseItemKey(keys[i])
		b, errB := market.ParseItemKey(keys[j])
		if errA != nil || errB != nil {
			return keys[i] < keys[j]
		}
		if a.ItemID != b.ItemID {
			return a.ItemID < b.ItemID
		}
		return a.Suffix < b.Suffix
	})
	return keys
}

// Render writes the Lua file for f. The same input always gives the same bytes.
func Render(f File) []byte {
	var b bytes.Buffer
	b.WriteString("-- CraftWise_Sync: written by the CraftWise companion app, overwritten on every download.\n")
	b.WriteString("-- Do not edit. CraftWise reads it at login or /reload and merges it into its market data.\n")
	b.WriteString("CraftWiseSync = {\n")
	fmt.Fprintf(&b, "  v = %d,\n  written = %d,\n  machine = %s,\n", FormatVersion, f.Written, luaString(f.Machine))
	m := f.Market
	if m == nil {
		m = &upload.PublicPayload{}
	}
	b.WriteString("  market = {\n")

	b.WriteString("    houses = {\n")
	for _, k := range sortedStrings(m.Houses) {
		h := m.Houses[k]
		fmt.Fprintf(&b, "      [%s] = { realm = %s, kind = %s", luaString(k), luaString(h.Realm), luaString(h.Kind))
		if h.Faction != "" {
			fmt.Fprintf(&b, ", faction = %s", luaString(h.Faction))
		}
		fmt.Fprintf(&b, ", label = %s },\n", luaString(h.Label))
	}
	b.WriteString("    },\n")

	b.WriteString("    scans = {\n")
	for _, k := range sortedStrings(m.Scans) {
		fmt.Fprintf(&b, "      [%s] = {\n", luaString(k))
		for _, s := range m.Scans[k] {
			fmt.Fprintf(&b, "        { t = %d, kind = %s", s.T, luaString(s.Kind))
			if s.Items != nil {
				fmt.Fprintf(&b, ", items = %d", *s.Items)
			}
			if s.LastOnly != nil {
				fmt.Fprintf(&b, ", lastOnly = %d", *s.LastOnly)
			}
			if s.Source != "" {
				fmt.Fprintf(&b, ", source = %s", luaString(s.Source))
			}
			b.WriteString(" },\n")
		}
		b.WriteString("      },\n")
	}
	b.WriteString("    },\n")

	b.WriteString("    names = {\n")
	for _, id := range sortedInts(m.Names) {
		fmt.Fprintf(&b, "      [%d] = %s,\n", id, luaString(m.Names[id]))
	}
	b.WriteString("    },\n")

	b.WriteString("    itemInfo = {\n")
	for _, id := range sortedInts(m.ItemInfo) {
		fmt.Fprintf(&b, "      [%d] = %s,\n", id, luaString(market.EncodeItemInfo(m.ItemInfo[id])))
	}
	b.WriteString("    },\n")

	b.WriteString("    classNames = {\n")
	for _, id := range sortedInts(m.ClassNames) {
		fmt.Fprintf(&b, "      [%d] = %s,\n", id, luaString(m.ClassNames[id]))
	}
	b.WriteString("    },\n")

	b.WriteString("    subclassNames = {\n")
	for _, c := range sortedInts(m.SubclassNames) {
		fmt.Fprintf(&b, "      [%d] = {", c)
		for _, s := range sortedInts(m.SubclassNames[c]) {
			fmt.Fprintf(&b, " [%d] = %s,", s, luaString(m.SubclassNames[c][s]))
		}
		b.WriteString(" },\n")
	}
	b.WriteString("    },\n")

	b.WriteString("    items = {\n")
	for _, k := range itemKeys(m.Items) {
		fmt.Fprintf(&b, "      %s = {\n", itemKey(k))
		houses := m.Items[k]
		for _, h := range sortedStrings(houses) {
			fmt.Fprintf(&b, "        [%s] = %s,\n", luaString(h), luaString(market.Encode(houses[h])))
		}
		b.WriteString("      },\n")
	}
	b.WriteString("    },\n")

	b.WriteString("  },\n")
	renderChars(&b, f.Chars)
	if f.Watch != nil {
		renderWatch(&b, f.Watch, f.Written)
	}
	b.WriteString("}\n")
	return b.Bytes()
}

var writtenRE = regexp.MustCompile(`(?m)^  written = (\d+),$`)

// Write puts the add-on into <wow>/Interface/AddOns/CraftWise_Sync: the TOC if it is missing or
// different, and the Lua file if it differs from what Render gives (the `written` time left out of
// the comparison). Both go through a temporary file and a rename. It reports whether the Lua file
// was written. Nothing else is created, changed or deleted.
func Write(wow string, f File) (bool, error) {
	dir := Dir(wow)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return false, err
	}
	if old, err := os.ReadFile(filepath.Join(dir, TocName)); err != nil || string(old) != Toc {
		if err := writeAtomic(filepath.Join(dir, TocName), []byte(Toc), 0o644); err != nil {
			return false, err
		}
	}
	path := filepath.Join(dir, LuaName)
	if old, err := os.ReadFile(path); err == nil {
		if m := writtenRE.FindSubmatch(old); m != nil {
			if t, err := strconv.ParseInt(string(m[1]), 10, 64); err == nil {
				same := f
				same.Written = t
				if bytes.Equal(old, Render(same)) {
					return false, nil
				}
			}
		}
	}
	if err := writeAtomic(path, Render(f), 0o644); err != nil {
		return false, err
	}
	return true, nil
}
