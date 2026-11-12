package savedvars

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/velibkolay/CraftWise/companion/market"
	"github.com/velibkolay/CraftWise/companion/svparse"
)

// testdata/CraftWise.lua is written by tests/companion_fixtures.lua: the addon run headless with stub
// items 9001-9009 on "Stub Realm" (see the scenario there). The values below come from that run.
const (
	fixture = "testdata/CraftWise.lua"
	horde   = "Stub Realm|H"
	booty   = "Stub Realm|N:BootyBay"
	charKey = "Stub Realm-Veli Tanner"
)

func load(t *testing.T) *File {
	t.Helper()
	f, err := ReadFile(fixture)
	if err != nil {
		t.Fatalf("%v (regenerate with: lua5.1 tests/companion_fixtures.lua)", err)
	}
	if len(f.Problems) > 0 {
		t.Fatalf("problems reading the fixture: %v", f.Problems)
	}
	return f
}

func i64(p *int64) int64 {
	if p == nil {
		return -999
	}
	return *p
}

func TestMarketHousesScansNames(t *testing.T) {
	m := load(t).Market
	if i64(m.V) != 1 || i64(m.PrunedAt) == -999 {
		t.Fatalf("v %v prunedAt %v", m.V, m.PrunedAt)
	}
	h := m.Houses[horde]
	if h.Kind != "faction" || h.Faction != "Horde" || h.Label != "Horde AH" || h.Realm != "Stub Realm" {
		t.Fatalf("horde house %+v", h)
	}
	b := m.Houses[booty]
	if b.Kind != "neutral" || b.Label != "Booty Bay" || b.Cut == nil || i64(b.Cut.Samples) != 0 || b.Cut.Rate != nil {
		t.Fatalf("booty bay %+v %+v", b, b.Cut)
	}
	scans := m.Scans[horde]
	if len(scans) != 5 || scans[0].Kind != "full" || i64(scans[0].Items) != 3 || i64(scans[0].LastOnly) != 4 ||
		scans[0].Source != "auctionator" || scans[1].Kind != "search" || scans[4].LastOnly != nil {
		t.Fatalf("scans %+v", scans)
	}
	if m.Names[9006] != `Test "Quoted" Gem` || m.Names[9001] != "Test Cloth" || len(m.Names) != 9 {
		t.Fatalf("names %v", m.Names)
	}
	if !m.Scope.Items[9001] || !m.Scope.Items[9004] || m.Scope.Items[9003] || !m.Scope.SkillLines[165] {
		t.Fatalf("scope %+v", m.Scope)
	}
}

func TestMarketItems(t *testing.T) {
	m := load(t).Market
	if len(m.Items) != 8 {
		t.Fatalf("%d item keys", len(m.Items))
	}
	// Scope item with history at two houses; the faction house has 3 scans' points over 3 days.
	cloth := m.Items[market.ItemKey{ItemID: 9001}]
	e := cloth[horde]
	if e.LastOnly() || len(e.Raw) == 0 || len(e.Days) != 3 || i64(e.Last.Min) != 117 || i64(e.Last.Qty) != 12 {
		t.Fatalf("cloth %+v last %+v", e, e.Last)
	}
	if _, ok := cloth[booty]; !ok {
		t.Fatal("cloth at Booty Bay")
	}
	// Outside the scope: last only, `off` set by a later full scan that didn't list it (#90).
	ore := m.Items[market.ItemKey{ItemID: 9003}][horde]
	if !ore.LastOnly() || ore.Last.Off == nil || i64(ore.Last.Min) != 50 || i64(ore.Last.Qty) != 30 || i64(ore.Last.Listings) != 2 {
		t.Fatalf("ore %+v", ore.Last)
	}
	// Random-suffix gear: one key per suffix.
	owl := m.Items[market.ItemKey{ItemID: 9005, Suffix: 1234}][horde]
	if i64(owl.Last.Min) != 95000 || m.Items[market.ItemKey{ItemID: 9005, Suffix: 5678}] == nil {
		t.Fatalf("suffix gear %+v", owl.Last)
	}
	// A browse row, packed although the snapshot reads its price at logout (#105): no listings.
	oil := m.Items[market.ItemKey{ItemID: 9008}][horde]
	if !oil.LastOnly() || i64(oil.Last.Min) != 345 || i64(oil.Last.Qty) != 7 || oil.Last.Listings != nil || oil.Last.Off == nil {
		t.Fatalf("oil %+v", oil.Last)
	}
	// Every packed string in the file decodes and packs back to itself.
	parsed, err := svparse.ParseFile(fixture)
	if err != nil {
		t.Fatal(err)
	}
	items := parsed.Get("CraftWiseMarketDB").(*svparse.Table).Get("items").(*svparse.Table)
	packed := 0
	for _, f := range items.Fields() {
		for _, h := range f.Value.(*svparse.Table).Fields() {
			s, ok := h.Value.(string)
			if !ok {
				continue
			}
			packed++
			d, err := market.Decode(s)
			if err != nil || market.Encode(d) != s {
				t.Errorf("%v %v: %q -> %q, %v", f.Key, h.Key, s, market.Encode(d), err)
			}
		}
	}
	if packed < 8 {
		t.Fatalf("only %d packed entries", packed)
	}
}

func TestItemInfoAndAuctionator(t *testing.T) {
	m := load(t).Market
	cloth := m.ItemInfo[9001]
	if i64(cloth.Quality) != 1 || i64(cloth.Icon) != 100001 || i64(cloth.Class) != 7 || i64(cloth.Subclass) != 5 || cloth.T == nil {
		t.Fatalf("cloth info %+v", cloth)
	}
	ore := m.ItemInfo[9003]
	if i64(ore.Quality) != 1 || ore.Icon != nil || ore.Class != nil {
		t.Fatalf("ore info: unknown fields must stay missing, got %+v", ore)
	}
	a := m.Auctionator
	if a.Source != "auctionator" || a.House != "unknown" || a.Label != "Auctionator (house unknown)" || len(a.Items) != 2 {
		t.Fatalf("auctionator %+v", a)
	}
	fish := a.Items[9007]
	if i64(fish.Copper) != 7 || i64(fish.Age) != 2 || fish.T == nil {
		t.Fatalf("fish %+v", fish)
	}
	if recipe := a.Items[9009]; i64(recipe.Copper) != 25000 || recipe.Age != nil {
		t.Fatalf("recipe %+v", recipe)
	}
	// Item gathers name, info, prices and the Auctionator price.
	ids := m.ItemIDs()
	if len(ids) != 9 || ids[0] != 9001 || ids[len(ids)-1] != 9009 {
		t.Fatalf("item IDs %v", ids)
	}
	gear := m.Item(9005)
	if gear.Name != "Test Boots of the Owl" || i64(gear.Info.Quality) != 2 || len(gear.Prices) != 2 || gear.Prices["9005:1234"][horde].Last == nil {
		t.Fatalf("gear %+v", gear)
	}
	if fishItem := m.Item(9007); fishItem.Auctionator == nil || fishItem.Prices != nil || fishItem.Name != "Test Fish" {
		t.Fatalf("fish item %+v", fishItem)
	}
}

func TestLedgerAuctions(t *testing.T) {
	m := load(t).Market
	l := m.Ledger
	if len(l.Entries) != 3 || l.Entries[0].Kind != "vbuy" || i64(l.Entries[0].Copper) != 120 || l.Entries[1].Where != horde ||
		l.Entries[2].Name != "Test Ore" || l.Entries[0].Char != charKey {
		t.Fatalf("entries %+v", l.Entries)
	}
	c := l.Chars[charKey]
	if i64(c.Reset.Money) != 250000 || len(c.Days) != 2 || c.Days["2026-11-04"] != 250000 || *c.Pos[9002].Cost != 1500 {
		t.Fatalf("ledger char %+v", c)
	}
	list := m.Auctions.Chars[charKey].List
	if i64(m.Auctions.V) != 1 || len(list) != 2 {
		t.Fatalf("auctions %+v", m.Auctions)
	}
	if a := list[0]; a.Status != "active" || a.Kind != "commodity" || i64(a.Unit) != 330 || i64(a.Q) != 5 || a.House != horde || i64(a.Dep) != 60 {
		t.Fatalf("active %+v", a)
	}
	if s := list[1]; s.Status != "sold" || s.SoldVia != "message" || s.SoldT == nil || !strings.Contains(s.Link, "[Test Potion]") {
		t.Fatalf("sold %+v", s)
	}
}

func TestSnapshot(t *testing.T) {
	f := load(t)
	s := f.DB.Snapshots[charKey]
	if s == nil || i64(s.V) != 1 || s.Raw == nil || len(s.Errors) != 0 || len(s.Skipped) != 0 {
		t.Fatalf("snapshot %+v", s)
	}
	if c := s.Char; c.Name != "Veli" || c.Surname != "Tanner" || i64(c.Level) != 23 || c.Guild != "Test Guild" || i64(c.Rested) != 4200 {
		t.Fatalf("char %+v", c)
	}
	if l := s.Location; *l.Subzone != "" || i64(l.MapID) != 1411 || *l.X != 0.5235 || !*l.Resting {
		t.Fatalf("location %+v", l)
	}
	if e := s.Equipment; len(e.Items) != 1 || e.Items[0].Slot != "Feet" || *e.Items[0].ILvl != 18 || e.Items[0].Stats != "+3 INT +3 SPI" ||
		i64(e.Items[0].DurMax) != 40 || len(e.Empty) != 17 {
		t.Fatalf("equipment %+v", e)
	}
	if p := s.Professions; len(p) != 1 || p[0].Name != "Leatherworking" || i64(p[0].Line) != 165 || i64(p[0].RecipesKnown) != 1 ||
		p[0].Known != "1" {
		t.Fatalf("professions %+v", p)
	}
	if r := s.RecipesLearned; len(r) != 1 || r[0].ID != 1 || r[0].Name != "Test Armor Kit" || r[0].Profession != "Leatherworking" ||
		r[0].How != "event" || r[0].T == nil || r[0].After != nil {
		t.Fatalf("recipesLearned %+v", r)
	}
	q := s.Quests
	if len(q.List) != 2 || q.List[0].Objectives[0].Text != "Test Hides: 2/6" || i64(q.List[0].Objectives[0].Need) != 6 ||
		!*q.List[1].Complete || i64(q.List[1].Group) != 3 || q.CollapsedHeaders[0] != "Collapsed Zone" || i64(q.InLog) != 3 {
		t.Fatalf("quests %+v", q)
	}
	r := s.Reputations
	if len(r.List) != 2 || r.List[0].Standing != "Honored" || r.List[0].Header != "Test Header" || !r.List[1].AtWar || i64(r.List[1].Value) != -5000 {
		t.Fatalf("reputations %+v", r)
	}
	if p := s.Pet; p.Name != "Test Wolf" || p.HappinessText != "happy" {
		t.Fatalf("pet %+v", p)
	}
	if h := s.Holdings; h.Bags[9001] != 40 || h.Names[9002] != "Test Hide" || len(h.NotCounted) != 2 || h.Bank != nil {
		t.Fatalf("holdings %+v", h)
	}
	fp := s.FlightPaths
	if len(fp.Maps) != 1 || fp.Maps[0].MapID != 1414 || len(fp.Maps[0].Nodes) != 2 || !fp.Maps[0].Nodes[1].Current {
		t.Fatalf("flight paths %+v", fp)
	}
	if lg := s.Ledger["reset"]; i64(lg.Net) != -1570 || i64(lg.Spent) != 1620 || i64(s.Ledger["today"].Since) == -999 {
		t.Fatalf("ledger %+v", s.Ledger)
	}
	fs := s.Fishing
	if i64(fs.Catches) != 6 || len(fs.Spots) != 2 || fs.Spots[0].Water != "open" || *fs.Spots[0].Minutes != 1.3 ||
		fs.Spots[1].Pool != "" || i64(fs.Spots[1].Obj) != 6001 || fs.Pools[0].PerVisit != "3-3, avg 3" || i64(fs.FindFish.SpellID) != 43308 {
		t.Fatalf("fishing %+v", fs)
	}
	if z := s.FishingZones; z.Reference || len(z.Zones) != 1 || z.Zones[0].Source != "own" || *z.Zones[0].PerCatch != 16 {
		t.Fatalf("fishing zones %+v", z)
	}
	a := s.Auctions
	if len(a.Active) != 1 || !a.Active[0].Overdue || len(a.Sold) != 1 || i64(a.Sold[0].Expected) != 5225 || i64(a.ExpectedTotal) != 5225 ||
		i64(a.ListedTotal) != 1567 || i64(a.ListedCounted) != 1 || a.ListedNote != "5% cut (confirmed)" {
		t.Fatalf("auctions %+v", a)
	}
	mk := s.Market
	if mk.Where != "CraftWiseMarketDB" || i64(mk.ItemInfo) != 9 || i64(mk.Houses[booty].LastFullScanLastOnly) != 1 || i64(mk.Auctionator.Items) != 2 {
		t.Fatalf("market %+v", mk)
	}
	if s.Crates == nil || len(s.Crates.List) != 0 || s.Favor == nil || i64(s.Favor.ID) != 3402 {
		t.Fatalf("crates %+v favor %+v", s.Crates, s.Favor)
	}
	fm := s.Farm
	if fm == nil || i64(fm.Saved) != 1 || len(fm.Sessions) != 1 || fm.More != nil || fm.Names[9001] != "Test Cloth" {
		t.Fatalf("farm %+v", fm)
	}
	if h := fm.Sessions[0]; i64(h.Seconds) != 240 || i64(h.Coin) != 345 || i64(h.Items) != 1279 || h.Zone != "Test Zone" ||
		len(h.Zones) != 2 || h.Zones[1].Zone != "Test Zone 2" || i64(h.Zones[0].Seconds) != 180 || len(h.Top) != 2 ||
		h.Top[0].ID != 9001 || h.Top[0].Source != "auction" || i64(h.Stop) != i64(h.Start)+240 {
		t.Fatalf("farm session %+v", h)
	}
	if c := fm.Current; c == nil || c.Stop != nil || *c.Running || c.Paused != "idle" || i64(c.Coin) != 37 || c.Zones != nil {
		t.Fatalf("farm current %+v", c)
	}
	c := fm.Current
	if f := c.Fish; f == nil || i64(f.Catches) != 2 || i64(f.Timed) != 1 || i64(f.Seconds) != 20 || i64(f.Coin) != 25 ||
		f.Best == nil || f.Zones != nil {
		t.Fatalf("farm fishing %+v", c.Fish)
	}
	if i64(c.LogLines) != 5 || len(c.Log) != 5 || len(c.LogZones) != 1 || c.Log[4] != "50,c,25,1,f" || c.Log[0] != "0,9007,3,1" {
		t.Fatalf("farm log %v %v %+v", c.Log, c.LogZones, c.LogLines)
	}
	if h := fm.Sessions[0]; i64(h.LogLines) != 3 || h.Log != nil || h.Fish != nil {
		t.Fatalf("farm session log %+v", h)
	}
}

func TestJSON(t *testing.T) {
	b, err := json.Marshal(load(t))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`"9005:1234":{"Stub Realm|H":`, `"itemInfo":{"9001":{"q":1,"i":100001,"c":7,"s":5,`, `"snapshots":{"Stub Realm-Veli Tanner":`} {
		if !strings.Contains(string(b), want) {
			t.Errorf("JSON lacks %s", want)
		}
	}
}

// Values that don't fit are reported with their path and left missing; the rest is read.
func TestProblemsKeepTheRest(t *testing.T) {
	src := `
CraftWiseMarketDB = {
	["v"] = 1,
	["houses"] = { ["R|H"] = { ["label"] = 5, ["kind"] = "faction" } },
	["items"] = {
		[1] = { ["R|H"] = "not|a|valid|entry" },
		[2] = { ["R|H"] = "1,2,3,4||" },
		["x:y"] = { ["R|H"] = "1,2,3,4||" },
		[3] = { ["R|H"] = { ["last"] = { ["t"] = 1, ["min"] = 2 }, ["raw"] = { { ["t"] = 5, ["tiers"] = { 10, 2, 20 } } } } },
		[4] = { ["R|H"] = { ["last"] = { ["t"] = 1 }, ["raw"] = { { ["t"] = 5, ["total"] = 3, ["tiers"] = { 10, 2, 20, 1 } } }, ["days"] = { [20000] = { ["lo"] = 10 } } } },
	},
	["itemInfo"] = { [1] = "1,,,,", [2] = "bad" },
	["auctionator"] = { ["items"] = { [1] = "a,b,c", [2] = "a,b" } },
	["ledger"] = { ["entries"] = { { ["t"] = 1.5, ["k"] = "vbuy" } } },
}
CraftWiseDB = { ["snapshots"] = { ["R-A B"] = { ["char"] = { ["level"] = "x", ["name"] = "A" } } } }
`
	f, err := Read(strings.NewReader(src))
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, p := range f.Problems {
		got = append(got, p.String())
	}
	want := []string{
		`CraftWiseDB.snapshots["R-A B"].char.level: want number, got string`,
		`CraftWiseMarketDB.auctionator.items[2]: malformed market entry: auctionator price "a,b": want 3 fields`,
		`CraftWiseMarketDB.houses["R|H"].label: want string, got number`,
		`CraftWiseMarketDB.itemInfo[2]: malformed market entry: item info "bad": want 5 fields`,
		`CraftWiseMarketDB.items["x:y"]: item key "x:y" is not an item ID`,
		`CraftWiseMarketDB.items[1]["R|H"]: malformed market entry: want 3 parts separated by '|', got 4`,
		`CraftWiseMarketDB.items[3]["R|H"].raw[1].tiers: odd number of values`,
		`CraftWiseMarketDB.ledger.entries[1].t: want an integer, got 1.5`,
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("problems:\n%s", strings.Join(got, "\n"))
	}
	m := f.Market
	if m.Houses["R|H"].Kind != "faction" || len(m.Items) != 2 || i64(m.Items[market.ItemKey{ItemID: 2}]["R|H"].Last.Listings) != 4 {
		t.Fatalf("market %+v", m)
	}
	table := m.Items[market.ItemKey{ItemID: 4}]["R|H"]
	if len(table.Raw) != 1 || table.Raw[0].Tiers[1] != (market.Tier{Price: 20, Qty: 1}) || i64(table.Days[20000].Lo) != 10 {
		t.Fatalf("table entry %+v", table)
	}
	if market.Encode(table) != "1,,,|a,3,,,k,2,k,1|uv4,a,,,,,," {
		t.Fatalf("table entry packs to %q", market.Encode(table))
	}
	if len(m.ItemInfo) != 1 || m.Auctionator.Items[1].Copper == nil || len(m.Ledger.Entries) != 1 || m.Ledger.Entries[0].T != nil {
		t.Fatalf("partial reads %+v %+v %+v", m.ItemInfo, m.Auctionator, m.Ledger)
	}
	if c := f.DB.Snapshots["R-A B"].Char; c.Name != "A" || c.Level != nil {
		t.Fatalf("char %+v", c)
	}
}

func TestSyntaxErrorIsReturned(t *testing.T) {
	if _, err := Read(strings.NewReader("CraftWiseDB = {")); err == nil {
		t.Fatal("want error")
	}
}
