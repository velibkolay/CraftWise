package upload

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/velibkolay/CraftWise/companion/savedvars"
)

// server answers with the given statuses in turn (the last one repeats) and records requests.
type server struct {
	mu       sync.Mutex
	answers  []func(w http.ResponseWriter)
	requests []*http.Request
	bodies   []string
}

func ok(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = io.WriteString(w, `{"ok":true,"received":{"prices":1},"rowsWritten":3}`)
}

func fail(status int, code string, retryAfter string) func(http.ResponseWriter) {
	return func(w http.ResponseWriter) {
		if retryAfter != "" {
			w.Header().Set("Retry-After", retryAfter)
		}
		w.WriteHeader(status)
		_, _ = io.WriteString(w, `{"error":"`+code+`","message":"test"}`)
	}
}

func (s *server) start(t *testing.T) *httptest.Server {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		s.mu.Lock()
		n := len(s.requests)
		s.requests = append(s.requests, r)
		s.bodies = append(s.bodies, string(body))
		a := s.answers[len(s.answers)-1]
		if n < len(s.answers) {
			a = s.answers[n]
		}
		s.mu.Unlock()
		a(w)
	}))
	t.Cleanup(ts.Close)
	return ts
}

func testClient(url string, slept *[]time.Duration) *Client {
	c := NewClient(url, "cw_test", "test")
	c.Sleep = func(_ context.Context, d time.Duration) error {
		*slept = append(*slept, d)
		return nil
	}
	return c
}

func TestPostSendsTokenAndJSON(t *testing.T) {
	s := &server{answers: []func(http.ResponseWriter){ok}}
	ts := s.start(t)
	var slept []time.Duration
	resp, err := testClient(ts.URL+"/", &slept).Post(context.Background(), PublicPath, PublicPayload{V: 1, Houses: map[string]House{}})
	if err != nil {
		t.Fatal(err)
	}
	if resp.RowsWritten == nil || *resp.RowsWritten != 3 {
		t.Errorf("response: %+v", resp)
	}
	r := s.requests[0]
	if r.Method != http.MethodPost || r.URL.Path != "/api/upload" || r.Header.Get("Authorization") != "Bearer cw_test" ||
		r.Header.Get("Content-Type") != "application/json" {
		t.Errorf("request: %s %s %v", r.Method, r.URL.Path, r.Header)
	}
	if s.bodies[0] != `{"v":1,"houses":{}}` {
		t.Errorf("body %s", s.bodies[0])
	}
	if len(slept) != 0 {
		t.Errorf("slept %v", slept)
	}
}

func TestPostRetriesServerErrorsWithBackoff(t *testing.T) {
	s := &server{answers: []func(http.ResponseWriter){fail(500, "", ""), fail(502, "", ""), ok}}
	ts := s.start(t)
	var slept []time.Duration
	if _, err := testClient(ts.URL, &slept).Post(context.Background(), PublicPath, map[string]int{"v": 1}); err != nil {
		t.Fatal(err)
	}
	if len(s.requests) != 3 || len(slept) != 2 {
		t.Fatalf("%d requests, slept %v", len(s.requests), slept)
	}
	// 2 s, then 4 s, each with up to 20% jitter.
	if slept[0] < 2*time.Second || slept[0] > 2400*time.Millisecond || slept[1] < 4*time.Second || slept[1] > 4800*time.Millisecond {
		t.Errorf("backoff %v", slept)
	}
}

func TestPostHonoursRetryAfter(t *testing.T) {
	s := &server{answers: []func(http.ResponseWriter){fail(429, "rate_limited", "17"), ok}}
	ts := s.start(t)
	var slept []time.Duration
	if _, err := testClient(ts.URL, &slept).Post(context.Background(), PublicPath, map[string]int{"v": 1}); err != nil {
		t.Fatal(err)
	}
	if len(slept) != 1 || slept[0] != 17*time.Second {
		t.Errorf("slept %v, want 17s", slept)
	}
}

func TestPostLongRetryAfterEndsWithRetryLater(t *testing.T) {
	s := &server{answers: []func(http.ResponseWriter){fail(429, "write_budget", "36000")}}
	ts := s.start(t)
	var slept []time.Duration
	_, err := testClient(ts.URL, &slept).Post(context.Background(), PublicPath, map[string]int{"v": 1})
	var later *RetryLater
	if !errors.As(err, &later) {
		t.Fatalf("err = %v", err)
	}
	if d := time.Until(later.At); d < 9*time.Hour || d > 10*time.Hour {
		t.Errorf("retry at %v", later.At)
	}
	var herr *HTTPError
	if !errors.As(err, &herr) || herr.Code != "write_budget" {
		t.Errorf("wrapped error %v", err)
	}
	if len(s.requests) != 1 || len(slept) != 0 {
		t.Errorf("%d requests, slept %v", len(s.requests), slept)
	}
}

func TestPostDoesNotRetryRefusals(t *testing.T) {
	for _, status := range []int{400, 401, 403, 413} {
		s := &server{answers: []func(http.ResponseWriter){fail(status, "nope", "")}}
		ts := s.start(t)
		var slept []time.Duration
		_, err := testClient(ts.URL, &slept).Post(context.Background(), PublicPath, map[string]int{"v": 1})
		var herr *HTTPError
		if !errors.As(err, &herr) || herr.Status != status || herr.Code != "nope" {
			t.Errorf("%d: err = %v", status, err)
		}
		var later *RetryLater
		if errors.As(err, &later) || len(s.requests) != 1 {
			t.Errorf("%d: retried (%d requests)", status, len(s.requests))
		}
	}
}

func TestPostGivesUpAfterAttempts(t *testing.T) {
	s := &server{answers: []func(http.ResponseWriter){fail(503, "", "")}}
	ts := s.start(t)
	var slept []time.Duration
	c := testClient(ts.URL, &slept)
	_, err := c.Post(context.Background(), PublicPath, map[string]int{"v": 1})
	var later *RetryLater
	if !errors.As(err, &later) {
		t.Fatalf("err = %v", err)
	}
	if len(s.requests) != c.Attempts || len(slept) != c.Attempts-1 {
		t.Errorf("%d requests, %d sleeps", len(s.requests), len(slept))
	}
	for _, d := range slept {
		if d > c.MaxBackoff*12/10 {
			t.Errorf("backoff %v over the cap", d)
		}
	}
}

func TestPostRetriesNetworkErrors(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	url := ts.URL
	ts.Close() // connection refused from now on
	var slept []time.Duration
	c := testClient(url, &slept)
	c.Attempts = 3
	_, err := c.Post(context.Background(), PublicPath, map[string]int{"v": 1})
	var later *RetryLater
	if !errors.As(err, &later) || len(slept) != 2 {
		t.Errorf("err = %v, slept %v", err, slept)
	}
}

func TestSendCommitsPerRequestAndStopsOnFailure(t *testing.T) {
	// Public: request 1 accepted, request 2 refused (400): request 3 is not sent. Private still goes.
	s := &server{answers: []func(http.ResponseWriter){ok, fail(400, "bad_shape", ""), ok}}
	ts := s.start(t)
	var slept []time.Duration
	c := testClient(ts.URL, &slept)

	f := readFixture(t)
	st := NewState("s", "f")
	plan := Build(f, st, Options{Now: fixtureNow, Private: true, MaxBytes: 2000})
	if len(plan.Public) < 3 {
		t.Fatalf("want at least 3 public requests, got %d", len(plan.Public))
	}
	saves := 0
	res := Send(context.Background(), c, plan, st, func(*State) error { saves++; return nil }, func(string, ...any) {})
	if res.Sent != 1+len(plan.Private) || saves != res.Sent {
		t.Errorf("sent %d, saved %d", res.Sent, saves)
	}
	if res.Failed != len(plan.Public)-1 || len(res.Errors) != 1 {
		t.Errorf("failed %d, errors %v", res.Failed, res.Errors)
	}
	if !strings.Contains(s.requests[len(s.requests)-1].URL.Path, "private") {
		t.Error("private requests not sent after a public failure")
	}
	// Request 1 is recorded: the next plan starts after it.
	next := Build(f, st, Options{Now: fixtureNow, Private: true, MaxBytes: 2000})
	if len(next.Public) != len(plan.Public)-1 || len(next.Private) != 0 {
		t.Errorf("next plan: %d public, %d private", len(next.Public), len(next.Private))
	}
	var first PublicPayload
	_ = json.Unmarshal([]byte(s.bodies[0]), &first)
	if first.V != 1 || len(first.Houses) == 0 {
		t.Errorf("first body: %s", s.bodies[0])
	}
}

// #145: above the server's soft write limit item info and class names are refused (429 write_budget,
// Retry-After 00:00 UTC) while price data is still taken. They travel in requests of their own after
// the prices, so every price request is accepted first and only the item info waits.
func TestSendSoftBudgetHoldsBackOnlyItemInfo(t *testing.T) {
	refuseInfo := func(w http.ResponseWriter, path, body string) {
		low := strings.Contains(body, `"names"`) || strings.Contains(body, `"itemInfo"`) || strings.Contains(body, `"classNames"`) ||
			strings.Contains(body, `"subclassNames"`)
		if path == PublicPath && low {
			fail(429, "write_budget", "36000")(w)
			return
		}
		ok(w)
	}
	var mu sync.Mutex
	var bodies []string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		mu.Lock()
		bodies = append(bodies, string(b))
		mu.Unlock()
		refuseInfo(w, r.URL.Path, string(b))
	}))
	t.Cleanup(ts.Close)
	var slept []time.Duration
	c := testClient(ts.URL, &slept)

	f := readFixture(t)
	st := NewState("s", "f")
	plan := Build(f, st, Options{Now: fixtureNow, Private: true, MaxBytes: 2000})
	res := Send(context.Background(), c, plan, st, func(*State) error { return nil }, func(string, ...any) {})
	if res.Counts["prices"] == 0 || res.Counts["scans"] == 0 || res.Counts["items"] != 0 || res.Counts["classes"] != 0 {
		t.Errorf("accepted %v", res.Counts)
	}
	if d := time.Until(res.RetryAt); d < 9*time.Hour || d > 10*time.Hour {
		t.Errorf("retry at %v", res.RetryAt)
	}
	if len(slept) != 0 {
		t.Errorf("slept %v", slept)
	}
	// every price was sent and recorded; the next plan holds only item info and class names
	next := Build(f, st, Options{Now: fixtureNow, Private: true, MaxBytes: 2000})
	if len(next.Public) == 0 || len(next.Private) != 0 {
		t.Fatalf("next plan: %d public, %d private", len(next.Public), len(next.Private))
	}
	for _, b := range next.Public {
		if b.Counts["prices"] != 0 || b.Counts["scans"] != 0 {
			t.Errorf("price data left over: %v", b.Counts)
		}
	}
}

func TestStateFile(t *testing.T) {
	path := t.TempDir() + "/state.json"
	st := NewState("https://a", "/x/CraftWise.lua")
	plan := Build(&savedvars.File{Market: smallMarket()}, st, Options{Now: fixtureNow})
	commitAll(plan, st)
	if err := st.Save(path); err != nil {
		t.Fatal(err)
	}
	back, err := LoadState(path, "https://a", "/x/CraftWise.lua")
	if err != nil {
		t.Fatal(err)
	}
	if p := Build(&savedvars.File{Market: smallMarket()}, back, Options{Now: fixtureNow}); !p.Empty() {
		t.Error("state did not survive the file")
	}
	other, _ := LoadState(path, "https://b", "/x/CraftWise.lua")
	if len(other.Prices) != 0 {
		t.Error("state of another site reused")
	}
}
