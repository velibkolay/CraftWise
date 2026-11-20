package app

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/velibkolay/CraftWise/companion/syncdata"
	"github.com/velibkolay/CraftWise/companion/upload"
)

// CachePath is the downloaded market, kept so the sync file always holds all of it (#239).
func (a *App) CachePath() string { return filepath.Join(a.Dir, "market-cache.json") }

// DownloadResult is what one download did.
type DownloadResult struct {
	Changed bool      // the sync file was written
	RetryAt time.Time // a refusal that says when to come back
}

// Download fetches the entries that changed on the site since the last download, merges them into
// the cache, marks them in the upload state (so the next upload doesn't send them back, no echo)
// and writes CraftWise_Sync for the addon (#239). It does nothing when "sync" is off. The order
// matters: the marks and the cache are saved before the file is written, so the addon never merges
// data the upload state doesn't know as downloaded.
func (a *App) Download(ctx context.Context) (DownloadResult, error) {
	var res DownloadResult
	cfg, err := a.Config()
	if err != nil {
		return res, err
	}
	if !cfg.Sync {
		return res, nil
	}
	if err := CheckSite(cfg.Site); err != nil {
		return res, err
	}
	if cfg.Token == "" {
		return res, fmt.Errorf("no upload token: create one on %s/me and put it in %s", cfg.Site, a.ConfigPath())
	}
	wow, file, err := Locate(cfg)
	if err != nil {
		return res, fmt.Errorf("%w (the game writes CraftWise's file at the first /reload or logout)", err)
	}
	if Inside(a.Dir, wow) {
		return res, fmt.Errorf("refusing to keep settings inside the World of Warcraft folder %s", wow)
	}
	a.work.Lock()
	defer a.work.Unlock()

	cache, err := syncdata.LoadCache(a.CachePath(), cfg.Site)
	if err != nil {
		a.Log.Printf("%v; downloading everything again", err)
		cache = syncdata.NewCache(cfg.Site)
	}
	client := a.newClient(cfg)
	a.Log.Printf("downloading the market since %d", cache.Since)
	dl, until, err := syncdata.Download(ctx, client, cache.Since, nil)
	if err != nil {
		var later *upload.RetryLater
		if errors.As(err, &later) {
			res.RetryAt = later.At
		}
		a.setStatus(func(s *Status) { s.Download = "download failed: " + err.Error() })
		return res, err
	}

	st, err := upload.LoadState(a.StatePath(), cfg.Site, file)
	if err != nil {
		a.Log.Printf("%v; the state starts empty", err)
		st = upload.NewState(cfg.Site, file)
	}
	now := time.Now()
	if a.clock != nil {
		now = a.clock()
	}
	st.MarkDownloaded(dl, now.Unix())
	if err := st.Save(a.StatePath()); err != nil {
		return res, err
	}
	cache.Merge(dl)
	cache.Since = until

	// The other machine's characters (#242): they need the private scope, so a token without it, or a
	// site that doesn't have the endpoint yet, leaves them out and never stops the market download.
	own := ownChars(st)
	charsText := ""
	if cfg.Private {
		got, charsUntil, cerr := syncdata.DownloadChars(ctx, client, cache.CharsSince, cfg.MachineName(), a.clock)
		switch {
		case cerr != nil:
			a.Log.Printf("downloading the characters failed: %v", cerr)
			charsText = ", characters failed: " + cerr.Error()
		default:
			cache.MergeChars(got, own)
			cache.CharsSince = charsUntil
			if len(got) > 0 {
				charsText = fmt.Sprintf(", %d characters", len(got))
			}
		}
	}
	// The watch list (#244): the site's changes are merged into the cache's list and marked as sent, so the
	// upload doesn't send them back.
	if cfg.Private {
		changes, watchUntil, werr := syncdata.DownloadWatch(ctx, client, cache.WatchSince, a.clock)
		switch {
		case werr != nil:
			a.Log.Printf("downloading the watch list failed: %v", werr)
			charsText += ", watch list failed: " + werr.Error()
		default:
			st.MarkWatchDownloaded(changes)
			if err := st.Save(a.StatePath()); err != nil {
				return res, err
			}
			cache.MergeWatch(changes)
			cache.WatchSince = watchUntil
			if len(changes) > 0 {
				charsText += fmt.Sprintf(", %d watch changes", len(changes))
			}
		}
	}
	if err := cache.Save(a.CachePath()); err != nil {
		return res, err
	}
	out := syncdata.File{Written: now.Unix(), Machine: cfg.MachineName(), Market: cache.Market}
	if cfg.Private {
		out.Chars = cache.OtherChars(own, cfg.MachineName())
		if cache.WatchSince > 0 {
			out.Watch = cache.Watch
			if out.Watch == nil {
				out.Watch = map[int64]syncdata.WatchState{}
			}
		}
	}
	changed, err := syncdata.Write(wow, out)
	if err != nil {
		return res, err
	}
	res.Changed = changed
	text := "market up to date"
	if !syncdata.Empty(dl) {
		text = fmt.Sprintf("downloaded %d items", len(dl.Items))
	}
	text += charsText
	if changed {
		text += ", wrote " + syncdata.LuaName
	}
	a.Log.Print(text)
	a.setStatus(func(s *Status) { s.Download = text })
	return res, nil
}

// ownChars are the character keys this machine uploads itself (the private documents in the upload
// state): their data comes from the game's own file, so the site's copy is never taken (#242).
func ownChars(st *upload.State) map[string]bool {
	own := map[string]bool{}
	for k := range st.Docs {
		if _, char, ok := strings.Cut(k, ""); ok {
			own[char] = true
		}
	}
	return own
}
