package upload

import (
	"context"
	"errors"
	"fmt"
	"time"
)

// Result of sending a plan.
type Result struct {
	Sent   int            // requests the server accepted
	Failed int            // requests not sent or refused
	Counts map[string]int // what the accepted requests carried
	Errors []error
	// RetryAt is set when a refusal said to come back later (or retries ran out).
	RetryAt time.Time
}

// TooLarge reports a result whose failure was a 413 (body too large): split and send again.
func TooLarge(r Result) bool {
	for _, e := range r.Errors {
		var h *HTTPError
		if errors.As(e, &h) && h.Status == 413 {
			return true
		}
	}
	return false
}

// OK reports a result without errors.
func (r Result) OK() bool { return len(r.Errors) == 0 }

// Send posts the plan's requests in order: the public ones, then the private ones. After each
// accepted request the state records it and is saved, so an interrupted upload continues where it
// stopped. A failed request stops the rest of its endpoint (later price records can depend on
// earlier ones); the other endpoint is still tried.
func Send(ctx context.Context, c *Client, plan *Plan, st *State, save func(*State) error, logf func(string, ...any)) Result {
	res := Result{Counts: map[string]int{}}
	send := func(name, path string, n int, body func(int) any, commit func(int), summary func(int) string, counts func(int) map[string]int) {
		for i := 0; i < n; i++ {
			resp, err := c.Post(ctx, path, body(i))
			if err != nil {
				res.Failed += n - i
				res.Errors = append(res.Errors, fmt.Errorf("%s request %d/%d (%s): %w", name, i+1, n, summary(i), err))
				var later *RetryLater
				if errors.As(err, &later) && (res.RetryAt.IsZero() || later.At.Before(res.RetryAt)) {
					res.RetryAt = later.At
				}
				return
			}
			commit(i)
			st.LastSuccess = time.Now().Unix()
			if err := save(st); err != nil {
				res.Errors = append(res.Errors, fmt.Errorf("saving the upload state: %w", err))
			}
			res.Sent++
			for k, v := range counts(i) {
				res.Counts[k] += v
			}
			rows := "?"
			if resp.RowsWritten != nil {
				rows = fmt.Sprint(*resp.RowsWritten)
			}
			logf("%s request %d/%d accepted: %s (%s rows written)", name, i+1, n, summary(i), rows)
		}
	}
	pub, priv := plan.Public, plan.Private
	send("public", PublicPath, len(pub),
		func(i int) any { return pub[i].Body },
		func(i int) { pub[i].Commit(st) },
		func(i int) string { return pub[i].Summary() },
		func(i int) map[string]int { return pub[i].Counts })
	if ctx.Err() == nil {
		send("private", PrivatePath, len(priv),
			func(i int) any { return priv[i].Body },
			func(i int) { priv[i].Commit(st) },
			func(i int) string { return priv[i].Summary() },
			func(i int) map[string]int { return priv[i].Counts })
	}
	return res
}
