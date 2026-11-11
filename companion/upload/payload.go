// Package upload turns CraftWise's SavedVariables into upload requests for wow.velikopter.com
// (#94, server side #95): a delta since the last successful upload (state.go, delta.go), split
// into requests the server accepts (batch.go), sent with retries (client.go, send.go).
//
// This file is the wire format of web/docs/api.md (version 1), kept in one place so it can follow
// the contract without touching the rest. Two endpoints:
//
//	POST /api/upload          public market data: a subset of CraftWiseMarketDB as the savedvars
//	                          and market types marshal it (houses, scans, names, itemInfo, items)
//	POST /api/private/upload  private data: snapshots, auctions, fishing (documents per character)
//	                          and the ledger
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
	MaxScans          = 200
	MaxRawPoints      = 500 // per entry
	MaxDays           = 400 // per entry
	MaxTiers          = 8   // per raw point
	MaxLedgerEntries  = 5000
	MaxPrivateDocSize = 450_000
	MaxCharacters     = 50 // per private section
	// Times the server accepts: from MinTime to now + MaxFuture.
	MinTime   = 1_600_000_000
	MaxFuture = 86400
)

// PublicPayload is the body of POST /api/upload. Houses goes into every request.
type PublicPayload struct {
	V        int                                `json:"v"`
	Houses   map[string]House                   `json:"houses"`
	Scans    map[string][]Scan                  `json:"scans,omitempty"`    // per house key
	Names    map[int64]string                   `json:"names,omitempty"`    // CraftWiseMarketDB.names
	ItemInfo map[int64]market.ItemInfo          `json:"itemInfo,omitempty"` // decoded (#92)
	Items    map[string]map[string]market.Entry `json:"items,omitempty"`    // [item key][house key]
}

// House is one auction house; key "<realm>|H", "<realm>|A" or "<realm>|N:<Name>". A neutral
// house has no faction.
type House struct {
	Realm   string `json:"realm"`
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
