package savedvars

import (
	"testing"

	"github.com/velibkolay/CraftWise/companion/market"
)

func ptr64(n int64) *int64 { return &n }

func TestHouseKeyOf(t *testing.T) {
	for key, want := range map[string]string{
		"H": "H", "A": "A", "N:BootyBay": "N:BootyBay",
		"CAMWOW EU4 Realm 8 PvP|H": "H", "CAMWOW EU4 Realm 6 PvP|A": "A", "Some Realm|N:Gadgetzan": "N:Gadgetzan",
	} {
		if got, ok := HouseKeyOf(key); !ok || got != want {
			t.Errorf("%q: got %q %v, want %q", key, got, ok, want)
		}
	}
	for _, key := range []string{"", "X", "Realm|X", "Realm|", "|H|H", "H|"} {
		if got, ok := HouseKeyOf(key); ok && key != "|H|H" {
			t.Errorf("%q should not be a house key, got %q", key, got)
		}
	}
}

// #382: the keys of a file from before the realm was hidden meet in the realm-less house; the newer entry wins,
// scans are merged by time and kind, the house record keeps no realm.
func TestNormalizeHouses(t *testing.T) {
	r6, r8 := "CAMWOW EU4 Realm 6 PvP|H", "CAMWOW EU4 Realm 8 PvP|H"
	m := &MarketDB{
		Houses: map[string]House{r6: {Realm: "CAMWOW EU4 Realm 6 PvP", Kind: "faction", Faction: "Horde", Label: "Horde AH"}, r8: {Realm: "x", Kind: "faction", Faction: "Horde", Label: "Horde AH"}},
		Scans:  map[string][]Scan{r6: {{T: ptr64(10), Kind: "full"}, {T: ptr64(30), Kind: "full"}}, r8: {{T: ptr64(20), Kind: "full"}, {T: ptr64(30), Kind: "full"}}},
		Items: map[market.ItemKey]map[string]market.Entry{
			{ItemID: 1}: {r6: {Last: &market.Last{T: ptr64(100), Min: ptr64(5)}}, r8: {Last: &market.Last{T: ptr64(200), Min: ptr64(7)}}},
			{ItemID: 2}: {r6: {Last: &market.Last{T: ptr64(300), Min: ptr64(9)}}, r8: {Last: &market.Last{T: ptr64(50), Min: ptr64(1)}}},
			{ItemID: 3}: {"H": {Last: &market.Last{T: ptr64(1), Min: ptr64(2)}}},
		},
	}
	m.NormalizeHouses()
	if len(m.Houses) != 1 || m.Houses["H"].Realm != "" || m.Houses["H"].Label != "Horde AH" {
		t.Errorf("houses %+v", m.Houses)
	}
	if got := m.Scans["H"]; len(got) != 3 || *got[0].T != 10 || *got[1].T != 20 || *got[2].T != 30 || len(m.Scans) != 1 {
		t.Errorf("scans %+v", m.Scans)
	}
	if got := *m.Items[market.ItemKey{ItemID: 1}]["H"].Last.Min; got != 7 {
		t.Errorf("item 1: the newer entry (Realm 8) should win, min %d", got)
	}
	if got := *m.Items[market.ItemKey{ItemID: 2}]["H"].Last.Min; got != 9 {
		t.Errorf("item 2: the newer entry (Realm 6) should win, min %d", got)
	}
	if len(m.Items[market.ItemKey{ItemID: 1}]) != 1 || len(m.Items[market.ItemKey{ItemID: 3}]) != 1 {
		t.Errorf("one house per item left: %+v", m.Items)
	}
	m.NormalizeHouses() // idempotent
	if len(m.Houses) != 1 || len(m.Scans["H"]) != 3 {
		t.Errorf("second run changed it: %+v %+v", m.Houses, m.Scans)
	}
	var nilDB *MarketDB
	nilDB.NormalizeHouses()
}
