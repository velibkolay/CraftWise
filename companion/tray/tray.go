// Package tray is a minimal notification-area icon with a menu, for Windows, written directly
// against the Win32 API (Shell_NotifyIconW, TrackPopupMenu) so the companion stays a single
// stdlib-only binary that cross-compiles without cgo. On other systems Available is false and the
// companion runs without a tray (command line, log file).
package tray

import "errors"

// Item is one menu line. A line without Action is shown greyed out (status lines); Separator
// draws a divider; Checked shows a check mark. Quit ends Run after Action ran.
type Item struct {
	Label     string
	Action    func()
	Separator bool
	Checked   bool
	Quit      bool
}

// Spec describes the tray icon. Items is called each time the menu opens, Tooltip every few
// seconds, so both always show the current status.
type Spec struct {
	Tooltip func() string
	Items   func() []Item
	// OnClick runs on a left click (nil: open the menu).
	OnClick func()
}

// ErrUnsupported: no tray on this system.
var ErrUnsupported = errors.New("no tray icon on this system")
