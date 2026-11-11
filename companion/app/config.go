// Package app is the companion app (#94): settings, finding the SavedVariables file, the upload
// run and the loop that watches the file. The tray (package tray) and the command line
// (cmd/craftwise-companion) are thin layers over it.
//
// The app only reads the game's files. Everything it writes (settings, upload state, log, dumps)
// lives in the user's config directory or a directory given on the command line, never in the
// World of Warcraft folder.
package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
)

// DefaultSite is the price site.
const DefaultSite = "https://wow.velikopter.com"

// Config is the settings file (JSON, editable by hand; "Open config" in the tray).
type Config struct {
	// Site the uploads go to.
	Site string `json:"site"`
	// Token: the upload token created on the private page (/me). Kept only in this file.
	Token string `json:"token"`
	// WoWPath: the _forever_ folder; empty = find it in the default install places.
	WoWPath string `json:"wowPath"`
	// Account: the folder name under WTF/Account; empty = the account whose CraftWise.lua was
	// written last.
	Account string `json:"account"`
	// Private: also upload the private data (snapshots, auctions, fishing, ledger).
	Private bool `json:"private"`
	// PollSeconds: how often the file is checked; SettleSeconds: how long it must stay unchanged
	// before it is read.
	PollSeconds   int `json:"pollSeconds"`
	SettleSeconds int `json:"settleSeconds"`
}

// DefaultConfig is what a new settings file holds.
func DefaultConfig() Config {
	return Config{Site: DefaultSite, Private: true, PollSeconds: 5, SettleSeconds: 3}
}

// DefaultDir is where the settings, state and log live: <user config dir>/CraftWise Companion
// (Windows %AppData%, macOS ~/Library/Application Support).
func DefaultDir() (string, error) {
	base, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(base, "CraftWise Companion"), nil
}

// LoadConfig reads the settings file; a missing one is created with the defaults (created = true).
func LoadConfig(path string) (cfg Config, created bool, err error) {
	cfg = DefaultConfig()
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		if err := SaveConfig(path, cfg); err != nil {
			return cfg, false, err
		}
		return cfg, true, nil
	}
	if err != nil {
		return cfg, false, err
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return cfg, false, fmt.Errorf("settings file %s: %w", path, err)
	}
	if cfg.PollSeconds <= 0 {
		cfg.PollSeconds = DefaultConfig().PollSeconds
	}
	if cfg.SettleSeconds <= 0 {
		cfg.SettleSeconds = DefaultConfig().SettleSeconds
	}
	cfg.Site = strings.TrimRight(strings.TrimSpace(cfg.Site), "/")
	cfg.Token = strings.TrimSpace(cfg.Token)
	return cfg, false, nil
}

// SaveConfig writes the settings file (readable by the user only: it holds the token).
func SaveConfig(path string, cfg Config) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0o600)
}

// CheckSite validates the site URL: https, or http for a local test server.
func CheckSite(site string) error {
	u, err := url.Parse(site)
	if err != nil || u.Host == "" {
		return fmt.Errorf("site %q is not a URL", site)
	}
	local := u.Hostname() == "localhost" || u.Hostname() == "127.0.0.1" || u.Hostname() == "::1"
	if u.Scheme != "https" && !(u.Scheme == "http" && local) {
		return fmt.Errorf("site %q must use https", site)
	}
	return nil
}

// DefaultWoWPaths are the places a _forever_ folder is looked for, per OS.
func DefaultWoWPaths(goos, home string) []string {
	switch goos {
	case "windows":
		var out []string
		for _, drive := range []string{"C", "D", "E", "F", "G"} {
			root := drive + `:\`
			out = append(out,
				root+`Program Files (x86)\World of Warcraft\_forever_`,
				root+`Program Files\World of Warcraft\_forever_`,
				root+`World of Warcraft\_forever_`,
				root+`Games\World of Warcraft\_forever_`,
			)
		}
		return out
	case "darwin":
		out := []string{"/Applications/World of Warcraft/_forever_"}
		if home != "" {
			out = append(out, filepath.Join(home, "Applications", "World of Warcraft", "_forever_"))
		}
		return out
	}
	return nil
}

func isDir(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.IsDir()
}

// FindWoW returns the configured _forever_ folder, or the first default one that has
// WTF/Account.
func FindWoW(cfg Config) (string, error) {
	if cfg.WoWPath != "" {
		if !isDir(filepath.Join(cfg.WoWPath, "WTF", "Account")) {
			return "", fmt.Errorf("no WTF%cAccount folder in %s (settings: wowPath)", filepath.Separator, cfg.WoWPath)
		}
		return cfg.WoWPath, nil
	}
	home, _ := os.UserHomeDir()
	for _, p := range DefaultWoWPaths(runtime.GOOS, home) {
		if isDir(filepath.Join(p, "WTF", "Account")) {
			return p, nil
		}
	}
	return "", errors.New("World of Warcraft _forever_ folder not found; set wowPath in the settings")
}

// SavedVariables returns CraftWise.lua of the configured account, or of the account whose file
// was written last, and the account folder name.
func SavedVariables(wow, account string) (path, acct string, err error) {
	if account != "" {
		p := filepath.Join(wow, "WTF", "Account", account, "SavedVariables", "CraftWise.lua")
		if _, err := os.Stat(p); err != nil {
			return "", "", fmt.Errorf("no CraftWise.lua for account %s: %w", account, err)
		}
		return p, account, nil
	}
	matches, _ := filepath.Glob(filepath.Join(wow, "WTF", "Account", "*", "SavedVariables", "CraftWise.lua"))
	type cand struct {
		path, acct string
		mod        int64
	}
	var list []cand
	for _, m := range matches {
		fi, err := os.Stat(m)
		if err != nil {
			continue
		}
		list = append(list, cand{m, filepath.Base(filepath.Dir(filepath.Dir(m))), fi.ModTime().UnixNano()})
	}
	if len(list) == 0 {
		return "", "", fmt.Errorf("no CraftWise.lua under %s (log in with CraftWise enabled, then /reload)", filepath.Join(wow, "WTF", "Account"))
	}
	sort.Slice(list, func(i, j int) bool { return list[i].mod > list[j].mod })
	return list[0].path, list[0].acct, nil
}

// Inside reports whether p is dir or inside it.
func Inside(p, dir string) bool {
	if dir == "" {
		return false
	}
	ap, err1 := filepath.Abs(p)
	ad, err2 := filepath.Abs(dir)
	if err1 != nil || err2 != nil {
		return false
	}
	rel, err := filepath.Rel(ad, ap)
	if err != nil {
		return false
	}
	if runtime.GOOS == "windows" || runtime.GOOS == "darwin" {
		rel2, err := filepath.Rel(strings.ToLower(ad), strings.ToLower(ap))
		if err == nil {
			rel = rel2
		}
	}
	return rel == "." || (rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)))
}
