//go:build windows

package autostart

import (
	"syscall"
	"unsafe"
)

var (
	advapi32 = syscall.NewLazyDLL("advapi32.dll")

	pRegCreateKeyExW  = advapi32.NewProc("RegCreateKeyExW")
	pRegQueryValueExW = advapi32.NewProc("RegQueryValueExW")
	pRegSetValueExW   = advapi32.NewProc("RegSetValueExW")
	pRegDeleteValueW  = advapi32.NewProc("RegDeleteValueW")
	pRegCloseKey      = advapi32.NewProc("RegCloseKey")
)

const (
	hkeyCurrentUser = 0x80000001

	keyQueryValue = 0x0001
	keySetValue   = 0x0002

	regSZ       = 1
	regExpandSZ = 2

	errorSuccess      = 0
	errorFileNotFound = 2
	errorMoreData     = 234
)

// Supported reports whether autostart can be set here.
func Supported() bool { return true }

// System is the Run key of the current user.
func System() Store { return runKey{} }

type runKey struct{}

// open opens (or creates, it normally exists) HKCU\RunKey with the given access.
func (runKey) open(access uint32) (uintptr, error) {
	sub, err := syscall.UTF16PtrFromString(RunKey)
	if err != nil {
		return 0, err
	}
	var h uintptr
	r, _, _ := pRegCreateKeyExW.Call(hkeyCurrentUser, uintptr(unsafe.Pointer(sub)), 0, 0, 0,
		uintptr(access), 0, uintptr(unsafe.Pointer(&h)), 0)
	if r != errorSuccess {
		return 0, syscall.Errno(r)
	}
	return h, nil
}

func (k runKey) Get(name string) (string, bool, error) {
	n, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		return "", false, err
	}
	h, err := k.open(keyQueryValue)
	if err != nil {
		return "", false, err
	}
	defer pRegCloseKey.Call(h)
	buf := make([]uint16, 260)
	for {
		var typ uint32
		size := uint32(len(buf) * 2)
		r, _, _ := pRegQueryValueExW.Call(h, uintptr(unsafe.Pointer(n)), 0,
			uintptr(unsafe.Pointer(&typ)), uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&size)))
		switch r {
		case errorFileNotFound:
			return "", false, nil
		case errorMoreData:
			buf = make([]uint16, size/2+1)
			continue
		case errorSuccess:
		default:
			return "", false, syscall.Errno(r)
		}
		if typ != regSZ && typ != regExpandSZ {
			// Not a string under our name: it exists, names no exe; turning on overwrites it.
			return "", true, nil
		}
		return syscall.UTF16ToString(buf[:size/2]), true, nil
	}
}

func (k runKey) Set(name, data string) error {
	n, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		return err
	}
	d, err := syscall.UTF16FromString(data) // with the terminating NUL, as REG_SZ wants
	if err != nil {
		return err
	}
	h, err := k.open(keySetValue)
	if err != nil {
		return err
	}
	defer pRegCloseKey.Call(h)
	r, _, _ := pRegSetValueExW.Call(h, uintptr(unsafe.Pointer(n)), 0, regSZ,
		uintptr(unsafe.Pointer(&d[0])), uintptr(len(d)*2))
	if r != errorSuccess {
		return syscall.Errno(r)
	}
	return nil
}

func (k runKey) Delete(name string) error {
	n, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		return err
	}
	h, err := k.open(keySetValue)
	if err != nil {
		return err
	}
	defer pRegCloseKey.Call(h)
	r, _, _ := pRegDeleteValueW.Call(h, uintptr(unsafe.Pointer(n)))
	if r != errorSuccess && r != errorFileNotFound {
		return syscall.Errno(r)
	}
	return nil
}
