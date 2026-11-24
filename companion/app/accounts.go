package app

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/velibkolay/CraftWise/companion/upload"
)

// The upload state is kept per account (#420): state-<account>.json in Dir, so two accounts never
// mix what was sent. Before that one state.json held the state of whichever file was uploaded.

// LegacyStatePath is the single state file of the builds before #420.
func (a *App) LegacyStatePath() string { return filepath.Join(a.Dir, "state.json") }

// StatePathFor is the upload state of one account.
func (a *App) StatePathFor(account string) string {
	clean := strings.Map(func(r rune) rune {
		switch r {
		case '/', '\\', ':', '*', '?', '"', '<', '>', '|':
			return '_'
		}
		return r
	}, account)
	return filepath.Join(a.Dir, "state-"+clean+".json")
}

// migrateState moves a legacy state.json to the account its file belongs to, so the next upload of
// that account is still only the delta. A legacy file without a readable SavedVariables path, or
// whose account already has a state file, is left alone (nothing is lost, nothing is overwritten).
func (a *App) migrateState() {
	legacy := a.LegacyStatePath()
	data, err := os.ReadFile(legacy)
	if err != nil {
		return
	}
	var raw struct {
		File string `json:"file"`
	}
	if json.Unmarshal(data, &raw) != nil || raw.File == "" {
		return
	}
	acct := AccountOf(raw.File)
	if acct == "" || acct == "." || acct == string(filepath.Separator) {
		return
	}
	dst := a.StatePathFor(acct)
	if _, err := os.Stat(dst); err == nil {
		return
	}
	if err := os.Rename(legacy, dst); err != nil {
		a.Log.Printf("moving state.json to %s: %v", filepath.Base(dst), err)
		return
	}
	a.Log.Printf("upload state moved to %s (one state per account)", filepath.Base(dst))
}

// lastSuccess is the newest accepted upload of any account's state.
func (a *App) lastSuccess() time.Time {
	files, _ := filepath.Glob(filepath.Join(a.Dir, "state-*.json"))
	var best int64
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		var raw struct {
			LastSuccess int64 `json:"lastSuccess"`
		}
		if json.Unmarshal(data, &raw) == nil && raw.LastSuccess > best {
			best = raw.LastSuccess
		}
	}
	if best == 0 {
		return time.Time{}
	}
	return time.Unix(best, 0)
}

// AccountRun is one account's upload.
type AccountRun struct {
	Account Account
	Result  upload.Result
	Err     error
}

// RunAccounts uploads every account (or opt.Account only): each file is read, its delta built
// against its own state and sent (#420). One account failing never stops the others.
func (a *App) RunAccounts(ctx context.Context, opt RunOptions) ([]AccountRun, error) {
	if opt.Now.IsZero() {
		opt.Now = time.Now()
	}
	a.work.Lock()
	defer a.work.Unlock()
	cfg, err := a.Config()
	if err == nil {
		err = CheckSite(cfg.Site)
	}
	if err == nil && !opt.DryRun && cfg.Token == "" {
		err = fmt.Errorf("no upload token: create one on %s/me and put it in %s", cfg.Site, a.ConfigPath())
	}
	var wow string
	var accts []Account
	if err == nil {
		wow, accts, err = LocateAccounts(cfg)
	}
	if err == nil && (Inside(a.Dir, wow) || (opt.DumpDir != "" && Inside(opt.DumpDir, wow))) {
		err = fmt.Errorf("refusing to write inside the World of Warcraft folder %s", wow)
	}
	if err != nil {
		if !opt.DryRun {
			a.setStatus(func(s *Status) { s.Attempt, s.OK, s.Text = opt.Now, false, err.Error() })
		}
		return nil, err
	}
	if opt.Account != "" {
		var only []Account
		for _, ac := range accts {
			if ac.Name == opt.Account {
				only = append(only, ac)
			}
		}
		accts = only
	}
	var runs []AccountRun
	for _, ac := range accts {
		o := opt
		if opt.DumpDir != "" && len(accts) > 1 {
			o.DumpDir = filepath.Join(opt.DumpDir, ac.Name)
		}
		res, err := a.runAccount(ctx, cfg, o, ac)
		runs = append(runs, AccountRun{ac, res, err})
	}
	if !opt.DryRun {
		a.setStatusFor(opt.Now, runs)
	}
	return runs, nil
}

// setStatusFor is the status line after a run: the first error, else what was sent and by which
// accounts, else "nothing new".
func (a *App) setStatusFor(now time.Time, runs []AccountRun) {
	var sentBy []Account
	counts := map[string]int{}
	var firstErr error
	var firstAcct Account
	var retry time.Time
	for _, r := range runs {
		err := r.Err
		if err == nil && !r.Result.OK() {
			err = r.Result.Errors[0]
		}
		if err != nil && firstErr == nil {
			firstErr, firstAcct = err, r.Account
		}
		if r.Result.RetryAt.After(retry) {
			retry = r.Result.RetryAt
		}
		if r.Result.Sent > 0 {
			sentBy = append(sentBy, r.Account)
			for k, v := range r.Result.Counts {
				counts[k] += v
			}
		}
	}
	a.setStatus(func(s *Status) {
		s.Attempt = now
		s.RetryAt = retry
		if len(runs) > 0 {
			last := runs[len(runs)-1].Account
			s.File, s.Account = last.File, last.Label()
		}
		switch {
		case firstErr != nil:
			s.OK, s.Text = false, firstErr.Error()
			if len(runs) > 1 {
				s.Text = firstAcct.Label() + ": " + s.Text
			}
			s.File, s.Account = firstAcct.File, firstAcct.Label()
		case len(sentBy) == 0:
			s.OK, s.Text = true, "nothing new"
		default:
			s.OK, s.Text = true, "sent "+countsText(counts)
			s.File, s.Account = sentBy[len(sentBy)-1].File, Labels(sentBy)
			s.Success = time.Now()
		}
	})
}

// RunOnce uploads every account once and folds the results into one: the total sent, every error,
// and the first failure as the error (an account's file that can't be read yet).
func (a *App) RunOnce(ctx context.Context, opt RunOptions) (upload.Result, error) {
	runs, err := a.RunAccounts(ctx, opt)
	total := upload.Result{Counts: map[string]int{}}
	if err != nil {
		return total, err
	}
	var firstErr error
	for _, r := range runs {
		if r.Err != nil && firstErr == nil {
			firstErr = r.Err
			if len(runs) > 1 {
				firstErr = fmt.Errorf("%s: %w", r.Account.Label(), r.Err)
			}
		}
		total.Sent += r.Result.Sent
		total.Failed += r.Result.Failed
		total.Errors = append(total.Errors, r.Result.Errors...)
		if r.Result.RetryAt.After(total.RetryAt) {
			total.RetryAt = r.Result.RetryAt
		}
		for k, v := range r.Result.Counts {
			total.Counts[k] += v
		}
	}
	return total, firstErr
}
