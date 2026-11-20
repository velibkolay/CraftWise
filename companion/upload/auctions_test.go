package upload

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/velibkolay/CraftWise/companion/savedvars"
)

func i64(v int64) *int64 { return &v }

// bigAuctions is n finished records (settled at 1,700,000,000 + i) and `active` listed ones, each about
// 350 bytes like the real ones (a 90 character item link).
func bigAuctions(n, active int) savedvars.AuctionChar {
	link := "|cnIQ1:|Hitem:5082::::::::20:1485:::::::::|h[Thin Kodo Leather With A Long Name]|h|r" + strings.Repeat("x", 120)
	var c savedvars.AuctionChar
	for i := 0; i < n; i++ {
		c.List = append(c.List, savedvars.Auction{ID: i64(int64(1000 + i)), Item: i64(5082), Name: "Thin Kodo Leather", Link: link,
			Q: i64(9), Status: "settled", SettledT: i64(1_700_000_000 + int64(i)), Seen: i64(1_699_000_000)})
	}
	for i := 0; i < active; i++ {
		// listed long ago: older than every finished record, but still on the AH
		c.List = append(c.List, savedvars.Auction{ID: i64(int64(900000 + i)), Item: i64(5082), Name: "Thin Kodo Leather", Link: link,
			Q: i64(9), Status: "active", T: i64(1_600_000_100 + int64(i))})
	}
	c.OwnedAt = i64(1_700_000_000)
	c.OwnedHouse = "Realm|H"
	return c
}

func TestTrimAuctionsLeavesASmallDocumentAlone(t *testing.T) {
	c := bigAuctions(20, 3)
	doc, cut := trimAuctions(c, MaxAuctionsDoc)
	if cut != 0 || len(doc.List) != 23 || doc.Trimmed != 0 {
		t.Fatalf("cut %d, %d records, trimmed %d", cut, len(doc.List), doc.Trimmed)
	}
	body, _ := json.Marshal(doc)
	if strings.Contains(string(body), "trimmed") {
		t.Errorf("an uncut document has no trimmed field: %s", body[:200])
	}
}

func TestTrimAuctionsKeepsListedAndNewestUnderTheLimit(t *testing.T) {
	c := bigAuctions(2500, 12) // about 1 MB
	doc, cut := trimAuctions(c, MaxAuctionsDoc)
	body, err := json.Marshal(doc)
	if err != nil {
		t.Fatal(err)
	}
	if len(body) > MaxAuctionsDoc || len(body) > MaxPrivateDocSize {
		t.Fatalf("document is %d bytes, limit %d", len(body), MaxAuctionsDoc)
	}
	if cut == 0 || doc.Trimmed != cut || len(doc.List)+cut != len(c.List) {
		t.Fatalf("cut %d, trimmed %d, kept %d of %d", cut, doc.Trimmed, len(doc.List), len(c.List))
	}
	active, newest, oldest := 0, int64(0), int64(1<<62)
	for _, a := range doc.List {
		if a.Status == "active" {
			active++
			continue
		}
		at := *a.SettledT
		if at > newest {
			newest = at
		}
		if at < oldest {
			oldest = at
		}
	}
	if active != 12 {
		t.Errorf("listed records kept: %d, want all 12", active)
	}
	if newest != 1_700_000_000+2499 {
		t.Errorf("the newest finished record must stay, newest kept is %d", newest)
	}
	// what was cut is the oldest: every kept finished record is newer than every cut one
	if want := int64(1_700_000_000 + cut); oldest != want {
		t.Errorf("oldest kept finished record %d, want %d (the %d oldest cut)", oldest, want, cut)
	}
	// the order of the list is unchanged
	for i := 1; i < len(doc.List); i++ {
		a, b := doc.List[i-1], doc.List[i]
		if a.Status != "active" && b.Status != "active" && *a.SettledT > *b.SettledT {
			t.Fatalf("record order changed at %d", i)
		}
	}
	if doc.OwnedAt == nil || doc.OwnedHouse != "Realm|H" {
		t.Errorf("the other fields of the character must stay: %+v", doc.AuctionChar)
	}
	// the cut copy is the only thing that changes: the input list is untouched
	if len(c.List) != 2512 {
		t.Errorf("input list changed: %d", len(c.List))
	}
}

func TestBuildCutsABigAuctionsDocumentInsteadOfDroppingIt(t *testing.T) {
	f := readFixture(t)
	f.Market.Auctions = &savedvars.Auctions{Chars: map[string]savedvars.AuctionChar{"Realm-Big": bigAuctions(2000, 5)}}
	st := NewState("https://example.test", "CraftWise.lua")
	plan := Build(f, st, Options{Now: fixtureNow + 1_000_000_000, Private: true})
	if n := plan.Skipped["auctions document over 450000 bytes"]; n != 0 {
		t.Fatalf("the document was dropped: %v", plan.SkippedText())
	}
	if len(plan.Trimmed) != 1 || len(plan.TrimmedText()) != 1 || !strings.Contains(plan.TrimmedText()[0], "oldest finished records") {
		t.Fatalf("trimmed: %v", plan.TrimmedText())
	}
	sent := false
	for _, b := range plan.Private {
		doc, ok := b.Body.Auctions["Realm-Big"]
		if !ok {
			continue
		}
		sent = true
		raw := doc.Data.(json.RawMessage)
		if len(raw) > MaxPrivateDocSize {
			t.Errorf("document of %d bytes is over the server's limit", len(raw))
		}
		var back struct {
			List    []json.RawMessage `json:"list"`
			Trimmed int               `json:"trimmed"`
		}
		if err := json.Unmarshal(raw, &back); err != nil {
			t.Fatal(err)
		}
		if back.Trimmed == 0 || len(back.List)+back.Trimmed != 2005 {
			t.Errorf("list %d, trimmed %d", len(back.List), back.Trimmed)
		}
	}
	if !sent {
		t.Fatal("no auctions document in the plan")
	}
	// Committed, the same data builds nothing new for it (the hash is of the cut document).
	commitAll(plan, st)
	again := Build(f, st, Options{Now: fixtureNow + 1_000_000_000, Private: true})
	for _, b := range again.Private {
		if _, ok := b.Body.Auctions["Realm-Big"]; ok {
			t.Error("an unchanged cut document must not be sent again")
		}
	}
	if len(again.Trimmed) != 1 {
		t.Errorf("the cut is reported on every build, not only the one that sent it: %v", again.TrimmedText())
	}
}
