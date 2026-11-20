package app

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/velibkolay/CraftWise/companion/syncdata"
)

// #244: the site's watch list changes are merged into the cache and written to the sync file as
// watch / watchGone; the next download asks since the time the server gave.
func TestDownloadWritesTheMergedWatchList(t *testing.T) {
	wow, files := fakeWoW(t, "A")
	ms, ts := newMarketServer(t, files[0])
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath, cfg.Machine = ts.URL, "cw_x", wow, "PC"
	a := newTestApp(t, cfg)
	a.clock = func() time.Time { return fixtureNow }
	ms.watch = `{"v":1,"watch":[{"i":2589,"t":1794000100},{"i":4306,"t":1794000200,"d":true},{"i":7,"t":1794000300}],"until":4444}`

	if _, err := a.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	lua := syncText(t, wow)
	for _, want := range []string{
		"  watch = {\n    [7] = 1794000300,\n    [2589] = 1794000100,\n  },\n",
		"  watchGone = {\n    [4306] = 1794000200,\n  },\n",
	} {
		if !strings.Contains(strings.ReplaceAll(lua, "\r\n", "\n"), want) {
			t.Errorf("sync file lacks %q", want)
		}
	}
	if len(ms.watchGets) != 1 || ms.watchGets[0] != "since=0" {
		t.Errorf("watch requests %v", ms.watchGets)
	}

	// the next answer: an older add of 4306 loses to the tombstone, a newer one wins; 7 is removed
	ms.watch = `{"v":1,"watch":[{"i":4306,"t":1794000100},{"i":2589,"t":1794000100,"d":true},{"i":7,"t":1794000400,"d":true}],"until":9000}`
	if _, err := a.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	if last := ms.watchGets[len(ms.watchGets)-1]; last != "since=4444" {
		t.Errorf("second request %q", last)
	}
	lua = strings.ReplaceAll(syncText(t, wow), "\r\n", "\n")
	for _, want := range []string{"  watch = {\n    [2589] = 1794000100,\n  },\n", "[4306] = 1794000200,", "[7] = 1794000400,"} {
		if !strings.Contains(lua, want) {
			t.Errorf("second file lacks %q:\n%s", want, lua)
		}
	}
}

// A site without the endpoint, or private data off, leaves the watch list out and never stops the market.
func TestDownloadWatchFailureDoesNotStopTheMarket(t *testing.T) {
	wow, files := fakeWoW(t, "A")
	ms, ts := newMarketServer(t, files[0])
	ms.watchStatus = 404
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath = ts.URL, "cw_x", wow
	a := newTestApp(t, cfg)
	a.clock = func() time.Time { return fixtureNow }
	res, err := a.Download(context.Background())
	if err != nil || !res.Changed {
		t.Fatalf("download: %+v %v", res, err)
	}
	lua := syncText(t, wow)
	if !strings.Contains(lua, "items = {") || strings.Contains(lua, "watch = {") {
		t.Error("market missing or a watch list invented")
	}
	if !strings.Contains(a.Status().Download, "watch list failed") {
		t.Errorf("status %q", a.Status().Download)
	}
	cache, _ := syncdata.LoadCache(a.CachePath(), ts.URL)
	if cache.WatchSince != 0 || cache.Since != 4242 {
		t.Errorf("since %d, watch since %d", cache.Since, cache.WatchSince)
	}

	cfg.Private = false
	if err := SaveConfig(a.ConfigPath(), cfg); err != nil {
		t.Fatal(err)
	}
	n := len(ms.watchGets)
	if _, err := a.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(ms.watchGets) != n {
		t.Error("watch list asked for with private off")
	}
}

// Changes that came down are not uploaded again; the addon's own change after them is.
func TestWatchDownloadIsNotEchoed(t *testing.T) {
	wow, files := fakeWoW(t, "A")
	ms, ts := newMarketServer(t, files[0])
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath, cfg.Machine = ts.URL, "cw_x", wow, "PC"
	a := newTestApp(t, cfg)
	a.clock = func() time.Time { return fixtureNow }
	// fixture watch: 9001 at ...5020, 9004 at ...5220, 9008 removed at ...5120. The site has 9004 unwatched later.
	ms.watch = `{"v":1,"watch":[{"i":9004,"t":1794005300,"d":true},{"i":9001,"t":1794005020}],"until":4444}`
	if _, err := a.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err := a.RunOnce(context.Background(), RunOptions{Now: fixtureNow}); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, b := range ms.uploadBodies {
		_, w, ok := strings.Cut(b, `"watch":[`)
		if !ok {
			continue
		}
		found = true
		if w != `{"i":9008,"t":1794005120,"d":true}]}` {
			t.Errorf("watch changes uploaded: %s", w)
		}
	}
	if !found {
		t.Error("the addon's own tombstone was not uploaded")
	}
}
