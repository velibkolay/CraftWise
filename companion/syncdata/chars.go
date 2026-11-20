package syncdata

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/velibkolay/CraftWise/companion/upload"
)

// CharsPath is the site's download of the private character data (#242; web/docs/api.md). It needs
// a token with the `private` scope.
const CharsPath = "/api/sync/characters"

// Char is one character of the other machine as the site stored it, kept as the JSON the site sent:
// the companion adds nothing and computes nothing, it passes the data on to CraftWise_Sync.
type Char struct {
	Machine  string          `json:"machine,omitempty"` // the machine that uploaded it (empty: unknown, uploaded before #242)
	Uploaded int64           `json:"uploaded"`          // when, server time
	Info     json.RawMessage `json:"info,omitempty"`    // realm, name, surname, faction, race, class, level, t
	Snapshot json.RawMessage `json:"snapshot,omitempty"` // { t, data }
	Auctions json.RawMessage `json:"auctions,omitempty"` // { t, data }
	Fishing  json.RawMessage `json:"fishing,omitempty"`  // { t, data }
	Ledger   json.RawMessage `json:"ledger,omitempty"`   // [ { t, k, i, q, m, w, n } ], oldest first
	Crafted  json.RawMessage `json:"crafted,omitempty"`  // [ { r, d, n, i, p, k, a } ]
}

// charsPage is one answer of the characters download.
type charsPage struct {
	V          int             `json:"v"`
	Characters map[string]Char `json:"characters"`
	Next       string          `json:"next"`
	Until      int64           `json:"until"`
}

// DownloadChars asks for the characters that were uploaded at or after since and follows the pages.
// notMachine is this machine's name: the site leaves the characters it uploaded out. It returns the
// characters and the time to ask from next time.
func DownloadChars(ctx context.Context, c *upload.Client, since int64, notMachine string, now func() time.Time) (map[string]Char, int64, error) {
	if now == nil {
		now = time.Now
	}
	started := now().Unix()
	all := map[string]Char{}
	var until int64
	cursor := ""
	for i := 0; ; i++ {
		if i >= maxPages {
			return nil, 0, fmt.Errorf("download of the characters: more than %d pages", maxPages)
		}
		q := url.Values{"since": {fmt.Sprint(since)}}
		if notMachine != "" {
			q.Set("notMachine", notMachine)
		}
		if cursor != "" {
			q.Set("cursor", cursor)
		}
		var pg charsPage
		if err := c.GetJSON(ctx, CharsPath+"?"+q.Encode(), &pg); err != nil {
			return nil, 0, err
		}
		if pg.V != 0 && pg.V != upload.Version {
			return nil, 0, fmt.Errorf("download of the characters: the site answered format version %d, this companion reads %d: update the companion", pg.V, upload.Version)
		}
		for k, ch := range pg.Characters {
			all[k] = ch
		}
		if pg.Until > 0 {
			until = pg.Until
		}
		if pg.Next == "" {
			break
		}
		cursor = pg.Next
	}
	if until == 0 {
		until = started - 60
	}
	if until < since {
		until = since
	}
	return all, until, nil
}

// MergeChars puts downloaded characters into the cache: a character comes whole, so it replaces the
// cached one. Characters in own (character keys this machine uploads itself) are skipped: own data
// always wins.
func (c *Cache) MergeChars(got map[string]Char, own map[string]bool) {
	for k, ch := range got {
		if own[k] {
			continue
		}
		if c.Chars == nil {
			c.Chars = map[string]Char{}
		}
		c.Chars[k] = ch
	}
}

// OtherChars is the characters for the sync file: the cached ones without this machine's own (by
// character key and by machine name).
func (c *Cache) OtherChars(own map[string]bool, machine string) map[string]Char {
	out := map[string]Char{}
	for k, ch := range c.Chars {
		if own[k] || (machine != "" && ch.Machine == machine) {
			continue
		}
		out[k] = ch
	}
	return out
}

var luaKeywords = map[string]bool{
	"and": true, "break": true, "do": true, "else": true, "elseif": true, "end": true, "false": true, "for": true,
	"function": true, "if": true, "in": true, "local": true, "nil": true, "not": true, "or": true, "repeat": true,
	"return": true, "then": true, "true": true, "until": true, "while": true,
}

func isLuaName(s string) bool {
	if s == "" || luaKeywords[s] {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (i > 0 && c >= '0' && c <= '9') {
			continue
		}
		return false
	}
	return true
}

// writeLuaJSON writes the JSON value in raw as a Lua value on one line: objects as tables with string
// keys (sorted), arrays as lists, numbers as they are, true and false, strings quoted. A null in an
// object leaves the key out (a missing field); a null in an array becomes false so the list keeps its
// positions. Empty raw writes nothing and reports false.
func writeLuaJSON(b *bytes.Buffer, raw json.RawMessage) (bool, error) {
	if len(bytes.TrimSpace(raw)) == 0 || string(bytes.TrimSpace(raw)) == "null" {
		return false, nil
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		return false, err
	}
	writeLuaValue(b, v)
	return true, nil
}

func writeLuaValue(b *bytes.Buffer, v any) {
	switch x := v.(type) {
	case nil:
		b.WriteString("false")
	case bool:
		if x {
			b.WriteString("true")
		} else {
			b.WriteString("false")
		}
	case json.Number:
		b.WriteString(x.String())
	case string:
		b.WriteString(luaString(x))
	case []any:
		b.WriteByte('{')
		for i, e := range x {
			if i > 0 {
				b.WriteString(", ")
			} else {
				b.WriteByte(' ')
			}
			writeLuaValue(b, e)
		}
		if len(x) > 0 {
			b.WriteByte(' ')
		}
		b.WriteByte('}')
	case map[string]any:
		keys := make([]string, 0, len(x))
		for k, e := range x {
			if e != nil {
				keys = append(keys, k)
			}
		}
		sort.Strings(keys)
		b.WriteByte('{')
		for i, k := range keys {
			if i > 0 {
				b.WriteString(", ")
			} else {
				b.WriteByte(' ')
			}
			if isLuaName(k) {
				b.WriteString(k)
			} else {
				b.WriteString("[" + luaString(k) + "]")
			}
			b.WriteString(" = ")
			writeLuaValue(b, x[k])
		}
		if len(keys) > 0 {
			b.WriteByte(' ')
		}
		b.WriteByte('}')
	}
}

// renderChars writes the `chars` table of CraftWise_Sync (docs/companion.md).
func renderChars(b *bytes.Buffer, chars map[string]Char) {
	b.WriteString("  chars = {\n")
	keys := sortedStrings(chars)
	for _, k := range keys {
		ch := chars[k]
		fmt.Fprintf(b, "    [%s] = {\n", luaString(k))
		if ch.Machine != "" {
			fmt.Fprintf(b, "      machine = %s,\n", luaString(ch.Machine))
		}
		fmt.Fprintf(b, "      uploaded = %d,\n", ch.Uploaded)
		for _, f := range []struct {
			name string
			raw  json.RawMessage
		}{{"info", ch.Info}, {"snapshot", ch.Snapshot}, {"auctions", ch.Auctions}, {"fishing", ch.Fishing}, {"ledger", ch.Ledger}, {"crafted", ch.Crafted}} {
			var line bytes.Buffer
			ok, err := writeLuaJSON(&line, f.raw)
			if err != nil || !ok {
				continue // a field the site didn't send (or sent broken) is missing, never filled in
			}
			fmt.Fprintf(b, "      %s = %s,\n", f.name, strings.TrimSpace(line.String()))
		}
		b.WriteString("    },\n")
	}
	b.WriteString("  },\n")
}
