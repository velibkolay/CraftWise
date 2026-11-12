package app

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/velibkolay/CraftWise/companion/upload"
)

// fakeWoW makes <tmp>/_forever_/WTF/Account/<acct>/SavedVariables/CraftWise.lua from the fixture.
func fakeWoW(t *testing.T, accounts ...string) (wow string, files []string) {
	t.Helper()
	data, err := os.ReadFile("../savedvars/testdata/CraftWise.lua")
	if err != nil {
		t.Fatal(err)
	}
	wow = filepath.Join(t.TempDir(), "World of Warcraft", "_forever_")
	for i, acct := range accounts {
		dir := filepath.Join(wow, "WTF", "Account", acct, "SavedVariables")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		p := filepath.Join(dir, "CraftWise.lua")
		if err := os.WriteFile(p, data, 0o644); err != nil {
			t.Fatal(err)
		}
		mod := time.Now().Add(time.Duration(i-len(accounts)) * time.Hour)
		if err := os.Chtimes(p, mod, mod); err != nil {
			t.Fatal(err)
		}
		files = append(files, p)
	}
	return wow, files
}

// snapshotTree lists every file under dir with its size and time, to prove nothing was written.
func snapshotTree(t *testing.T, dir string) string {
	t.Helper()
	var b strings.Builder
	_ = filepath.Walk(dir, func(p string, fi os.FileInfo, err error) error {
		if err == nil {
			fmt.Fprintf(&b, "%s %s %d\n", p, fi.ModTime(), fi.Size())
		}
		return nil
	})
	return b.String()
}

type recorder struct {
	mu    sync.Mutex
	paths []string
	auth  []string
}

func (r *recorder) server(t *testing.T, status int) *httptest.Server {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		_, _ = io.ReadAll(req.Body)
		r.mu.Lock()
		r.paths = append(r.paths, req.URL.Path)
		r.auth = append(r.auth, req.Header.Get("Authorization"))
		r.mu.Unlock()
		if status != 200 {
			w.WriteHeader(status)
			_, _ = io.WriteString(w, `{"error":"bad_shape","message":"x"}`)
			return
		}
		_, _ = io.WriteString(w, `{"ok":true,"rowsWritten":1}`)
	}))
	t.Cleanup(ts.Close)
	return ts
}

func newTestApp(t *testing.T, cfg Config) *App {
	t.Helper()
	a, err := New(t.TempDir(), "test", nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := SaveConfig(a.ConfigPath(), cfg); err != nil {
		t.Fatal(err)
	}
	return a
}

// The fixture's times lie in November 2026; the server accepts times up to now + 1 day.
var fixtureNow = time.Unix(1794010000, 0)

func TestRunOnceUploadsDeltaAndNeverWritesToWoW(t *testing.T) {
	wow, _ := fakeWoW(t, "OLD", "ACCOUNT1")
	before := snapshotTree(t, wow)
	rec := &recorder{}
	ts := rec.server(t, 200)
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath = ts.URL, "cw_secret", wow
	a := newTestApp(t, cfg)

	res, err := a.RunOnce(context.Background(), RunOptions{Now: fixtureNow})
	if err != nil || !res.OK() {
		t.Fatalf("run: %v %v", err, res.Errors)
	}
	// prices, then item info (#145), then private data
	if len(rec.paths) != 3 || rec.paths[0] != upload.PublicPath || rec.paths[1] != upload.PublicPath || rec.paths[2] != upload.PrivatePath ||
		rec.auth[0] != "Bearer cw_secret" {
		t.Fatalf("requests %v %v", rec.paths, rec.auth)
	}
	s := a.Status()
	if !s.OK || !strings.HasPrefix(s.Text, "sent ") || !strings.Contains(s.File, "ACCOUNT1") {
		t.Errorf("status %+v (want the newest account's file)", s)
	}

	res, err = a.RunOnce(context.Background(), RunOptions{Now: fixtureNow})
	if err != nil || res.Sent != 0 || len(rec.paths) != 3 {
		t.Errorf("second run sent again: %v, %d requests", err, len(rec.paths))
	}
	if a.Status().Text != "nothing new" {
		t.Errorf("status %+v", a.Status())
	}
	if after := snapshotTree(t, wow); after != before {
		t.Errorf("the WoW folder changed:\nbefore\n%s\nafter\n%s", before, after)
	}
	if _, err := os.Stat(a.StatePath()); err != nil {
		t.Errorf("no state file: %v", err)
	}
}

func TestRunOnceFailureStatusAndNoState(t *testing.T) {
	wow, _ := fakeWoW(t, "A")
	rec := &recorder{}
	ts := rec.server(t, 400)
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath, cfg.Private = ts.URL, "cw_x", wow, false
	a := newTestApp(t, cfg)
	res, err := a.RunOnce(context.Background(), RunOptions{Now: fixtureNow})
	if err != nil || res.OK() || res.Sent != 0 {
		t.Fatalf("res %+v err %v", res, err)
	}
	if s := a.Status(); s.OK || !strings.Contains(s.Text, "bad_shape") {
		t.Errorf("status %+v", s)
	}
	if _, err := os.Stat(a.StatePath()); !errors.Is(err, os.ErrNotExist) {
		t.Error("state written though nothing was accepted")
	}
}

func TestRunOnceNeedsToken(t *testing.T) {
	wow, _ := fakeWoW(t, "A")
	cfg := DefaultConfig()
	cfg.WoWPath = wow
	a := newTestApp(t, cfg)
	if _, err := a.RunOnce(context.Background(), RunOptions{Now: fixtureNow}); err == nil || !strings.Contains(err.Error(), "token") {
		t.Errorf("err = %v", err)
	}
	// A dry run needs none and writes the bodies.
	dump := filepath.Join(t.TempDir(), "dump")
	if _, err := a.RunOnce(context.Background(), RunOptions{Now: fixtureNow, DryRun: true, DumpDir: dump}); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"public-001.json", "private-001.json"} {
		if _, err := os.Stat(filepath.Join(dump, name)); err != nil {
			t.Error(err)
		}
	}
	// ... but never into the WoW folder.
	if _, err := a.RunOnce(context.Background(), RunOptions{Now: fixtureNow, DryRun: true, DumpDir: filepath.Join(wow, "dump")}); err == nil {
		t.Error("dump into the WoW folder allowed")
	}
}

func TestReadSavedVariablesIncomplete(t *testing.T) {
	data, _ := os.ReadFile("../savedvars/testdata/CraftWise.lua")
	p := filepath.Join(t.TempDir(), "CraftWise.lua")
	if err := os.WriteFile(p, data[:len(data)/2], 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadSavedVariables(p); !errors.Is(err, ErrIncomplete) {
		t.Errorf("half a file: err = %v", err)
	}
	if err := os.WriteFile(p, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if f, err := ReadSavedVariables(p); err != nil || f.Market == nil {
		t.Errorf("whole file: %v", err)
	}
}

func TestConfigCreatedWithDefaults(t *testing.T) {
	p := filepath.Join(t.TempDir(), "sub", "config.json")
	cfg, created, err := LoadConfig(p)
	if err != nil || !created || cfg.Site != DefaultSite || !cfg.Private || cfg.PollSeconds != 5 {
		t.Fatalf("%+v %v %v", cfg, created, err)
	}
	if err := os.WriteFile(p, []byte(`{"site":"https://example.test/ ","token":" cw_a ","private":false}`), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, created, err = LoadConfig(p)
	if err != nil || created || cfg.Site != "https://example.test" || cfg.Token != "cw_a" || cfg.Private || cfg.SettleSeconds != 3 {
		t.Errorf("%+v %v %v", cfg, created, err)
	}
}

func TestCheckSite(t *testing.T) {
	for site, ok := range map[string]bool{
		"https://wow.velikopter.com": true,
		"http://localhost:8787":      true,
		"http://127.0.0.1:8787":      true,
		"http://wow.velikopter.com":  false,
		"wow.velikopter.com":         false,
	} {
		if (CheckSite(site) == nil) != ok {
			t.Errorf("CheckSite(%q)", site)
		}
	}
}

func TestDefaultWoWPaths(t *testing.T) {
	win := DefaultWoWPaths("windows", `C:\Users\v`)
	if win[0] != `C:\Program Files (x86)\World of Warcraft\_forever_` {
		t.Errorf("windows: %v", win[0])
	}
	mac := DefaultWoWPaths("darwin", "/Users/v")
	if mac[0] != "/Applications/World of Warcraft/_forever_" || mac[1] != "/Users/v/Applications/World of Warcraft/_forever_" {
		t.Errorf("macOS: %v", mac)
	}
}

func TestSavedVariablesAccountChoice(t *testing.T) {
	wow, files := fakeWoW(t, "OLDER", "NEWER")
	p, acct, err := SavedVariables(wow, "")
	if err != nil || acct != "NEWER" || p != files[1] {
		t.Errorf("auto: %s %s %v", p, acct, err)
	}
	p, acct, err = SavedVariables(wow, "OLDER")
	if err != nil || acct != "OLDER" || p != files[0] {
		t.Errorf("configured: %s %s %v", p, acct, err)
	}
	if _, _, err := SavedVariables(wow, "NOPE"); err == nil {
		t.Error("missing account accepted")
	}
	if _, err := FindWoW(Config{WoWPath: t.TempDir()}); err == nil {
		t.Error("folder without WTF/Account accepted")
	}
}

func TestInside(t *testing.T) {
	base := t.TempDir()
	if !Inside(filepath.Join(base, "a", "b"), base) || !Inside(base, base) {
		t.Error("inside not detected")
	}
	if Inside(base+"x", base) || Inside(filepath.Dir(base), base) {
		t.Error("outside reported inside")
	}
}

func TestLoopUploadsAtStartAndAfterAChange(t *testing.T) {
	wow, files := fakeWoW(t, "A")
	rec := &recorder{}
	ts := rec.server(t, 200)
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath, cfg.Private = ts.URL, "cw_x", wow, false
	cfg.PollSeconds, cfg.SettleSeconds = 1, 1
	a := newTestApp(t, cfg)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go func() { a.Loop(ctx); close(done) }()

	waitFor := func(n int) {
		t.Helper()
		deadline := time.Now().Add(10 * time.Second)
		for time.Now().Before(deadline) {
			rec.mu.Lock()
			got := len(rec.paths)
			rec.mu.Unlock()
			if got >= n {
				return
			}
			time.Sleep(50 * time.Millisecond)
		}
		log, _ := os.ReadFile(a.LogPath())
		t.Fatalf("waited for %d requests; log:\n%s", n, log)
	}
	waitFor(2) // at start: prices, then item info (#145)

	// The game writes the file again with a newer price for one item.
	data, _ := os.ReadFile(files[0])
	more := strings.Replace(string(data), `"tnzxxc,1e,u,2,to1vgo||"`, `"tnzxxd,1f,u,2,to1vgo||"`, 1)
	if more == string(data) {
		t.Fatal("fixture entry not found")
	}
	if err := os.WriteFile(files[0], []byte(more), 0o644); err != nil {
		t.Fatal(err)
	}
	waitFor(3)
	a.Trigger() // nothing new: no request
	time.Sleep(300 * time.Millisecond)
	rec.mu.Lock()
	n := len(rec.paths)
	rec.mu.Unlock()
	if n != 3 {
		t.Errorf("%d requests, want 3", n)
	}
	cancel()
	<-done
}
