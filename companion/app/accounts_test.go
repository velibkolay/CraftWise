package app

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestAccountLabel(t *testing.T) {
	for name, want := range map[string]string{"445303671#2": "#2", "plain": "plain"} {
		if got := (Account{Name: name}).Label(); got != want {
			t.Errorf("%s: %q, want %q", name, got, want)
		}
	}
}

func TestAccountsListsEveryAccountOrTheConfiguredOne(t *testing.T) {
	wow, _ := fakeWoW(t, "445#2", "445#1")
	all, err := Accounts(wow, "")
	if err != nil || len(all) != 2 || all[0].Name != "445#1" || all[1].Name != "445#2" || Labels(all) != "#1, #2" {
		t.Fatalf("all: %+v %v", all, err)
	}
	one, err := Accounts(wow, "445#2")
	if err != nil || len(one) != 1 || one[0].Name != "445#2" {
		t.Fatalf("fixed: %+v %v", one, err)
	}
	if _, err := Accounts(wow, "NOPE"); err == nil {
		t.Error("missing configured account accepted")
	}
}

// Two accounts upload on their own states: each file's delta is sent once, neither mixes the other's.
func TestRunOnceKeepsAccountStatesApart(t *testing.T) {
	wow, _ := fakeWoW(t, "A", "B")
	rec := &recorder{}
	ts := rec.server(t, 200)
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath = ts.URL, "cw_x", wow
	a := newTestApp(t, cfg)

	if _, err := a.RunOnce(context.Background(), RunOptions{Now: fixtureNow}); err != nil {
		t.Fatal(err)
	}
	if len(rec.paths) != 6 {
		t.Fatalf("both accounts should upload: %d requests", len(rec.paths))
	}
	for _, acct := range []string{"A", "B"} {
		if _, err := os.Stat(a.StatePathFor(acct)); err != nil {
			t.Errorf("no state for %s: %v", acct, err)
		}
	}
	if s := a.Status(); s.Account != "A, B" || !strings.Contains(s.Text, "sent") {
		t.Errorf("status %+v", s)
	}
	// B alone starts again when its state is gone; A stays quiet.
	if err := os.Remove(a.StatePathFor("B")); err != nil {
		t.Fatal(err)
	}
	if _, err := a.RunOnce(context.Background(), RunOptions{Now: fixtureNow}); err != nil {
		t.Fatal(err)
	}
	if len(rec.paths) != 9 {
		t.Errorf("only B should upload again: %d requests", len(rec.paths))
	}
	if s := a.Status(); s.Account != "B" {
		t.Errorf("status account %q, want B", s.Account)
	}
}

// The one state.json of the builds before #420 belongs to the account its file lies in: it moves to
// that account's state, so that account sends only a delta and the other account sends everything.
func TestLegacyStateMigratesToItsAccount(t *testing.T) {
	wow, _ := fakeWoW(t, "445#1", "445#2")
	rec := &recorder{}
	ts := rec.server(t, 200)
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath = ts.URL, "cw_x", wow

	// Make a real state for #1 and keep it as the old single state.json.
	first := newTestApp(t, cfg)
	cfg1 := cfg
	cfg1.Account = "445#1"
	if err := SaveConfig(first.ConfigPath(), cfg1); err != nil {
		t.Fatal(err)
	}
	if _, err := first.RunOnce(context.Background(), RunOptions{Now: fixtureNow}); err != nil {
		t.Fatal(err)
	}
	first.Close()
	legacy := first.LegacyStatePath()
	if err := os.Rename(first.StatePathFor("445#1"), legacy); err != nil {
		t.Fatal(err)
	}

	// A new start in the same folder migrates it.
	a, err := New(first.Dir, "test", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer a.Close()
	if exists(legacy) {
		t.Error("state.json still there")
	}
	if !exists(a.StatePathFor("445#1")) {
		t.Fatal("migrated state missing")
	}
	if a.Status().Success.IsZero() {
		t.Error("last success of the old state lost")
	}
	if err := SaveConfig(a.ConfigPath(), cfg); err != nil { // both accounts again
		t.Fatal(err)
	}
	runs, err := a.RunAccounts(context.Background(), RunOptions{Now: fixtureNow})
	if err != nil || len(runs) != 2 {
		t.Fatalf("%v %v", runs, err)
	}
	if runs[0].Result.Sent != 0 {
		t.Errorf("#1 sent %d again after the migration", runs[0].Result.Sent)
	}
	if runs[1].Result.Sent == 0 {
		t.Error("#2 sent nothing: it must not borrow #1's state")
	}
}

// A legacy state that can't be placed stays where it is.
func TestLegacyStateLeftAloneWhenItCannotBePlaced(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "state.json"), []byte(`{"site":"x"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	a, err := New(dir, "test", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer a.Close()
	if !exists(filepath.Join(dir, "state.json")) {
		t.Error("state.json removed")
	}
}

// loopApp prepares an app over the given account folders with fast polling.
func loopApp(t *testing.T, account string, accounts ...string) (a *App, wow string, files []string) {
	t.Helper()
	wow, files = fakeWoW(t, accounts...)
	rec := &recorder{}
	ts := rec.server(t, 200)
	cfg := DefaultConfig()
	cfg.Site, cfg.Token, cfg.WoWPath, cfg.Account = ts.URL, "cw_x", wow, account
	cfg.PollSeconds, cfg.SettleSeconds, cfg.Sync = 1, 1, false
	a = newTestApp(t, cfg)
	a.findEvery = 300 * time.Millisecond
	return
}

func startLoop(t *testing.T, a *App) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { a.Loop(ctx); close(done) }()
	t.Cleanup(func() { cancel(); <-done })
}

func waitFor(t *testing.T, what string, ok func() bool) {
	t.Helper()
	for i := 0; i < 150; i++ {
		if ok() {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

func logHas(a *App, s string) bool {
	data, _ := os.ReadFile(a.LogPath())
	return strings.Contains(string(data), s)
}

// touch gives the file a new modification time, as the game does when it writes it.
func touch(t *testing.T, file string) {
	t.Helper()
	later := time.Now().Add(time.Hour)
	if err := os.Chtimes(file, later, later); err != nil {
		t.Fatal(err)
	}
}

// A change in either account's file uploads that account, and only that one (#420).
func TestLoopUploadsTheAccountThatChanged(t *testing.T) {
	a, _, files := loopApp(t, "", "445#1", "445#2")
	startLoop(t, a)
	waitFor(t, "both accounts' first upload", func() bool { return exists(a.StatePathFor("445#1")) && exists(a.StatePathFor("445#2")) })
	waitFor(t, "the watching line", func() bool { return logHas(a, "watching 2 accounts: #1, #2") })

	// #2 changed (its state is gone, so its whole file counts as new): only #2 uploads.
	st1, _ := os.ReadFile(a.StatePathFor("445#1"))
	if err := os.Remove(a.StatePathFor("445#2")); err != nil {
		t.Fatal(err)
	}
	touch(t, files[1])
	waitFor(t, "#2 uploaded", func() bool { return exists(a.StatePathFor("445#2")) })
	if got, _ := os.ReadFile(a.StatePathFor("445#1")); string(got) != string(st1) {
		t.Error("#1's state changed though only #2's file did")
	}
	if s := a.Status(); s.Account != "#2" {
		t.Errorf("status account %q, want #2", s.Account)
	}

	// and the other way round
	if err := os.Remove(a.StatePathFor("445#1")); err != nil {
		t.Fatal(err)
	}
	touch(t, files[0])
	waitFor(t, "#1 uploaded", func() bool { return exists(a.StatePathFor("445#1")) })
	if s := a.Status(); s.Account != "#1" {
		t.Errorf("status account %q, want #1", s.Account)
	}
}

// A third account folder that shows up while the companion runs is found and uploaded.
func TestLoopFindsANewAccount(t *testing.T) {
	a, wow, _ := loopApp(t, "", "445#1", "445#2")
	startLoop(t, a)
	waitFor(t, "first uploads", func() bool { return exists(a.StatePathFor("445#2")) })

	data, err := os.ReadFile("../savedvars/testdata/CraftWise.lua")
	if err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(wow, "WTF", "Account", "445#3", "SavedVariables")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "CraftWise.lua"), data, 0o644); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "#3 uploaded", func() bool { return exists(a.StatePathFor("445#3")) })
	waitFor(t, "the new watching line", func() bool { return logHas(a, "watching 3 accounts: #1, #2, #3") })
}

// With account set only that account is watched and uploaded, whatever the other files do.
func TestLoopRespectsAFixedAccount(t *testing.T) {
	a, _, files := loopApp(t, "445#1", "445#1", "445#2")
	startLoop(t, a)
	waitFor(t, "#1's first upload", func() bool { return exists(a.StatePathFor("445#1")) })

	touch(t, files[1]) // the other account changes: nobody listens
	if err := os.Remove(a.StatePathFor("445#1")); err != nil {
		t.Fatal(err)
	}
	touch(t, files[0])
	waitFor(t, "#1 uploaded again", func() bool { return exists(a.StatePathFor("445#1")) })
	time.Sleep(1500 * time.Millisecond)
	if exists(a.StatePathFor("445#2")) {
		t.Error("the account that is not configured was uploaded")
	}
	if !logHas(a, "watching 1 accounts: #1") {
		t.Error("log lacks the watching line")
	}
}
