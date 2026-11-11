//go:build windows

package tray

import (
	"errors"
	"runtime"
	"sync"
	"syscall"
	"unsafe"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")

	pRegisterClassExW       = user32.NewProc("RegisterClassExW")
	pCreateWindowExW        = user32.NewProc("CreateWindowExW")
	pDefWindowProcW         = user32.NewProc("DefWindowProcW")
	pDestroyWindow          = user32.NewProc("DestroyWindow")
	pGetMessageW            = user32.NewProc("GetMessageW")
	pTranslateMessage       = user32.NewProc("TranslateMessage")
	pDispatchMessageW       = user32.NewProc("DispatchMessageW")
	pPostQuitMessage        = user32.NewProc("PostQuitMessage")
	pPostMessageW           = user32.NewProc("PostMessageW")
	pCreatePopupMenu        = user32.NewProc("CreatePopupMenu")
	pAppendMenuW            = user32.NewProc("AppendMenuW")
	pTrackPopupMenu         = user32.NewProc("TrackPopupMenu")
	pDestroyMenu            = user32.NewProc("DestroyMenu")
	pGetCursorPos           = user32.NewProc("GetCursorPos")
	pSetForegroundWindow    = user32.NewProc("SetForegroundWindow")
	pLoadIconW              = user32.NewProc("LoadIconW")
	pCreateIcon             = user32.NewProc("CreateIcon")
	pSetTimer               = user32.NewProc("SetTimer")
	pRegisterWindowMessageW = user32.NewProc("RegisterWindowMessageW")
	pShellNotifyIconW       = shell32.NewProc("Shell_NotifyIconW")
	pGetModuleHandleW       = kernel32.NewProc("GetModuleHandleW")
	pCreateMutexW           = kernel32.NewProc("CreateMutexW")
	pCloseHandle            = kernel32.NewProc("CloseHandle")
)

const (
	nimAdd    = 0
	nimModify = 1
	nimDelete = 2

	nifMessage = 0x1
	nifIcon    = 0x2
	nifTip     = 0x4

	wmDestroy     = 0x0002
	wmNull        = 0x0000
	wmTimer       = 0x0113
	wmLButtonUp   = 0x0202
	wmRButtonUp   = 0x0205
	wmContextMenu = 0x007B
	wmApp         = 0x8000
	wmTray        = wmApp + 1

	mfString    = 0x0000
	mfGrayed    = 0x0001
	mfChecked   = 0x0008
	mfSeparator = 0x0800

	tpmRightButton = 0x0002
	tpmBottomAlign = 0x0020
	tpmNoNotify    = 0x0080
	tpmReturnCmd   = 0x0100

	idiApplication     = 32512
	errorAlreadyExists = 183
	tooltipTimer       = 1
)

type wndClassEx struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   uintptr
	Icon       uintptr
	Cursor     uintptr
	Background uintptr
	MenuName   *uint16
	ClassName  *uint16
	IconSm     uintptr
}

type point struct{ X, Y int32 }

type msg struct {
	Hwnd    uintptr
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      point
	Private uint32
}

type guid struct {
	Data1 uint32
	Data2 uint16
	Data3 uint16
	Data4 [8]byte
}

// notifyIconData is NOTIFYICONDATAW (976 bytes on 64-bit Windows).
type notifyIconData struct {
	Size            uint32
	Wnd             uintptr
	ID              uint32
	Flags           uint32
	CallbackMessage uint32
	Icon            uintptr
	Tip             [128]uint16
	State           uint32
	StateMask       uint32
	Info            [256]uint16
	Version         uint32
	InfoTitle       [64]uint16
	InfoFlags       uint32
	GuidItem        guid
	BalloonIcon     uintptr
}

// Available reports whether Run can show an icon here.
func Available() bool { return true }

// SingleInstance takes a named mutex; ok is false when another instance holds it.
func SingleInstance(name string) (release func(), ok bool) {
	h, _, err := pCreateMutexW.Call(0, 0, uintptr(unsafe.Pointer(utf16(name))))
	if h == 0 {
		return func() {}, true // can't tell; don't block the app
	}
	if errno, isErrno := err.(syscall.Errno); isErrno && errno == errorAlreadyExists {
		pCloseHandle.Call(h)
		return func() {}, false
	}
	return func() { pCloseHandle.Call(h) }, true
}

func utf16(s string) *uint16 {
	p, err := syscall.UTF16PtrFromString(s)
	if err != nil {
		p, _ = syscall.UTF16PtrFromString("?")
	}
	return p
}

type state struct {
	mu             sync.Mutex
	spec           Spec
	hwnd           uintptr
	icon           uintptr
	taskbarCreated uint32
	actions        map[uintptr]Item
}

var current *state

// Run shows the icon and runs the message loop on this goroutine's thread until a Quit item.
func Run(spec Spec) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	if current != nil {
		return errors.New("tray already running")
	}
	s := &state{spec: spec}
	current = s

	inst, _, _ := pGetModuleHandleW.Call(0)
	className := utf16("CraftWiseCompanionTray")
	wc := wndClassEx{
		WndProc:   syscall.NewCallback(wndProc),
		Instance:  inst,
		ClassName: className,
	}
	wc.Size = uint32(unsafe.Sizeof(wc))
	if r, _, err := pRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc))); r == 0 {
		return err
	}
	// A hidden top-level window (never shown): unlike a message-only window it receives the
	// TaskbarCreated broadcast, so the icon comes back after Explorer restarts.
	hwnd, _, err := pCreateWindowExW.Call(0, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(utf16("CraftWise Companion"))),
		0, 0, 0, 0, 0, 0, 0, inst, 0)
	if hwnd == 0 {
		return err
	}
	s.hwnd = hwnd
	tc, _, _ := pRegisterWindowMessageW.Call(uintptr(unsafe.Pointer(utf16("TaskbarCreated"))))
	s.taskbarCreated = uint32(tc)
	s.icon = makeIcon(inst)
	if err := s.notify(nimAdd); err != nil {
		pDestroyWindow.Call(hwnd)
		return err
	}
	pSetTimer.Call(hwnd, tooltipTimer, 5000, 0)

	var m msg
	for {
		r, _, err := pGetMessageW.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		switch int32(r) {
		case -1:
			return err
		case 0:
			current = nil
			return nil
		}
		pTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		pDispatchMessageW.Call(uintptr(unsafe.Pointer(&m)))
	}
}

func (s *state) notify(op uintptr) error {
	nid := notifyIconData{Wnd: s.hwnd, ID: 1, Flags: nifMessage | nifIcon | nifTip, CallbackMessage: wmTray, Icon: s.icon}
	nid.Size = uint32(unsafe.Sizeof(nid))
	tip := "CraftWise Companion"
	if s.spec.Tooltip != nil {
		tip = s.spec.Tooltip()
	}
	u, _ := syscall.UTF16FromString(tip)
	if len(u) > len(nid.Tip) {
		u = append(u[:len(nid.Tip)-1], 0)
	}
	copy(nid.Tip[:], u)
	if r, _, err := pShellNotifyIconW.Call(op, uintptr(unsafe.Pointer(&nid))); r == 0 && op != nimDelete {
		return err
	}
	return nil
}

func wndProc(hwnd, message, wParam, lParam uintptr) uintptr {
	s := current
	if s == nil {
		r, _, _ := pDefWindowProcW.Call(hwnd, message, wParam, lParam)
		return r
	}
	switch uint32(message) {
	case wmTray:
		switch uint32(lParam) {
		case wmLButtonUp:
			if s.spec.OnClick != nil {
				go s.spec.OnClick()
			} else {
				s.showMenu()
			}
		case wmRButtonUp, wmContextMenu:
			s.showMenu()
		}
		return 0
	case wmTimer:
		_ = s.notify(nimModify)
		return 0
	case wmDestroy:
		_ = s.notify(nimDelete)
		pPostQuitMessage.Call(0)
		return 0
	}
	if s.taskbarCreated != 0 && uint32(message) == s.taskbarCreated {
		_ = s.notify(nimAdd)
		return 0
	}
	r, _, _ := pDefWindowProcW.Call(hwnd, message, wParam, lParam)
	return r
}

func (s *state) showMenu() {
	menu, _, _ := pCreatePopupMenu.Call()
	if menu == 0 {
		return
	}
	defer pDestroyMenu.Call(menu)
	var items []Item
	if s.spec.Items != nil {
		items = s.spec.Items()
	}
	ids := map[uintptr]Item{}
	for i, it := range items {
		id := uintptr(i + 1)
		var flags uintptr = mfString
		if it.Checked {
			flags |= mfChecked
		}
		switch {
		case it.Separator:
			pAppendMenuW.Call(menu, mfSeparator, 0, 0)
		case it.Action == nil && !it.Quit:
			pAppendMenuW.Call(menu, flags|mfGrayed, id, uintptr(unsafe.Pointer(utf16(it.Label))))
		default:
			pAppendMenuW.Call(menu, flags, id, uintptr(unsafe.Pointer(utf16(it.Label))))
			ids[id] = it
		}
	}
	var pt point
	pGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	// Without the foreground window the menu wouldn't close when clicking elsewhere.
	pSetForegroundWindow.Call(s.hwnd)
	cmd, _, _ := pTrackPopupMenu.Call(menu, tpmRightButton|tpmBottomAlign|tpmReturnCmd|tpmNoNotify,
		uintptr(pt.X), uintptr(pt.Y), 0, s.hwnd, 0)
	pPostMessageW.Call(s.hwnd, wmNull, 0, 0)
	it, ok := ids[cmd]
	if !ok {
		return
	}
	if it.Quit {
		if it.Action != nil {
			it.Action()
		}
		pDestroyWindow.Call(s.hwnd)
		return
	}
	go it.Action()
}

// makeIcon draws a 16x16 gold coin; the stock application icon if that fails.
func makeIcon(inst uintptr) uintptr {
	const n = 16
	and := make([]byte, n*2) // 1 bit per pixel, rows padded to 16 bits; 1 = transparent
	xor := make([]byte, n*n*4)
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			dx, dy := float64(x)-7.5, float64(y)-7.5
			d := dx*dx + dy*dy
			i := (y*n + x) * 4
			switch {
			case d > 7.5*7.5:
				and[y*2+x/8] |= 0x80 >> (x % 8)
			case d > 6*6: // rim
				xor[i], xor[i+1], xor[i+2], xor[i+3] = 0x10, 0x60, 0x90, 0xFF // BGRA
			default:
				xor[i], xor[i+1], xor[i+2], xor[i+3] = 0x30, 0xB8, 0xF0, 0xFF
			}
		}
	}
	h, _, _ := pCreateIcon.Call(inst, n, n, 1, 32, uintptr(unsafe.Pointer(&and[0])), uintptr(unsafe.Pointer(&xor[0])))
	if h == 0 {
		h, _, _ = pLoadIconW.Call(0, idiApplication)
	}
	return h
}
