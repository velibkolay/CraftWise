//go:build !windows

package autostart

// Supported reports whether autostart can be set here.
func Supported() bool { return false }

// System is nil outside Windows.
func System() Store { return nil }
