package upload

import (
	"fmt"
	"math"
	"sort"

	"github.com/velibkolay/CraftWise/companion/savedvars"
)

const craftedChunk = 500 // rows per unit: a request holds several, a failed one resends little

func craftedKey(char string, recipe, day int64) string {
	return fmt.Sprintf("%s\x1f%d\x1f%d", char, recipe, day)
}

// validDay reports a local day written as YYYYMMDD (2020 to 2100, month and day in range).
func validDay(d int64) bool {
	y, m, dd := d/10000, d/100%100, d%100
	return y >= 2020 && y <= 2100 && m >= 1 && m <= 12 && dd >= 1 && dd <= 31
}

// crafted sends the craft log days (#266) whose hash differs from the one sent: one row per
// character, recipe and day. Values the addon didn't record (profit and time of older days) are
// left out; a value that doesn't fit is dropped, never guessed.
func (d *delta) crafted(c *savedvars.Crafted) []unit[PrivatePayload] {
	if c == nil {
		return nil
	}
	type pending struct {
		row  CraftedRow
		key  string
		hash uint64
	}
	var rows []pending
	chars := make([]string, 0, len(c.Chars))
	for ch := range c.Chars {
		chars = append(chars, ch)
	}
	sort.Strings(chars)
	for _, ch := range chars {
		if !validChar(ch) {
			d.skip("craft log of an invalid character key")
			continue
		}
		for recipe, rec := range c.Chars[ch] {
			for day, v := range rec.Days {
				if v.Crafts != nil && *v.Crafts == 0 {
					continue // nothing crafted that day
				}
				if recipe < 1 || !validDay(day) || v.Crafts == nil || *v.Crafts < 1 {
					d.skip("craft log day without a valid recipe, day or craft count")
					continue
				}
				row := CraftedRow{C: ch, R: recipe, D: day, N: *v.Crafts}
				if v.Items != nil && *v.Items >= 0 {
					row.I = v.Items
				}
				if v.Profit != nil && !math.IsNaN(*v.Profit) && math.Abs(*v.Profit) < 1e12 {
					p := int64(math.Round(*v.Profit))
					row.P = &p
				}
				if v.Known != nil && *v.Known >= 0 && *v.Known <= row.N {
					row.K = v.Known
				}
				if v.Active != nil && *v.Active >= 0 && *v.Active <= 86400 {
					a := math.Round(*v.Active*100) / 100
					row.A = &a
				}
				key := craftedKey(ch, recipe, day)
				h := hashJSON(row)
				if d.st.Crafted[key] == h {
					continue
				}
				rows = append(rows, pending{row, key, h})
			}
		}
	}
	sort.Slice(rows, func(i, j int) bool {
		a, b := rows[i].row, rows[j].row
		if a.D != b.D {
			return a.D < b.D
		}
		if a.C != b.C {
			return a.C < b.C
		}
		return a.R < b.R
	})
	var units []unit[PrivatePayload]
	for start := 0; start < len(rows); start += craftedChunk {
		chunk := rows[start:min(start+craftedChunk, len(rows))]
		out := make([]CraftedRow, len(chunk))
		bytes := 0
		for i, p := range chunk {
			out[i] = p.row
			bytes += size(p.row)
		}
		units = append(units, unit[PrivatePayload]{
			add:  func(p *PrivatePayload) { p.Crafted = append(p.Crafted, out...) },
			kind: "crafted", count: len(out), bytes: bytes,
			commit: func(st *State) {
				for _, p := range chunk {
					st.Crafted[p.key] = p.hash
				}
			},
		})
	}
	return units
}
