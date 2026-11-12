// Package savedvars reads CraftWise's SavedVariables file (WTF/Account/<account>/SavedVariables/
// CraftWise.lua) into typed Go values: the market data (CraftWiseMarketDB: houses, prices per item
// and house, scans, names, item info, Auctionator fallback prices, ledger, auctions) and the
// character snapshots (CraftWiseDB.snapshots).
//
// Reading never guesses: a value that is missing or doesn't have the documented type is left
// missing (nil) and listed in File.Problems with its path; the rest of the file is still read.
// The formats are documented in docs/snapshot.md and in the Lua modules that write them.
package savedvars

import (
	"fmt"
	"io"
	"sort"

	"github.com/velibkolay/CraftWise/companion/market"
	"github.com/velibkolay/CraftWise/companion/svparse"
)

// File is what CraftWise keeps account-wide. DB or Market is nil when the file doesn't assign it.
type File struct {
	DB       *DB               `json:"db,omitempty"`
	Market   *MarketDB         `json:"market,omitempty"`
	Problems []svparse.Problem `json:"problems,omitempty"`
}

// DB is the part of CraftWiseDB the companion reads.
type DB struct {
	Snapshots map[string]*Snapshot `json:"snapshots,omitempty"`
}

// MarketDB is CraftWiseMarketDB (#26, #46, #81, #90, #92, #120).
type MarketDB struct {
	V      *int64           `json:"v,omitempty"`
	Houses map[string]House `json:"houses,omitempty"`
	// Scans per house key: the last 30 recordings, oldest first.
	Scans map[string][]Scan `json:"scans,omitempty"`
	// Items[itemKey][houseKey] = price entry (decoded from the packed string, or the table form an
	// entry still in use at logout is saved in).
	Items    map[market.ItemKey]map[string]market.Entry `json:"items,omitempty" lua:"-"`
	Names    map[int64]string                           `json:"names,omitempty"`
	ItemInfo map[int64]market.ItemInfo                  `json:"itemInfo,omitempty" lua:"-"`
	// ItemInfoV is the itemInfo format (#120: 2 = "q,i,c,s,t,p"; missing in older files, format 1
	// "q,i,c,s,t"). Each string is read by its field count, so a file can hold both.
	ItemInfoV *int64 `json:"itemInfoV,omitempty"`
	// The client's names of item classes and subclasses (#120): ClassNames[classID],
	// SubclassNames[classID][subclassID]. Missing in files written before #120.
	ClassNames    map[int64]string           `json:"classNames,omitempty"`
	SubclassNames map[int64]map[int64]string `json:"subclassNames,omitempty"`
	Auctionator   *Auctionator               `json:"auctionator,omitempty" lua:"-"`
	Scope         *Scope                     `json:"scope,omitempty"`
	CutSamples    []CutSample                `json:"cutSamples,omitempty"`
	PrunedAt      *int64                     `json:"prunedAt,omitempty"`
	Ledger        *Ledger                    `json:"ledger,omitempty"`
	Auctions      *Auctions                  `json:"auctions,omitempty"`
}

// House is one auction house seen (#26): key "<realm>|H", "<realm>|A" or "<realm>|N:BootyBay".
type House struct {
	Realm   string    `json:"realm,omitempty"`
	Kind    string    `json:"kind,omitempty"` // "faction" or "neutral"
	Faction string    `json:"faction,omitempty"`
	Label   string    `json:"label,omitempty"`
	Cut     *HouseCut `json:"cut,omitempty"`
}

// HouseCut is the cut measured at a house from own sales; Rate is nil until measured.
type HouseCut struct {
	Samples *int64   `json:"samples,omitempty"`
	Rate    *float64 `json:"rate,omitempty"`
}

// Scan is one recording at a house: kind "full", "search" or "gear"; Items = scope items stored
// with history, LastOnly = items outside the scope stored with `last` only (#90).
type Scan struct {
	T        *int64 `json:"t,omitempty"`
	Kind     string `json:"kind,omitempty"`
	Items    *int64 `json:"items,omitempty"`
	LastOnly *int64 `json:"lastOnly,omitempty"`
	Source   string `json:"source,omitempty"`
}

// Auctionator is the fallback export (#90): Auctionator's prices for items CraftWise had no price
// for. House unknown (Auctionator mixes houses), never mixed into Items.
type Auctionator struct {
	Source string                            `json:"source,omitempty"`
	House  string                            `json:"house,omitempty"`
	Label  string                            `json:"label,omitempty"`
	Items  map[int64]market.AuctionatorPrice `json:"items,omitempty"`
}

// Scope is the market scope: items that keep history, and the skill lines that define it.
type Scope struct {
	Items      map[int64]bool `json:"items,omitempty"`
	SkillLines map[int64]bool `json:"skillLines,omitempty"`
}

// CutSample is one AH sale mail (#26 phase 3): what sold, what arrived, the cut.
type CutSample struct {
	House    string `json:"house,omitempty"`
	Listed   *int64 `json:"listed,omitempty"`
	Received *int64 `json:"received,omitempty"`
	Cut      *int64 `json:"cut,omitempty"`
	Deposit  *int64 `json:"deposit,omitempty"`
	T        *int64 `json:"t,omitempty"`
	Item     *int64 `json:"i,omitempty"`
	Q        *int64 `json:"q,omitempty"`
}

// Ledger is the purchase and sale log (#46): entries of the last 30 days, per-character money marks
// and paid-cost positions.
type Ledger struct {
	Entries []LedgerEntry         `json:"entries,omitempty"`
	Chars   map[string]LedgerChar `json:"chars,omitempty"`
}

// LedgerEntry: kind "ahbuy", "ahsell" (Where = house key), "vbuy", "vsell", "buyback" (Where =
// merchant name). Copper is the total of the trade.
type LedgerEntry struct {
	T      *int64 `json:"t,omitempty"`
	Char   string `json:"c,omitempty"`
	Kind   string `json:"k,omitempty"`
	Item   *int64 `json:"i,omitempty"`
	Q      *int64 `json:"q,omitempty"`
	Copper *int64 `json:"m,omitempty"`
	Where  string `json:"w,omitempty"`
	Name   string `json:"n,omitempty"`
	Link   string `json:"l,omitempty"`
}

type LedgerChar struct {
	Reset   *MoneyMark         `json:"reset,omitempty"`
	Session *MoneyMark         `json:"session,omitempty"`
	Days    map[string]int64   `json:"days,omitempty"` // "YYYY-MM-DD" = money at the start of that day
	Pos     map[int64]Position `json:"pos,omitempty"`
}

type MoneyMark struct {
	T     *int64 `json:"t,omitempty"`
	Money *int64 `json:"money,omitempty"`
}

// Position is the paid cost of the units still held (#47). Units leaving take the average cost
// with them, so Known and Cost can have fractions.
type Position struct {
	Held    *float64 `json:"held,omitempty"`
	Known   *float64 `json:"known,omitempty"`
	Cost    *float64 `json:"cost,omitempty"`
	Transit *float64 `json:"transit,omitempty"`
}

// Auctions is the auction tracker's store (#81), per character, records kept 30 days after they end.
type Auctions struct {
	V     *int64                 `json:"v,omitempty"`
	Chars map[string]AuctionChar `json:"chars,omitempty"`
}

type AuctionChar struct {
	List       []Auction `json:"list"`
	OwnedAt    *int64    `json:"ownedAt,omitempty"`
	OwnedHouse string    `json:"ownedHouse,omitempty"`
}

// Auction is one tracked auction as Auctions.lua stores it. Status: "active", "sold", "gone",
// "expired", "cancelled", "settled", "returned".
type Auction struct {
	ID          *int64 `json:"id,omitempty"`
	Item        *int64 `json:"i,omitempty"`
	Name        string `json:"n,omitempty"`
	Link        string `json:"l,omitempty"`
	Q           *int64 `json:"q,omitempty"`
	Kind        string `json:"kind,omitempty"` // "item" or "commodity"
	Unit        *int64 `json:"unit,omitempty"` // buyout per unit
	Bid         *int64 `json:"bid,omitempty"`  // bid per unit
	Dur         *int64 `json:"dur,omitempty"`
	DurText     string `json:"durText,omitempty"`
	Exp         *int64 `json:"exp,omitempty"`
	Dep         *int64 `json:"dep,omitempty"`
	PostDeposit *int64 `json:"postDeposit,omitempty"`
	PostSize    *int64 `json:"postSize,omitempty"`
	T           *int64 `json:"t,omitempty"`
	House       string `json:"h,omitempty"`
	Status      string `json:"st,omitempty"`
	Untracked   bool   `json:"untracked,omitempty"`
	Seen        *int64 `json:"seen,omitempty"`
	OwnedBuyout *int64 `json:"ownedBuyout,omitempty"`
	OwnedBid    *int64 `json:"ownedBid,omitempty"`
	SoldT       *int64 `json:"soldT,omitempty"`
	SoldVia     string `json:"soldVia,omitempty"`
	ExpT        *int64 `json:"expT,omitempty"`
	CancelT     *int64 `json:"cancelT,omitempty"`
	GoneT       *int64 `json:"goneT,omitempty"`
	SettledT    *int64 `json:"settledT,omitempty"`
	Received    *int64 `json:"received,omitempty"`
	Sale        *int64 `json:"sale,omitempty"`
	Cut         *int64 `json:"cut,omitempty"`
	SaleDeposit *int64 `json:"saleDeposit,omitempty"`
	ReturnedT   *int64 `json:"returnedT,omitempty"`
	ReturnKind  string `json:"returnKind,omitempty"`
	Uncertain   bool   `json:"uncertain,omitempty"`
	Candidates  *int64 `json:"candidates,omitempty"`
	QtyUnknown  bool   `json:"qtyUnknown,omitempty"`
	Why         string `json:"why,omitempty"`
}

// ReadFile parses and reads a CraftWise.lua SavedVariables file.
func ReadFile(path string) (*File, error) {
	parsed, err := svparse.ParseFile(path)
	if err != nil {
		return nil, err
	}
	return FromParsed(parsed), nil
}

// Read parses and reads a SavedVariables file from r.
func Read(r io.Reader) (*File, error) {
	parsed, err := svparse.Parse(r)
	if err != nil {
		return nil, err
	}
	return FromParsed(parsed), nil
}

// FromParsed reads an already parsed file.
func FromParsed(parsed *svparse.File) *File {
	r := &reader{}
	out := &File{}
	if v := parsed.Get("CraftWiseDB"); v != nil {
		out.DB = r.db(v)
	}
	if v := parsed.Get("CraftWiseMarketDB"); v != nil {
		out.Market = r.market(v)
	}
	out.Problems = svparse.SortedProblems(r.problems)
	return out
}

type reader struct {
	problems []svparse.Problem
}

func (r *reader) add(path, format string, args ...any) {
	r.problems = append(r.problems, svparse.Problem{Path: path, Msg: fmt.Sprintf(format, args...)})
}

func (r *reader) unmarshal(v any, dst any, prefix string) {
	for _, p := range svparse.Unmarshal(v, dst) {
		if p.Path == "" {
			p.Path = prefix
		} else if p.Path[0] == '[' {
			p.Path = prefix + p.Path
		} else {
			p.Path = prefix + "." + p.Path
		}
		r.problems = append(r.problems, p)
	}
}

func (r *reader) table(v any, path string) *svparse.Table {
	t, ok := v.(*svparse.Table)
	if !ok && v != nil {
		r.add(path, "want table, got %T", v)
	}
	return t
}

func (r *reader) db(v any) *DB {
	t := r.table(v, "CraftWiseDB")
	if t == nil {
		return nil
	}
	out := &DB{}
	snaps := r.table(t.Get("snapshots"), "CraftWiseDB.snapshots")
	if snaps == nil {
		return out
	}
	out.Snapshots = map[string]*Snapshot{}
	for _, f := range snaps.Fields() {
		key, ok := f.Key.(string)
		path := fmt.Sprintf("CraftWiseDB.snapshots[%q]", key)
		if !ok {
			r.add(fmt.Sprintf("CraftWiseDB.snapshots[%v]", f.Key), "want a character key")
			continue
		}
		tbl := r.table(f.Value, path)
		if tbl == nil {
			continue
		}
		s := &Snapshot{Raw: tbl}
		r.unmarshal(tbl, s, path)
		out.Snapshots[key] = s
	}
	return out
}

func (r *reader) market(v any) *MarketDB {
	const root = "CraftWiseMarketDB"
	t := r.table(v, root)
	if t == nil {
		return nil
	}
	out := &MarketDB{}
	r.unmarshal(t, out, root)

	if items := r.table(t.Get("items"), root+".items"); items != nil {
		out.Items = map[market.ItemKey]map[string]market.Entry{}
		for _, f := range items.Fields() {
			path := root + ".items" + keyText(f.Key)
			key, err := market.ParseItemKey(f.Key)
			if err != nil {
				r.add(path, "%v", err)
				continue
			}
			perItem := r.table(f.Value, path)
			if perItem == nil {
				continue
			}
			houses := map[string]market.Entry{}
			for _, h := range perItem.Fields() {
				house, ok := h.Key.(string)
				hpath := path + keyText(h.Key)
				if !ok {
					r.add(hpath, "want a house key")
					continue
				}
				if e, ok := r.entry(h.Value, hpath); ok {
					houses[house] = e
				}
			}
			if len(houses) > 0 {
				out.Items[key] = houses
			}
		}
	}

	if info := r.table(t.Get("itemInfo"), root+".itemInfo"); info != nil {
		out.ItemInfo = map[int64]market.ItemInfo{}
		for _, f := range info.Fields() {
			path := root + ".itemInfo" + keyText(f.Key)
			id, ok := itemID(f.Key)
			s, isString := f.Value.(string)
			if !ok || !isString {
				r.add(path, "want [itemID] = \"q,i,c,s,t,p\"")
				continue
			}
			decoded, err := market.DecodeItemInfo(s)
			if err != nil {
				r.add(path, "%v", err)
				continue
			}
			out.ItemInfo[id] = decoded
		}
	}

	if a := r.table(t.Get("auctionator"), root+".auctionator"); a != nil {
		out.Auctionator = &Auctionator{}
		var head struct {
			Source string `json:"source"`
			House  string `json:"house"`
			Label  string `json:"label"`
		}
		r.unmarshal(a, &head, root+".auctionator")
		out.Auctionator.Source, out.Auctionator.House, out.Auctionator.Label = head.Source, head.House, head.Label
		if items := r.table(a.Get("items"), root+".auctionator.items"); items != nil {
			out.Auctionator.Items = map[int64]market.AuctionatorPrice{}
			for _, f := range items.Fields() {
				path := root + ".auctionator.items" + keyText(f.Key)
				id, ok := itemID(f.Key)
				s, isString := f.Value.(string)
				if !ok || !isString {
					r.add(path, "want [itemID] = \"t,copper,age\"")
					continue
				}
				price, err := market.DecodeAuctionator(s)
				if err != nil {
					r.add(path, "%v", err)
					continue
				}
				out.Auctionator.Items[id] = price
			}
		}
	}
	return out
}

// entry reads a packed entry, or the table form (Market.lua decodes entries in use into tables; they
// are packed again at logout, but one used after that is saved as a table).
func (r *reader) entry(v any, path string) (market.Entry, bool) {
	switch e := v.(type) {
	case string:
		decoded, err := market.Decode(e)
		if err != nil {
			r.add(path, "%v", err)
			return market.Entry{}, false
		}
		return decoded, true
	case *svparse.Table:
		var t struct {
			Last *market.Last         `json:"last"`
			Raw  []tablePoint         `json:"raw"`
			Days map[int64]market.Day `json:"days"`
		}
		before := len(r.problems)
		r.unmarshal(e, &t, path)
		if len(r.problems) > before {
			return market.Entry{}, false
		}
		out := market.Entry{Last: t.Last, Days: t.Days}
		if out.Days == nil {
			out.Days = map[int64]market.Day{}
		}
		for i, p := range t.Raw {
			if len(p.Tiers)%2 != 0 {
				r.add(fmt.Sprintf("%s.raw[%d].tiers", path, i+1), "odd number of values")
				return market.Entry{}, false
			}
			point := market.Point{T: p.T, Total: p.Total, Listings: p.Listings, M: p.M, Tiers: []market.Tier{}}
			for j := 0; j < len(p.Tiers); j += 2 {
				point.Tiers = append(point.Tiers, market.Tier{Price: p.Tiers[j], Qty: p.Tiers[j+1]})
			}
			out.Raw = append(out.Raw, point)
		}
		return out, true
	}
	r.add(path, "want a packed entry, got %T", v)
	return market.Entry{}, false
}

type tablePoint struct {
	T        int64   `json:"t"`
	Total    *int64  `json:"total"`
	Listings *int64  `json:"listings"`
	M        *int64  `json:"m"`
	Tiers    []int64 `json:"tiers"`
}

func itemID(key any) (int64, bool) {
	f, ok := key.(float64)
	if !ok || f != float64(int64(f)) || f <= 0 {
		return 0, false
	}
	return int64(f), true
}

func keyText(key any) string {
	switch k := key.(type) {
	case string:
		return fmt.Sprintf("[%q]", k)
	case float64:
		if k == float64(int64(k)) {
			return fmt.Sprintf("[%d]", int64(k))
		}
	}
	return fmt.Sprintf("[%v]", key)
}

// Item is everything known about one item: its name and client info (#92), and its prices per
// house. Missing parts are nil.
type Item struct {
	ID          int64                              `json:"id"`
	Name        string                             `json:"name,omitempty"`
	Info        *market.ItemInfo                   `json:"info,omitempty"`
	Prices      map[string]map[string]market.Entry `json:"prices,omitempty"` // item key text -> house -> entry
	Auctionator *market.AuctionatorPrice           `json:"auctionator,omitempty"`
}

// ItemIDs lists every item ID with a price (per house, or from Auctionator), ascending.
func (m *MarketDB) ItemIDs() []int64 {
	seen := map[int64]bool{}
	for key := range m.Items {
		seen[key.ItemID] = true
	}
	if m.Auctionator != nil {
		for id := range m.Auctionator.Items {
			seen[id] = true
		}
	}
	out := make([]int64, 0, len(seen))
	for id := range seen {
		out = append(out, id)
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

// Item gathers what the market data has for one item ID (suffix variants included).
func (m *MarketDB) Item(id int64) Item {
	out := Item{ID: id, Name: m.Names[id]}
	if info, ok := m.ItemInfo[id]; ok {
		out.Info = &info
	}
	for key, houses := range m.Items {
		if key.ItemID == id {
			if out.Prices == nil {
				out.Prices = map[string]map[string]market.Entry{}
			}
			out.Prices[key.String()] = houses
		}
	}
	if m.Auctionator != nil {
		if p, ok := m.Auctionator.Items[id]; ok {
			out.Auctionator = &p
		}
	}
	return out
}
