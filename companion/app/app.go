package app

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/velibkolay/CraftWise/companion/savedvars"
	"github.com/velibkolay/CraftWise/companion/svparse"
	"github.com/velibkolay/CraftWise/companion/upload"
	"github.com/velibkolay/CraftWise/companion/watch"
)

// App holds the paths and the status the tray shows.
type App struct {
	Dir     string // settings, state and log
	Version string
	Log     *log.Logger

	mu      sync.Mutex
	status  Status
	trigger chan struct{}
	// newClient is replaced in tests.
	newClient func(cfg Config) *upload.Client
}

// Status is the last upload attempt, for the tray and --status.
type Status struct {
	Attempt time.Time // last attempt
	Success time.Time // last accepted request
	OK      bool
	Text    string // one line: what was sent, or the error
	RetryAt time.Time
	File    string // the SavedVariables file
}

// ConfigPath, StatePath and LogPath are the files in Dir.
func (a *App) ConfigPath() string { return filepath.Join(a.Dir, "config.json") }
func (a *App) StatePath() string  { return filepath.Join(a.Dir, "state.json") }
func (a *App) LogPath() string    { return filepath.Join(a.Dir, "companion.log") }

// New opens the app in dir: creates it, opens the log (also written to extra, e.g. stderr).
func New(dir, version string, extra io.Writer) (*App, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	a := &App{Dir: dir, Version: version, trigger: make(chan struct{}, 1)}
	lw, err := openLog(a.LogPath())
	if err != nil {
		return nil, err
	}
	var w io.Writer = lw
	if extra != nil {
		w = io.MultiWriter(lw, extra)
	}
	a.Log = log.New(w, "", log.LstdFlags)
	a.newClient = func(cfg Config) *upload.Client {
		return upload.NewClient(cfg.Site, cfg.Token, "CraftWise-Companion/"+version)
	}
	if data, err := os.ReadFile(a.StatePath()); err == nil {
		var raw struct {
			LastSuccess int64 `json:"lastSuccess"`
		}
		if json.Unmarshal(data, &raw) == nil && raw.LastSuccess > 0 {
			a.status.Success = time.Unix(raw.LastSuccess, 0)
		}
	}
	return a, nil
}

// openLog appends to the log, starting a new one (the old kept as .1) above 1 MB.
func openLog(path string) (io.Writer, error) {
	if fi, err := os.Stat(path); err == nil && fi.Size() > 1<<20 {
		_ = os.Rename(path, path+".1")
	}
	return os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
}

// Status returns the last upload status.
func (a *App) Status() Status {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.status
}

func (a *App) setStatus(f func(*Status)) {
	a.mu.Lock()
	defer a.mu.Unlock()
	f(&a.status)
}

// Config loads the settings (creating the file on first use).
func (a *App) Config() (Config, error) {
	cfg, created, err := LoadConfig(a.ConfigPath())
	if created {
		a.Log.Printf("created the settings file %s: put the upload token from %s/me in it", a.ConfigPath(), cfg.Site)
	}
	return cfg, err
}

// RunOptions for one upload.
type RunOptions struct {
	DryRun  bool   // build the requests, send nothing, change no state
	DumpDir string // dry run: write the request bodies here
	Full    bool   // ignore what was uploaded before
	Now     time.Time
}

// ErrIncomplete is a file that couldn't be read completely (still being written).
var ErrIncomplete = errors.New("SavedVariables file still being written")

// ReadSavedVariables reads the file into memory (the game's file is opened read-only, briefly)
// and parses it. A file that changed while being read, or ends in the middle of a value, gives
// ErrIncomplete.
func ReadSavedVariables(path string) (*savedvars.File, error) {
	before := watch.SigOf(os.Stat(path))
	data, err := os.ReadFile(path)
	if err != nil {
		if before.Exists && !errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf("%w: %v", ErrIncomplete, err) // e.g. locked while the game writes it
		}
		return nil, err
	}
	after := watch.SigOf(os.Stat(path))
	if before != after || int64(len(data)) != after.Size {
		return nil, ErrIncomplete
	}
	parsed, err := svparse.Parse(bytes.NewReader(data))
	if err != nil {
		var syn *svparse.SyntaxError
		if errors.As(err, &syn) {
			return nil, fmt.Errorf("%w: %v", ErrIncomplete, err)
		}
		return nil, err
	}
	return savedvars.FromParsed(parsed), nil
}

// Locate finds the SavedVariables file from the settings.
func Locate(cfg Config) (wow, file string, err error) {
	wow, err = FindWoW(cfg)
	if err != nil {
		return "", "", err
	}
	file, _, err = SavedVariables(wow, cfg.Account)
	return wow, file, err
}

// RunOnce reads the file, builds the delta and sends it (or dumps it on a dry run).
func (a *App) RunOnce(ctx context.Context, opt RunOptions) (upload.Result, error) {
	if opt.Now.IsZero() {
		opt.Now = time.Now()
	}
	res, file, err := a.runOnce(ctx, opt)
	if opt.DryRun {
		return res, err
	}
	a.setStatus(func(s *Status) {
		s.Attempt = opt.Now
		s.File = file
		s.RetryAt = res.RetryAt
		switch {
		case err != nil:
			s.OK, s.Text = false, err.Error()
		case !res.OK():
			s.OK, s.Text = false, res.Errors[0].Error()
		case res.Sent == 0:
			s.OK, s.Text = true, "nothing new"
		default:
			s.OK, s.Text = true, "sent "+countsText(res.Counts)
		}
		if res.Sent > 0 {
			s.Success = time.Now()
		}
	})
	return res, err
}

func countsText(c map[string]int) string {
	b := upload.Batch[struct{}]{Counts: c}
	return b.Summary()
}

func (a *App) runOnce(ctx context.Context, opt RunOptions) (upload.Result, string, error) {
	var none upload.Result
	cfg, err := a.Config()
	if err != nil {
		return none, "", err
	}
	if err := CheckSite(cfg.Site); err != nil {
		return none, "", err
	}
	if !opt.DryRun && cfg.Token == "" {
		return none, "", fmt.Errorf("no upload token: create one on %s/me and put it in %s", cfg.Site, a.ConfigPath())
	}
	wow, file, err := Locate(cfg)
	if err != nil {
		return none, "", err
	}
	if Inside(a.Dir, wow) || (opt.DumpDir != "" && Inside(opt.DumpDir, wow)) {
		return none, file, fmt.Errorf("refusing to write inside the World of Warcraft folder %s", wow)
	}
	f, err := ReadSavedVariables(file)
	if err != nil {
		return none, file, err
	}
	if len(f.Problems) > 0 {
		a.Log.Printf("%s: %d values not read (first: %s)", file, len(f.Problems), f.Problems[0])
	}

	st := upload.NewState(cfg.Site, file)
	if !opt.Full {
		if st, err = upload.LoadState(a.StatePath(), cfg.Site, file); err != nil {
			a.Log.Printf("%v; sending everything again", err)
			st = upload.NewState(cfg.Site, file)
		}
	}
	bo := upload.Options{Now: opt.Now.Unix(), Private: cfg.Private}
	plan := upload.Build(f, st, bo)
	for _, line := range plan.SkippedText() {
		a.Log.Printf("left out (server would refuse it): %s", line)
	}

	if opt.DryRun {
		return none, file, a.dryRun(plan, opt.DumpDir)
	}
	if plan.Empty() {
		return none, file, nil
	}
	client := a.newClient(cfg)
	save := func(s *upload.State) error { return s.Save(a.StatePath()) }
	total := upload.Result{Counts: map[string]int{}}
	for try := 0; ; try++ {
		a.Log.Printf("uploading %s: %d public and %d private requests", file, len(plan.Public), len(plan.Private))
		res := upload.Send(ctx, client, plan, st, save, a.Log.Printf)
		for _, e := range res.Errors {
			a.Log.Printf("upload failed: %v", e)
		}
		total.Sent += res.Sent
		for k, v := range res.Counts {
			total.Counts[k] += v
		}
		// 413: the server wants smaller requests. Build the rest again in halves (the state
		// already holds what was accepted).
		if !upload.TooLarge(res) || try == 2 {
			total.Failed, total.Errors, total.RetryAt = res.Failed, res.Errors, res.RetryAt
			return total, file, nil
		}
		bo.MaxBytes = upload.DefaultMaxBytes >> (try + 1)
		bo.MaxRows = upload.DefaultMaxRows >> (try + 1)
		plan = upload.Build(f, st, bo)
	}
}

func (a *App) dryRun(plan *upload.Plan, dir string) error {
	write := func(name string, body any) error {
		if dir == "" {
			return nil
		}
		data, err := json.MarshalIndent(body, "", " ")
		if err != nil {
			return err
		}
		return os.WriteFile(filepath.Join(dir, name), data, 0o600)
	}
	if dir != "" {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return err
		}
	}
	for i, b := range plan.Public {
		a.Log.Printf("dry run: public request %d: %s, ~%d bytes, ~%d rows", i+1, b.Summary(), b.Bytes, b.Rows)
		if err := write(fmt.Sprintf("public-%03d.json", i+1), b.Body); err != nil {
			return err
		}
	}
	for i, b := range plan.Private {
		a.Log.Printf("dry run: private request %d: %s, ~%d bytes", i+1, b.Summary(), b.Bytes)
		if err := write(fmt.Sprintf("private-%03d.json", i+1), b.Body); err != nil {
			return err
		}
	}
	if plan.Empty() {
		a.Log.Printf("dry run: nothing new to send")
	}
	return nil
}

// Trigger asks the loop for an upload now ("Upload now").
func (a *App) Trigger() {
	select {
	case a.trigger <- struct{}{}:
	default:
	}
}

// Loop uploads at start, when the file changed and settled, on Trigger, and when a refused upload
// said to come back later, until ctx ends.
func (a *App) Loop(ctx context.Context) {
	var w *watch.Watcher
	var wctx context.Context
	var stop context.CancelFunc = func() {}
	defer func() { stop() }()
	var retry *time.Timer
	retryC := func() <-chan time.Time {
		if retry == nil {
			return nil
		}
		return retry.C
	}

	// ensureWatcher (re)starts the watcher when the file to watch changed (settings edited).
	ensureWatcher := func(cfg Config) {
		_, file, err := Locate(cfg)
		if err != nil || (w != nil && w.Path == file) {
			return
		}
		stop()
		wctx, stop = context.WithCancel(ctx)
		w = watch.New(file, time.Duration(cfg.PollSeconds)*time.Second, time.Duration(cfg.SettleSeconds)*time.Second)
		go w.Run(wctx)
		a.Log.Printf("watching %s", file)
	}
	watchC := func() <-chan struct{} {
		if w == nil {
			return nil
		}
		return w.C
	}

	incomplete := 0 // reads in a row that found the file still being written
	run := func(why string) {
		cfg, err := a.Config()
		if err == nil {
			ensureWatcher(cfg)
		}
		a.Log.Printf("upload (%s)", why)
		res, err := a.RunOnce(ctx, RunOptions{})
		if errors.Is(err, ErrIncomplete) && w != nil && incomplete < 10 {
			incomplete++
			a.Log.Printf("%v; reading again shortly", err)
			w.Retry()
			return
		}
		incomplete = 0
		if err != nil {
			a.Log.Printf("upload: %v", err)
		}
		if retry != nil {
			retry.Stop()
			retry = nil
		}
		if !res.RetryAt.IsZero() {
			retry = time.NewTimer(time.Until(res.RetryAt))
		}
	}

	run("start")
	// Settings may be fixed later (token, path): look for the file every minute until found.
	find := time.NewTicker(time.Minute)
	defer find.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-a.trigger:
			run("upload now")
		case <-watchC():
			run("file changed")
		case <-retryC():
			retry = nil
			run("retry")
		case <-find.C:
			if w == nil {
				if cfg, err := a.Config(); err == nil {
					ensureWatcher(cfg)
					if w != nil {
						run("file found")
					}
				}
			}
		}
	}
}
