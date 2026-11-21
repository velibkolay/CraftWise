// Package upload turns CraftWise's SavedVariables into upload requests for wow.velikopter.com
// (#94, server side #95): a delta since the last successful upload (state.go, delta.go), split
// into requests the server accepts (batch.go), sent with retries (client.go, send.go).
//
// This file is the wire format of web/docs/api.md (version 1), kept in one place so it can follow
// the contract without touching the rest. Two endpoints:
//
//	POST /api/upload          public market data: a subset of CraftWiseMarketDB as the savedvars
//	                          and market types marshal it (houses, scans, names, itemInfo, items,
//	                          classNames, subclassNames)
//	POST /api/private/upload  private data: snapshots, auctions, fishing (documents per character),
//	                          the ledger, the craft log (#266) and the item watch list
//
// A value the addon doesn't have is left out (omitempty / nil), never filled in. The Auctionator
// fallback prices (#90) are never sent.
package upload

import "github.com/velibkolay/CraftWise/companion/market"

// Version is the payload version the server checks (`v`).
const Version = 1

// Server limits per request (web/src/limits.ts). Batches stay below them.
const (
	MaxBodyBytes      = 500_000
	MaxPriceEntries   = 2000 // item/house entries
	MaxItems          = 5000 // item IDs in names + itemInfo
	MaxHouses         = 20
	MaxConnected      = 20 // other realms per realm in `connected` (#366)
	MaxScans          = 200
	MaxRawPoints      = 500  // per entry
	MaxDays           = 400  // per entry
	MaxTiers          = 8    // per raw point
	MaxClassNames     = 1000 // class and subclass names together
	MaxClassNameLen   = 64
	MaxClassID        = 65535 // class and subclass IDs 0..MaxClassID
	MaxLedgerEntries  = 5000
	MaxCraftedRows    = 5000 // craft log days per private upload (#266)
	MaxPrivateDocSize = 450_000
	MaxCharacters     = 50 // per private section
	// Times the server accepts: from MinTime to now + MaxFuture.
	MinTime   = 1_600_000_000
	MaxFuture = 86400
)

// MaxWatch is the most watched items in one private upload (#165, web/src/limits.ts).
const MaxWatch = 1000

// PublicPayload is the body of POST /api/upload. Houses goes into every request.
type PublicPayload struct {
	V      int              `json:"v"`
	Houses map[string]House `json:"houses"`
	// Connected is the realm pairs the addon recorded (#366): [realm][otherRealm] = first seen. Both
	// directions, validated like the houses. The site groups connected realms by it.
	Connected map[string]map[string]int64        `json:"connected,omitempty"`
	Scans     map[string][]Scan                  `json:"scans,omitempty"`    // per house key
	Names     map[int64]string                   `json:"names,omitempty"`    // CraftWiseMarketDB.names
	ItemInfo  map[int64]market.ItemInfo          `json:"itemInfo,omitempty"` // decoded (#92), sell price p (#120)
	Items     map[string]map[string]market.Entry `json:"items,omitempty"`    // [item key][house key]
	// The client's class and subclass names (#120): [classID] and [classID][subclassID].
	ClassNames    map[int64]string           `json:"classNames,omitempty"`
	SubclassNames map[int64]map[int64]string `json:"subclassNames,omitempty"`
}

// House is one auction house; key "H", "A" or "N:<Name>" (no realm, #382). A neutral
// house has no faction.
type House struct {
	Realm   string `json:"realm,omitempty"`
	Kind    string `json:"kind"`
	Faction string `json:"faction,omitempty"`
	Label   string `json:"label"`
}

// Scan is one recording at a house (CraftWiseMarketDB.scans[house][i]).
type Scan struct {
	T        int64  `json:"t"`
	Kind     string `json:"kind"`
	Items    *int64 `json:"items,omitempty"`
	LastOnly *int64 `json:"lastOnly,omitempty"`
	Source   string `json:"source,omitempty"`
}

// PrivatePayload is the body of POST /api/private/upload. Documents are keyed by character
// ("<realm>-<name> <surname>"); the server keeps the newest per character.
type PrivatePayload struct {
	V         int            `json:"v"`
	Snapshots map[string]Doc `json:"snapshots,omitempty"`
	Auctions  map[string]Doc `json:"auctions,omitempty"`
	Fishing   map[string]Doc `json:"fishing,omitempty"`
	Ledger    []LedgerEntry  `json:"ledger,omitempty"`
	// Crafted is the craft log (#266): one row per character, recipe and day that changed.
	Crafted []CraftedRow `json:"crafted,omitempty"`
	// Watch are the changes of the item watch list (#165, #244): the site merges them per item with its
	// own list (newest wins), it never replaces the list.
	Watch []WatchItem `json:"watch,omitempty"`
}

// WatchItem is one change of the watch list: the item ID, the Unix time it was watched or unwatched,
// and D = it was unwatched at T (a tombstone, CraftWiseDB.watchGone). The download of the site's
// changes (GET /api/sync/watch) has the same shape.
type WatchItem struct {
	I int64 `json:"i"`
	T int64 `json:"t"`
	D bool  `json:"d,omitempty"`
}

// sentValue is the item's state as State.WatchSent keeps it: the time, negative for unwatched.
func (w WatchItem) sentValue() int64 {
	if w.D {
		return -w.T
	}
	return w.T
}

// WatchWins reports whether a change (t, gone) replaces the state (cur, curGone) of the same item: the
// newer time wins, and on the same time "watched" wins over "unwatched" (an item is never lost to a
// tie). The site and the addon apply the same rule.
func WatchWins(t int64, gone bool, cur int64, curGone bool) bool {
	return t > cur || (t == cur && curGone && !gone)
}

// CraftedRow is one day of the craft log: c = character, r = recipe spell ID, d = local day as
// YYYYMMDD, n = crafts, i = items made, p = estimated profit in copper at craft time (may be
// negative), k = crafts that had a profit, a = seconds of active crafting. i, p, k and a are left
// out when the addon didn't record them.
type CraftedRow struct {
	C string   `json:"c"`
	R int64    `json:"r"`
	D int64    `json:"d"`
	N int64    `json:"n"`
	I *int64   `json:"i,omitempty"`
	P *int64   `json:"p,omitempty"`
	K *int64   `json:"k,omitempty"`
	A *float64 `json:"a,omitempty"`
}

// Doc is one private document: its time and the data (a JSON object).
type Doc struct {
	T    int64 `json:"t"`
	Data any   `json:"data"`
}

// LedgerEntry is CraftWiseMarketDB.ledger.entries[i] as the addon stores it (#46).
type LedgerEntry struct {
	T int64  `json:"t"`
	C string `json:"c"`
	K string `json:"k"`
	I *int64 `json:"i,omitempty"`
	Q *int64 `json:"q,omitempty"`
	M *int64 `json:"m,omitempty"`
	W string `json:"w,omitempty"`
	N string `json:"n,omitempty"`
	L string `json:"l,omitempty"`
}

// Response is what both endpoints answer on success; on failure ErrorBody.
type Response struct {
	OK          bool           `json:"ok"`
	Received    map[string]int `json:"received,omitempty"`
	RowsWritten *int64         `json:"rowsWritten,omitempty"`
}

// ErrorBody is the server's error answer.
type ErrorBody struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}
