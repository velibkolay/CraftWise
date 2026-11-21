package savedvars

import (
	"regexp"
	"sort"

	"github.com/velibkolay/CraftWise/companion/market"
)

// House keys have no realm (#382): since the 20 Nov 2026 client update the realm name is hidden from
// addons, and connected realms share their auction houses. A house is "H" (Horde AH), "A" (Alliance
// AH) or "N:<Zone>" (a neutral AH). A file written before then carries "<realm>|H", "<realm>|A" and
// "<realm>|N:<Zone>"; the realm is dropped and the keys that meet are merged, the newer entry winning
// (the addon does the same once at load, Market.lua MigrateHouseKeys).
var houseKeyRE = regexp.MustCompile(`^(?:[^|]+\|)?(H|A|N:[A-Za-z0-9]+)$`)

// HouseKeyOf is the realm-less house key of a key as a file holds it; false for anything else.
func HouseKeyOf(key string) (string, bool) {
	m := houseKeyRE.FindStringSubmatch(key)
	if m == nil {
		return "", false
	}
	return m[1], true
}

// scansKept is how many scans per house the addon keeps (Market.lua SCANS_KEPT).
const scansKept = 30

// NormalizeHouses rewrites the house keys of houses, scans and items to realm-less keys. Idempotent.
// A key that is not a house key at all is left as it is (the upload skips it with its reason).
func (m *MarketDB) NormalizeHouses() {
	if m == nil {
		return
	}
	for key, h := range m.Houses {
		house, ok := HouseKeyOf(key)
		if !ok {
			continue
		}
		h.Realm = ""
		if key != house {
			delete(m.Houses, key)
			if mine, there := m.Houses[house]; there {
				if mine.Cut == nil {
					mine.Cut = h.Cut
				}
				h = mine
			}
		}
		m.Houses[house] = h
	}
	for key, scans := range m.Scans {
		house, ok := HouseKeyOf(key)
		if !ok || house == key {
			continue
		}
		delete(m.Scans, key)
		merged := append(append([]Scan{}, m.Scans[house]...), scans...)
		seen := map[[2]any]bool{}
		out := merged[:0]
		for _, s := range merged {
			var t int64
			if s.T != nil {
				t = *s.T
			}
			id := [2]any{t, s.Kind}
			if seen[id] {
				continue
			}
			seen[id] = true
			out = append(out, s)
		}
		sort.SliceStable(out, func(i, j int) bool { return scanT(out[i]) < scanT(out[j]) })
		if len(out) > scansKept {
			out = out[len(out)-scansKept:]
		}
		m.Scans[house] = out
	}
	for _, houses := range m.Items {
		var old []string
		for key := range houses {
			if house, ok := HouseKeyOf(key); ok && house != key {
				old = append(old, key)
			}
		}
		sort.Strings(old)
		for _, key := range old {
			house, _ := HouseKeyOf(key)
			e := houses[key]
			delete(houses, key)
			if mine, there := houses[house]; there && lastT(mine) >= lastT(e) {
				continue
			}
			houses[house] = e
		}
	}
}

func scanT(s Scan) int64 {
	if s.T == nil {
		return 0
	}
	return *s.T
}

func lastT(e market.Entry) int64 {
	if e.Last == nil || e.Last.T == nil {
		return 0
	}
	return *e.Last.T
}
