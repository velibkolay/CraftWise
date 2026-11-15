package upload

import (
	"testing"

	"github.com/velibkolay/CraftWise/companion/market"
)

// downloaded builds what the site's merged market would hold if it held exactly the fixture's
// market: the bodies of a first upload put together.
func downloaded(t *testing.T) *PublicPayload {
	t.Helper()
	plan := Build(readFixture(t), NewState("s", "f"), Options{Now: fixtureNow})
	out := &PublicPayload{V: Version, Houses: map[string]House{}}
	for _, b := range plan.Public {
		p := b.Body
		for k, h := range p.Houses {
			out.Houses[k] = h
		}
		for k, v := range p.Scans {
			if out.Scans == nil {
				out.Scans = map[string][]Scan{}
			}
			out.Scans[k] = append(out.Scans[k], v...)
		}
		for k, v := range p.Names {
			if out.Names == nil {
				out.Names = map[int64]string{}
			}
			out.Names[k] = v
		}
		for k, v := range p.ItemInfo {
			if out.ItemInfo == nil {
				out.ItemInfo = map[int64]market.ItemInfo{}
			}
			out.ItemInfo[k] = v
		}
		for k, v := range p.ClassNames {
			if out.ClassNames == nil {
				out.ClassNames = map[int64]string{}
			}
			out.ClassNames[k] = v
		}
		for k, v := range p.SubclassNames {
			if out.SubclassNames == nil {
				out.SubclassNames = map[int64]map[int64]string{}
			}
			out.SubclassNames[k] = v
		}
		for item, houses := range p.Items {
			for h, e := range houses {
				if out.Items == nil {
					out.Items = map[string]map[string]market.Entry{}
				}
				if out.Items[item] == nil {
					out.Items[item] = map[string]market.Entry{}
				}
				out.Items[item][h] = e
			}
		}
	}
	return out
}

// No echo (#239): once the addon has merged a download into CraftWiseMarketDB, the next upload
// sends none of it back, only recordings made on this machine.
func TestDownloadedMarketIsNotSentBack(t *testing.T) {
	dl := downloaded(t)
	if len(dl.Items) == 0 || len(dl.Scans) == 0 || len(dl.ItemInfo) == 0 {
		t.Fatalf("the fixture has no market to download: %d items", len(dl.Items))
	}
	f := readFixture(t) // the local file after the merge: it holds all of it

	// Without the marks, everything would go out.
	if plan := Build(f, NewState("s", "f"), Options{Now: fixtureNow}); len(plan.Public) == 0 {
		t.Fatal("control: a fresh state sends nothing")
	}

	st := NewState("s", "f")
	st.MarkDownloaded(dl, fixtureNow)
	plan := Build(f, st, Options{Now: fixtureNow})
	if len(plan.Public) != 0 {
		for _, b := range plan.Public {
			t.Logf("sent: %s", b.Summary())
		}
		t.Fatalf("%d public requests after a download, want none", len(plan.Public))
	}

	// A real local recording is sent, and only that one: a new raw point older than the newest
	// downloaded one still counts.
	var item market.ItemKey
	var house string
	var newest, oldest int64
	for k, houses := range f.Market.Items {
		for h, e := range houses {
			if len(e.Raw) > 1 {
				item, house = k, h
				oldest, newest = e.Raw[0].T, e.Raw[0].T
				for _, p := range e.Raw {
					if p.T > newest {
						newest = p.T
					}
					if p.T < oldest {
						oldest = p.T
					}
				}
			}
		}
	}
	if house == "" {
		t.Skip("no fixture entry with several raw points")
	}
	e := f.Market.Items[item][house]
	local := market.Point{T: newest - 1, Total: market.Int(5), Tiers: []market.Tier{{Price: 7, Qty: 5}}}
	for _, p := range e.Raw {
		if p.T == local.T {
			t.Skip("fixture already has a point at that time")
		}
	}
	e.Raw = append(append([]market.Point{}, e.Raw...), local)
	f.Market.Items[item][house] = e
	plan = Build(f, st, Options{Now: fixtureNow})
	sent := 0
	for _, b := range plan.Public {
		for _, houses := range b.Body.Items {
			for _, rec := range houses {
				for _, p := range rec.Raw {
					sent++
					if p.T != local.T {
						t.Errorf("sent the downloaded point at %d", p.T)
					}
				}
			}
		}
	}
	if sent != 1 {
		t.Errorf("sent %d raw points, want the 1 local one", sent)
	}
	_ = oldest
}

func TestMarkDownloadedForgetsOldRawPoints(t *testing.T) {
	st := NewState("s", "f")
	e := market.Entry{Raw: []market.Point{{T: 1000, Tiers: []market.Tier{}}, {T: 1000 + 10*day, Tiers: []market.Tier{}}}}
	st.MarkDownloaded(&PublicPayload{Items: map[string]map[string]market.Entry{"5": {"h": e}}}, 1000+10*day)
	got := st.Got[priceKey("h", "5")]
	if len(got) != 1 || got[0] != 1000+10*day {
		t.Errorf("remembered raw points %v", got)
	}
}
