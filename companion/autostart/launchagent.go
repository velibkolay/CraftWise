package autostart

import (
	"bytes"
	"encoding/xml"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
)

// LaunchLabel is the label and file name (without .plist) of the macOS LaunchAgent.
const LaunchLabel = "com.velikopter.craftwise-companion"

// LaunchAgent is a Store on macOS: the one value is a LaunchAgent plist in Dir (normally
// ~/Library/LaunchAgents). Set writes the plist for the program in the data (Quote form, as on
// Windows), Get returns the program of the plist quoted, Delete removes the file. It does not
// call launchctl: launchd loads the agent at the next login, and a running companion is not
// started a second time. It is plain file handling, so it is tested on any system.
type LaunchAgent struct {
	Dir string
}

func (l LaunchAgent) path() string { return filepath.Join(l.Dir, LaunchLabel+".plist") }

// Get returns the quoted program of the plist; a missing file is not an error.
func (l LaunchAgent) Get(string) (string, bool, error) {
	b, err := os.ReadFile(l.path())
	if errors.Is(err, fs.ErrNotExist) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	// A file we can't read a program from exists but names no exe; turning on overwrites it.
	prog := PlistProgram(b)
	if prog == "" {
		return "", true, nil
	}
	return Quote(prog), true, nil
}

// Set writes the plist for the program in data.
func (l LaunchAgent) Set(_, data string) error {
	if err := os.MkdirAll(l.Dir, 0o755); err != nil {
		return err
	}
	tmp := l.path() + ".tmp"
	if err := os.WriteFile(tmp, []byte(Plist(CommandPath(data))), 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, l.path()); err != nil {
		os.Remove(tmp)
		return err
	}
	return nil
}

// Delete removes the plist; a missing file is not an error.
func (l LaunchAgent) Delete(string) error {
	if err := os.Remove(l.path()); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

// Plist is the LaunchAgent for program: run it at login, once (no KeepAlive: the companion
// exits when the user quits it or on a settings error, and must stay down then).
func Plist(program string) string {
	var esc bytes.Buffer
	xml.EscapeText(&esc, []byte(program))
	return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>` + LaunchLabel + `</string>
	<key>ProgramArguments</key>
	<array>
		<string>` + esc.String() + `</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
`
}

// PlistProgram is the first ProgramArguments string of a plist, "" when there is none or the
// file is not readable as a plist.
func PlistProgram(data []byte) string {
	dec := xml.NewDecoder(bytes.NewReader(data))
	dec.Strict = false
	dec.Entity = xml.HTMLEntity
	var key string
	inArgs := false
	for {
		tok, err := dec.Token()
		if err != nil {
			return ""
		}
		start, ok := tok.(xml.StartElement)
		if !ok {
			continue
		}
		switch start.Name.Local {
		case "key":
			var s string
			if dec.DecodeElement(&s, &start) != nil {
				return ""
			}
			key = s
		case "string":
			var s string
			if dec.DecodeElement(&s, &start) != nil {
				return ""
			}
			if inArgs {
				return s
			}
			key = ""
		case "array":
			inArgs = key == "ProgramArguments"
			key = ""
		default:
			key = ""
		}
	}
}
