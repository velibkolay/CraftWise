package upload

import (
	"encoding/json"
	"sort"

	"github.com/velibkolay/CraftWise/companion/savedvars"
)

// MaxAuctionsDoc is what one character's auctions document may weigh, as JSON. It is below
// MaxPrivateDocSize (the server's limit, 450,000) so that the growth between two uploads and the
// difference between bytes here and characters there never decide whether a document is accepted.
// The tracker keeps finished records 30 days (Auctions.lua, KEEP_DAYS), at about 350 bytes a record
// that is about 1,150 records; a busy seller passes that, and the document was then left out whole (#372).
const MaxAuctionsDoc = 400_000

// auctionDoc is the uploaded auctions document: the character's record as the addon keeps it, and
// `trimmed` when the oldest finished records were left out to stay under MaxAuctionsDoc. The addon's
// own data is never changed; only the copy on the site is shorter.
type auctionDoc struct {
	savedvars.AuctionChar
	Trimmed int `json:"trimmed,omitempty"`
}

// auctionTime is when a record last changed: the time it ended, else it was posted or seen.
func auctionTime(a savedvars.Auction) int64 {
	for _, p := range []*int64{a.SettledT, a.ReturnedT, a.CancelT, a.ExpT, a.GoneT, a.SoldT, a.T, a.Seen} {
		if p != nil && *p != 0 {
			return *p
		}
	}
	return 0
}

// trimAuctions returns the document for one character, cut to at most max bytes by leaving out the
// oldest records. Listed ("active") records go last: they are what the AH still holds. Records
// keep their order. The second result is how many records were left out.
func trimAuctions(c savedvars.AuctionChar, max int) (auctionDoc, int) {
	doc := auctionDoc{AuctionChar: c}
	whole, err := json.Marshal(doc)
	if err != nil || len(whole) <= max {
		return doc, 0
	}
	type rec struct {
		at     int64
		active bool
		n      int // bytes with its comma
		idx    int
	}
	recs := make([]rec, len(c.List))
	rest := len(whole) + len(`,"trimmed":000000`)
	for i, a := range c.List {
		b, _ := json.Marshal(a)
		recs[i] = rec{auctionTime(a), a.Status == "active", len(b) + 1, i}
		rest -= len(b) + 1
	}
	order := make([]int, len(recs))
	for i := range order {
		order[i] = i
	}
	// Keep first: listed records, then the newest.
	sort.SliceStable(order, func(x, y int) bool {
		a, b := recs[order[x]], recs[order[y]]
		if a.active != b.active {
			return a.active
		}
		return a.at > b.at
	})
	keep := make([]bool, len(recs))
	used, kept := rest, 0
	for _, i := range order {
		if used+recs[i].n > max {
			break
		}
		used += recs[i].n
		keep[i] = true
		kept++
	}
	list := make([]savedvars.Auction, 0, kept)
	for i, a := range c.List {
		if keep[i] {
			list = append(list, a)
		}
	}
	doc.List = list
	doc.Trimmed = len(c.List) - kept
	return doc, doc.Trimmed
}
