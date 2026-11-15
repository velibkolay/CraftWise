package syncdata

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/velibkolay/CraftWise/companion/market"
	"github.com/velibkolay/CraftWise/companion/svparse"
	"github.com/velibkolay/CraftWise/companion/upload"
)

const bs = string(rune(92)) // a backslash, written out so no escaping is needed in this file

type goldenCase struct {
	Name   string `json:"name"`
	Packed string `json:"packed"`
}

func golden(t *testing.T) []goldenCase {
	t.Helper()
	f, err := svparse.ParseFile("../market/testdata/golden.lua")
	if err != nil {
		t.Fatal(err)
	}
	var cases []goldenCase
	if p := svparse.Unmarshal(f.Get("CraftWiseMarketGolden"), &cases); len(p) > 0 {
		t.Fatal(p)
	}
	return cases
}

// The download is JSON in the shape of POST /api/upload; the file holds Market.lua's packed strings.
// Every golden entry goes packed -> JSON -> packed again, through the rendered Lua file.
func TestGoldenRoundTripThroughJSONAndFile(t *testing.T) {
	cases := golden(t)
	if len(cases) < 90 {
		t.Fatalf("only %d golden entries", len(cases))
	}
	items := map[string]map[string]market.Entry{}
	want := map[string]string{}
	for i, c := range cases {
		e, err := market.Decode(c.Packed)
		if err != nil {
			t.Fatalf("%s: %v", c.Name, err)
		}
		key := fmt.Sprint(1000 + i)
		items[key] = map[string]market.Entry{"Realm|H": e}
		want[key] = c.Packed
	}
	body, err := json.Marshal(upload.PublicPayload{V: 1, Items: items})
	if err != nil {
		t.Fatal(err)
	}
	var pg page
	if err := json.Unmarshal(body, &pg); err != nil {
		t.Fatal(err)
	}
	out := string(Render(File{Written: 5, Machine: "PC", Market: &pg.PublicPayload}))
	for key, packed := range want {
		line := fmt.Sprintf("[%s] = {\n        [\"Realm|H\"] = %s,", key, luaString(packed))
		if !strings.Contains(out, line) {
			t.Errorf("item %s: packed %q not in the file", key, packed)
		}
	}
}

func TestRenderIsPlainLuaData(t *testing.T) {
	one := int64(1)
	m := &upload.PublicPayload{
		Houses:        map[string]upload.House{"R|H": {Realm: "R", Kind: "faction", Faction: "Horde", Label: "R Horde"}},
		Scans:         map[string][]upload.Scan{"R|H": {{T: 1794000000, Kind: "full", Items: &one, Source: "x"}}},
		Names:         map[int64]string{2589: "Linen " + bs + "Cloth\"\n"},
		ItemInfo:      map[int64]market.ItemInfo{2589: {Quality: &one, Icon: &one}},
		ClassNames:    map[int64]string{7: "Trade Goods"},
		SubclassNames: map[int64]map[int64]string{7: {5: "Cloth"}},
		Items: map[string]map[string]market.Entry{
			"2589":     {"R|H": {Last: &market.Last{T: &one, Min: &one, Qty: &one}}},
			"2589:123": {"R|H": {}},
		},
	}
	got := string(Render(File{Written: 1763200000, Machine: "Mac", Market: m}))
	for _, want := range []string{
		"CraftWiseSync = {", "v = 1,", "written = 1763200000,", `machine = "Mac",`,
		`["R|H"] = { realm = "R", kind = "faction", faction = "Horde", label = "R Horde" },`,
		`{ t = 1794000000, kind = "full", items = 1, source = "x" },`,
		`[2589] = "Linen ` + bs + bs + `Cloth` + bs + `"` + bs + `010",`,
		`[2589] = "1,1,,,,",`, `[7] = "Trade Goods",`, `[7] = { [5] = "Cloth", },`,
		`[2589] = {`, `["2589:123"] = {`, `["R|H"] = "1,1,1,||",`,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("file lacks %q\n%s", want, got)
		}
	}
	if string(Render(File{Written: 1763200000, Machine: "Mac", Market: m})) != got {
		t.Error("Render is not deterministic")
	}
}

func TestWriteIsAtomicAndTouchesOnlyItsTwoFiles(t *testing.T) {
	wow := t.TempDir()
	other := filepath.Join(wow, "Interface", "AddOns", "CraftWise", "CraftWise.lua")
	if err := os.MkdirAll(filepath.Dir(other), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(other, []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	f := File{Written: 10, Machine: "PC", Market: &upload.PublicPayload{Names: map[int64]string{1: "a"}}}
	changed, err := Write(wow, f)
	if err != nil || !changed {
		t.Fatalf("first write: %v %v", changed, err)
	}
	dir := Dir(wow)
	entries, _ := os.ReadDir(dir)
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	if strings.Join(names, ",") != LuaName+","+TocName {
		t.Fatalf("files in the add-on folder: %v (no temporary file may stay)", names)
	}
	toc, _ := os.ReadFile(filepath.Join(dir, TocName))
	if !strings.Contains(string(toc), "## Interface: 16001") || strings.Contains(string(toc), "SavedVariables") {
		t.Errorf("toc:\n%s", toc)
	}
	if b, _ := os.ReadFile(other); string(b) != "keep" {
		t.Error("another add-on's file changed")
	}
	// Same data later: not written again (the game need not see a new file).
	f.Written = 99
	if changed, err := Write(wow, f); err != nil || changed {
		t.Fatalf("same data: changed=%v err=%v", changed, err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, LuaName))
	if !strings.Contains(string(b), "written = 10,") {
		t.Error("an unchanged file was rewritten")
	}
	// New data: written, with the new time.
	f.Market.Names[2] = "b"
	if changed, err := Write(wow, f); err != nil || !changed {
		t.Fatalf("new data: changed=%v err=%v", changed, err)
	}
	b, _ = os.ReadFile(filepath.Join(dir, LuaName))
	if !strings.Contains(string(b), "written = 99,") || !strings.Contains(string(b), `[2] = "b"`) {
		t.Errorf("file:\n%s", b)
	}
	// A different machine name counts as a change.
	f.Machine = "Mac"
	if changed, _ := Write(wow, f); !changed {
		t.Error("a new machine name was not written")
	}
}

func TestCacheMerge(t *testing.T) {
	one, two := int64(1), int64(2)
	c := NewCache("s")
	c.Merge(&upload.PublicPayload{
		Names: map[int64]string{1: "a", 2: "b"},
		Scans: map[string][]upload.Scan{"h": {{T: 10, Kind: "full"}, {T: 30, Kind: "full"}}},
		Items: map[string]map[string]market.Entry{"1": {"h": {Last: &market.Last{T: &one}}, "g": {Last: &market.Last{T: &one}}}},
	})
	c.Merge(&upload.PublicPayload{
		Names: map[int64]string{2: "B"},
		Scans: map[string][]upload.Scan{"h": {{T: 20, Kind: "full"}, {T: 30, Kind: "full", Items: &two}}},
		Items: map[string]map[string]market.Entry{"1": {"h": {Last: &market.Last{T: &two}}}},
	})
	m := c.Market
	if m.Names[1] != "a" || m.Names[2] != "B" {
		t.Errorf("names %v", m.Names)
	}
	if len(m.Scans["h"]) != 3 || m.Scans["h"][1].T != 20 || m.Scans["h"][2].Items == nil {
		t.Errorf("scans %+v", m.Scans["h"])
	}
	if *m.Items["1"]["h"].Last.T != 2 || m.Items["1"]["g"].Last == nil {
		t.Errorf("items %+v", m.Items)
	}
	path := filepath.Join(t.TempDir(), "cache.json")
	c.Since = 77
	if err := c.Save(path); err != nil {
		t.Fatal(err)
	}
	back, err := LoadCache(path, "s")
	if err != nil || back.Since != 77 || back.Market.Names[2] != "B" {
		t.Fatalf("reload: %+v %v", back, err)
	}
	if other, _ := LoadCache(path, "other-site"); other.Since != 0 || len(other.Market.Names) != 0 {
		t.Error("a cache of another site was used")
	}
}

func client(srv *httptest.Server) *upload.Client {
	c := upload.NewClient(srv.URL, "cw_test", "test")
	c.Attempts, c.Backoff = 2, time.Millisecond
	c.Sleep = func(context.Context, time.Duration) error { return nil }
	return c
}

func TestDownloadFollowsPagesAndSendsSince(t *testing.T) {
	var queries []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer cw_test" || r.URL.Path != MarketPath {
			http.Error(w, "no", 401)
			return
		}
		queries = append(queries, r.URL.RawQuery)
		if r.URL.Query().Get("cursor") == "" {
			fmt.Fprint(w, `{"v":1,"houses":{},"names":{"1":"a"},"items":{"5":{"h":{"last":{"t":9,"min":3,"qty":2}}}},"until":500,"next":"c2"}`)
			return
		}
		fmt.Fprint(w, `{"v":1,"houses":{},"names":{"2":"b"},"items":{"6":{"h":{"raw":[{"t":8,"total":1,"tiers":[{"price":4,"qty":1}]}]}}},"until":500}`)
	}))
	defer srv.Close()
	p, until, err := Download(context.Background(), client(srv), 123, nil)
	if err != nil {
		t.Fatal(err)
	}
	if until != 500 || len(queries) != 2 || queries[0] != "since=123" || queries[1] != "cursor=c2&since=123" {
		t.Errorf("until %d queries %v", until, queries)
	}
	if p.Names[1] != "a" || p.Names[2] != "b" || *p.Items["5"]["h"].Last.Min != 3 || p.Items["6"]["h"].Raw[0].Tiers[0].Price != 4 {
		t.Errorf("merged answer %+v", p)
	}
}

func TestDownloadErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(403)
		fmt.Fprint(w, `{"error":"forbidden","message":"token is not allowed"}`)
	}))
	defer srv.Close()
	if _, _, err := Download(context.Background(), client(srv), 0, nil); err == nil || !strings.Contains(err.Error(), "token is not allowed") {
		t.Errorf("err = %v", err)
	}
	newer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"v":2}`) }))
	defer newer.Close()
	if _, _, err := Download(context.Background(), client(newer), 0, nil); err == nil || !strings.Contains(err.Error(), "update the companion") {
		t.Errorf("err = %v", err)
	}
	empty := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"v":1}`) }))
	defer empty.Close()
	now := time.Unix(10_000, 0)
	_, until, err := Download(context.Background(), client(empty), 0, func() time.Time { return now })
	if err != nil || until != 10_000-60 {
		t.Errorf("until without a server time: %d %v", until, err)
	}
}
