package upload

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/velibkolay/CraftWise/companion/market"
	"github.com/velibkolay/CraftWise/companion/savedvars"
)

// fixtureNow is a little after the newest time in savedvars/testdata/CraftWise.lua.
const fixtureNow = 1794010000

func readFixture(t *testing.T) *savedvars.File {
	t.Helper()
	f, err := savedvars.ReadFile("../savedvars/testdata/CraftWise.lua")
	if err != nil {
		t.Fatal(err)
	}
	return f
}

func commitAll(p *Plan, st *State) {
	for _, b := range p.Public {
		b.Commit(st)
	}
	for _, b := range p.Private {
		b.Commit(st)
	}
}

func asJSON(t *testing.T, v any) map[string]any {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	var out map[string]any
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestFirstUploadSendsEverythingOnce(t *testing.T) {
	f := readFixture(t)
	st := NewState("https://example.test", "CraftWise.lua")
	plan := Build(f, st, Options{Now: fixtureNow, Private: true})
	if len(plan.Public) != 1 || len(plan.Private) != 1 {
		t.Fatalf("want 1 public and 1 private request, got %d and %d (skipped %v)", len(plan.Public), len(plan.Private), plan.SkippedText())
	}
	if len(plan.Skipped) != 0 {
		t.Errorf("skipped: %v", plan.SkippedText())
	}

	pub := asJSON(t, plan.Public[0].Body)
	if pub["v"].(float64) != 1 {
		t.Errorf("v = %v", pub["v"])
	}
	houses := pub["houses"].(map[string]any)
	if len(houses) != 2 {
		t.Fatalf("houses: %v", houses)
	}
	if _, has := houses["Stub Realm|N:BootyBay"].(map[string]any)["faction"]; has {
		t.Error("a neutral house must not carry a faction")
	}
	if houses["Stub Realm|H"].(map[string]any)["faction"] != "Horde" {
		t.Error("Horde house without its faction")
	}
	if _, has := pub["auctionator"]; has {
		t.Error("Auctionator prices must never be uploaded")
	}
	// Every entry of the market data, both houses.
	wantEntries := 0
	for _, houses := range f.Market.Items {
		wantEntries += len(houses)
	}
	gotEntries := 0
	for _, perHouse := range pub["items"].(map[string]any) {
		gotEntries += len(perHouse.(map[string]any))
	}
	if gotEntries != wantEntries || plan.Public[0].Counts["prices"] != wantEntries {
		t.Errorf("entries: got %d (counted %d), want %d", gotEntries, plan.Public[0].Counts["prices"], wantEntries)
	}
	if len(pub["names"].(map[string]any)) != len(f.Market.Names) {
		t.Errorf("names: %v", pub["names"])
	}
	if len(pub["itemInfo"].(map[string]any)) != len(f.Market.ItemInfo) {
		t.Errorf("itemInfo: %v", pub["itemInfo"])
	}
	scans := 0
	for _, list := range pub["scans"].(map[string]any) {
		scans += len(list.([]any))
	}
	wantScans := 0
	for _, list := range f.Market.Scans {
		wantScans += len(list)
	}
	if scans != wantScans {
		t.Errorf("scans: got %d, want %d", scans, wantScans)
	}

	priv := asJSON(t, plan.Private[0].Body)
	char := "Stub Realm-Veli Tanner"
	snap := priv["snapshots"].(map[string]any)[char].(map[string]any)
	if snap["t"].(float64) != 1794006120 || snap["data"].(map[string]any)["char"].(map[string]any)["name"] != "Veli" {
		t.Errorf("snapshot doc: %v", snap)
	}
	auc := priv["auctions"].(map[string]any)[char].(map[string]any)
	if auc["t"].(float64) != fixtureNow || len(auc["data"].(map[string]any)["list"].([]any)) != 2 {
		t.Errorf("auctions doc (CraftWiseMarketDB.auctions.chars, t = read time): %v", auc)
	}
	fish := priv["fishing"].(map[string]any)[char].(map[string]any)["data"].(map[string]any)
	if fish["catches"].(float64) != 6 || fish["fishingZones"] == nil {
		t.Errorf("fishing doc: %v", fish)
	}
	if n := len(priv["ledger"].([]any)); n != 3 {
		t.Errorf("ledger: %d entries", n)
	}

	commitAll(plan, st)
	again := Build(f, st, Options{Now: fixtureNow + 60, Private: true})
	if !again.Empty() {
		t.Errorf("second build of the same file: %d public, %d private requests", len(again.Public), len(again.Private))
	}
}

func TestPrivateOff(t *testing.T) {
	plan := Build(readFixture(t), NewState("s", "f"), Options{Now: fixtureNow})
	if len(plan.Private) != 0 {
		t.Error("private requests built with Private off")
	}
}

// market builds a small market DB by hand.
func smallMarket() *savedvars.MarketDB {
	i := market.Int
	return &savedvars.MarketDB{
		Houses: map[string]savedvars.House{
			"R|H":          {Realm: "R", Kind: "faction", Faction: "Horde", Label: "Horde AH"},
			"R|N:BootyBay": {Realm: "R", Kind: "neutral", Label: "Booty Bay"},
			"R|A":          {Realm: "R", Kind: "faction", Faction: "Horde", Label: "wrong faction"},
		},
		Names:    map[int64]string{2589: "Linen Cloth"},
		ItemInfo: map[int64]market.ItemInfo{2589: {Quality: i(1), Icon: i(132889), Class: i(7), Subclass: i(5), T: i(fixtureNow - 100)}},
		Items: map[market.ItemKey]map[string]market.Entry{
			{ItemID: 2589}: {
				"R|H": {
					Last: &market.Last{T: i(fixtureNow - 100), Min: i(95), Qty: i(400), Listings: i(6)},
					Raw: []market.Point{
						{T: fixtureNow - 7200, Total: i(380), Listings: i(5), Tiers: []market.Tier{{Price: 96, Qty: 10}}},
						{T: fixtureNow - 100, Total: i(400), Listings: i(6), M: i(120), Tiers: []market.Tier{{Price: 95, Qty: 10}, {Price: 100, Qty: 40}}},
					},
					Days: map[int64]market.Day{
						fixtureNow/86400 - 5: {Lo: i(90), Typ: i(100), Hi: i(140), QtyMax: i(500), ListMax: i(7), N: i(4), Gone: i(20)},
						fixtureNow / 86400:   {Lo: i(95), Typ: i(97), Hi: i(96), QtyMax: i(400), ListMax: i(6), N: i(2)},
					},
				},
				"R|A": {Last: &market.Last{T: i(fixtureNow), Min: i(1), Qty: i(1)}},
			},
			{ItemID: 15210, Suffix: 1017}: {
				"R|N:BootyBay": {Last: &market.Last{T: i(fixtureNow - 600), Min: i(25000), Qty: i(1)}},
			},
		},
		Auctionator: &savedvars.Auctionator{Items: map[int64]market.AuctionatorPrice{2589: {T: i(1), Copper: i(5)}}},
	}
}

func TestPayloadShape(t *testing.T) {
	m := smallMarket()
	plan := Build(&savedvars.File{Market: m}, NewState("s", "f"), Options{Now: fixtureNow})
	if len(plan.Public) != 1 {
		t.Fatalf("%d requests", len(plan.Public))
	}
	got, err := json.Marshal(plan.Public[0].Body)
	if err != nil {
		t.Fatal(err)
	}
	day := int64(fixtureNow / 86400)
	want := `{"v":1,` +
		`"houses":{"R|H":{"realm":"R","kind":"faction","faction":"Horde","label":"Horde AH"},"R|N:BootyBay":{"realm":"R","kind":"neutral","label":"Booty Bay"}},` +
		`"names":{"2589":"Linen Cloth"},` +
		`"itemInfo":{"2589":{"q":1,"i":132889,"c":7,"s":5,"t":1794009900}},` +
		`"items":{` +
		`"15210:1017":{"R|N:BootyBay":{"last":{"t":1794009400,"min":25000,"qty":1}}},` +
		`"2589":{"R|H":{"last":{"t":1794009900,"min":95,"qty":400,"listings":6},` +
		`"raw":[{"t":1794002800,"total":380,"listings":5,"tiers":[{"price":96,"qty":10}]},` +
		`{"t":1794009900,"total":400,"listings":6,"m":120,"tiers":[{"price":95,"qty":10},{"price":100,"qty":40}]}],` +
		`"days":{"` + itoa(day-5) + `":{"lo":90,"typ":100,"hi":140,"qtyMax":500,"listMax":7,"n":4,"gone":20},` +
		`"` + itoa(day) + `":{"lo":95,"typ":97,"hi":96,"qtyMax":400,"listMax":6,"n":2}}}}}}`
	if string(got) != want {
		t.Errorf("payload\n got %s\nwant %s", got, want)
	}
	if !strings.Contains(strings.Join(plan.SkippedText(), "\n"), "house without a valid") {
		t.Errorf("the Alliance key with a Horde faction must be left out: %v", plan.SkippedText())
	}
}

func itoa(n int64) string { b, _ := json.Marshal(n); return string(b) }

func TestDeltaSendsOnlyNewPointsAndChangedDays(t *testing.T) {
	m := smallMarket()
	f := &savedvars.File{Market: m}
	st := NewState("s", "f")
	commitAll(Build(f, st, Options{Now: fixtureNow}), st)

	// The addon records a new point today: raw grows, today's aggregate changes, last moves on.
	i := market.Int
	e := m.Items[market.ItemKey{ItemID: 2589}]["R|H"]
	e.Raw = append(e.Raw, market.Point{T: fixtureNow + 300, Total: i(390), Listings: i(6), Tiers: []market.Tier{{Price: 94, Qty: 5}}})
	e.Last = &market.Last{T: i(fixtureNow + 300), Min: i(94), Qty: i(390), Listings: i(6)}
	e.Days = map[int64]market.Day{}
	for k, v := range m.Items[market.ItemKey{ItemID: 2589}]["R|H"].Days {
		e.Days[k] = v
	}
	e.Days[fixtureNow/86400] = market.Day{Lo: i(94), Typ: i(96), Hi: i(96), QtyMax: i(400), ListMax: i(6), N: i(3)}
	m.Items[market.ItemKey{ItemID: 2589}]["R|H"] = e

	plan := Build(f, st, Options{Now: fixtureNow + 400})
	if len(plan.Public) != 1 {
		t.Fatalf("%d requests", len(plan.Public))
	}
	b := plan.Public[0].Body
	if len(b.Names) != 0 || len(b.ItemInfo) != 0 || len(b.Scans) != 0 {
		t.Errorf("unchanged names/info/scans sent again: %+v", b)
	}
	if len(b.Items) != 1 {
		t.Fatalf("items: %v", b.Items)
	}
	got := b.Items["2589"]["R|H"]
	if len(got.Raw) != 1 || got.Raw[0].T != fixtureNow+300 {
		t.Errorf("raw: want only the new point, got %+v", got.Raw)
	}
	if len(got.Days) != 1 || *got.Days[fixtureNow/86400].N != 3 {
		t.Errorf("days: want only today, got %+v", got.Days)
	}
	if got.Last == nil || *got.Last.Min != 94 {
		t.Errorf("last: %+v", got.Last)
	}
	if plan.Public[0].Rows != 1+2+4 {
		t.Errorf("rows estimate %d, want 7", plan.Public[0].Rows)
	}

	// `off` set by a later full scan: last is sent again with the same time.
	commitAll(plan, st)
	e.Last = &market.Last{T: i(fixtureNow + 300), Min: i(94), Qty: i(390), Listings: i(6), Off: i(fixtureNow + 500)}
	m.Items[market.ItemKey{ItemID: 2589}]["R|H"] = e
	plan = Build(f, st, Options{Now: fixtureNow + 600})
	if len(plan.Public) != 1 || plan.Public[0].Body.Items["2589"]["R|H"].Last.Off == nil {
		t.Fatalf("off change not sent: %+v", plan.Public)
	}
	if r := plan.Public[0].Body.Items["2589"]["R|H"]; len(r.Raw) != 0 || len(r.Days) != 0 {
		t.Errorf("raw/days sent again: %+v", r)
	}
}

func TestInvalidValuesLeftOut(t *testing.T) {
	i := market.Int
	tiers := make([]market.Tier, 9)
	for n := range tiers {
		tiers[n] = market.Tier{Price: int64(n + 1), Qty: 1}
	}
	m := &savedvars.MarketDB{
		Houses: map[string]savedvars.House{"R|H": {Realm: "R", Kind: "faction", Faction: "Horde", Label: "Horde AH"}},
		Items: map[market.ItemKey]map[string]market.Entry{
			{ItemID: 1}: {"R|H": {
				Last: &market.Last{T: i(fixtureNow), Qty: i(3)}, // no min
				Raw: []market.Point{
					{T: fixtureNow - 10, Tiers: []market.Tier{{Price: 1, Qty: 1}}},                                 // no total
					{T: fixtureNow - 9, Total: i(2), Tiers: tiers},                                                 // 9 tiers
					{T: fixtureNow - 8, Total: i(2), Tiers: []market.Tier{{Price: 5, Qty: 1}, {Price: 5, Qty: 1}}}, // not rising
					{T: fixtureNow - 7, Total: i(2), Tiers: []market.Tier{{Price: 5, Qty: 2}}},
				},
			}},
			{ItemID: 2}: {"R|H": {Last: &market.Last{T: i(1000), Min: i(1), Qty: i(1)}}}, // time out of range
		},
	}
	plan := Build(&savedvars.File{Market: m}, NewState("s", "f"), Options{Now: fixtureNow})
	if len(plan.Public) != 1 {
		t.Fatalf("%d requests", len(plan.Public))
	}
	e := plan.Public[0].Body.Items["1"]["R|H"]
	if e.Last != nil || len(e.Raw) != 1 || e.Raw[0].T != fixtureNow-7 {
		t.Errorf("entry: %+v", e)
	}
	if _, sent := plan.Public[0].Body.Items["2"]; sent {
		t.Error("entry with nothing valid was sent")
	}
	skipped := 0
	for _, n := range plan.Skipped {
		skipped += n
	}
	if skipped != 5 {
		t.Errorf("skipped: %v", plan.SkippedText())
	}
}

func TestBatchesSplitAndResume(t *testing.T) {
	i := market.Int
	m := &savedvars.MarketDB{
		Houses: map[string]savedvars.House{"R|H": {Realm: "R", Kind: "faction", Faction: "Horde", Label: "Horde AH"}},
		Items:  map[market.ItemKey]map[string]market.Entry{},
	}
	for id := int64(1); id <= 2500; id++ {
		m.Items[market.ItemKey{ItemID: id}] = map[string]market.Entry{"R|H": {Last: &market.Last{T: i(fixtureNow), Min: i(id), Qty: i(1)}}}
	}
	f := &savedvars.File{Market: m}
	st := NewState("s", "f")
	plan := Build(f, st, Options{Now: fixtureNow})
	// 2,500 entries: more than 2,000 per request, and 4 rows each (10,000 > 8,000 per request).
	if len(plan.Public) != 2 {
		t.Fatalf("%d requests", len(plan.Public))
	}
	total := 0
	for _, b := range plan.Public {
		if b.Counts["prices"] > MaxPriceEntries || b.Rows > DefaultMaxRows || b.Bytes > DefaultMaxBytes {
			t.Errorf("request over the limits: %+v", b.Counts)
		}
		data, _ := json.Marshal(b.Body)
		if len(data) > b.Bytes || len(data) < b.Bytes*9/10 {
			t.Errorf("size estimate %d, actual %d", b.Bytes, len(data))
		}
		total += b.Counts["prices"]
	}
	if total != 2500 {
		t.Errorf("%d entries in all", total)
	}
	// Only the first request went through: the next build sends the rest.
	plan.Public[0].Commit(st)
	rest := Build(f, st, Options{Now: fixtureNow})
	if len(rest.Public) != 1 || rest.Public[0].Counts["prices"] != 2500-plan.Public[0].Counts["prices"] {
		t.Errorf("resume: %d requests", len(rest.Public))
	}

	// Small byte limit: many requests, each with all houses.
	small := Build(f, NewState("s", "f"), Options{Now: fixtureNow, MaxBytes: 20_000})
	if len(small.Public) < 5 {
		t.Errorf("%d requests at 20 KB", len(small.Public))
	}
	for _, b := range small.Public {
		if len(b.Body.Houses) != 1 {
			t.Error("request without the houses")
		}
	}
}

func TestRawPointsSplitOverRequests(t *testing.T) {
	i := market.Int
	var raw []market.Point
	for n := 0; n < MaxRawPoints+20; n++ {
		raw = append(raw, market.Point{T: fixtureNow - 100_000 + int64(n)*60, Total: i(1), Tiers: []market.Tier{{Price: 5, Qty: 1}}})
	}
	m := &savedvars.MarketDB{
		Houses: map[string]savedvars.House{"R|H": {Realm: "R", Kind: "faction", Faction: "Horde", Label: "Horde AH"}},
		Items:  map[market.ItemKey]map[string]market.Entry{{ItemID: 1}: {"R|H": {Last: &market.Last{T: i(fixtureNow), Min: i(5), Qty: i(1)}, Raw: raw}}},
	}
	f := &savedvars.File{Market: m}
	st := NewState("s", "f")
	plan := Build(f, st, Options{Now: fixtureNow})
	if len(plan.Public) != 2 {
		t.Fatalf("%d requests", len(plan.Public))
	}
	a, b := plan.Public[0].Body.Items["1"]["R|H"], plan.Public[1].Body.Items["1"]["R|H"]
	if len(a.Raw) != MaxRawPoints || len(b.Raw) != 20 || a.Last == nil || b.Last != nil {
		t.Errorf("pieces: %d (last %v), %d (last %v)", len(a.Raw), a.Last != nil, len(b.Raw), b.Last != nil)
	}
	plan.Public[0].Commit(st)
	rest := Build(f, st, Options{Now: fixtureNow})
	if len(rest.Public) != 1 || len(rest.Public[0].Body.Items["1"]["R|H"].Raw) != 20 || rest.Public[0].Body.Items["1"]["R|H"].Last != nil {
		t.Errorf("resume after the first piece: %+v", rest.Public)
	}
}

func TestLedgerSameSecond(t *testing.T) {
	i := market.Int
	entry := func(t int64, item int64) savedvars.LedgerEntry {
		return savedvars.LedgerEntry{T: i(t), Char: "R-Veli Tanner", Kind: "vsell", Item: i(item), Q: i(1), Copper: i(10), Where: "Vendor", Link: "|Hitem:1|h[x]|h"}
	}
	db := &savedvars.MarketDB{Ledger: &savedvars.Ledger{Entries: []savedvars.LedgerEntry{entry(fixtureNow-100, 1), entry(fixtureNow-50, 2)}}}
	f := &savedvars.File{Market: db}
	st := NewState("s", "f")
	plan := Build(f, st, Options{Now: fixtureNow, Private: true})
	if len(plan.Private) != 1 || len(plan.Private[0].Body.Ledger) != 2 || plan.Private[0].Body.Ledger[0].L == "" {
		t.Fatalf("first: %+v", plan.Private)
	}
	commitAll(plan, st)
	if p := Build(f, st, Options{Now: fixtureNow, Private: true}); !p.Empty() {
		t.Error("ledger sent again unchanged")
	}
	// An identical sale in the same second as the newest sent one: the whole second goes again,
	// so the server numbers both copies.
	db.Ledger.Entries = append(db.Ledger.Entries, entry(fixtureNow-50, 2), entry(fixtureNow-10, 3))
	plan = Build(f, st, Options{Now: fixtureNow, Private: true})
	got := plan.Private[0].Body.Ledger
	if len(got) != 3 || got[0].T != fixtureNow-50 || got[1].T != fixtureNow-50 || got[2].T != fixtureNow-10 {
		t.Errorf("second: %+v", got)
	}
}

func TestValidChar(t *testing.T) {
	for key, want := range map[string]bool{
		"Stub Realm-Veli Tanner":       true,
		"Realm-Name":                   true,
		"Some-Realm-Name":              true,
		"no dash":                      false,
		"-Name":                        false,
		"Realm-":                       false,
		"Realm-Na\nme":                 false,
		strings.Repeat("r", 65) + "-n": false,
	} {
		if validChar(key) != want {
			t.Errorf("validChar(%q) = %v", key, !want)
		}
	}
}
