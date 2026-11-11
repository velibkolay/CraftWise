package app

import (
	"os/exec"
	"runtime"
)

// OpenURL opens a web page in the default browser.
func OpenURL(u string) error {
	switch runtime.GOOS {
	case "windows":
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", u).Start()
	case "darwin":
		return exec.Command("open", u).Start()
	}
	return exec.Command("xdg-open", u).Start()
}

// OpenFile opens a text file (settings, log) in a text editor.
func OpenFile(path string) error {
	switch runtime.GOOS {
	case "windows":
		return exec.Command("notepad.exe", path).Start()
	case "darwin":
		return exec.Command("open", "-t", path).Start()
	}
	return exec.Command("xdg-open", path).Start()
}
