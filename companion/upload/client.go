package upload

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// Endpoints relative to the site URL.
const (
	PublicPath  = "/api/upload"
	PrivatePath = "/api/private/upload"
)

// Client sends upload requests with the bearer token, retrying what can succeed later.
type Client struct {
	Site      string // e.g. https://wow.velikopter.com
	Token     string
	UserAgent string
	HTTP      *http.Client

	// Retries: up to Attempts tries, waiting Backoff, 2x, 4x ... (at most MaxBackoff, with up to
	// 20% jitter) between them. A Retry-After the server sends is used instead when it is at most
	// MaxWait; a longer one ends the upload with a *RetryLater error.
	Attempts   int
	Backoff    time.Duration
	MaxBackoff time.Duration
	MaxWait    time.Duration

	// Sleep waits (tests replace it); it returns early with ctx's error.
	Sleep func(ctx context.Context, d time.Duration) error
}

// NewClient has the defaults: 5 attempts, 2 s first backoff, 60 s cap, Retry-After up to 2 min.
func NewClient(site, token, userAgent string) *Client {
	return &Client{
		Site:       strings.TrimRight(site, "/"),
		Token:      token,
		UserAgent:  userAgent,
		HTTP:       &http.Client{Timeout: 60 * time.Second},
		Attempts:   5,
		Backoff:    2 * time.Second,
		MaxBackoff: 60 * time.Second,
		MaxWait:    2 * time.Minute,
	}
}

// HTTPError is a refused request that retrying won't fix (bad token, bad shape, too large).
type HTTPError struct {
	Status  int
	Code    string
	Message string
}

func (e *HTTPError) Error() string {
	if e.Code != "" {
		return fmt.Sprintf("HTTP %d %s: %s", e.Status, e.Code, e.Message)
	}
	return fmt.Sprintf("HTTP %d: %s", e.Status, e.Message)
}

// RetryLater is a refusal with a long Retry-After (rate limit, daily write budget) or retries
// used up on a temporary failure. At is when to try again.
type RetryLater struct {
	At  time.Time
	Err error
}

func (e *RetryLater) Error() string {
	return fmt.Sprintf("%v (next try %s)", e.Err, e.At.Local().Format("15:04"))
}
func (e *RetryLater) Unwrap() error { return e.Err }

func sleepCtx(ctx context.Context, d time.Duration) error {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

// Post sends body as JSON to path and decodes the success answer.
func (c *Client) Post(ctx context.Context, path string, body any) (*Response, error) {
	data, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	if len(data) > MaxBodyBytes {
		return nil, fmt.Errorf("request body %d bytes, over the server's %d", len(data), MaxBodyBytes)
	}
	sleep := c.Sleep
	if sleep == nil {
		sleep = sleepCtx
	}
	backoff := c.Backoff
	var lastErr error
	for attempt := 1; ; attempt++ {
		resp, wait, err := c.once(ctx, path, data)
		if err == nil {
			return resp, nil
		}
		var herr *HTTPError
		if errors.As(err, &herr) && wait < 0 {
			return nil, err // permanent
		}
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		lastErr = err
		if wait > c.MaxWait {
			return nil, &RetryLater{At: time.Now().Add(wait), Err: err}
		}
		if attempt >= c.Attempts {
			return nil, &RetryLater{At: time.Now().Add(c.MaxBackoff), Err: fmt.Errorf("%d attempts: %w", attempt, lastErr)}
		}
		if wait <= 0 {
			wait = backoff + time.Duration(rand.Int63n(int64(backoff)/5+1))
			backoff *= 2
			if backoff > c.MaxBackoff {
				backoff = c.MaxBackoff
			}
		}
		if err := sleep(ctx, wait); err != nil {
			return nil, err
		}
	}
}

// once sends one request. wait < 0: permanent failure; 0: retry with backoff; > 0: Retry-After.
func (c *Client) once(ctx context.Context, path string, data []byte) (*Response, time.Duration, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.Site+path, bytes.NewReader(data))
	if err != nil {
		return nil, -1, &HTTPError{Message: err.Error()}
	}
	req.Header.Set("Authorization", "Bearer "+c.Token)
	req.Header.Set("Content-Type", "application/json")
	if c.UserAgent != "" {
		req.Header.Set("User-Agent", c.UserAgent)
	}
	res, err := c.HTTP.Do(req)
	if err != nil {
		return nil, 0, err // network: retry
	}
	defer res.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if err != nil {
		return nil, 0, err
	}
	if res.StatusCode >= 200 && res.StatusCode < 300 {
		var out Response
		if err := json.Unmarshal(raw, &out); err != nil || !out.OK {
			return nil, -1, &HTTPError{Status: res.StatusCode, Message: "unexpected answer: " + snippet(raw)}
		}
		return &out, 0, nil
	}
	var eb ErrorBody
	_ = json.Unmarshal(raw, &eb)
	herr := &HTTPError{Status: res.StatusCode, Code: eb.Error, Message: eb.Message}
	if herr.Message == "" {
		herr.Message = snippet(raw)
	}
	switch {
	case res.StatusCode == http.StatusTooManyRequests || res.StatusCode == http.StatusServiceUnavailable:
		return nil, retryAfter(res.Header.Get("Retry-After")), herr
	case res.StatusCode == http.StatusRequestTimeout || res.StatusCode >= 500:
		return nil, 0, herr
	}
	return nil, -1, herr
}

// retryAfter reads Retry-After in seconds (or an HTTP date); 0 when absent or unreadable.
func retryAfter(v string) time.Duration {
	v = strings.TrimSpace(v)
	if v == "" {
		return 0
	}
	if s, err := strconv.Atoi(v); err == nil && s >= 0 {
		return time.Duration(s) * time.Second
	}
	if t, err := http.ParseTime(v); err == nil {
		if d := time.Until(t); d > 0 {
			return d
		}
	}
	return 0
}

func snippet(b []byte) string {
	s := strings.TrimSpace(string(b))
	if len(s) > 200 {
		s = s[:200] + "..."
	}
	if s == "" {
		return "empty answer"
	}
	return s
}
