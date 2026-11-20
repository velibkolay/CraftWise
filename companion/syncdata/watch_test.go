package syncdata

import (
	"strings"
	"testing"

	"github.com/velibkolay/CraftWise/companion/upload"
)

// #244: the same changes in any order give the same list: the newest change wins, a tie keeps the item.
func TestMergeWatchRule(t *testing.T) {
	changes := []upload.WatchItem{
		{I: 1, T: 100}, {I: 1, T: 200, D: true}, {I: 2, T: 50, D: true}, {I: 2, T: 50}, {I: 3, T: 10, D: true}, {I: 0, T: 5}, {I: 4, T: 0},
	}
	forward, backward := NewCache("s"), NewCache("s")
	forward.MergeWatch(changes)
	for i := len(changes) - 1; i >= 0; i-- {
		backward.MergeWatch(changes[i : i+1])
	}
	want := map[int64]WatchState{1: {T: 200, Gone: true}, 2: {T: 50}, 3: {T: 10, Gone: true}}
	for _, c := range []*Cache{forward, backward} {
		if len(c.Watch) != len(want) {
			t.Fatalf("%v", c.Watch)
		}
		for id, w := range want {
			if c.Watch[id] != w {
				t.Errorf("item %d: %v, want %v", id, c.Watch[id], w)
			}
		}
	}
}

func TestRenderWatchFile(t *testing.T) {
	written := int64(1794010000)
	w := map[int64]WatchState{
		9: {T: written - 5},
		2: {T: written - 100},
		5: {T: written - 100, Gone: true},
		6: {T: written - (WatchKeepDays+1)*86400, Gone: true}, // an old tombstone is left out
	}
	text := string(Render(File{Written: written, Machine: "PC", Watch: w}))
	want := "  watch = {\n    [2] = 1794009900,\n    [9] = 1794009995,\n  },\n  watchGone = {\n    [5] = 1794009900,\n  },\n"
	if !strings.Contains(text, want) {
		t.Errorf("file lacks the lists:\n%s", text)
	}
	if string(Render(File{Written: written, Machine: "PC", Watch: w})) != text {
		t.Error("not deterministic")
	}
	// no list (private data off): the addon is left alone
	if strings.Contains(string(Render(File{Written: written, Machine: "PC"})), "watch") {
		t.Error("a watch list was written without one")
	}
	// an empty list is written as empty tables
	if !strings.Contains(string(Render(File{Written: written, Machine: "PC", Watch: map[int64]WatchState{}})), "  watch = {\n  },\n  watchGone = {\n  },\n") {
		t.Error("empty list")
	}
}
