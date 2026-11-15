//go:build darwin

package autostart

import (
	"os"
	"path/filepath"
)

// Supported reports whether autostart can be set here.
func Supported() bool { return true }

// Label is the name of the setting.
func Label() string { return "Start at login" }

// System is the LaunchAgent of the current user in ~/Library/LaunchAgents.
func System() Store {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	return LaunchAgent{Dir: filepath.Join(home, "Library", "LaunchAgents")}
}
