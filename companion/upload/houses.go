package upload

import (
	"regexp"
	"strings"

	"github.com/velibkolay/CraftWise/companion/savedvars"
)

// MigrateHouseKeys moves what the state remembers under an old house key ("<realm>|H") to the realm-less
// key (#382), so the first upload after the change does not send the whole market again. Per item the
// mark of the entry with the newer `last` is kept, scans take the newer time. Idempotent; false when
// nothing was left to move.
func (s *State) MigrateHouseKeys() bool {
	s.init()
	moved := false
	for key, t := range s.Scans {
		house, ok := savedvars.HouseKeyOf(key)
		if !ok || house == key {
			continue
		}
		delete(s.Scans, key)
		if t > s.Scans[house] {
			s.Scans[house] = t
		}
		moved = true
	}
	for key, mark := range s.Prices {
		houseKey, item, ok := strings.Cut(key, "\x1f")
		if !ok {
			continue
		}
		house, ok := savedvars.HouseKeyOf(houseKey)
		if !ok || house == houseKey {
			continue
		}
		delete(s.Prices, key)
		nk := priceKey(house, item)
		if mine, there := s.Prices[nk]; !there || mark.LastT > mine.LastT {
			s.Prices[nk] = mark
		}
		moved = true
	}
	for key, times := range s.Got {
		m := gotKeyRE.FindStringSubmatch(key)
		if m == nil {
			continue
		}
		delete(s.Got, key)
		nk := m[1] + m[2]
		s.Got[nk] = mergeTimes(s.Got[nk], times)
		moved = true
	}
	return moved
}

// A Got key is "<house><itemKey>": an old one has the realm in front of the house.
var gotKeyRE = regexp.MustCompile(`^[^|]+\|(H|A|N:[A-Za-z]+)(\d+(?::\d+)?)$`)

func mergeTimes(a, b []int64) []int64 {
	seen := map[int64]bool{}
	var out []int64
	for _, list := range [][]int64{a, b} {
		for _, t := range list {
			if !seen[t] {
				seen[t] = true
				out = append(out, t)
			}
		}
	}
	return out
}
