package app

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/velibkolay/CraftWise/companion/syncdata"
	"github.com/velibkolay/CraftWise/companion/upload"
)

const otherChars = `{"v":1,"characters":{
 "R-Mage Alt":{"machine":"Mac","uploaded":1794000100,"info":{"realm":"R","name":"Mage","level":12},
   "snapshot":{"t":1794000000,"data":{"v":1,"bags":{"2589":20}}},"ledger":[{"t":5,"k":"ahbuy","i":1}],"crafted":[]},
 "R-Own Char":{"machine":"Mac","uploaded":1794000200,"info":{"name":"Own"},"snapshot":{"t":1,"data":{"v":1}},"ledger":[],"crafted":[]}
},"next":null,"until":4343}`

func syncText(t *testing.T, wow string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(syncdata.Dir(wow), syncdata.LuaName))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// The other machine's characters go into the sync file, this machine's own never do (own data wins).
func TestDownloadWritesTheOtherMachinesCharacters(t *testing.T) {
	wow, files := fakeWoW(t, "A")
	ms, ts := newMarketServer(t, files[0])
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath, cfg.Machine = ts.URL, "cw_x", wow, "PC"
	a := newTestApp(t, cfg)
	a.clock = func() time.Time { return fixtureNow }

	// the state knows this machine's own characters from what it uploaded: "R-Own Char" is one of them
	st := upload.NewState(ts.URL, files[0])
	st.Docs = map[string]uint64{"snapshots\x1fR-Own Char": 1}
	if err := st.Save(a.StatePathFor("A")); err != nil {
		t.Fatal(err)
	}
	ms.chars = otherChars

	if _, err := a.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	lua := syncText(t, wow)
	for _, want := range []string{
		`  chars = {`,
		`    ["R-Mage Alt"] = {`,
		`      machine = "Mac",`,
		`      uploaded = 1794000100,`,
		`      info = { level = 12, name = "Mage", realm = "R" },`,
		`      snapshot = { data = { bags = { ["2589"] = 20 }, v = 1 }, t = 1794000000 },`,
		`      ledger = { { i = 1, k = "ahbuy", t = 5 } },`,
		`      crafted = {},`,
	} {
		if !strings.Contains(lua, want) {
			t.Errorf("sync file lacks %q", want)
		}
	}
	if strings.Contains(lua, "Own Char") {
		t.Error("an own character was written")
	}
	if len(ms.charGets) != 1 || ms.charGets[0] != "notMachine=PC&since=0" {
		t.Errorf("character requests %v", ms.charGets)
	}

	// the next download asks since the time the server gave; the cache keeps the characters
	ms.chars = `{"v":1,"characters":{},"next":null,"until":9000}`
	if _, err := a.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	if last := ms.charGets[len(ms.charGets)-1]; last != "notMachine=PC&since=4343" {
		t.Errorf("second request %q", last)
	}
	if !strings.Contains(syncText(t, wow), `["R-Mage Alt"]`) {
		t.Error("the characters left the file when nothing changed")
	}
}

// A token without the private scope, or a site without the endpoint, leaves the characters out and
// the market comes through.
func TestDownloadCharactersFailureDoesNotStopTheMarket(t *testing.T) {
	wow, files := fakeWoW(t, "A")
	ms, ts := newMarketServer(t, files[0])
	ms.charsStatus = 403
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath = ts.URL, "cw_x", wow
	a := newTestApp(t, cfg)
	a.clock = func() time.Time { return fixtureNow }
	res, err := a.Download(context.Background())
	if err != nil || !res.Changed {
		t.Fatalf("download: %+v %v", res, err)
	}
	if !strings.Contains(syncText(t, wow), "items = {") || strings.Contains(syncText(t, wow), "uploaded =") {
		t.Error("market missing or characters invented")
	}
	if !strings.Contains(a.Status().Download, "characters failed") {
		t.Errorf("status %q", a.Status().Download)
	}
	cache, _ := syncdata.LoadCache(a.CachePath(), ts.URL)
	if cache.CharsSince != 0 || cache.Since != 4242 {
		t.Errorf("since %d, characters since %d", cache.Since, cache.CharsSince)
	}

	// with the private upload off, the characters aren't asked for at all
	cfg.Private = false
	if err := SaveConfig(a.ConfigPath(), cfg); err != nil {
		t.Fatal(err)
	}
	n := len(ms.charGets)
	if _, err := a.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(ms.charGets) != n {
		t.Error("characters asked for with private off")
	}
}
