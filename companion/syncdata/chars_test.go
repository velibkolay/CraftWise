package syncdata

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDownloadCharsFollowsPagesAndSendsTheMachine(t *testing.T) {
	var queries []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer cw_test" || r.URL.Path != CharsPath {
			http.Error(w, "no", 401)
			return
		}
		queries = append(queries, r.URL.RawQuery)
		if r.URL.Query().Get("cursor") == "" {
			fmt.Fprint(w, `{"v":1,"characters":{"R-A":{"machine":"Mac","uploaded":10,"ledger":[]}},"next":"c.10.Ui1B","until":500}`)
			return
		}
		fmt.Fprint(w, `{"v":1,"characters":{"R-B":{"uploaded":11}},"next":null,"until":500}`)
	}))
	defer srv.Close()
	got, until, err := DownloadChars(context.Background(), client(srv), 123, "PC", nil)
	if err != nil {
		t.Fatal(err)
	}
	if until != 500 || len(got) != 2 || got["R-A"].Machine != "Mac" || got["R-B"].Machine != "" {
		t.Errorf("until %d chars %+v", until, got)
	}
	if len(queries) != 2 || queries[0] != "notMachine=PC&since=123" || queries[1] != "cursor=c.10.Ui1B&notMachine=PC&since=123" {
		t.Errorf("queries %v", queries)
	}
	newer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"v":2}`) }))
	defer newer.Close()
	if _, _, err := DownloadChars(context.Background(), client(newer), 0, "", nil); err == nil || !strings.Contains(err.Error(), "update the companion") {
		t.Errorf("err = %v", err)
	}
}

func TestCharsCacheKeepsOwnOut(t *testing.T) {
	c := NewCache("s")
	c.MergeChars(map[string]Char{"R-Mine": {Machine: "PC"}, "R-Theirs": {Machine: "Mac", Uploaded: 1}}, map[string]bool{"R-Mine": true})
	if len(c.Chars) != 1 || c.Chars["R-Theirs"].Uploaded != 1 {
		t.Errorf("merged %+v", c.Chars)
	}
	// a whole new copy replaces the old one
	c.MergeChars(map[string]Char{"R-Theirs": {Machine: "Mac", Uploaded: 2}}, nil)
	if c.Chars["R-Theirs"].Uploaded != 2 {
		t.Error("not replaced")
	}
	// later it turns out to be this machine's character, or its machine name
	c.Chars["R-Mine"] = Char{Machine: "Mac"}
	c.Chars["R-Named"] = Char{Machine: "PC"}
	other := c.OtherChars(map[string]bool{"R-Mine": true}, "PC")
	if len(other) != 1 || other["R-Theirs"].Uploaded != 2 {
		t.Errorf("other chars %+v", other)
	}
}

func TestRenderChars(t *testing.T) {
	var raw Char
	err := json.Unmarshal([]byte(`{"machine":"Mac","uploaded":9,"info":{"name":"Zed","end":"x"},
		"snapshot":{"t":3,"data":{"a b":[1,null,"q\"\n",2.5,true],"nil":null,"n":{"z":false}}},"ledger":[],"crafted":[{"r":1}]}`), &raw)
	if err != nil {
		t.Fatal(err)
	}
	out := string(Render(File{Written: 1, Machine: "PC", Chars: map[string]Char{"R-Zed": raw, "R-Empty": {Uploaded: 4}}}))
	for _, want := range []string{
		"  chars = {\n",
		"    [\"R-Empty\"] = {\n      uploaded = 4,\n    },\n",
		"      machine = \"Mac\",\n",
		`      info = { ["end"] = "x", name = "Zed" },`,
		`      snapshot = { data = { ["a b"] = { 1, false, "q\"` + bs + `010", 2.5, true }, n = { z = false } }, t = 3 },`,
		"      ledger = {},\n",
		"      crafted = { { r = 1 } },\n",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in\n%s", want, out)
		}
	}
	if strings.Contains(out, "nil =") {
		t.Error("a null field was written")
	}
	// an unchanged cache gives the same bytes, so the file isn't rewritten
	if string(Render(File{Written: 1, Machine: "PC", Chars: map[string]Char{"R-Zed": raw, "R-Empty": {Uploaded: 4}}})) != out {
		t.Error("render is not deterministic")
	}
}
