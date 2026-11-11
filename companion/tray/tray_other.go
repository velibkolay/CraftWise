//go:build !windows

package tray

// Available reports whether Run can show an icon here.
func Available() bool { return false }

// Run returns ErrUnsupported outside Windows.
func Run(Spec) error { return ErrUnsupported }

// SingleInstance always succeeds outside Windows (release is a no-op).
func SingleInstance(string) (release func(), ok bool) { return func() {}, true }
