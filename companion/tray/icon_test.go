package tray

import "testing"

func TestEmbeddedIconHasAllSizes(t *testing.T) {
	entries, err := parseICO(iconICO)
	if err != nil {
		t.Fatal(err)
	}
	want := []int{16, 20, 24, 32, 40, 48, 64, 256}
	if len(entries) != len(want) {
		t.Fatalf("got %d images, want %d", len(entries), len(want))
	}
	for i, w := range want {
		if entries[i].Size != w {
			t.Errorf("image %d: size %d, want %d", i, entries[i].Size, w)
		}
		d := entries[i].Data
		if w == 256 {
			if string(d[1:4]) != "PNG" {
				t.Errorf("256 px image is not a PNG")
			}
		} else if len(d) < 40 || d[0] != 40 {
			t.Errorf("%d px image is not a DIB", w)
		}
	}
}

func TestParseICORejectsGarbage(t *testing.T) {
	for _, b := range [][]byte{nil, {1, 2, 3}, {0, 0, 1, 0, 1, 0}, {0, 0, 1, 0, 1, 0, 16, 16, 0, 0, 1, 0, 32, 0, 99, 0, 0, 0, 22, 0, 0, 0}} {
		if _, err := parseICO(b); err == nil {
			t.Errorf("accepted %v", b)
		}
	}
}

func TestTrayIconPixels(t *testing.T) {
	for dpi, want := range map[int]int{0: 16, 96: 16, 120: 20, 144: 24, 168: 28, 192: 32, 288: 48} {
		if got := trayIconPixels(dpi); got != want {
			t.Errorf("dpi %d: %d, want %d", dpi, got, want)
		}
	}
}

func TestPickIcon(t *testing.T) {
	entries, _ := parseICO(iconICO)
	for want, size := range map[int]int{16: 16, 17: 20, 24: 24, 28: 32, 48: 48, 100: 256, 300: 256} {
		e, ok := pickIcon(entries, want)
		if !ok || e.Size != size {
			t.Errorf("want %d: got %d, want %d", want, e.Size, size)
		}
	}
	if _, ok := pickIcon(nil, 16); ok {
		t.Error("empty list picked something")
	}
}
