package market

import (
	"errors"
	"math"
	"reflect"
	"strings"
	"testing"

	"github.com/velibkolay/CraftWise/companion/svparse"
)

// Golden fixtures written by tests/companion_fixtures.lua from CraftWise/Market.lua itself.
const goldenPath = "testdata/golden.lua"

type luaPoint struct {
	T        int64   `json:"t"`
	Total    *int64  `json:"total"`
	Listings *int64  `json:"listings"`
	M        *int64  `json:"m"`
	Tiers    []int64 `json:"tiers"`
}

type luaEntry struct {
	Last *Last         `json:"last"`
	Raw  []luaPoint    `json:"raw"`
	Days map[int64]Day `json:"days"`
}

func (l luaEntry) entry() Entry {
	e := Entry{Last: l.Last, Days: l.Days}
	for _, p := range l.Raw {
		point := Point{T: p.T, Total: p.Total, Listings: p.Listings, M: p.M}
		for i := 0; i+1 < len(p.Tiers); i += 2 {
			point.Tiers = append(point.Tiers, Tier{Price: p.Tiers[i], Qty: p.Tiers[i+1]})
		}
		e.Raw = append(e.Raw, point)
	}
	return normalize(e)
}

// normalize makes empty lists and maps nil so Lua's {} and Go's empty values compare equal.
func normalize(e Entry) Entry {
	if len(e.Raw) == 0 {
		e.Raw = nil
	}
	for i := range e.Raw {
		if len(e.Raw[i].Tiers) == 0 {
			e.Raw[i].Tiers = nil
		}
	}
	if len(e.Days) == 0 {
		e.Days = nil
	}
	return e
}

func loadGolden(t *testing.T) *svparse.File {
	t.Helper()
	f, err := svparse.ParseFile(goldenPath)
	if err != nil {
		t.Fatalf("%v (regenerate with: lua5.1 tests/companion_fixtures.lua)", err)
	}
	return f
}

func unmarshal(t *testing.T, v any, dst any) {
	t.Helper()
	if problems := svparse.Unmarshal(v, dst); len(problems) > 0 {
		t.Fatalf("fixture: %v", problems)
	}
}

func TestGoldenEntries(t *testing.T) {
	var cases []struct {
		Name    string   `json:"name"`
		Packed  string   `json:"packed"`
		Input   luaEntry `json:"input"`
		Decoded luaEntry `json:"decoded"`
	}
	unmarshal(t, loadGolden(t).Get("CraftWiseMarketGolden"), &cases)
	if len(cases) < 90 {
		t.Fatalf("only %d golden entries", len(cases))
	}
	for _, c := range cases {
		input, want := c.Input.entry(), c.Decoded.entry()
		if got := Encode(input); got != c.Packed {
			t.Errorf("%s: Encode(input)\n got %q\nwant %q", c.Name, got, c.Packed)
		}
		decoded, err := Decode(c.Packed)
		if err != nil {
			t.Errorf("%s: Decode: %v", c.Name, err)
			continue
		}
		if !reflect.DeepEqual(normalize(decoded), want) {
			t.Errorf("%s: Decode(%q)\n got %+v\nwant %+v", c.Name, c.Packed, normalize(decoded), want)
		}
		if got := Encode(decoded); got != c.Packed {
			t.Errorf("%s: Encode(Decode(s)) = %q, want %q", c.Name, got, c.Packed)
		}
		if decoded.LastOnly() != PackedLastOnly(c.Packed) {
			t.Errorf("%s: LastOnly %v but packed %q", c.Name, decoded.LastOnly(), c.Packed)
		}
		last, err := DecodeLast(c.Packed)
		if err != nil || !reflect.DeepEqual(last, want.Last) {
			t.Errorf("%s: DecodeLast = %+v, %v; want %+v", c.Name, last, err, want.Last)
		}
	}
}

func TestGoldenItemInfo(t *testing.T) {
	var cases []struct {
		Name    string   `json:"name"`
		Packed  string   `json:"packed"`
		T       *int64   `json:"t"`
		Input   ItemInfo `json:"input"`
		Decoded ItemInfo `json:"decoded"`
	}
	unmarshal(t, loadGolden(t).Get("CraftWiseItemInfoGolden"), &cases)
	if len(cases) < 7 {
		t.Fatalf("only %d item info cases", len(cases))
	}
	for _, c := range cases {
		input := c.Input
		input.T = c.T
		if got := EncodeItemInfo(input); got != c.Packed {
			t.Errorf("%s: EncodeItemInfo = %q, want %q", c.Name, got, c.Packed)
		}
		decoded, err := DecodeItemInfo(c.Packed)
		if err != nil || !reflect.DeepEqual(decoded, c.Decoded) {
			t.Errorf("%s: DecodeItemInfo(%q) = %+v, %v; want %+v", c.Name, c.Packed, decoded, err, c.Decoded)
		}
		if got := EncodeItemInfo(decoded); got != c.Packed {
			t.Errorf("%s: round trip %q, want %q", c.Name, got, c.Packed)
		}
	}
}

func TestGoldenAuctionator(t *testing.T) {
	var cases []struct {
		Name    string           `json:"name"`
		Packed  string           `json:"packed"`
		T       int64            `json:"t"`
		Copper  float64          `json:"copper"`
		Age     *float64         `json:"age"`
		Decoded AuctionatorPrice `json:"decoded"`
	}
	unmarshal(t, loadGolden(t).Get("CraftWiseAuctionatorGolden"), &cases)
	if len(cases) < 4 {
		t.Fatalf("only %d auctionator cases", len(cases))
	}
	for _, c := range cases {
		// ExportAuctionator floors copper and age before writing.
		in := AuctionatorPrice{T: Int(c.T), Copper: Int(int64(math.Floor(c.Copper)))}
		if c.Age != nil {
			in.Age = Int(int64(math.Floor(*c.Age)))
		}
		if got := EncodeAuctionator(in); got != c.Packed {
			t.Errorf("%s: EncodeAuctionator = %q, want %q", c.Name, got, c.Packed)
		}
		decoded, err := DecodeAuctionator(c.Packed)
		if err != nil || !reflect.DeepEqual(decoded, c.Decoded) {
			t.Errorf("%s: DecodeAuctionator(%q) = %+v, %v; want %+v", c.Name, c.Packed, decoded, err, c.Decoded)
		}
		if got := EncodeAuctionator(decoded); got != c.Packed {
			t.Errorf("%s: round trip %q, want %q", c.Name, got, c.Packed)
		}
	}
}

func TestDecodeRejectsMalformed(t *testing.T) {
	for _, s := range []string{
		"", "|", "a|b|c|d", "1,2,3|", "1,2|x|", // part count, last field count
		"1,2,3,4,5,6||",                // last with too many fields
		"|,1,1,1||",                    // raw point without time delta (also bad part count)
		"|,1,1,|",                      // raw point without time delta
		"|1,1,1,,2|",                   // price level without units
		"|1,1,1,,2,|",                  // empty units
		"|1,1,1,|1,2,3",                // day with too few fields
		"|1,1,1,|,1,,,,,,",             // day without delta
		"to3n9c,2-8,q,3||",             // not base 36
		"to3n9c,zzzzzzzzzzzzzzz,q,3||", // overflow
	} {
		if _, err := Decode(s); err == nil || !errors.Is(err, ErrMalformed) {
			t.Errorf("Decode(%q) = %v, want ErrMalformed", s, err)
		}
	}
	for _, s := range []string{"1,2", "1,2,3,4", "x-,1,2"} {
		if _, err := DecodeAuctionator(s); err == nil {
			t.Errorf("DecodeAuctionator(%q) accepted", s)
		}
	}
	for _, s := range []string{"1,2,3,4", "1,2,3,4,5,6", "1,!,3,4,5"} {
		if _, err := DecodeItemInfo(s); err == nil {
			t.Errorf("DecodeItemInfo(%q) accepted", s)
		}
	}
}

func TestEncodeMatchesLuaRules(t *testing.T) {
	// Values below 1 are written "0" (Market.lua Base36); gone 0 is left out; off 0 is kept.
	e := Entry{
		Last: &Last{T: Int(-5), Min: Int(0), Off: Int(0)},
		Days: map[int64]Day{3: {Gone: Int(0), N: Int(-1)}, 1: {Lo: Int(10), Typ: Int(4)}},
	}
	if got, want := Encode(e), "0,0,,,0||2,a,b,,,,,;4,,,,,,0,"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestItemKey(t *testing.T) {
	cases := []struct {
		in   any
		want ItemKey
		text string
	}{
		{float64(2589), ItemKey{ItemID: 2589}, "2589"},
		{"9005:1234", ItemKey{ItemID: 9005, Suffix: 1234}, "9005:1234"},
		{"9005:-17", ItemKey{ItemID: 9005, Suffix: -17}, "9005:-17"},
		{"9005", ItemKey{ItemID: 9005}, "9005"},
	}
	for _, c := range cases {
		got, err := ParseItemKey(c.in)
		if err != nil || got != c.want || got.String() != c.text {
			t.Errorf("ParseItemKey(%v) = %+v (%s), %v", c.in, got, got.String(), err)
		}
	}
	for _, bad := range []any{1.5, float64(0), "x", "12:y", true} {
		if _, err := ParseItemKey(bad); err == nil {
			t.Errorf("ParseItemKey(%v) accepted", bad)
		}
	}
	if !strings.Contains(ItemKey{ItemID: 1, Suffix: 2}.String(), ":") {
		t.Fatal("suffix key")
	}
}
