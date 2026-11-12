package upload

import "fmt"

// Batch is one request: its body, the size and D1 rows the server will estimate for it, and what
// to record in the state once the server accepted it.
type Batch[T any] struct {
	Body    T
	Bytes   int // approximate body size
	Rows    int // the server's upper-bound estimate of rows written
	Counts  map[string]int
	commits []func(*State)
}

// Commit records the batch as uploaded.
func (b *Batch[T]) Commit(st *State) {
	st.init()
	for _, c := range b.commits {
		c(st)
	}
}

// Summary is a short description for the log, e.g. "12 prices, 3 scans".
func (b *Batch[T]) Summary() string {
	out := ""
	for _, k := range []string{"scans", "classes", "items", "prices", "snapshots", "auctions", "fishing", "ledger"} {
		if n := b.Counts[k]; n > 0 {
			if out != "" {
				out += ", "
			}
			out += fmt.Sprintf("%d %s", n, k)
		}
	}
	if out == "" {
		return "nothing"
	}
	return out
}

const envelopeBytes = 96 // {"v":1,"houses":{},"items":{}...} keys and brackets

// packPublic fills requests in order. Every request carries all houses (the contract asks for it;
// there are at most 20). Low-priority units (item info, class names) never share a request with
// scans or prices, so a soft-limit refusal of theirs holds back nothing else (#145).
func packPublic(units []unit[PublicPayload], houses map[string]House, opt Options, skip func(string)) []*Batch[PublicPayload] {
	var out []*Batch[PublicPayload]
	var cur *Batch[PublicPayload]
	var keys map[string]bool
	low := false // the current request carries low-priority units
	base := envelopeBytes + size(houses)
	full := func(u unit[PublicPayload]) bool {
		c := cur.Counts
		return cur.Bytes+u.bytes > opt.MaxBytes || cur.Rows+u.rows > opt.MaxRows ||
			(u.kind == "prices" && c["prices"] >= MaxPriceEntries) ||
			(u.kind == "items" && c["items"] >= MaxItems) ||
			(u.kind == "scans" && c["scans"] >= MaxScans) ||
			(u.kind == "classes" && c["classes"] >= MaxClassNames) ||
			(u.key != "" && keys[u.key]) ||
			lowPriority(u.kind) != low
	}
	for _, u := range units {
		if u.add == nil {
			continue
		}
		if base+u.bytes+1024 > MaxBodyBytes {
			skip(u.kind + " record too large for one request")
			continue
		}
		if cur == nil || (len(cur.commits) > 0 && full(u)) {
			cur = &Batch[PublicPayload]{
				Body:   PublicPayload{V: Version, Houses: houses},
				Bytes:  base,
				Counts: map[string]int{},
			}
			keys = map[string]bool{}
			low = lowPriority(u.kind)
			out = append(out, cur)
		}
		u.add(&cur.Body)
		cur.Bytes += u.bytes
		cur.Rows += u.rows
		if u.key != "" {
			keys[u.key] = true
		}
		cur.Counts[u.kind]++
		cur.commits = append(cur.commits, u.commit)
	}
	return out
}

func packPrivate(units []unit[PrivatePayload], opt Options, skip func(string)) []*Batch[PrivatePayload] {
	var out []*Batch[PrivatePayload]
	var cur *Batch[PrivatePayload]
	for _, u := range units {
		if u.bytes+envelopeBytes+1024 > MaxBodyBytes {
			skip(u.kind + " document too large for one request")
			continue
		}
		full := cur == nil || cur.Bytes+u.bytes > opt.MaxBytes
		if !full && u.kind == "ledger" {
			full = cur.Counts["ledger"]+u.count > MaxLedgerEntries
		} else if !full {
			full = cur.Counts[u.kind] >= MaxCharacters
		}
		if full && (cur == nil || len(cur.commits) > 0) {
			cur = &Batch[PrivatePayload]{Body: PrivatePayload{V: Version}, Bytes: envelopeBytes, Counts: map[string]int{}}
			out = append(out, cur)
		}
		u.add(&cur.Body)
		cur.Bytes += u.bytes
		cur.Counts[u.kind] += u.count
		cur.commits = append(cur.commits, u.commit)
	}
	return out
}
