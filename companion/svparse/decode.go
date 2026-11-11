package svparse

import (
	"fmt"
	"math"
	"reflect"
	"sort"
	"strings"
)

// Problem is a value that didn't fit the Go type it was decoded into. The field is left at its
// zero value (nil for pointers): a value that doesn't fit is shown as missing, never guessed.
type Problem struct {
	Path string // e.g. snapshots["Realm-Name"].char.level
	Msg  string
}

func (p Problem) String() string { return p.Path + ": " + p.Msg }

// Unmarshal copies a parsed value into dst (a pointer), as encoding/json does for JSON:
//
//   - struct fields by their `lua:"name"` tag, else their `json:"name"` tag, else the field name;
//     `-` skips a field; keys without a field are ignored
//   - string, bool, float64, float32, int64, int, int32 and pointers to them (pointer = nil when
//     the key is missing); integers only take numbers without a fraction
//   - []T from the table's array part (keys 1..n)
//   - map[string]T from string keys, map[int64]T / map[int]T from integral number keys
//   - any (the parsed value as it is), *Table (the table itself)
//
// It fills what fits and returns every value that didn't, with its path.
func Unmarshal(v any, dst any) []Problem {
	rv := reflect.ValueOf(dst)
	if rv.Kind() != reflect.Pointer || rv.IsNil() {
		return []Problem{{Path: "", Msg: "Unmarshal needs a non-nil pointer"}}
	}
	d := &decoder{}
	d.decode(v, rv.Elem(), "")
	return d.problems
}

type decoder struct {
	problems []Problem
}

func (d *decoder) problem(path, format string, args ...any) {
	d.problems = append(d.problems, Problem{Path: path, Msg: fmt.Sprintf(format, args...)})
}

var tableType = reflect.TypeOf((*Table)(nil))

func typeName(v any) string {
	switch v.(type) {
	case nil:
		return "nil"
	case bool:
		return "boolean"
	case float64:
		return "number"
	case string:
		return "string"
	case *Table:
		return "table"
	}
	return fmt.Sprintf("%T", v)
}

func keyPath(path string, key any) string {
	switch k := key.(type) {
	case string:
		if path == "" {
			return k
		}
		return fmt.Sprintf("%s[%q]", path, k)
	case float64:
		return fmt.Sprintf("%s[%s]", path, formatNumber(k))
	}
	return fmt.Sprintf("%s[%v]", path, key)
}

func fieldPath(path, name string) string {
	if path == "" {
		return name
	}
	return path + "." + name
}

func formatNumber(f float64) string {
	if f == math.Trunc(f) && math.Abs(f) < 1e15 {
		return fmt.Sprintf("%d", int64(f))
	}
	return fmt.Sprintf("%g", f)
}

// decode sets out from v. A nil v leaves out as it is. It returns false when v itself didn't fit
// (problems deeper inside a table don't count: the table is kept with those fields missing).
func (d *decoder) decode(v any, out reflect.Value, path string) bool {
	if v == nil {
		return true
	}
	before := len(d.problems)
	d.decodeValue(v, out, path)
	for _, p := range d.problems[before:] {
		if p.Path == path {
			return false
		}
	}
	return true
}

func (d *decoder) decodeValue(v any, out reflect.Value, path string) {
	t := out.Type()
	if t == tableType {
		tbl, ok := v.(*Table)
		if !ok {
			d.problem(path, "want table, got %s", typeName(v))
			return
		}
		out.Set(reflect.ValueOf(tbl))
		return
	}
	switch t.Kind() {
	case reflect.Interface:
		if t.NumMethod() == 0 {
			out.Set(reflect.ValueOf(v))
			return
		}
		d.problem(path, "can't decode into %s", t)
	case reflect.Pointer:
		elem := reflect.New(t.Elem())
		if d.decode(v, elem.Elem(), path) {
			out.Set(elem)
		}
	case reflect.String:
		s, ok := v.(string)
		if !ok {
			d.problem(path, "want string, got %s", typeName(v))
			return
		}
		out.SetString(s)
	case reflect.Bool:
		b, ok := v.(bool)
		if !ok {
			d.problem(path, "want boolean, got %s", typeName(v))
			return
		}
		out.SetBool(b)
	case reflect.Float64, reflect.Float32:
		f, ok := v.(float64)
		if !ok {
			d.problem(path, "want number, got %s", typeName(v))
			return
		}
		out.SetFloat(f)
	case reflect.Int64, reflect.Int, reflect.Int32:
		f, ok := v.(float64)
		if !ok {
			d.problem(path, "want number, got %s", typeName(v))
			return
		}
		n, ok := integral(f)
		if !ok || out.OverflowInt(n) {
			d.problem(path, "want an integer, got %s", formatNumber(f))
			return
		}
		out.SetInt(n)
	case reflect.Slice:
		tbl, ok := v.(*Table)
		if !ok {
			d.problem(path, "want table (list), got %s", typeName(v))
			return
		}
		items := tbl.Array()
		s := reflect.MakeSlice(t, 0, len(items))
		for i, item := range items {
			elem := reflect.New(t.Elem()).Elem()
			d.decode(item, elem, keyPath(path, float64(i+1)))
			s = reflect.Append(s, elem)
		}
		out.Set(s)
	case reflect.Map:
		tbl, ok := v.(*Table)
		if !ok {
			d.problem(path, "want table, got %s", typeName(v))
			return
		}
		m := reflect.MakeMapWithSize(t, tbl.Len())
		for _, f := range tbl.Fields() {
			fp := keyPath(path, f.Key)
			key := reflect.New(t.Key()).Elem()
			switch t.Key().Kind() {
			case reflect.String:
				s, ok := f.Key.(string)
				if !ok {
					d.problem(fp, "want a string key, got %s", typeName(f.Key))
					continue
				}
				key.SetString(s)
			case reflect.Int64, reflect.Int, reflect.Int32:
				num, ok := f.Key.(float64)
				n, whole := integral(num)
				if !ok || !whole || key.OverflowInt(n) {
					d.problem(fp, "want an integer key, got %s", typeName(f.Key))
					continue
				}
				key.SetInt(n)
			default:
				d.problem(fp, "can't use %s as a map key", t.Key())
				continue
			}
			elem := reflect.New(t.Elem()).Elem()
			if d.decode(f.Value, elem, fp) {
				m.SetMapIndex(key, elem)
			}
		}
		out.Set(m)
	case reflect.Struct:
		tbl, ok := v.(*Table)
		if !ok {
			d.problem(path, "want table, got %s", typeName(v))
			return
		}
		for _, f := range structFields(t) {
			d.decode(tbl.Get(f.name), out.Field(f.index), fieldPath(path, f.name))
		}
	default:
		d.problem(path, "can't decode into %s", t)
	}
}

func integral(f float64) (int64, bool) {
	if f != math.Trunc(f) || math.IsInf(f, 0) || f > math.MaxInt64 || f < math.MinInt64 {
		return 0, false
	}
	return int64(f), true
}

type structField struct {
	name  string
	index int
}

// structFields lists the exported fields with their Lua key names.
func structFields(t reflect.Type) []structField {
	var out []structField
	for i := 0; i < t.NumField(); i++ {
		f := t.Field(i)
		if !f.IsExported() {
			continue
		}
		name := f.Name
		tag, ok := f.Tag.Lookup("lua")
		if !ok {
			tag, ok = f.Tag.Lookup("json")
		}
		if ok {
			tag = strings.Split(tag, ",")[0]
			if tag == "-" {
				continue
			}
			if tag != "" {
				name = tag
			}
		}
		out = append(out, structField{name: name, index: i})
	}
	return out
}

// SortedProblems orders problems by path, for stable output.
func SortedProblems(list []Problem) []Problem {
	out := append([]Problem(nil), list...)
	sort.SliceStable(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out
}
