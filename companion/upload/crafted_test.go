package upload

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/velibkolay/CraftWise/companion/savedvars"
)

// A craft log in the shape the addon really writes (Crafts.lua, CL.Record; checked against a real
// SavedVariables file, values invented): a day is a positional list { crafts, items, profit, known, active },
// a new day starts as { 0, 0, 0, 0 }, days from before the time was recorded have four values.
const craftedLua = `CraftWiseDB = {
["crafted"] = {
["before"] = { [2549] = 12 },
["seeded"] = true,
["chars"] = {
["Realm-Aria"] = {
[2549] = {
["days"] = {
[20261114] = { 10, 10, 2500, 10, 31.5 },
[20261115] = { 4, 4, -120, 3 },
[20261116] = { 2, 0, 0, 0, 0 },
[20261117] = { 0, 0, 0, 0, 0 },
},
["earlier"] = { 50, 50, 900, 40 },
["speed"] = { ["n"] = 6, ["sum"] = 12, ["gaps"] = { 2, 2, 2, 2, 2, 2 } },
},
[3000] = { ["days"] = { [20261115] = { 0, 0, 0, 0 } } },
},
["Bad key"] = { [2549] = { ["days"] = { [20261115] = { 1, 1 } } } },
},
},
}
`

func craftedFile(t *testing.T) *savedvars.File {
	t.Helper()
	f, err := savedvars.Read(strings.NewReader(craftedLua))
	if err != nil {
		t.Fatal(err)
	}
	if len(f.Problems) != 0 {
		t.Fatalf("problems %v", f.Problems)
	}
	return f
}

func craftedRows(plan *Plan) []CraftedRow {
	var out []CraftedRow
	for _, b := range plan.Private {
		out = append(out, b.Body.Crafted...)
	}
	return out
}

func TestCraftedReadAndUpload(t *testing.T) {
	f := craftedFile(t)
	st := NewState("s", "f")
	plan := Build(f, st, Options{Now: fixtureNow, Private: true})
	rows := craftedRows(plan)
	if len(rows) != 3 {
		t.Fatalf("%d rows, want the 3 valid days: %+v", len(rows), rows)
	}
	// oldest day first; the day without profit and time carries neither
	if rows[0].D != 20261114 || rows[0].N != 10 || *rows[0].P != 2500 || *rows[0].K != 10 || *rows[0].A != 31.5 || *rows[0].I != 10 {
		t.Errorf("first row %+v", rows[0])
	}
	if *rows[1].P != -120 || rows[1].A != nil {
		t.Errorf("second row %+v: a loss is sent, a day without time has no a", rows[1])
	}
	// a day that started as { 0, 0, 0, 0 } and never had a priced craft: 0 means not recorded
	if rows[2].N != 2 || rows[2].P != nil || rows[2].K != nil || rows[2].I != nil || rows[2].A == nil || *rows[2].A != 0 {
		t.Errorf("third row %+v: zero items, profit and known must stay missing", rows[2])
	}
	if plan.Skipped["craft log of an invalid character key"] != 1 {
		t.Errorf("skipped %v", plan.Skipped)
	}
	if got := plan.Private[0].Summary(); got != "3 crafted" {
		t.Errorf("summary %q", got)
	}
	body, _ := json.Marshal(plan.Private[0].Body)
	if !strings.Contains(string(body), `"crafted":[{"c":"Realm-Aria","r":2549,"d":20261114,"n":10,"i":10,"p":2500,"k":10,"a":31.5}`) {
		t.Errorf("body %s", body)
	}
}

func TestCraftedDelta(t *testing.T) {
	f := craftedFile(t)
	st := NewState("s", "f")
	commitAll(Build(f, st, Options{Now: fixtureNow, Private: true}), st)
	if rows := craftedRows(Build(f, st, Options{Now: fixtureNow + 60, Private: true})); len(rows) != 0 {
		t.Fatalf("unchanged days were sent again: %+v", rows)
	}
	// one day grows, one new day appears: only those two go out
	rec := f.DB.Crafted.Chars["Realm-Aria"][2549]
	rec.Days[20261115] = savedvars.CraftedDay{5, 5, 100, 5}
	rec.Days[20261117] = savedvars.CraftedDay{5}
	rows := craftedRows(Build(f, st, Options{Now: fixtureNow + 60, Private: true}))
	if len(rows) != 2 || rows[0].D != 20261115 || rows[0].N != 5 || *rows[0].P != 100 || rows[1].D != 20261117 {
		t.Fatalf("after a change: %+v", rows)
	}
	// a state kept for another file sends everything again
	if rows := craftedRows(Build(f, NewState("s", "g"), Options{Now: fixtureNow, Private: true})); len(rows) != 4 {
		t.Fatalf("fresh state sent %d rows", len(rows))
	}
}

func TestCraftedLimits(t *testing.T) {
	// no craft log (an older addon), private uploads off: nothing
	if rows := craftedRows(Build(&savedvars.File{DB: &savedvars.DB{}}, NewState("s", "f"), Options{Now: fixtureNow, Private: true})); len(rows) != 0 {
		t.Fatal("rows without a craft log")
	}
	f := craftedFile(t)
	if p := Build(f, NewState("s", "f"), Options{Now: fixtureNow}); len(p.Private) != 0 {
		t.Error("private requests with Private off")
	}
	// more days than one request takes are split, none lost
	days := map[int64]savedvars.CraftedDay{}
	for i := int64(0); i < 12000; i++ {
		days[20260101+i%28+100*(i/28%12)+10000*(i/336)] = savedvars.CraftedDay{1}
	}
	big := &savedvars.File{DB: &savedvars.DB{Crafted: &savedvars.Crafted{Chars: map[string]map[int64]savedvars.CraftedRecipe{
		"Realm-Aria": {2549: {Days: days}},
	}}}}
	plan := Build(big, NewState("s", "f"), Options{Now: fixtureNow, Private: true})
	total := 0
	for _, b := range plan.Private {
		if len(b.Body.Crafted) > MaxCraftedRows {
			t.Fatalf("request with %d rows", len(b.Body.Crafted))
		}
		total += len(b.Body.Crafted)
	}
	if total != len(days) || len(plan.Private) < 3 {
		t.Fatalf("%d rows in %d requests, want %d", total, len(plan.Private), len(days))
	}
}
