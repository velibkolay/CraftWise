package syncdata

import (
	"context"
	"fmt"
	"net/url"
	"time"

	"github.com/velibkolay/CraftWise/companion/upload"
)

// MarketPath is the site's download endpoint (#238; web/docs/api.md).
const MarketPath = "/api/sync/market"

// page is one answer: the body of POST /api/upload, plus the server time the answer is valid up to
// and, when the download is split, the cursor of the next page.
type page struct {
	upload.PublicPayload
	Until int64  `json:"until"`
	Next  string `json:"next"`
}

// maxPages stops a server that never ends a download.
const maxPages = 500

// Download asks for everything that changed after since and follows the pages. It returns the
// merged answer and the time to ask from next time (the server's own `until`, else the time the
// request started minus a minute).
func Download(ctx context.Context, c *upload.Client, since int64, now func() time.Time) (*upload.PublicPayload, int64, error) {
	if now == nil {
		now = time.Now
	}
	started := now().Unix()
	all := NewCache("")
	var until int64
	cursor := ""
	for i := 0; ; i++ {
		if i >= maxPages {
			return nil, 0, fmt.Errorf("download: more than %d pages", maxPages)
		}
		q := url.Values{"since": {fmt.Sprint(since)}}
		if cursor != "" {
			q.Set("cursor", cursor)
		}
		var pg page
		if err := c.GetJSON(ctx, MarketPath+"?"+q.Encode(), &pg); err != nil {
			return nil, 0, err
		}
		if pg.V != 0 && pg.V != upload.Version {
			return nil, 0, fmt.Errorf("download: the site answered format version %d, this companion reads %d: update the companion", pg.V, upload.Version)
		}
		all.Merge(&pg.PublicPayload)
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
	return all.Market, until, nil
}

// Empty reports a download with nothing in it.
func Empty(p *upload.PublicPayload) bool {
	return len(p.Houses) == 0 && len(p.Scans) == 0 && len(p.Names) == 0 && len(p.ItemInfo) == 0 &&
		len(p.Items) == 0 && len(p.ClassNames) == 0 && len(p.SubclassNames) == 0
}
