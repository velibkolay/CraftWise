package svparse

import (
	"strings"
	"testing"
)

type testChar struct {
	Name   string   `json:"name"`
	Level  *int64   `json:"level,omitempty"`
	Money  int64    `json:"money"`
	X      *float64 `json:"x,omitempty"`
	Guild  any      `json:"guild"`
	Hidden string   `json:"-"`
	Alias  string   `lua:"luaName" json:"jsonName"`
}

type testSnap struct {
	T       *int64            `json:"t"`
	Char    *testChar         `json:"char"`
	Skipped map[string]string `json:"skipped"`
	List    []testItem        `json:"list"`
	Counts  map[int64]int64   `json:"counts"`
	Raw     *Table            `json:"raw"`
	Missing *testChar         `json:"missing"`
}

type testItem struct {
	ID   int64  `json:"id"`
	Text string `json:"text"`
}

func TestUnmarshal(t *testing.T) {
	v, err := ParseString(`{
		["t"] = 1794000000,
		["char"] = { ["name"] = "Veli", ["level"] = 23, ["money"] = 5, ["x"] = 0.25, ["guild"] = false,
			["-"] = "x", ["luaName"] = "lua tag wins", ["unknown"] = 1 },
		["skipped"] = { ["pet"] = "no hunter pet out" },
		["list"] = { { ["id"] = 1, ["text"] = "a" }, { ["id"] = 2 }, },
		["counts"] = { [2589] = 20, [783] = 3 },
		["raw"] = { 1, 2 },
	}`)
	if err != nil {
		t.Fatal(err)
	}
	var s testSnap
	if problems := Unmarshal(v, &s); len(problems) != 0 {
		t.Fatal(problems)
	}
	if *s.T != 1794000000 || s.Char.Name != "Veli" || *s.Char.Level != 23 || *s.Char.X != 0.25 || s.Char.Guild != false {
		t.Fatalf("%+v %+v", s, s.Char)
	}
	if s.Char.Alias != "lua tag wins" || s.Char.Hidden != "" {
		t.Fatalf("tags: %+v", s.Char)
	}
	if s.Skipped["pet"] != "no hunter pet out" || len(s.List) != 2 || s.List[1].ID != 2 || s.List[1].Text != "" {
		t.Fatalf("%+v", s)
	}
	if s.Counts[2589] != 20 || s.Counts[783] != 3 || s.Raw.ArrayLen() != 2 || s.Missing != nil {
		t.Fatalf("%+v", s)
	}
}

func TestUnmarshalProblemsLeaveFieldsMissing(t *testing.T) {
	v, err := ParseString(`{
		["t"] = 1.5,
		["char"] = { ["name"] = 7, ["level"] = "twenty", ["money"] = 10 },
		["list"] = "not a list",
		["counts"] = { ["a"] = 1, [2] = 2.5, [3] = 4 },
	}`)
	if err != nil {
		t.Fatal(err)
	}
	var s testSnap
	problems := SortedProblems(Unmarshal(v, &s))
	var got []string
	for _, p := range problems {
		got = append(got, p.String())
	}
	want := []string{
		`char.level: want number, got string`,
		`char.name: want string, got number`,
		`counts["a"]: want an integer key, got string`,
		`counts[2]: want an integer, got 2.5`,
		`list: want table (list), got string`,
		`t: want an integer, got 1.5`,
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("problems:\n%s", strings.Join(got, "\n"))
	}
	// The table with a bad field is kept, the bad fields are missing, the rest is read.
	if s.T != nil || s.Char == nil || s.Char.Level != nil || s.Char.Name != "" || s.Char.Money != 10 {
		t.Fatalf("%+v %+v", s, s.Char)
	}
	if len(s.Counts) != 1 || s.Counts[3] != 4 || s.List != nil {
		t.Fatalf("%+v", s)
	}
}
