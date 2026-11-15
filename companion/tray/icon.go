package tray

import (
	_ "embed"
	"encoding/binary"
	"errors"
)

// iconICO is the W key brand mark in 16, 20, 24, 32, 40, 48, 64 and 256 px, made by
// tools/gen_companion_icon.py (#310). The exe's own icon (rsrc_windows_amd64.syso) holds the same images.
//
//go:embed craftwise.ico
var iconICO []byte

// iconEntry is one image of an .ico: its size in pixels and its data (a DIB or a PNG).
type iconEntry struct {
	Size int
	Data []byte
}

// parseICO lists the (square) images of an .ico file.
func parseICO(b []byte) ([]iconEntry, error) {
	if len(b) < 6 || binary.LittleEndian.Uint16(b[0:]) != 0 || binary.LittleEndian.Uint16(b[2:]) != 1 {
		return nil, errors.New("not an icon file")
	}
	n := int(binary.LittleEndian.Uint16(b[4:]))
	if n == 0 || len(b) < 6+16*n {
		return nil, errors.New("icon directory truncated")
	}
	out := make([]iconEntry, 0, n)
	for i := 0; i < n; i++ {
		e := b[6+16*i:]
		size := int(e[0])
		if size == 0 {
			size = 256
		}
		length := int(binary.LittleEndian.Uint32(e[8:]))
		off := int(binary.LittleEndian.Uint32(e[12:]))
		if off < 0 || length <= 0 || off+length > len(b) {
			return nil, errors.New("icon image out of range")
		}
		out = append(out, iconEntry{Size: size, Data: b[off : off+length]})
	}
	return out, nil
}

// trayIconPixels is the size of a small icon for a screen at dpi (96 = 100 %): 16 px at 100 %.
func trayIconPixels(dpi int) int {
	if dpi < 96 {
		dpi = 96
	}
	return (16*dpi + 48) / 96
}

// pickIcon returns the smallest image that is at least want px (so it is only ever scaled down), else the
// largest one. ok is false for an empty list.
func pickIcon(entries []iconEntry, want int) (e iconEntry, ok bool) {
	for _, c := range entries {
		if c.Size >= want && (!ok || c.Size < e.Size) {
			e, ok = c, true
		}
	}
	if ok {
		return e, true
	}
	for _, c := range entries {
		if !ok || c.Size > e.Size {
			e, ok = c, true
		}
	}
	return e, ok
}
