package syncdata

import (
	"bytes"
	"context"
	"fmt"
	"net/url"
	"sort"
	"time"

	"github.com/velibkolay/CraftWise/companion/upload"
)

// WatchPath is the site's download of the watch list changes (#244; web/docs/api.md). It needs a token
// with the `private` scope.
const WatchPath = "/api/sync/watch"

// WatchKeepDays: a tombstone older than this is not written to the sync file (the addon drops its own
// after the same time).
const WatchKeepDays = 180

// WatchState is the state of one item in the merged watch list: the time of its newest change, and
// whether that change was an unwatch (a tombstone).
type WatchState struct {
	T    int64 `json:"t"`
	Gone bool  `json:"d,omitempty"`
}

type watchPage struct {
	V     int                `json:"v"`
	Watch []upload.WatchItem `json:"watch"`
	Until int64              `json:"until"`
}

// DownloadWatch asks for the watch list changes the site stored at or after since. It returns them and the
// time to ask from next time.
func DownloadWatch(ctx context.Context, c *upload.Client, since int64, now func() time.Time) ([]upload.WatchItem, int64, error) {
	if now == nil {
		now = time.Now
	}
	started := now().Unix()
	var pg watchPage
	if err := c.GetJSON(ctx, WatchPath+"?"+url.Values{"since": {fmt.Sprint(since)}}.Encode(), &pg); err != nil {
		return nil, 0, err
	}
	if pg.V != 0 && pg.V != upload.Version {
		return nil, 0, fmt.Errorf("download of the watch list: the site answered format version %d, this companion reads %d: update the companion", pg.V, upload.Version)
	}
	until := pg.Until
	if until == 0 {
		until = started - 60
	}
	if until < since {
		until = since
	}
	return pg.Watch, until, nil
}

// MergeWatch puts downloaded changes into the cache's list: per item the newest change wins, and on the
// same time "watched" wins (the same rule as the site and the addon, so the order never matters).
func (c *Cache) MergeWatch(changes []upload.WatchItem) {
	for _, ch := range changes {
		if ch.I < 1 || ch.T < 1 {
			continue
		}
		if old, ok := c.Watch[ch.I]; ok && !upload.WatchWins(ch.T, ch.D, old.T, old.Gone) {
			continue
		}
		if c.Watch == nil {
			c.Watch = map[int64]WatchState{}
		}
		c.Watch[ch.I] = WatchState{T: ch.T, Gone: ch.D}
	}
}

// renderWatch writes `watch` and `watchGone` of CraftWise_Sync (docs/companion.md): watch = { [itemID] =
// time watched }, watchGone = { [itemID] = time unwatched } without the tombstones older than WatchKeepDays.
func renderWatch(b *bytes.Buffer, w map[int64]WatchState, written int64) {
	var on, gone []int64
	for id, s := range w {
		switch {
		case !s.Gone:
			on = append(on, id)
		case s.T >= written-WatchKeepDays*86400:
			gone = append(gone, id)
		}
	}
	for _, f := range []struct {
		name string
		ids  []int64
	}{{"watch", on}, {"watchGone", gone}} {
		sort.Slice(f.ids, func(i, j int) bool { return f.ids[i] < f.ids[j] })
		fmt.Fprintf(b, "  %s = {\n", f.name)
		for _, id := range f.ids {
			fmt.Fprintf(b, "    [%d] = %d,\n", id, w[id].T)
		}
		b.WriteString("  },\n")
	}
}
