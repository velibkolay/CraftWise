package upload

import (
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"unicode"
	"unicode/utf16"

	"github.com/velibkolay/CraftWise/companion/market"
	"github.com/velibkolay/CraftWise/companion/savedvars"
)

const day = 86400

// Plan is one upload: the requests to send, in order, and what was left out and why.
type Plan struct {
	Public  []*Batch[PublicPayload]
	Private []*Batch[PrivatePayload]
	// Skipped lists values the server would refuse (missing required fields, out of range); they
	// are never filled in. Counted per reason.
	Skipped map[string]int
}

// Empty reports a plan with nothing to send.
func (p *Plan) Empty() bool { return len(p.Public) == 0 && len(p.Private) == 0 }

// SkippedText is Skipped as sorted lines.
func (p *Plan) SkippedText() []string {
	out := make([]string, 0, len(p.Skipped))
	for reason, n := range p.Skipped {
		out = append(out, fmt.Sprintf("%d x %s", n, reason))
	}
	sort.Strings(out)
	return out
}

// Options for Build.
type Options struct {
	Now     int64 // Unix time
	Private bool  // build the private requests too
	// Batch limits; zero = defaults (DefaultMaxBytes, DefaultMaxRows).
	MaxBytes int
	MaxRows  int
}

// Defaults: request bodies well below the server's 500 KB, and at most this many D1 rows
// (the server's upper-bound estimate) per request, so one request never needs a large part of
// the free plan's daily write budget at once.
const (
	DefaultMaxBytes = 400_000
	DefaultMaxRows  = 8000
)

// Build computes what is new in f since st and splits it into requests. st is not changed;
// Batch.Commit records a sent batch in it.
func Build(f *savedvars.File, st *State, opt Options) *Plan {
	st.init()
	if opt.MaxBytes <= 0 {
		opt.MaxBytes = DefaultMaxBytes
	}
	if opt.MaxRows <= 0 {
		opt.MaxRows = DefaultMaxRows
	}
	d := &delta{st: st, now: opt.Now, skipped: map[string]int{}}
	plan := &Plan{Skipped: d.skipped}
	if f.Market != nil {
		units := d.public(f.Market)
		plan.Public = packPublic(units, d.houses, opt, d.skip)
	}
	if opt.Private {
		units := d.private(f)
		plan.Private = packPrivate(units, opt, d.skip)
	}
	return plan
}

type delta struct {
	st      *State
	now     int64
	skipped map[string]int
	houses  map[string]House
}

func (d *delta) skip(reason string) { d.skipped[reason]++ }

func (d *delta) validTime(t *int64) bool {
	return t != nil && *t >= MinTime && *t <= d.now+MaxFuture
}

var (
	houseKeyRE = regexp.MustCompile(`^([^|]{1,64})\|(H|A|N:[A-Za-z]{1,32})$`)
	lowerRE    = regexp.MustCompile(`^[a-z]{1,16}$`)
)

// jsLen is a string's length as JavaScript counts it (UTF-16 code units): the server's limits.
func jsLen(s string) int { return len(utf16.Encode([]rune(s))) }

func okString(s string, max int) bool { return s != "" && jsLen(s) <= max }

// house checks one house against the server's rules; nil when it can't be sent.
func (d *delta) house(key string, h savedvars.House) *House {
	m := houseKeyRE.FindStringSubmatch(key)
	if m == nil || h.Realm != m[1] || !okString(h.Label, 64) {
		return nil
	}
	out := &House{Realm: h.Realm, Label: h.Label}
	switch m[2] {
	case "H", "A":
		want := map[string]string{"H": "Horde", "A": "Alliance"}[m[2]]
		if h.Kind != "faction" || h.Faction != want {
			return nil
		}
		out.Kind, out.Faction = "faction", want
	default:
		if h.Kind != "neutral" || h.Faction != "" {
			return nil
		}
		out.Kind = "neutral"
	}
	return out
}

// unit is one piece of a request: a scan, an item, a price record, a document or a ledger group.
type unit[T any] struct {
	add    func(*T)
	house  string // public: the house it needs in `houses`
	key    string // price: "<house>\x1f<item>", never twice in one request
	kind   string // "scans", "items", "prices"; "snapshots", "auctions", "fishing", "ledger"
	count  int    // private ledger: entries
	bytes  int
	rows   int
	commit func(*State)
}

func size(v any) int {
	b, _ := json.Marshal(v)
	return len(b) + 1
}

func (d *delta) public(m *savedvars.MarketDB) []unit[PublicPayload] {
	d.houses = map[string]House{}
	for key, h := range m.Houses {
		if out := d.house(key, h); out != nil {
			d.houses[key] = *out
		} else {
			d.skip("house without a valid key, realm, kind, faction or label (its prices and scans too)")
		}
	}
	var units []unit[PublicPayload]

	// Scans, per house in key order, oldest first.
	houseKeys := make([]string, 0, len(m.Scans))
	for h := range m.Scans {
		houseKeys = append(houseKeys, h)
	}
	sort.Strings(houseKeys)
	for _, h := range houseKeys {
		if _, ok := d.houses[h]; !ok {
			continue
		}
		sent := d.st.Scans[h]
		for _, s := range m.Scans[h] {
			if s.T == nil || *s.T <= sent {
				continue
			}
			if !d.validTime(s.T) || !lowerRE.MatchString(s.Kind) || jsLen(s.Source) > 32 {
				d.skip("scan without a valid time or kind")
				continue
			}
			scan := Scan{T: *s.T, Kind: s.Kind, Items: s.Items, LastOnly: s.LastOnly, Source: s.Source}
			house := h
			units = append(units, unit[PublicPayload]{
				add: func(p *PublicPayload) {
					if p.Scans == nil {
						p.Scans = map[string][]Scan{}
					}
					p.Scans[house] = append(p.Scans[house], scan)
				},
				house: h, kind: "scans", bytes: size(scan) + size(h), rows: 2,
				commit: func(st *State) {
					if scan.T > st.Scans[house] {
						st.Scans[house] = scan.T
					}
				},
			})
		}
	}

	// Class names, item info and names are low priority (#145): above 80% of the day's write budget
	// the server refuses them until 00:00 UTC, so they go after the prices, in requests of their own
	// (packPublic), and a refusal never holds back price data.
	low := d.classNames(m)

	// Item info and names: new or changed items (a new sell price, #120, is a change).
	ids := map[int64]bool{}
	for id := range m.Names {
		ids[id] = true
	}
	for id := range m.ItemInfo {
		ids[id] = true
	}
	idList := make([]int64, 0, len(ids))
	for id := range ids {
		idList = append(idList, id)
	}
	sort.Slice(idList, func(i, j int) bool { return idList[i] < idList[j] })
	for _, id := range idList {
		name := m.Names[id]
		if name != "" && jsLen(name) > 200 {
			d.skip("item name over 200 characters (name left out)")
			name = ""
		}
		info, hasInfo := m.ItemInfo[id]
		if hasInfo && info.T != nil && !d.validTime(info.T) {
			info.T = nil // when the client gave it: checked by the server, not stored
		}
		if hasInfo && info == (market.ItemInfo{}) {
			hasInfo = false
		}
		if name == "" && !hasInfo {
			continue
		}
		// The time the addon read the info is left out of the comparison: it changes without the
		// info changing.
		cmp := info
		cmp.T = nil
		h := hashJSON(struct {
			N    string
			Info market.ItemInfo
			Has  bool
		}{name, cmp, hasInfo})
		if d.st.Items[id] == h {
			continue
		}
		id := id
		bytes := 0
		if name != "" {
			bytes += size(id) + 2 + size(name)
		}
		if hasInfo {
			bytes += size(id) + 2 + size(info)
		}
		low = append(low, unit[PublicPayload]{
			add: func(p *PublicPayload) {
				if name != "" {
					if p.Names == nil {
						p.Names = map[int64]string{}
					}
					p.Names[id] = name
				}
				if hasInfo {
					if p.ItemInfo == nil {
						p.ItemInfo = map[int64]market.ItemInfo{}
					}
					p.ItemInfo[id] = info
				}
			},
			// the item row (an upsert counts twice) and its search words
			kind: "items", bytes: bytes, rows: 2 + nameWords(name),
			commit: func(st *State) { st.Items[id] = h },
		})
	}

	// Prices: items with history first (they cost more to lose), then `last`-only items.
	type entryRef struct {
		key   market.ItemKey
		house string
		e     market.Entry
	}
	var refs []entryRef
	for key, houses := range m.Items {
		for h, e := range houses {
			if _, ok := d.houses[h]; !ok {
				continue
			}
			refs = append(refs, entryRef{key, h, e})
		}
	}
	sort.Slice(refs, func(i, j int) bool {
		a, b := refs[i], refs[j]
		if a.e.LastOnly() != b.e.LastOnly() {
			return !a.e.LastOnly()
		}
		if a.house != b.house {
			return a.house < b.house
		}
		if a.key.ItemID != b.key.ItemID {
			return a.key.ItemID < b.key.ItemID
		}
		return a.key.Suffix < b.key.Suffix
	})
	for _, r := range refs {
		units = append(units, d.price(r.house, r.key.String(), r.e)...)
	}
	return append(units, low...)
}

// lowPriority reports the kinds the server holds back above its soft write limit (#145).
func lowPriority(kind string) bool { return kind == "items" || kind == "classes" }

// classNames sends the client's class and subclass names (#120) that are new or changed since the last
// upload: they change almost never (another client language, a patch), so after the first upload this
// sends nothing.
func (d *delta) classNames(m *savedvars.MarketDB) []unit[PublicPayload] {
	type named struct {
		class, sub int64
		isSub      bool
		name       string
	}
	var list []named
	okID := func(id int64) bool { return id >= 0 && id <= MaxClassID }
	okName := func(name string) bool {
		if !okString(name, MaxClassNameLen) || controlRE.MatchString(name) {
			d.skip("class or subclass name empty, over 64 characters or with control characters")
			return false
		}
		return true
	}
	for c, name := range m.ClassNames {
		if !okID(c) {
			d.skip("class name of a class ID out of range")
			continue
		}
		if okName(name) {
			list = append(list, named{class: c, name: name})
		}
	}
	for c, subs := range m.SubclassNames {
		for s, name := range subs {
			if !okID(c) || !okID(s) {
				d.skip("subclass name of a class or subclass ID out of range")
				continue
			}
			if okName(name) {
				list = append(list, named{class: c, sub: s, isSub: true, name: name})
			}
		}
	}
	sort.Slice(list, func(i, j int) bool {
		a, b := list[i], list[j]
		if a.class != b.class {
			return a.class < b.class
		}
		if a.isSub != b.isSub {
			return !a.isSub
		}
		return a.sub < b.sub
	})
	var units []unit[PublicPayload]
	for _, n := range list {
		n := n
		key := fmt.Sprint(n.class)
		if n.isSub {
			key += fmt.Sprintf(":%d", n.sub)
		}
		if d.st.Classes[key] == n.name {
			continue
		}
		units = append(units, unit[PublicPayload]{
			add: func(p *PublicPayload) {
				if !n.isSub {
					if p.ClassNames == nil {
						p.ClassNames = map[int64]string{}
					}
					p.ClassNames[n.class] = n.name
					return
				}
				if p.SubclassNames == nil {
					p.SubclassNames = map[int64]map[int64]string{}
				}
				if p.SubclassNames[n.class] == nil {
					p.SubclassNames[n.class] = map[int64]string{}
				}
				p.SubclassNames[n.class][n.sub] = n.name
			},
			// one row, an upsert counts twice
			kind: "classes", bytes: size(n.class) + size(n.sub) + size(n.name) + 6, rows: 2,
			commit: func(st *State) { st.Classes[key] = n.name },
		})
	}
	return units
}

// nameWords is about how many search words the server stores for a name (at most 12).
func nameWords(name string) int {
	n := len(strings.FieldsFunc(name, func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '\'' }))
	if n > 12 {
		n = 12
	}
	return n
}

func optEqual(a, b *int64) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}

func nonNeg(ps ...*int64) bool {
	for _, p := range ps {
		if p != nil && *p < 0 {
			return false
		}
	}
	return true
}

// price builds the new part of one entry: `last` when newer, raw points after the newest one sent,
// and the days that can still change and differ from what was sent. More raw points than the
// server takes in one record are split over several records (in separate requests).
func (d *delta) price(house, item string, e market.Entry) []unit[PublicPayload] {
	key := priceKey(house, item)
	old := d.st.Prices[key]
	if old == nil {
		old = &PriceMark{}
	}
	next := &PriceMark{LastT: old.LastT, Off: old.Off, RawT: old.RawT}

	var last *market.Last
	if l := e.Last; l != nil {
		switch {
		case !d.validTime(l.T) || l.Min == nil || l.Qty == nil || !nonNeg(l.Min, l.Qty, l.Listings) ||
			(l.Off != nil && !d.validTime(l.Off)):
			if l.T == nil || *l.T > old.LastT {
				d.skip("price without a valid last time, minimum or quantity (last left out)")
			}
		case *l.T > old.LastT || (*l.T == old.LastT && !optEqual(l.Off, old.Off)):
			cp := *l
			last = &cp
		}
		if l.T != nil && *l.T >= old.LastT {
			next.LastT, next.Off = *l.T, l.Off
		}
	}

	var raw []market.Point
	oldest := int64(-1)
	for _, p := range e.Raw {
		if oldest < 0 || p.T < oldest {
			oldest = p.T
		}
		if p.T <= old.RawT {
			continue
		}
		if p.T > next.RawT {
			next.RawT = p.T
		}
		t := p.T
		if !d.validTime(&t) || p.Total == nil || !nonNeg(p.Total, p.Listings, p.M) || len(p.Tiers) > MaxTiers {
			d.skip("raw point without a valid time or total, or with more than 8 tiers")
			continue
		}
		ok, prev := true, int64(-1)
		for _, tier := range p.Tiers {
			if tier.Price <= prev || tier.Qty < 0 {
				ok = false
				break
			}
			prev = tier.Price
		}
		if !ok {
			d.skip("raw point whose tier prices don't rise")
			continue
		}
		if p.Tiers == nil {
			p.Tiers = []market.Tier{}
		}
		raw = append(raw, p)
	}
	sort.Slice(raw, func(i, j int) bool { return raw[i].T < raw[j].T })

	// Days that can still change: from the oldest raw point's day (or today) on. Market.lua only
	// rewrites the aggregate of a day that has raw points, and keeps raw points 48 hours.
	today := d.now / day
	next.DaysFrom = today
	if oldest >= 0 && oldest/day < today {
		next.DaysFrom = oldest / day
	}
	next.Days = map[int64]uint64{}
	days := map[int64]market.Day{}
	for n, v := range e.Days {
		h := hashJSON(v)
		if n >= next.DaysFrom {
			next.Days[n] = h
		}
		if n < old.DaysFrom || old.Days[n] == h {
			continue
		}
		if n < MinTime/day || n > (d.now+MaxFuture)/day || !nonNeg(v.Lo, v.Typ, v.Hi, v.QtyMax, v.ListMax, v.N, v.Gone) {
			d.skip("daily aggregate out of range")
			continue
		}
		days[n] = v
	}
	if len(days) > MaxDays { // the addon keeps 30
		d.skip("price entry with more days than one request takes")
		return nil
	}

	if last == nil && len(raw) == 0 && len(days) == 0 {
		// Nothing new. The stored mark stays valid: it only compares more days than needed.
		return nil
	}

	// Raw points in pieces of at most MaxRawPoints (separate requests); the first piece carries
	// last and days.
	var units []unit[PublicPayload]
	pieces := (len(raw) + MaxRawPoints - 1) / MaxRawPoints
	if pieces == 0 {
		pieces = 1
	}
	for i := 0; i < pieces; i++ {
		var rec market.Entry
		lo, hi := i*MaxRawPoints, (i+1)*MaxRawPoints
		if hi > len(raw) {
			hi = len(raw)
		}
		if lo < hi {
			rec.Raw = raw[lo:hi]
		}
		// The server's upper bound: 2 per upserted row, 1 per raw point.
		rows := len(rec.Raw)
		if i == 0 {
			rec.Last = last
			if len(days) > 0 {
				rec.Days = days
			}
			rows += 2 * len(days)
			if last != nil {
				rows += 4 // prices row and the daily row built from last
			}
		}
		var commit func(*State)
		if i == pieces-1 {
			commit = func(st *State) { st.Prices[key] = next }
		} else {
			pieceT := rec.Raw[len(rec.Raw)-1].T
			first := i == 0
			commit = func(st *State) {
				m := st.Prices[key]
				if m == nil {
					m = &PriceMark{}
				}
				cp := *m
				cp.RawT = pieceT
				if first {
					cp.LastT, cp.Off, cp.DaysFrom, cp.Days = next.LastT, next.Off, next.DaysFrom, next.Days
				}
				st.Prices[key] = &cp
			}
		}
		units = append(units, unit[PublicPayload]{
			add: func(p *PublicPayload) {
				if p.Items == nil {
					p.Items = map[string]map[string]market.Entry{}
				}
				if p.Items[item] == nil {
					p.Items[item] = map[string]market.Entry{}
				}
				p.Items[item][house] = rec
			},
			house: house, key: key, kind: "prices",
			bytes: size(rec) + size(item) + size(house) + 4, rows: rows, commit: commit,
		})
	}
	return units
}

var controlRE = regexp.MustCompile(`[\x00-\x1f]`)

// validChar reports a character key the server takes: "<realm>-<name>[ <surname>]", no control
// characters, 1 to 64 characters on both sides of a dash.
func validChar(key string) bool {
	if controlRE.MatchString(key) {
		return false
	}
	for i := 0; i < len(key); i++ {
		if key[i] == '-' {
			l, r := jsLen(key[:i]), jsLen(key[i+1:])
			if l >= 1 && l <= 64 && r >= 1 && r <= 64 {
				return true
			}
		}
	}
	return false
}

// fishingDoc is the fishing document: the snapshot's fishing summary (#69, #86) with its zone
// ranking (#88) as "fishingZones", the snapshot's own name for it.
type fishingDoc struct {
	*savedvars.FishingSummary
	Zones *savedvars.FishingZones `json:"fishingZones,omitempty"`
}

func (d *delta) private(f *savedvars.File) []unit[PrivatePayload] {
	var units []unit[PrivatePayload]
	if f.DB != nil {
		chars := make([]string, 0, len(f.DB.Snapshots))
		for c := range f.DB.Snapshots {
			chars = append(chars, c)
		}
		sort.Strings(chars)
		for _, c := range chars {
			s := f.DB.Snapshots[c]
			if !validChar(c) || !d.validTime(s.T) {
				d.skip("snapshot without a valid character key or time")
				continue
			}
			t := *s.T
			units = d.doc(units, "snapshots", c, t, s)
			if s.Fishing != nil || s.FishingZones != nil {
				units = d.doc(units, "fishing", c, t, fishingDoc{s.Fishing, s.FishingZones})
			}
		}
	}
	// The auction tracker's records per character (#81); t = when the file was read.
	if f.Market != nil && f.Market.Auctions != nil {
		chars := make([]string, 0, len(f.Market.Auctions.Chars))
		for c := range f.Market.Auctions.Chars {
			chars = append(chars, c)
		}
		sort.Strings(chars)
		for _, c := range chars {
			if !validChar(c) {
				d.skip("auctions of an invalid character key")
				continue
			}
			units = d.doc(units, "auctions", c, d.now, f.Market.Auctions.Chars[c])
		}
	}
	if f.Market != nil && f.Market.Ledger != nil {
		units = append(units, d.ledger(f.Market.Ledger.Entries)...)
	}
	return units
}

func (d *delta) doc(units []unit[PrivatePayload], kind, char string, t int64, data any) []unit[PrivatePayload] {
	body, err := json.Marshal(data)
	if err != nil {
		d.skip(kind + " document that can't be encoded")
		return units
	}
	if len(body) > MaxPrivateDocSize {
		d.skip(fmt.Sprintf("%s document over %d bytes", kind, MaxPrivateDocSize))
		return units
	}
	h := hashJSON(json.RawMessage(body))
	key := docKey(kind, char)
	if d.st.Docs[key] == h {
		return units
	}
	doc := Doc{T: t, Data: json.RawMessage(body)}
	return append(units, unit[PrivatePayload]{
		add: func(p *PrivatePayload) {
			m := map[string]*map[string]Doc{"snapshots": &p.Snapshots, "auctions": &p.Auctions, "fishing": &p.Fishing}[kind]
			if *m == nil {
				*m = map[string]Doc{}
			}
			(*m)[char] = doc
		},
		kind: kind, bytes: size(char) + 2 + size(doc), count: 1,
		commit: func(st *State) { st.Docs[key] = h },
	})
}

// ledger sends entries newer than the newest one sent, and the entries of that same second again
// when more were added. Entries of one second go in one request: the server numbers identical
// entries within a request.
func (d *delta) ledger(entries []savedvars.LedgerEntry) []unit[PrivatePayload] {
	type group struct {
		t   int64
		all int
		out []LedgerEntry
	}
	byT := map[int64]*group{}
	for _, e := range entries {
		if !d.validTime(e.T) || !validChar(e.Char) || !lowerRE.MatchString(e.Kind) || !nonNeg(e.Item, e.Q, e.Copper) {
			d.skip("ledger entry without a valid time, character or kind")
			continue
		}
		g := byT[*e.T]
		if g == nil {
			g = &group{t: *e.T}
			byT[*e.T] = g
		}
		g.all++
		out := LedgerEntry{T: *e.T, C: e.Char, K: e.Kind, I: e.Item, Q: e.Q, M: e.Copper}
		if okString(e.Where, 100) {
			out.W = e.Where
		}
		if okString(e.Name, 200) {
			out.N = e.Name
		}
		if okString(e.Link, 500) {
			out.L = e.Link
		}
		g.out = append(g.out, out)
	}
	groups := make([]*group, 0, len(byT))
	for _, g := range byT {
		if g.t > d.st.LedgerT || (g.t == d.st.LedgerT && g.all > d.st.LedgerAtT) {
			groups = append(groups, g)
		}
	}
	sort.Slice(groups, func(i, j int) bool { return groups[i].t < groups[j].t })
	units := make([]unit[PrivatePayload], 0, len(groups))
	for _, g := range groups {
		g := g
		if len(g.out) > MaxLedgerEntries {
			d.skip("ledger second with more entries than one request takes")
			continue
		}
		bytes := 0
		for _, e := range g.out {
			bytes += size(e)
		}
		units = append(units, unit[PrivatePayload]{
			add:  func(p *PrivatePayload) { p.Ledger = append(p.Ledger, g.out...) },
			kind: "ledger", count: len(g.out), bytes: bytes,
			commit: func(st *State) { st.LedgerT, st.LedgerAtT = g.t, g.all },
		})
	}
	return units
}
