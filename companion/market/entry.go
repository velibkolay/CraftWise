// Package market reads CraftWise's packed price entries: a port of EncodeEntry/DecodeEntry in
// CraftWise/Market.lua (#26, #90). Golden tests (market_test.go) check both directions against
// fixtures written by the Lua code itself (tests/companion_fixtures.lua).
//
// Packed entry: "last|raw|days", numbers in base 36, deltas zigzag coded.
//
//	last = t,min,qty,listings[,off]
//	raw  = points joined by ";", point = dt,total,listings,m,dp1,q1,dp2,q2...
//	days = days joined by ";", day = dDay,lo,dTyp,dHi,qtyMax,listMax,n,gone
//
// An empty field is nil. Items outside the market scope have `last` only: the string ends in "||".
package market

import (
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

// Last is the latest observation of an item at a house. Off is the time of a later full scan that
// didn't list it (#90). Every field can be missing (nil), as in the Lua table.
type Last struct {
	T        *int64 `json:"t,omitempty"`
	Min      *int64 `json:"min,omitempty"`
	Qty      *int64 `json:"qty,omitempty"`
	Listings *int64 `json:"listings,omitempty"`
	Off      *int64 `json:"off,omitempty"`
}

// Tier is one price level of a raw point: unit price and units at that price.
type Tier struct {
	Price int64 `json:"price"`
	Qty   int64 `json:"qty"`
}

// Point is one observation with depth (48 h kept). M is the median unit price of the point's
// cheapest 15%, only stored when the tiers don't hold all units.
type Point struct {
	T        int64  `json:"t"`
	Total    *int64 `json:"total,omitempty"`
	Listings *int64 `json:"listings,omitempty"`
	M        *int64 `json:"m,omitempty"`
	Tiers    []Tier `json:"tiers"`
}

// Day is the daily aggregate (30 days kept). Gone = units that disappeared (sold or expired).
type Day struct {
	Lo      *int64 `json:"lo,omitempty"`
	Typ     *int64 `json:"typ,omitempty"`
	Hi      *int64 `json:"hi,omitempty"`
	QtyMax  *int64 `json:"qtyMax,omitempty"`
	ListMax *int64 `json:"listMax,omitempty"`
	N       *int64 `json:"n,omitempty"`
	Gone    *int64 `json:"gone,omitempty"`
}

// Entry is one item at one house. Days is keyed by day number (Unix time / 86400).
type Entry struct {
	Last *Last         `json:"last,omitempty"`
	Raw  []Point       `json:"raw,omitempty"`
	Days map[int64]Day `json:"days,omitempty"`
}

// LastOnly reports an entry without history (no raw points, no days): items outside the scope.
func (e Entry) LastOnly() bool { return len(e.Raw) == 0 && len(e.Days) == 0 }

// PackedLastOnly is LastOnly on the packed string, without decoding it (Market.lua IsLastOnly).
func PackedLastOnly(s string) bool { return strings.HasSuffix(s, "||") }

// Int returns a pointer to n, for building entries.
func Int(n int64) *int64 { return &n }

// base36 is Market.lua's Base36: values below 1 are written "0" (the Lua code floors and never
// writes a sign), so negative numbers don't survive a round trip there either.
func base36(n int64) string {
	if n <= 0 {
		return "0"
	}
	return strconv.FormatInt(n, 36)
}

func opt(p *int64) string {
	if p == nil {
		return ""
	}
	return base36(*p)
}

func zig(n int64) int64 {
	if n >= 0 {
		return n * 2
	}
	return -n*2 - 1
}

func unzig(z int64) int64 {
	if z%2 == 0 {
		return z / 2
	}
	return -(z + 1) / 2
}

// Encode packs an entry exactly as Market.lua's EncodeEntry does.
func Encode(e Entry) string {
	var b strings.Builder
	if l := e.Last; l != nil {
		b.WriteString(opt(l.T))
		b.WriteByte(',')
		b.WriteString(opt(l.Min))
		b.WriteByte(',')
		b.WriteString(opt(l.Qty))
		b.WriteByte(',')
		b.WriteString(opt(l.Listings))
		if l.Off != nil {
			b.WriteByte(',')
			b.WriteString(base36(*l.Off))
		}
	}
	b.WriteByte('|')
	var prevT int64
	for i, p := range e.Raw {
		if i > 0 {
			b.WriteByte(';')
		}
		b.WriteString(base36(zig(p.T - prevT)))
		prevT = p.T
		b.WriteByte(',')
		b.WriteString(opt(p.Total))
		b.WriteByte(',')
		b.WriteString(opt(p.Listings))
		b.WriteByte(',')
		b.WriteString(opt(p.M))
		var prevPrice int64
		for _, tier := range p.Tiers {
			b.WriteByte(',')
			b.WriteString(base36(zig(tier.Price - prevPrice)))
			b.WriteByte(',')
			b.WriteString(base36(tier.Qty))
			prevPrice = tier.Price
		}
	}
	b.WriteByte('|')
	days := make([]int64, 0, len(e.Days))
	for day := range e.Days {
		days = append(days, day)
	}
	sort.Slice(days, func(i, j int) bool { return days[i] < days[j] })
	var prevDay int64
	for i, day := range days {
		d := e.Days[day]
		if i > 0 {
			b.WriteByte(';')
		}
		var lo int64
		if d.Lo != nil {
			lo = *d.Lo
		}
		b.WriteString(base36(zig(day - prevDay)))
		b.WriteByte(',')
		b.WriteString(opt(d.Lo))
		b.WriteByte(',')
		if d.Typ != nil {
			b.WriteString(base36(zig(*d.Typ - lo)))
		}
		b.WriteByte(',')
		if d.Hi != nil {
			b.WriteString(base36(zig(*d.Hi - lo)))
		}
		b.WriteByte(',')
		b.WriteString(opt(d.QtyMax))
		b.WriteByte(',')
		b.WriteString(opt(d.ListMax))
		b.WriteByte(',')
		b.WriteString(opt(d.N))
		b.WriteByte(',')
		if d.Gone != nil && *d.Gone > 0 {
			b.WriteString(base36(*d.Gone))
		}
		prevDay = day
	}
	return b.String()
}

// ErrMalformed wraps every decoding error.
var ErrMalformed = errors.New("malformed market entry")

func malformed(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrMalformed, fmt.Sprintf(format, args...))
}

// num is Market.lua's Num: "" is nil, otherwise base 36 digits.
func num(s string) (*int64, error) {
	if s == "" {
		return nil, nil
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z') {
			return nil, malformed("%q is not a base 36 number", s)
		}
	}
	n, err := strconv.ParseInt(s, 36, 64)
	if err != nil {
		return nil, malformed("%q: %v", s, err)
	}
	return &n, nil
}

func required(s, what string) (int64, error) {
	n, err := num(s)
	if err != nil {
		return 0, err
	}
	if n == nil {
		return 0, malformed("%s is empty", what)
	}
	return *n, nil
}

// Decode unpacks a string written by Market.lua (or Encode). It reads what DecodeEntry reads and
// returns an error where DecodeEntry would fail or silently misalign (a price level without units).
func Decode(s string) (Entry, error) {
	parts := strings.Split(s, "|")
	if len(parts) != 3 {
		return Entry{}, malformed("want 3 parts separated by '|', got %d", len(parts))
	}
	e := Entry{Days: map[int64]Day{}}
	if parts[0] != "" {
		f := strings.Split(parts[0], ",")
		if len(f) < 4 || len(f) > 5 {
			return Entry{}, malformed("last: want 4 or 5 fields, got %d", len(f))
		}
		var vals [5]*int64
		for i, field := range f {
			v, err := num(field)
			if err != nil {
				return Entry{}, fmt.Errorf("last: %w", err)
			}
			vals[i] = v
		}
		e.Last = &Last{T: vals[0], Min: vals[1], Qty: vals[2], Listings: vals[3], Off: vals[4]}
	}
	if parts[1] != "" {
		var prevT int64
		for i, text := range strings.Split(parts[1], ";") {
			f := strings.Split(text, ",")
			if len(f) < 4 || len(f)%2 != 0 {
				return Entry{}, malformed("raw point %d: %d fields", i+1, len(f))
			}
			dt, err := required(f[0], "time delta")
			if err != nil {
				return Entry{}, fmt.Errorf("raw point %d: %w", i+1, err)
			}
			prevT += unzig(dt)
			p := Point{T: prevT, Tiers: []Tier{}}
			for j, dst := range []**int64{&p.Total, &p.Listings, &p.M} {
				if *dst, err = num(f[j+1]); err != nil {
					return Entry{}, fmt.Errorf("raw point %d: %w", i+1, err)
				}
			}
			var prevPrice int64
			for j := 4; j < len(f); j += 2 {
				dp, err := required(f[j], "price delta")
				if err != nil {
					return Entry{}, fmt.Errorf("raw point %d: %w", i+1, err)
				}
				q, err := required(f[j+1], "units")
				if err != nil {
					return Entry{}, fmt.Errorf("raw point %d: %w", i+1, err)
				}
				prevPrice += unzig(dp)
				p.Tiers = append(p.Tiers, Tier{Price: prevPrice, Qty: q})
			}
			e.Raw = append(e.Raw, p)
		}
	}
	if parts[2] != "" {
		var prevDay int64
		for i, text := range strings.Split(parts[2], ";") {
			f := strings.Split(text, ",")
			if len(f) != 8 {
				return Entry{}, malformed("day %d: want 8 fields, got %d", i+1, len(f))
			}
			dd, err := required(f[0], "day delta")
			if err != nil {
				return Entry{}, fmt.Errorf("day %d: %w", i+1, err)
			}
			prevDay += unzig(dd)
			var vals [8]*int64
			for j := 1; j < 8; j++ {
				if vals[j], err = num(f[j]); err != nil {
					return Entry{}, fmt.Errorf("day %d: %w", i+1, err)
				}
			}
			var lo int64
			if vals[1] != nil {
				lo = *vals[1]
			}
			d := Day{Lo: vals[1], QtyMax: vals[4], ListMax: vals[5], N: vals[6], Gone: vals[7]}
			if vals[2] != nil {
				d.Typ = Int(lo + unzig(*vals[2]))
			}
			if vals[3] != nil {
				d.Hi = Int(lo + unzig(*vals[3]))
			}
			e.Days[prevDay] = d
		}
	}
	return e, nil
}

// DecodeLast reads only `last` of a packed entry (Market.lua PackedLast), nil when it has none.
func DecodeLast(s string) (*Last, error) {
	head, _, ok := strings.Cut(s, "|")
	if !ok {
		return nil, malformed("no '|' in %q", s)
	}
	if head == "" {
		return nil, nil
	}
	e, err := Decode(head + "||")
	if err != nil {
		return nil, err
	}
	return e.Last, nil
}
