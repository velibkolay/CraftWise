package autostart

import (
	"errors"
	"strings"
	"testing"
)

// fakeStore is the Run key in memory; it counts writes.
type fakeStore struct {
	values         map[string]string
	sets, deletes  int
	getErr, setErr error
	deleteErr      error
}

func newFake() *fakeStore { return &fakeStore{values: map[string]string{}} }

func (f *fakeStore) Get(name string) (string, bool, error) {
	if f.getErr != nil {
		return "", false, f.getErr
	}
	v, ok := f.values[name]
	return v, ok, nil
}

func (f *fakeStore) Set(name, data string) error {
	if f.setErr != nil {
		return f.setErr
	}
	f.sets++
	f.values[name] = data
	return nil
}

func (f *fakeStore) Delete(name string) error {
	if f.deleteErr != nil {
		return f.deleteErr
	}
	f.deletes++
	delete(f.values, name)
	return nil
}

const exe = `C:\Users\Veli\Apps\CraftWise\craftwise-companion.exe`

func manager(f *fakeStore, path string) Manager {
	return Manager{Store: f, Exe: func() (string, error) { return path, nil }}
}

func TestCommandPath(t *testing.T) {
	for in, want := range map[string]string{
		`"C:\a b\c.exe"`:          `C:\a b\c.exe`,
		`"C:\a b\c.exe" -no-tray`: `C:\a b\c.exe`,
		`  "C:\x.exe"  `:          `C:\x.exe`,
		`C:\x.exe`:                `C:\x.exe`,
		`"C:\unterminated.exe`:    `C:\unterminated.exe`,
		``:                        ``,
	} {
		if got := CommandPath(in); got != want {
			t.Errorf("CommandPath(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestSamePath(t *testing.T) {
	same := [][2]string{
		{exe, exe},
		{exe, strings.ToUpper(exe)},
		{exe, strings.ReplaceAll(exe, `\`, "/")},
		{` ` + exe, exe + ` `},
	}
	for _, p := range same {
		if !SamePath(p[0], p[1]) {
			t.Errorf("SamePath(%q, %q) = false", p[0], p[1])
		}
	}
	diff := [][2]string{
		{exe, `D:\craftwise-companion.exe`},
		{exe, exe + ".old"},
		{"", ""},
	}
	for _, p := range diff {
		if SamePath(p[0], p[1]) {
			t.Errorf("SamePath(%q, %q) = true", p[0], p[1])
		}
	}
}

func TestStateOff(t *testing.T) {
	s, err := manager(newFake(), exe).State()
	if err != nil || s.On || s.Exists || s.Exe != exe || s.String() != "off" {
		t.Fatalf("State() = %+v, %v", s, err)
	}
}

func TestStateOnForThisExe(t *testing.T) {
	for _, data := range []string{Quote(exe), exe, `"` + strings.ToLower(exe) + `" -no-tray`} {
		f := newFake()
		f.values[ValueName] = data
		s, err := manager(f, exe).State()
		if err != nil || !s.On || s.String() != "on" {
			t.Errorf("data %q: State() = %+v, %v", data, s, err)
		}
	}
}

func TestStateOffWhenExeMoved(t *testing.T) {
	f := newFake()
	f.values[ValueName] = Quote(`C:\Downloads\craftwise-companion.exe`)
	s, err := manager(f, exe).State()
	if err != nil || s.On || !s.Exists {
		t.Fatalf("State() = %+v, %v", s, err)
	}
	if !strings.HasPrefix(s.String(), "off (registered for ") {
		t.Errorf("String() = %q", s.String())
	}
}

func TestOnWritesQuotedExe(t *testing.T) {
	f := newFake()
	s, err := manager(f, exe).Set(true)
	if err != nil || !s.On {
		t.Fatalf("Set(true) = %+v, %v", s, err)
	}
	if got := f.values[ValueName]; got != `"`+exe+`"` {
		t.Errorf("value = %q", got)
	}
	// Already on: no second write.
	if _, err := manager(f, exe).Set(true); err != nil || f.sets != 1 {
		t.Errorf("Set(true) again: %v, %d writes", err, f.sets)
	}
}

func TestOnRewritesMovedExe(t *testing.T) {
	f := newFake()
	f.values[ValueName] = Quote(`C:\Downloads\craftwise-companion.exe`)
	s, err := manager(f, exe).Toggle()
	if err != nil || !s.On || f.values[ValueName] != Quote(exe) {
		t.Fatalf("Toggle() = %+v, %v, value %q", s, err, f.values[ValueName])
	}
}

func TestOffDeletesWhicheverExe(t *testing.T) {
	for _, data := range []string{Quote(exe), Quote(`D:\other.exe`), ""} {
		f := newFake()
		f.values[ValueName] = data
		s, err := manager(f, exe).Set(false)
		if err != nil || s.On || s.Exists {
			t.Errorf("data %q: Set(false) = %+v, %v", data, s, err)
		}
		if _, ok := f.values[ValueName]; ok || f.deletes != 1 {
			t.Errorf("data %q: value still there or %d deletes", data, f.deletes)
		}
	}
}

func TestOffWhenMissingDoesNothing(t *testing.T) {
	f := newFake()
	if _, err := manager(f, exe).Set(false); err != nil || f.deletes != 0 || f.sets != 0 {
		t.Fatalf("Set(false): %v, %d deletes, %d sets", err, f.deletes, f.sets)
	}
}

func TestToggleRoundTrip(t *testing.T) {
	f := newFake()
	m := manager(f, exe)
	if s, err := m.Toggle(); err != nil || !s.On {
		t.Fatalf("first Toggle() = %+v, %v", s, err)
	}
	if s, err := m.Toggle(); err != nil || s.On || len(f.values) != 0 {
		t.Fatalf("second Toggle() = %+v, %v, %v", s, err, f.values)
	}
}

func TestApply(t *testing.T) {
	f := newFake()
	m := manager(f, exe)
	if s, err := m.Apply("ON"); err != nil || !s.On {
		t.Fatalf(`Apply("ON") = %+v, %v`, s, err)
	}
	if s, err := m.Apply(" off "); err != nil || s.On {
		t.Fatalf(`Apply("off") = %+v, %v`, s, err)
	}
	if _, err := m.Apply("yes"); err == nil {
		t.Error(`Apply("yes") accepted`)
	}
	if f.sets != 1 || f.deletes != 1 {
		t.Errorf("%d sets, %d deletes", f.sets, f.deletes)
	}
}

func TestErrors(t *testing.T) {
	boom := errors.New("access denied")

	if _, err := (Manager{}).State(); !errors.Is(err, ErrUnsupported) {
		t.Errorf("no store: %v", err)
	}
	if _, err := (Manager{}).Apply("on"); !errors.Is(err, ErrUnsupported) {
		t.Errorf("no store, Apply: %v", err)
	}

	f := newFake()
	f.getErr = boom
	if _, err := manager(f, exe).Toggle(); !errors.Is(err, boom) || f.sets != 0 {
		t.Errorf("read error: %v, %d sets", err, f.sets)
	}

	f = newFake()
	f.setErr = boom
	if s, err := manager(f, exe).Set(true); !errors.Is(err, boom) || s.On {
		t.Errorf("write error: %+v, %v", s, err)
	}

	f = newFake()
	f.values[ValueName] = Quote(exe)
	f.deleteErr = boom
	if s, err := manager(f, exe).Set(false); !errors.Is(err, boom) || !s.On {
		t.Errorf("delete error: %+v, %v", s, err)
	}

	m := Manager{Store: newFake(), Exe: func() (string, error) { return "", boom }}
	if _, err := m.Set(true); !errors.Is(err, boom) {
		t.Errorf("exe error: %v", err)
	}
}

func TestSupportedMatchesSystem(t *testing.T) {
	if Supported() != (System() != nil) {
		t.Errorf("Supported() = %v, System() = %v", Supported(), System())
	}
	if Supported() != (New().Store != nil) {
		t.Error("New() store doesn't match Supported()")
	}
}
