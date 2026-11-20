// Package syncdata downloads the site's merged market (#237, #239) and writes the one data file the
// addon loads, CraftWise_Sync (lua.go). The companion writes nothing else into the game folder.
package syncdata

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"

	"github.com/velibkolay/CraftWise/companion/market"
	"github.com/velibkolay/CraftWise/companion/upload"
)

// Cache is everything downloaded so far and the time to ask `since` next. The site answers with
// the entries that changed, each one complete (merged from both machines, #238), so merging a
// download replaces entries; the file for the addon is written from the whole cache.
type Cache struct {
	Site   string                `json:"site"`
	Since  int64                 `json:"since"` // server time of the last complete download; 0 = never
	Market *upload.PublicPayload `json:"market"`
	// The other machine's characters (#242), each whole as the site sent it, and the server time to
	// ask `since` next time for them (0 = never).
	Chars      map[string]Char `json:"chars,omitempty"`
	CharsSince int64           `json:"charsSince,omitempty"`
	// The merged watch list (#244): per item the newest change, tombstones included, and the server time to
	// ask `since` next time (0 = never).
	Watch      map[int64]WatchState `json:"watch,omitempty"`
	WatchSince int64                `json:"watchSince,omitempty"`
}

// NewCache is an empty cache for site.
func NewCache(site string) *Cache {
	return &Cache{Site: site, Market: &upload.PublicPayload{V: upload.Version}}
}

// LoadCache reads the cache file. A missing file, or one of another site, gives an empty cache
// (everything is downloaded again).
func LoadCache(path, site string) (*Cache, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return NewCache(site), nil
	}
	if err != nil {
		return nil, err
	}
	var c Cache
	if err := json.Unmarshal(data, &c); err != nil || c.Market == nil || c.Site != site {
		return NewCache(site), nil
	}
	return &c, nil
}

// Save writes the cache atomically.
func (c *Cache) Save(path string) error {
	data, err := json.Marshal(c)
	if err != nil {
		return err
	}
	return writeAtomic(path, data, 0o600)
}

// Merge puts a download into the cache: entries, names, item info and class names replace the
// cached ones with the same key; scans are added (same time and kind once); houses are replaced.
func (c *Cache) Merge(p *upload.PublicPayload) {
	m := c.Market
	for k, h := range p.Houses {
		if m.Houses == nil {
			m.Houses = map[string]upload.House{}
		}
		m.Houses[k] = h
	}
	for house, scans := range p.Scans {
		if m.Scans == nil {
			m.Scans = map[string][]upload.Scan{}
		}
		type id struct {
			t    int64
			kind string
		}
		seen := map[id]int{}
		list := m.Scans[house]
		for i, s := range list {
			seen[id{s.T, s.Kind}] = i
		}
		for _, s := range scans {
			if i, ok := seen[id{s.T, s.Kind}]; ok {
				list[i] = s
				continue
			}
			seen[id{s.T, s.Kind}] = len(list)
			list = append(list, s)
		}
		sort.SliceStable(list, func(i, j int) bool { return list[i].T < list[j].T })
		m.Scans[house] = list
	}
	for id, n := range p.Names {
		if m.Names == nil {
			m.Names = map[int64]string{}
		}
		m.Names[id] = n
	}
	for id, info := range p.ItemInfo {
		if m.ItemInfo == nil {
			m.ItemInfo = map[int64]market.ItemInfo{}
		}
		m.ItemInfo[id] = info
	}
	for c2, n := range p.ClassNames {
		if m.ClassNames == nil {
			m.ClassNames = map[int64]string{}
		}
		m.ClassNames[c2] = n
	}
	for c2, subs := range p.SubclassNames {
		if m.SubclassNames == nil {
			m.SubclassNames = map[int64]map[int64]string{}
		}
		if m.SubclassNames[c2] == nil {
			m.SubclassNames[c2] = map[int64]string{}
		}
		for s, n := range subs {
			m.SubclassNames[c2][s] = n
		}
	}
	for item, houses := range p.Items {
		if m.Items == nil {
			m.Items = map[string]map[string]market.Entry{}
		}
		if m.Items[item] == nil {
			m.Items[item] = map[string]market.Entry{}
		}
		for house, e := range houses {
			m.Items[item][house] = e
		}
	}
}

// writeAtomic writes data to a temporary file next to path and renames it over path, so a reader
// (the game loading its add-ons) never sees half a file.
func writeAtomic(path string, data []byte, perm os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return err
	}
	return nil
}
