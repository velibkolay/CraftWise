package upload

import (
	"fmt"
	"sort"

	"github.com/velibkolay/CraftWise/companion/market"
)

// itemHash is what State.Items holds per item: a hash of the name and the item info (the time the
// addon read it left out, it changes without the info changing).
func itemHash(name string, info market.ItemInfo, hasInfo bool) uint64 {
	cmp := info
	cmp.T = nil
	return hashJSON(struct {
		N    string
		Info market.ItemInfo
		Has  bool
	}{name, cmp, hasInfo})
}

// RawKeep is how long the state remembers downloaded raw points (the addon keeps raw points 48 h).
const RawKeep = 3 * day

// MarkDownloaded records data that came from the site's merged market (#239) as already sent, so
// the next upload doesn't send the other machine's recordings back as new (no echo). The addon
// merges the downloaded entries into CraftWiseMarketDB at the next login or /reload; the upload
// after that finds them in SavedVariables and compares them with these marks:
//   - scans: the newest time per house moves up;
//   - names and item info: the hash a local copy of the same values has;
//   - class names: the names;
//   - prices: `last` moves the newest time up, the raw point times are remembered (State.Got),
//     the days' hashes are stored.
//
// A real local recording is never hidden by this: it has its own times, and a local day that differs
// from the downloaded one is sent again (the server keeps the larger one, #238).
func (s *State) MarkDownloaded(p *PublicPayload, now int64) {
	s.init()
	for house, scans := range p.Scans {
		for _, sc := range scans {
			if sc.T > s.Scans[house] {
				s.Scans[house] = sc.T
			}
		}
	}
	ids := map[int64]bool{}
	for id := range p.Names {
		ids[id] = true
	}
	for id := range p.ItemInfo {
		ids[id] = true
	}
	for id := range ids {
		info, has := p.ItemInfo[id]
		if has && info == (market.ItemInfo{}) {
			has = false
		}
		name := p.Names[id]
		if name == "" && !has {
			continue
		}
		s.Items[id] = itemHash(name, info, has)
	}
	for c, name := range p.ClassNames {
		s.Classes[fmt.Sprint(c)] = name
	}
	for c, subs := range p.SubclassNames {
		for sub, name := range subs {
			s.Classes[fmt.Sprintf("%d:%d", c, sub)] = name
		}
	}
	for item, houses := range p.Items {
		for house, e := range houses {
			s.markEntry(priceKey(house, item), e)
		}
	}
	// Forget downloaded raw points the addon no longer keeps.
	for key, times := range s.Got {
		kept := times[:0]
		for _, t := range times {
			if t >= now-RawKeep {
				kept = append(kept, t)
			}
		}
		if len(kept) == 0 {
			delete(s.Got, key)
		} else {
			s.Got[key] = kept
		}
	}
}

func (s *State) markEntry(key string, e market.Entry) {
	m := s.Prices[key]
	if m == nil {
		m = &PriceMark{}
		s.Prices[key] = m
	}
	if l := e.Last; l != nil && l.T != nil && *l.T >= m.LastT {
		m.LastT, m.Off = *l.T, l.Off
	}
	if len(e.Raw) > 0 {
		have := map[int64]bool{}
		for _, t := range s.Got[key] {
			have[t] = true
		}
		for _, p := range e.Raw {
			if !have[p.T] {
				have[p.T] = true
				s.Got[key] = append(s.Got[key], p.T)
			}
		}
		sort.Slice(s.Got[key], func(i, j int) bool { return s.Got[key][i] < s.Got[key][j] })
	}
	if len(e.Days) > 0 && m.Days == nil {
		m.Days = map[int64]uint64{}
	}
	for n, d := range e.Days {
		if n >= m.DaysFrom {
			m.Days[n] = hashJSON(d)
		}
	}
}

// MarkWatchDownloaded records watch list changes that came from the site (#244) as already sent, so the
// next upload doesn't send them back: a change that wins over what the state has replaces it.
func (s *State) MarkWatchDownloaded(changes []WatchItem) {
	for _, c := range changes {
		if c.I < 1 || c.T < 1 {
			continue
		}
		if old, ok := s.WatchSent[c.I]; ok {
			t, gone := old, false
			if old < 0 {
				t, gone = -old, true
			}
			if !WatchWins(c.T, c.D, t, gone) {
				continue
			}
		}
		if s.WatchSent == nil {
			s.WatchSent = map[int64]int64{}
		}
		s.WatchSent[c.I] = c.sentValue()
	}
}
