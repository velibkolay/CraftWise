package app

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/velibkolay/CraftWise/companion/syncdata"
	"github.com/velibkolay/CraftWise/companion/upload"
)

// marketServer answers uploads with ok and GET /api/sync/market with the fixture's market as the
// bodies of a first upload, one per page (the shape of POST /api/upload plus until and next).
type marketServer struct {
	mu      sync.Mutex
	pages   [][]byte
	gets    []string // raw queries of the downloads
	uploads []string // paths of the uploads
	machine string
	status  int // download status, 0 = 200

	// GET /api/sync/characters (#242): the answer (empty = no characters) or a status to refuse with.
	chars       string
	charsStatus int
	charGets    []string
}

func newMarketServer(t *testing.T, file string) (*marketServer, *httptest.Server) {
	t.Helper()
	f, err := ReadSavedVariables(file)
	if err != nil {
		t.Fatal(err)
	}
	plan := upload.Build(f, upload.NewState("x", "y"), upload.Options{Now: fixtureNow.Unix()})
	ms := &marketServer{}
	for i, b := range plan.Public {
		raw, err := json.Marshal(b.Body)
		if err != nil {
			t.Fatal(err)
		}
		var m map[string]any
		_ = json.Unmarshal(raw, &m)
		m["until"] = 4242
		if i+1 < len(plan.Public) {
			m["next"] = "page" + string(rune('2'+i))
		}
		raw, _ = json.Marshal(m)
		ms.pages = append(ms.pages, raw)
	}
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ms.mu.Lock()
		defer ms.mu.Unlock()
		ms.machine = r.Header.Get("X-CraftWise-Machine")
		if r.Method == http.MethodGet && r.URL.Path == syncdata.CharsPath {
			ms.charGets = append(ms.charGets, r.URL.RawQuery)
			if ms.charsStatus != 0 {
				w.WriteHeader(ms.charsStatus)
				_, _ = io.WriteString(w, `{"error":"forbidden","message":"token lacks the private scope"}`)
				return
			}
			if ms.chars == "" {
				_, _ = io.WriteString(w, `{"v":1,"characters":{},"next":null,"until":4343}`)
				return
			}
			_, _ = io.WriteString(w, ms.chars)
			return
		}
		if r.Method == http.MethodGet {
			ms.gets = append(ms.gets, r.URL.RawQuery)
			if ms.status != 0 {
				w.WriteHeader(ms.status)
				_, _ = io.WriteString(w, `{"error":"forbidden","message":"token is not allowed"}`)
				return
			}
			page := 0
			if c := r.URL.Query().Get("cursor"); c != "" {
				page = int(c[len(c)-1]-'2') + 1
			}
			_, _ = w.Write(ms.pages[page])
			return
		}
		_, _ = io.Copy(io.Discard, r.Body)
		ms.uploads = append(ms.uploads, r.URL.Path)
		_, _ = io.WriteString(w, `{"ok":true,"rowsWritten":1}`)
	}))
	t.Cleanup(ts.Close)
	return ms, ts
}

func TestDownloadWritesTheSyncFileAndDoesNotEcho(t *testing.T) {
	wow, files := fakeWoW(t, "A")
	ms, ts := newMarketServer(t, files[0])
	if len(ms.pages) < 2 {
		t.Fatalf("want a download in 2 pages, have %d", len(ms.pages))
	}
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath, cfg.Machine = ts.URL, "cw_x", wow, "Mac"
	a := newTestApp(t, cfg)
	a.clock = func() time.Time { return fixtureNow }

	res, err := a.Download(context.Background())
	if err != nil || !res.Changed {
		t.Fatalf("download: %+v %v", res, err)
	}
	dir := syncdata.Dir(wow)
	lua, err := os.ReadFile(filepath.Join(dir, syncdata.LuaName))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"CraftWiseSync = {", `machine = "Mac",`, "items = {", "itemInfo = {"} {
		if !strings.Contains(string(lua), want) {
			t.Errorf("sync file lacks %q", want)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, syncdata.TocName)); err != nil {
		t.Error(err)
	}
	if ms.machine != "Mac" || len(ms.gets) != 2 || ms.gets[0] != "since=0" {
		t.Errorf("requests %v machine %q", ms.gets, ms.machine)
	}

	// No echo: the file as the addon would have merged it holds exactly this market; the upload
	// sends no public request, only the private data.
	if _, err := a.RunOnce(context.Background(), RunOptions{Now: fixtureNow}); err != nil {
		t.Fatal(err)
	}
	for _, p := range ms.uploads {
		if p == upload.PublicPath {
			t.Errorf("the downloaded market was uploaded again: %v", ms.uploads)
		}
	}

	// The next download asks since the time the server gave, and nothing new leaves the file alone.
	before, _ := os.Stat(filepath.Join(dir, syncdata.LuaName))
	ms.pages = [][]byte{[]byte(`{"v":1,"houses":{},"until":5000}`)}
	res, err = a.Download(context.Background())
	if err != nil || res.Changed {
		t.Fatalf("second download: %+v %v", res, err)
	}
	if last := ms.gets[len(ms.gets)-1]; last != "since=4242" {
		t.Errorf("second download asked %q", last)
	}
	after, _ := os.Stat(filepath.Join(dir, syncdata.LuaName))
	if !after.ModTime().Equal(before.ModTime()) {
		t.Error("the sync file was rewritten without new data")
	}
	if a.Status().Download == "" {
		t.Error("no download status")
	}
}

func TestDownloadFailureKeepsSinceAndTheFile(t *testing.T) {
	wow, files := fakeWoW(t, "A")
	ms, ts := newMarketServer(t, files[0])
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath = ts.URL, "cw_x", wow
	a := newTestApp(t, cfg)
	a.clock = func() time.Time { return fixtureNow }
	if _, err := a.Download(context.Background()); err != nil {
		t.Fatal(err)
	}
	lua, _ := os.ReadFile(filepath.Join(syncdata.Dir(wow), syncdata.LuaName))

	ms.mu.Lock()
	ms.status = 403
	ms.mu.Unlock()
	if _, err := a.Download(context.Background()); err == nil || !strings.Contains(err.Error(), "token is not allowed") {
		t.Fatalf("err = %v", err)
	}
	cache, err := syncdata.LoadCache(a.CachePath(), ts.URL)
	if err != nil || cache.Since != 4242 {
		t.Errorf("since after a failed download: %d %v", cache.Since, err)
	}
	if now, _ := os.ReadFile(filepath.Join(syncdata.Dir(wow), syncdata.LuaName)); string(now) != string(lua) {
		t.Error("the sync file changed after a failed download")
	}
}

func TestDownloadOffAndWithoutToken(t *testing.T) {
	wow, files := fakeWoW(t, "A")
	ms, ts := newMarketServer(t, files[0])
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath, cfg.Sync = ts.URL, "cw_x", wow, false
	a := newTestApp(t, cfg)
	if res, err := a.Download(context.Background()); err != nil || res.Changed || len(ms.gets) != 0 {
		t.Errorf("sync off: %+v %v %v", res, err, ms.gets)
	}
	if _, err := os.Stat(syncdata.Dir(wow)); err == nil {
		t.Error("the sync add-on was written while sync is off")
	}
	cfg.Sync, cfg.Token = true, ""
	if err := SaveConfig(a.ConfigPath(), cfg); err != nil {
		t.Fatal(err)
	}
	if _, err := a.Download(context.Background()); err == nil || !strings.Contains(err.Error(), "no upload token") {
		t.Errorf("err = %v", err)
	}
}

func TestMachineNameDefaultsToHost(t *testing.T) {
	if (Config{Machine: " PC "}).MachineName() != "PC" {
		t.Error("setting not used")
	}
	if (Config{}).MachineName() == "" {
		t.Error("empty machine name")
	}
}
