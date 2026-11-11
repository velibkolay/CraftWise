package svparse

import (
	"errors"
	"fmt"
	"math"
	"strings"
	"testing"
)

// The layout the game writes: tab-indented, ["key"] = value, list items with -- [n] comments.
const sample = `
CraftWiseDB = {
	["v"] = 1,
	["snapshots"] = {
		["Realm 8 PvP-Velikopter Tanner"] = {
			["t"] = 1794000000,
			["char"] = {
				["name"] = "Velikopter",
				["guild"] = false,
				["money"] = 123456,
				["x"] = 0.2543,
			},
			["list"] = {
				"first", -- [1]
				"second", -- [2]
				{
					["text"] = "Kill 5 \"boars\"\n\\done",
				}, -- [3]
			},
		},
	},
	[12345] = "number key",
	[-2] = -0.5,
	["big"] = 1e+15,
	["hex"] = 0x1F,
}
CraftWiseMarketDB = nil
CraftWiseCharDB = {
}
`

func TestParseSavedVariablesLayout(t *testing.T) {
	f, err := Parse(strings.NewReader(sample))
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(f.Names, ","); got != "CraftWiseDB,CraftWiseMarketDB,CraftWiseCharDB" {
		t.Fatalf("names %q", got)
	}
	if v, ok := f.Values["CraftWiseMarketDB"]; !ok || v != nil {
		t.Fatalf("CraftWiseMarketDB = %v, %v", v, ok)
	}
	if tbl, ok := f.Get("CraftWiseCharDB").(*Table); !ok || tbl.Len() != 0 {
		t.Fatalf("empty table: %#v", f.Get("CraftWiseCharDB"))
	}
	db := f.Get("CraftWiseDB").(*Table)
	if db.Get("v") != 1.0 {
		t.Fatalf("v = %v", db.Get("v"))
	}
	if db.Get(12345) != "number key" || db.Get(int64(12345)) != "number key" {
		t.Fatalf("number key: %v", db.Get(12345))
	}
	if db.Get(-2) != -0.5 || db.Get("big") != 1e15 || db.Get("hex") != 31.0 {
		t.Fatalf("numbers: %v %v %v", db.Get(-2), db.Get("big"), db.Get("hex"))
	}
	snap := db.Get("snapshots").(*Table).Get("Realm 8 PvP-Velikopter Tanner").(*Table)
	char := snap.Get("char").(*Table)
	if char.Get("guild") != false || char.Get("x") != 0.2543 || char.Get("money") != 123456.0 {
		t.Fatalf("char: %v %v %v", char.Get("guild"), char.Get("x"), char.Get("money"))
	}
	list := snap.Get("list").(*Table)
	if list.ArrayLen() != 3 || list.Get(1) != "first" || list.Get(2) != "second" {
		t.Fatalf("list: %d %v", list.ArrayLen(), list.Array())
	}
	if got := list.Get(3).(*Table).Get("text"); got != "Kill 5 \"boars\"\n\\done" {
		t.Fatalf("escapes: %q", got)
	}
	// File order is kept.
	var keys []string
	for _, field := range db.Fields() {
		keys = append(keys, fmt.Sprint(field.Key))
	}
	if strings.Join(keys, ",") != "v,snapshots,12345,-2,big,hex" {
		t.Fatalf("order %v", keys)
	}
}

func TestStrings(t *testing.T) {
	cases := map[string]string{
		`"plain"`:                  "plain",
		`'single "q"'`:             `single "q"`,
		`"tab\tbell\a\b\f\v\r"`:    "tab\tbell\a\b\f\v\r",
		`"dec \65\066\0677\0"`:     "dec AB" + "C7" + "\x00",
		`"high \255\200"`:          "high \xff\xc8",
		"\"q-escape\\\nnext\"":     "q-escape\nnext", // string.format("%q") writes a line break so
		"\"crlf\\\r\nnext\"":       "crlf\nnext",
		`"unknown \x \q"`:          "unknown x q", // Lua 5.1: the character itself
		`"utf8 Kılıç Çelik"`:       "utf8 Kılıç Çelik",
		"[[long\n]]":               "long\n",
		"[[\nfirst line dropped]]": "first line dropped",
		"[==[with ]] inside]==]":   "with ]] inside",
		`"|cffffffff|Hitem:2589::::::::20:::::::::|h[Linen Cloth]|h|r"`: "|cffffffff|Hitem:2589::::::::20:::::::::|h[Linen Cloth]|h|r",
	}
	for src, want := range cases {
		got, err := ParseString(src)
		if err != nil {
			t.Errorf("%s: %v", src, err)
			continue
		}
		if got != want {
			t.Errorf("%s: got %q want %q", src, got, want)
		}
	}
}

func TestNumbers(t *testing.T) {
	cases := map[string]float64{
		"0": 0, "42": 42, "-7": -7, "- 7": -7, "3.25": 3.25, ".5": 0.5, "5.": 5, "1e3": 1000, "1E-2": 0.01,
		"2.5e+2": 250, "0xff": 255, "0XA": 10, "9007199254740993": 9007199254740992, "1794000000": 1794000000,
		"-1.5e308": -1.5e308, "1e400": math.Inf(1),
	}
	for src, want := range cases {
		got, err := ParseString(src)
		if err != nil {
			t.Errorf("%s: %v", src, err)
			continue
		}
		if got != want {
			t.Errorf("%s: got %v want %v", src, got, want)
		}
	}
}

func TestComments(t *testing.T) {
	src := `-- header
	X = { --[[ block
	comment ]] 1, --[==[ another ]==] 2, -- [2]
	-- trailing
	}
	Y = 3; Z = "a--b"`
	f, err := Parse(strings.NewReader(src))
	if err != nil {
		t.Fatal(err)
	}
	x := f.Get("X").(*Table)
	if x.ArrayLen() != 2 || x.Get(2) != 2.0 || f.Get("Y") != 3.0 || f.Get("Z") != "a--b" {
		t.Fatalf("got %v %v %v", x.Array(), f.Get("Y"), f.Get("Z"))
	}
}

func TestTableForms(t *testing.T) {
	v, err := ParseString(`{ name = "n", ["k"] = true, [true] = "yes", nil, false, 7; [10] = nil, }`)
	if err != nil {
		t.Fatal(err)
	}
	tbl := v.(*Table)
	if tbl.Get("name") != "n" || tbl.Get("k") != true || tbl.Get(true) != "yes" {
		t.Fatalf("keys: %v", tbl.Fields())
	}
	// nil takes position 1 without storing anything, as in Lua.
	if tbl.Has(1) || tbl.Get(2) != false || tbl.Get(3) != 7.0 || tbl.Has(10) {
		t.Fatalf("positional: %v", tbl.Fields())
	}
	if tbl.ArrayLen() != 0 {
		t.Fatalf("array len %d", tbl.ArrayLen())
	}
	sorted := tbl.SortedFields()
	if sorted[0].Key != 2.0 || sorted[2].Key != "k" || sorted[4].Key != true {
		t.Fatalf("sorted %v", sorted)
	}
}

func TestDuplicateKeyLastWins(t *testing.T) {
	v, err := ParseString(`{ ["a"] = 1, ["b"] = 2, ["a"] = 3, ["b"] = nil }`)
	if err != nil {
		t.Fatal(err)
	}
	tbl := v.(*Table)
	if tbl.Get("a") != 3.0 || tbl.Has("b") || tbl.Len() != 1 {
		t.Fatalf("%v", tbl.Fields())
	}
}

func TestSyntaxErrors(t *testing.T) {
	cases := map[string]string{
		`X = {`:               "unfinished table",
		`X = "abc`:            "unfinished string",
		"X = \"a\nb\"":        "unfinished string (line break)",
		`X = { 1 2 }`:         "expected ',' or '}'",
		`X = function() end`:  "unexpected name",
		`X = inf`:             "unexpected name",
		`X = 1.2.3`:           "malformed number",
		`X = 12abc`:           "malformed number",
		`X = { [nil] = 1 }`:   "table key is nil",
		`X = { [{}] = 1 }`:    "table key is a table",
		`X = "\300"`:          "escape sequence too large",
		`= 5`:                 "expected a global name",
		`X 5`:                 "expected '='",
		`local X = 5`:         "unexpected \"local\"",
		`X = [==[ open`:       "unfinished long string",
		`X = { a 1 }`:         "expected '=' after a",
		`X = { ["a"] 1 }`:     "expected '=' after the key",
		"X = 1\nY = { 1, ] }": "line 2 col 10",
	}
	for src, want := range cases {
		_, err := Parse(strings.NewReader(src))
		var se *SyntaxError
		if err == nil || !errors.As(err, &se) {
			t.Errorf("%q: want syntax error, got %v", src, err)
			continue
		}
		if !strings.Contains(err.Error(), want) {
			t.Errorf("%q: error %q lacks %q", src, err, want)
		}
	}
}

func TestDepthLimit(t *testing.T) {
	src := "X = " + strings.Repeat("{", MaxDepth+1) + strings.Repeat("}", MaxDepth+1)
	if _, err := Parse(strings.NewReader(src)); err == nil || !strings.Contains(err.Error(), "nested too deep") {
		t.Fatalf("got %v", err)
	}
	ok := "X = " + strings.Repeat("{", MaxDepth) + strings.Repeat("}", MaxDepth)
	if _, err := Parse(strings.NewReader(ok)); err != nil {
		t.Fatal(err)
	}
}

// A file of several MB (2.6 MB here) parses in one pass: 50,000 items like CraftWiseMarketDB.items.
func TestLargeFile(t *testing.T) {
	var b strings.Builder
	b.WriteString("CraftWiseMarketDB = {\n\t[\"items\"] = {\n")
	for i := 0; i < 50000; i++ {
		fmt.Fprintf(&b, "\t\t[%d] = {\n\t\t\t[\"PvP|H\"] = \"%s,%s,a,3||\",\n\t\t},\n", 20000+i, "tqk7c0", "1z")
	}
	b.WriteString("\t},\n}\n")
	if b.Len() < 2_500_000 {
		t.Fatalf("fixture only %d bytes", b.Len())
	}
	f, err := Parse(strings.NewReader(b.String()))
	if err != nil {
		t.Fatal(err)
	}
	items := f.Get("CraftWiseMarketDB").(*Table).Get("items").(*Table)
	if items.Len() != 50000 || items.Get(69999).(*Table).Get("PvP|H") != "tqk7c0,1z,a,3||" {
		t.Fatalf("items %d", items.Len())
	}
}
