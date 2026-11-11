// Command craftwise-companion uploads CraftWise's SavedVariables to wow.velikopter.com (#94).
//
// It watches WTF/Account/<account>/SavedVariables/CraftWise.lua (written by the game on /reload
// and logout), and after each change uploads what is new since the last upload: public market
// data (prices, scans, item names and info) and, unless turned off, private data (character
// snapshots, auction and fishing summaries, ledger). It only reads the game's files.
//
// Without flags it runs in the Windows notification area; elsewhere (or with -no-tray) it runs in
// the foreground and logs to the terminal. See docs/companion.md.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"time"

	"github.com/velibkolay/CraftWise/companion/app"
	"github.com/velibkolay/CraftWise/companion/tray"
)

// version is set at build time: -ldflags "-X main.version=1.2.3".
var version = "dev"

func main() {
	os.Exit(run())
}

func run() int {
	var (
		once    = flag.Bool("once", false, "upload once and exit (exit code 1 on failure)")
		dryRun  = flag.Bool("dry-run", false, "with -once: build the requests and log them, send nothing")
		dump    = flag.String("dump", "", "with -dry-run: write the request bodies as JSON into this directory")
		full    = flag.Bool("full", false, "with -once: send everything again, ignoring what was uploaded before")
		noTray  = flag.Bool("no-tray", false, "run in the foreground without a tray icon")
		dir     = flag.String("dir", "", "settings, state and log directory (default: the user config directory)")
		open    = flag.String("open", "", "open site, me, config or log, then exit")
		status  = flag.Bool("status", false, "print where the files are and the last upload, then exit")
		showVer = flag.Bool("version", false, "print the version")
	)
	flag.Parse()
	if *showVer {
		fmt.Println("craftwise-companion", version)
		return 0
	}
	if *dump != "" {
		*dryRun = true
	}
	if *dryRun {
		*once = true
	}

	d := *dir
	if d == "" {
		var err error
		if d, err = app.DefaultDir(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 2
		}
	}
	interactive := *once || *noTray || !tray.Available() || *status || *open != ""
	var console *os.File
	if interactive {
		console = os.Stderr
	}
	a, err := app.New(d, version, writerOrNil(console))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}

	switch {
	case *open != "":
		if err := openThing(a, *open); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return 0
	case *status:
		printStatus(a)
		return 0
	}

	if !*dryRun {
		release, ok := tray.SingleInstance(`Local\CraftWiseCompanion`)
		if !ok {
			a.Log.Printf("another CraftWise Companion is already running")
			return 1
		}
		defer release()
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	if *once {
		res, err := a.RunOnce(ctx, app.RunOptions{DryRun: *dryRun, DumpDir: *dump, Full: *full})
		if err != nil {
			a.Log.Printf("%v", err)
			return 1
		}
		if !*dryRun {
			a.Log.Printf("%s", statusLine(a.Status()))
		}
		if !res.OK() {
			return 1
		}
		return 0
	}

	a.Log.Printf("CraftWise Companion %s started (settings: %s)", version, a.ConfigPath())
	if interactive {
		a.Loop(ctx)
		return 0
	}
	go a.Loop(ctx)
	err = tray.Run(tray.Spec{
		Tooltip: func() string { return "CraftWise Companion\n" + short(statusLine(a.Status()), 90) },
		Items:   func() []tray.Item { return menu(a, cancel) },
	})
	cancel()
	if err != nil {
		a.Log.Printf("tray: %v", err)
		return 1
	}
	return 0
}

func writerOrNil(f *os.File) io.Writer {
	if f == nil {
		return nil
	}
	return f
}

func menu(a *app.App, quit context.CancelFunc) []tray.Item {
	s := a.Status()
	items := []tray.Item{{Label: short(statusLine(s), 80)}}
	if !s.RetryAt.IsZero() && time.Until(s.RetryAt) > 0 {
		items = append(items, tray.Item{Label: "Next try " + s.RetryAt.Format("15:04")})
	}
	cfg, _ := a.Config()
	site := strings.TrimRight(cfg.Site, "/")
	if site == "" {
		site = app.DefaultSite
	}
	report := func(err error) {
		if err != nil {
			a.Log.Printf("%v", err)
		}
	}
	return append(items,
		tray.Item{Separator: true},
		tray.Item{Label: "Upload now", Action: a.Trigger},
		tray.Item{Label: "Open " + strings.TrimPrefix(site, "https://"), Action: func() { report(app.OpenURL(site)) }},
		tray.Item{Label: "Open my page", Action: func() { report(app.OpenURL(site + "/me")) }},
		tray.Item{Separator: true},
		tray.Item{Label: "Open settings", Action: func() { report(app.OpenFile(a.ConfigPath())) }},
		tray.Item{Label: "Open log", Action: func() { report(app.OpenFile(a.LogPath())) }},
		tray.Item{Separator: true},
		tray.Item{Label: "Quit", Quit: true, Action: func() { a.Log.Printf("quit"); quit() }},
	)
}

func statusLine(s app.Status) string {
	switch {
	case s.Attempt.IsZero() && s.Success.IsZero():
		return "No upload yet"
	case s.Attempt.IsZero():
		return "Last upload " + when(s.Success)
	case s.OK && s.Text == "nothing new" && !s.Success.IsZero():
		return "Checked " + when(s.Attempt) + ": nothing new (last upload " + when(s.Success) + ")"
	case s.OK:
		return "Checked " + when(s.Attempt) + ": " + s.Text
	}
	return "Upload " + when(s.Attempt) + " failed: " + s.Text
}

func when(t time.Time) string {
	if time.Since(t) < 20*time.Hour {
		return t.Format("15:04")
	}
	return t.Format("Jan 2 15:04")
}

func short(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}

func openThing(a *app.App, what string) error {
	cfg, err := a.Config()
	if err != nil && what != "config" && what != "log" {
		return err
	}
	switch what {
	case "site":
		return app.OpenURL(cfg.Site)
	case "me":
		return app.OpenURL(cfg.Site + "/me")
	case "config":
		return app.OpenFile(a.ConfigPath())
	case "log":
		return app.OpenFile(a.LogPath())
	}
	return errors.New("-open takes site, me, config or log")
}

func printStatus(a *app.App) {
	fmt.Println("settings:", a.ConfigPath())
	fmt.Println("state:   ", a.StatePath())
	fmt.Println("log:     ", a.LogPath())
	cfg, err := a.Config()
	if err != nil {
		fmt.Println("settings error:", err)
		return
	}
	if _, file, err := app.Locate(cfg); err != nil {
		fmt.Println("SavedVariables:", err)
	} else {
		fmt.Println("SavedVariables:", filepath.Clean(file))
	}
	fmt.Println(statusLine(a.Status()))
}
