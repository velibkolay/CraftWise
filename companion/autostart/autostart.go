// Package autostart turns "Start with Windows" on and off: the value ValueName under
// HKCU\Software\Microsoft\Windows\CurrentVersion\Run, its data the quoted path of the running exe.
//
// The decisions (is it on, what to write, what to delete) live here and work on a Store, so they
// are tested anywhere with a fake; the registry Store (registry_windows.go) is the only part that
// needs Windows. Elsewhere System returns nil and Supported is false.
package autostart

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ValueName is the name of the Run value.
const ValueName = "CraftWise Companion"

// RunKey is the key under HKEY_CURRENT_USER that holds it.
const RunKey = `Software\Microsoft\Windows\CurrentVersion\Run`

// ErrUnsupported: no autostart on this system.
var ErrUnsupported = errors.New("only on Windows")

// Store reads and writes string values of one key (the Run key).
type Store interface {
	// Get returns the value's data; ok is false when the value doesn't exist.
	Get(name string) (data string, ok bool, err error)
	// Set writes the value (REG_SZ).
	Set(name, data string) error
	// Delete removes the value; a missing value is not an error.
	Delete(name string) error
}

// Manager decides on and off for the exe that Exe returns.
type Manager struct {
	Store Store
	Exe   func() (string, error) // nil: Executable
}

// New is the Manager for this system's Store; Store is nil where Supported is false.
func New() Manager { return Manager{Store: System()} }

// State is what is registered.
type State struct {
	On         bool   // the value exists and starts this exe
	Exists     bool   // the value exists (for this exe or another)
	Registered string // the value's data
	Exe        string // this exe
}

// String is one line for -status and the log.
func (s State) String() string {
	switch {
	case s.On:
		return "on"
	case !s.Exists:
		return "off"
	}
	return fmt.Sprintf("off (registered for %q, not this exe)", s.Registered)
}

// Executable is the running exe: absolute, symlinks resolved.
func Executable() (string, error) {
	p, err := os.Executable()
	if err != nil {
		return "", err
	}
	if r, err := filepath.EvalSymlinks(p); err == nil {
		p = r
	}
	return filepath.Abs(p)
}

// Quote is the Run value's data for exe.
func Quote(exe string) string { return `"` + exe + `"` }

// CommandPath is the program path of a Run value's data: the quoted part, or (unquoted) the whole
// data. Arguments after a quoted path are ignored.
func CommandPath(data string) string {
	data = strings.TrimSpace(data)
	if strings.HasPrefix(data, `"`) {
		rest := data[1:]
		if i := strings.IndexByte(rest, '"'); i >= 0 {
			return rest[:i]
		}
		return rest
	}
	return data
}

// SamePath compares two Windows paths: case-insensitive, / and \ alike, trailing separators and
// surrounding space ignored.
func SamePath(a, b string) bool {
	norm := func(p string) string {
		p = strings.ReplaceAll(strings.TrimSpace(p), "/", `\`)
		return strings.TrimRight(p, `\`)
	}
	na, nb := norm(a), norm(b)
	return na != "" && strings.EqualFold(na, nb)
}

func (m Manager) exe() (string, error) {
	if m.Exe != nil {
		return m.Exe()
	}
	return Executable()
}

// State reads what is registered and compares it with this exe.
func (m Manager) State() (State, error) {
	if m.Store == nil {
		return State{}, ErrUnsupported
	}
	exe, err := m.exe()
	if err != nil {
		return State{}, fmt.Errorf("autostart: %w", err)
	}
	data, ok, err := m.Store.Get(ValueName)
	if err != nil {
		return State{Exe: exe}, fmt.Errorf("autostart: %w", err)
	}
	s := State{Exe: exe}
	if ok {
		s.Exists = true
		s.Registered = data
		s.On = SamePath(CommandPath(data), exe)
	}
	return s, nil
}

// Set turns autostart on (writes the value for this exe unless it is already there) or off
// (removes the value, whichever exe it names).
func (m Manager) Set(on bool) (State, error) {
	s, err := m.State()
	if err != nil {
		return s, err
	}
	switch {
	case on && !s.On:
		if err := m.Store.Set(ValueName, Quote(s.Exe)); err != nil {
			return s, fmt.Errorf("autostart: %w", err)
		}
	case !on && s.Exists:
		if err := m.Store.Delete(ValueName); err != nil {
			return s, fmt.Errorf("autostart: %w", err)
		}
	default:
		return s, nil
	}
	return m.State()
}

// Toggle turns it on when it is off for this exe (also when the value names another path), off
// when it is on.
func (m Manager) Toggle() (State, error) {
	s, err := m.State()
	if err != nil {
		return s, err
	}
	return m.Set(!s.On)
}

// Apply is the -autostart flag: "on" or "off".
func (m Manager) Apply(arg string) (State, error) {
	switch strings.ToLower(strings.TrimSpace(arg)) {
	case "on":
		return m.Set(true)
	case "off":
		return m.Set(false)
	}
	return State{}, errors.New("-autostart takes on or off")
}
