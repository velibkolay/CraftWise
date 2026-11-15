//go:build !windows && !darwin

package autostart

// Supported reports whether autostart can be set here.
func Supported() bool { return false }

// Label is the name of the setting.
func Label() string { return "Start at login" }

// System is nil on systems with no autostart.
func System() Store { return nil }
