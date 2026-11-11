package upload

import (
	"encoding/json"
	"errors"
	"fmt"
	"hash/fnv"
	"os"
	"path/filepath"
)

// State is what was uploaded successfully, so the next upload sends only what is new. It is kept
// per site and SavedVariables file: when either changes, everything is sent again. The server
// treats every upload as idempotent, so sending something twice is harmless, only wasteful.
type State struct {
	Site string `json:"site"`
	File string `json:"file"`

	// Scans: newest scan time sent per house.
	Scans map[string]int64 `json:"scans,omitempty"`
	// Items: hash of the item info and name sent per item ID.
	Items map[int64]uint64 `json:"items,omitempty"`
	// Prices per "<house>\x1f<itemKey>".
	Prices map[string]*PriceMark `json:"prices,omitempty"`
	// Docs: hash of the private document sent, per "<kind>\x1f<character>".
	Docs map[string]uint64 `json:"docs,omitempty"`
	// Ledger: newest entry time sent and how many entries had that time.
	LedgerT     int64 `json:"ledgerT,omitempty"`
	LedgerAtT   int   `json:"ledgerAtT,omitempty"`
	LastSuccess int64 `json:"lastSuccess,omitempty"`
}

// PriceMark is what was sent of one item at one house.
type PriceMark struct {
	LastT int64  `json:"l,omitempty"` // last.t
	Off   *int64 `json:"o,omitempty"` // last.off
	RawT  int64  `json:"r,omitempty"` // newest raw point
	// Days before DaysFrom can't change any more (their raw points are gone) and were sent; days
	// from DaysFrom on are sent again when their hash differs.
	DaysFrom int64            `json:"d,omitempty"`
	Days     map[int64]uint64 `json:"h,omitempty"`
}

// NewState is an empty state for a site and file.
func NewState(site, file string) *State {
	return &State{Site: site, File: file}
}

func (s *State) init() {
	if s.Scans == nil {
		s.Scans = map[string]int64{}
	}
	if s.Items == nil {
		s.Items = map[int64]uint64{}
	}
	if s.Prices == nil {
		s.Prices = map[string]*PriceMark{}
	}
	if s.Docs == nil {
		s.Docs = map[string]uint64{}
	}
}

// LoadState reads the state file. A missing file, or one for another site or SavedVariables file,
// gives an empty state (everything is sent again).
func LoadState(path, site, file string) (*State, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return NewState(site, file), nil
	}
	if err != nil {
		return nil, err
	}
	var s State
	if err := json.Unmarshal(data, &s); err != nil {
		return nil, fmt.Errorf("state file %s: %w", path, err)
	}
	if s.Site != site || s.File != file {
		return NewState(site, file), nil
	}
	return &s, nil
}

// Save writes the state atomically (temporary file, then rename).
func (s *State) Save(path string) error {
	data, err := json.Marshal(s)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func priceKey(house, item string) string { return house + "\x1f" + item }
func docKey(kind, char string) string    { return kind + "\x1f" + char }

// hashJSON is an FNV-1a hash of v's JSON encoding (map keys are sorted by encoding/json).
func hashJSON(v any) uint64 {
	h := fnv.New64a()
	_ = json.NewEncoder(h).Encode(v)
	return h.Sum64()
}
