// Package svparse reads World of Warcraft SavedVariables files: Lua 5.1 source made of top-level
// assignments (`CraftWiseDB = { ... }`) whose values are literals only (tables, strings, numbers,
// booleans, nil). It never runs code.
//
// Values are Go values:
//
//	nil      Lua nil
//	bool     true / false
//	float64  every number (Lua 5.1 numbers are doubles)
//	string   strings, byte for byte (Lua strings are bytes, not necessarily UTF-8)
//	*Table   tables
//
// The parser reads from an io.Reader through a buffer, so a file of several MB is read once
// without being held twice in memory.
package svparse

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
)

// MaxDepth is the deepest table nesting accepted. The game writes far fewer levels; the limit only
// stops a broken or hostile file from exhausting the stack.
const MaxDepth = 200

// Field is one key/value pair of a table, in file order.
type Field struct {
	Key   any // string, float64 or bool
	Value any
}

// Table is a Lua table. Positional items (`"a", -- [1]`) get the keys 1, 2, ... as in Lua.
type Table struct {
	fields []Field
	index  map[any]int
}

// NewTable returns an empty table.
func NewTable() *Table { return &Table{index: map[any]int{}} }

// normKey turns Go integers into float64 so Get(5) finds the key 5.
func normKey(key any) any {
	switch k := key.(type) {
	case int:
		return float64(k)
	case int64:
		return float64(k)
	case int32:
		return float64(k)
	}
	return key
}

// Set stores a value; nil removes the key, as in Lua.
func (t *Table) Set(key, value any) {
	key = normKey(key)
	if i, ok := t.index[key]; ok {
		if value == nil {
			t.fields = append(t.fields[:i], t.fields[i+1:]...)
			delete(t.index, key)
			for j := i; j < len(t.fields); j++ {
				t.index[t.fields[j].Key] = j
			}
			return
		}
		t.fields[i].Value = value
		return
	}
	if value == nil {
		return
	}
	t.index[key] = len(t.fields)
	t.fields = append(t.fields, Field{Key: key, Value: value})
}

// Get returns the value at key (nil when missing). Integer keys may be given as int or int64.
func (t *Table) Get(key any) any {
	if t == nil {
		return nil
	}
	if i, ok := t.index[normKey(key)]; ok {
		return t.fields[i].Value
	}
	return nil
}

// Has reports whether key is present.
func (t *Table) Has(key any) bool {
	if t == nil {
		return false
	}
	_, ok := t.index[normKey(key)]
	return ok
}

// Fields returns the pairs in file order. The slice must not be modified.
func (t *Table) Fields() []Field {
	if t == nil {
		return nil
	}
	return t.fields
}

// Len is the number of pairs.
func (t *Table) Len() int {
	if t == nil {
		return 0
	}
	return len(t.fields)
}

// ArrayLen is n for the keys 1..n all present (Lua's # on a table without holes).
func (t *Table) ArrayLen() int {
	if t == nil {
		return 0
	}
	n := 0
	for {
		if _, ok := t.index[float64(n+1)]; !ok {
			return n
		}
		n++
	}
}

// Array returns the values at 1..ArrayLen().
func (t *Table) Array() []any {
	n := t.ArrayLen()
	out := make([]any, n)
	for i := range out {
		out[i] = t.Get(float64(i + 1))
	}
	return out
}

// SortedFields returns the pairs ordered by key: numbers ascending, then strings, then booleans.
func (t *Table) SortedFields() []Field {
	out := append([]Field(nil), t.Fields()...)
	rank := func(k any) int {
		switch k.(type) {
		case float64:
			return 0
		case string:
			return 1
		}
		return 2
	}
	sort.SliceStable(out, func(i, j int) bool {
		a, b := out[i].Key, out[j].Key
		if rank(a) != rank(b) {
			return rank(a) < rank(b)
		}
		switch x := a.(type) {
		case float64:
			return x < b.(float64)
		case string:
			return x < b.(string)
		case bool:
			return !x && b.(bool)
		}
		return false
	})
	return out
}

// SyntaxError says where the input stopped being a SavedVariables file.
type SyntaxError struct {
	Line, Col int
	Msg       string
}

func (e *SyntaxError) Error() string {
	return fmt.Sprintf("svparse: line %d col %d: %s", e.Line, e.Col, e.Msg)
}

// File holds the top-level assignments in file order. A name assigned nil (`X = nil`) is present
// with a nil value.
type File struct {
	Names  []string
	Values map[string]any
}

// Get returns the value assigned to a global name.
func (f *File) Get(name string) any { return f.Values[name] }

// ParseFile reads a SavedVariables file from disk.
func ParseFile(path string) (*File, error) {
	fh, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer fh.Close()
	return Parse(fh)
}

// Parse reads a whole SavedVariables file: `Name = value` assignments, optionally separated by ";".
func Parse(r io.Reader) (*File, error) {
	p := newParser(r)
	f := &File{Values: map[string]any{}}
	for {
		p.skipSpace()
		if p.err != nil {
			return nil, p.err
		}
		if p.eof() {
			return f, nil
		}
		if p.peek() == ';' {
			p.next()
			continue
		}
		line, col := p.line, p.col
		name := p.name()
		if name == "" {
			return nil, p.fail(line, col, "expected a global name")
		}
		if keywords[name] {
			return nil, p.fail(line, col, fmt.Sprintf("unexpected %q", name))
		}
		p.skipSpace()
		if p.peek() != '=' {
			return nil, p.fail(p.line, p.col, fmt.Sprintf("expected '=' after %s", name))
		}
		p.next()
		v := p.value(0)
		if p.err != nil {
			return nil, p.err
		}
		if _, seen := f.Values[name]; !seen {
			f.Names = append(f.Names, name)
		}
		f.Values[name] = v
	}
}

// ParseValue reads a single value (e.g. `{ ... }` or `"text"`) and nothing else.
func ParseValue(r io.Reader) (any, error) {
	p := newParser(r)
	v := p.value(0)
	if p.err != nil {
		return nil, p.err
	}
	p.skipSpace()
	if p.err != nil {
		return nil, p.err
	}
	if !p.eof() {
		return nil, p.fail(p.line, p.col, "unexpected text after the value")
	}
	return v, nil
}

// ParseString is ParseValue on a string.
func ParseString(s string) (any, error) { return ParseValue(strings.NewReader(s)) }

var keywords = map[string]bool{
	"and": true, "break": true, "do": true, "else": true, "elseif": true, "end": true, "false": true,
	"for": true, "function": true, "if": true, "in": true, "local": true, "nil": true, "not": true,
	"or": true, "repeat": true, "return": true, "then": true, "true": true, "until": true, "while": true,
}

type parser struct {
	r         *bufio.Reader
	cur       int // current byte, -1 at end
	line, col int
	err       error
	buf       bytes.Buffer
}

func newParser(r io.Reader) *parser {
	p := &parser{r: bufio.NewReaderSize(r, 64*1024), line: 1, col: 0}
	p.advance()
	return p
}

func (p *parser) advance() {
	b, err := p.r.ReadByte()
	if err != nil {
		if !errors.Is(err, io.EOF) && p.err == nil {
			p.err = err
		}
		p.cur = -1
		return
	}
	if p.cur == '\n' {
		p.line++
		p.col = 1
	} else {
		p.col++
	}
	p.cur = int(b)
}

func (p *parser) eof() bool { return p.cur < 0 }
func (p *parser) peek() int { return p.cur }
func (p *parser) next() int {
	c := p.cur
	p.advance()
	return c
}

func (p *parser) fail(line, col int, msg string) error {
	if p.err == nil {
		p.err = &SyntaxError{Line: line, Col: col, Msg: msg}
	}
	return p.err
}

func isSpace(c int) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f'
}
func isNameStart(c int) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}
func isDigit(c int) bool { return c >= '0' && c <= '9' }

// skipSpace skips white space and comments (`-- line`, `--[[ block ]]`, `--[==[ block ]==]`).
func (p *parser) skipSpace() {
	for p.err == nil {
		switch {
		case isSpace(p.cur):
			p.next()
		case p.cur == '-':
			// A '-' that doesn't start a comment is a minus sign: leave it for value().
			nextByte, err := p.r.Peek(1)
			if err != nil || nextByte[0] != '-' {
				return
			}
			line, col := p.line, p.col
			p.next()
			p.next()
			if p.cur == '[' {
				if level, ok := p.longOpen(); ok {
					if _, ok := p.longBody(level, line, col, false); !ok {
						return
					}
					continue
				}
			}
			for p.cur >= 0 && p.cur != '\n' {
				p.next()
			}
		default:
			return
		}
	}
}

func (p *parser) name() string {
	if !isNameStart(p.cur) {
		return ""
	}
	p.buf.Reset()
	for isNameStart(p.cur) || isDigit(p.cur) {
		p.buf.WriteByte(byte(p.next()))
	}
	return p.buf.String()
}

func (p *parser) value(depth int) any {
	p.skipSpace()
	if p.err != nil {
		return nil
	}
	line, col := p.line, p.col
	switch c := p.cur; {
	case c < 0:
		p.fail(line, col, "unexpected end of input, expected a value")
		return nil
	case c == '{':
		if depth >= MaxDepth {
			p.fail(line, col, "tables nested too deep")
			return nil
		}
		return p.table(depth + 1)
	case c == '"' || c == '\'':
		s, _ := p.quoted()
		return s
	case c == '[':
		level, ok := p.longOpen()
		if !ok {
			p.fail(line, col, "expected a value")
			return nil
		}
		s, _ := p.longBody(level, line, col, true)
		return s
	case c == '-':
		p.next()
		p.skipSpace()
		if p.err != nil {
			return nil
		}
		if !(isDigit(p.cur) || p.cur == '.') {
			p.fail(p.line, p.col, "expected a number after '-'")
			return nil
		}
		n := p.number()
		return -n
	case isDigit(c) || c == '.':
		return p.number()
	case isNameStart(c):
		switch name := p.name(); name {
		case "nil":
			return nil
		case "true":
			return true
		case "false":
			return false
		default:
			p.fail(line, col, fmt.Sprintf("unexpected name %q, expected a value", name))
			return nil
		}
	default:
		p.fail(line, col, fmt.Sprintf("unexpected %q, expected a value", rune(c)))
		return nil
	}
}

// number reads a numeral as Lua 5.1's lexer does: digits, '.', an exponent with its sign, and any
// letters after it; then converts it (decimal, or hexadecimal with 0x).
func (p *parser) number() float64 {
	line, col := p.line, p.col
	p.buf.Reset()
	for {
		c := p.cur
		if isDigit(c) || c == '.' || isNameStart(c) {
			p.buf.WriteByte(byte(p.next()))
			if (c == 'e' || c == 'E') && (p.cur == '+' || p.cur == '-') && !strings.HasPrefix(strings.ToLower(p.buf.String()), "0x") {
				p.buf.WriteByte(byte(p.next()))
			}
			continue
		}
		break
	}
	text := p.buf.String()
	lower := strings.ToLower(text)
	if strings.HasPrefix(lower, "0x") {
		u, err := strconv.ParseUint(text[2:], 16, 64)
		if err != nil {
			p.fail(line, col, fmt.Sprintf("malformed number %q", text))
			return 0
		}
		return float64(u)
	}
	// strconv accepts forms Lua doesn't (inf, nan, underscores, hex floats); only plain decimals pass.
	for _, ch := range lower {
		if !(ch >= '0' && ch <= '9' || ch == '.' || ch == 'e' || ch == '+' || ch == '-') {
			p.fail(line, col, fmt.Sprintf("malformed number %q", text))
			return 0
		}
	}
	f, err := strconv.ParseFloat(text, 64)
	if err != nil && !errors.Is(err, strconv.ErrRange) {
		p.fail(line, col, fmt.Sprintf("malformed number %q", text))
		return 0
	}
	if math.IsNaN(f) {
		p.fail(line, col, fmt.Sprintf("malformed number %q", text))
		return 0
	}
	return f
}

// quoted reads a '...' or "..." string with Lua 5.1 escapes.
func (p *parser) quoted() (string, bool) {
	line, col := p.line, p.col
	quote := p.next()
	p.buf.Reset()
	for {
		c := p.cur
		switch {
		case c < 0:
			p.fail(line, col, "unfinished string")
			return "", false
		case c == '\n' || c == '\r':
			p.fail(line, col, "unfinished string (line break)")
			return "", false
		case c == quote:
			p.next()
			return p.buf.String(), true
		case c == '\\':
			p.next()
			e := p.cur
			switch e {
			case 'a':
				p.buf.WriteByte('\a')
			case 'b':
				p.buf.WriteByte('\b')
			case 'f':
				p.buf.WriteByte('\f')
			case 'n':
				p.buf.WriteByte('\n')
			case 'r':
				p.buf.WriteByte('\r')
			case 't':
				p.buf.WriteByte('\t')
			case 'v':
				p.buf.WriteByte('\v')
			case '\n', '\r':
				// A backslash before a line break is a line break (string.format("%q") writes it).
				p.next()
				if (p.cur == '\n' || p.cur == '\r') && p.cur != e {
					p.next()
				}
				p.buf.WriteByte('\n')
				continue
			case -1:
				p.fail(line, col, "unfinished string")
				return "", false
			default:
				if isDigit(e) {
					n := 0
					for i := 0; i < 3 && isDigit(p.cur); i++ {
						n = n*10 + p.next() - '0'
					}
					if n > 255 {
						p.fail(p.line, p.col, "escape sequence too large")
						return "", false
					}
					p.buf.WriteByte(byte(n))
					continue
				}
				// Lua 5.1: any other escaped character stands for itself (\\, \", \', ...).
				p.buf.WriteByte(byte(e))
			}
			p.next()
		default:
			p.buf.WriteByte(byte(p.next()))
		}
	}
}

// longOpen reads `[` `=`* `[` and returns the level. At a lone '[' (a table key) nothing is consumed.
func (p *parser) longOpen() (int, bool) {
	ahead, _ := p.r.Peek(64)
	level := 0
	for level < len(ahead) && ahead[level] == '=' {
		level++
	}
	if level >= len(ahead) || ahead[level] != '[' {
		return 0, false
	}
	for i := 0; i <= level+1; i++ {
		p.next()
	}
	return level, true
}

// longBody reads up to the closing `]` `=`*level `]`. A line break right after the opening is dropped.
func (p *parser) longBody(level, line, col int, keep bool) (string, bool) {
	p.buf.Reset()
	if p.cur == '\r' || p.cur == '\n' {
		first := p.next()
		if (p.cur == '\r' || p.cur == '\n') && p.cur != first {
			p.next()
		}
	}
	for {
		c := p.cur
		if c < 0 {
			p.fail(line, col, "unfinished long string or comment")
			return "", false
		}
		if c == ']' {
			ahead, _ := p.r.Peek(level + 1)
			closing := len(ahead) == level+1 && ahead[level] == ']'
			for i := 0; closing && i < level; i++ {
				closing = ahead[i] == '='
			}
			if closing {
				for i := 0; i <= level+1; i++ {
					p.next()
				}
				return p.buf.String(), true
			}
		}
		if keep {
			p.buf.WriteByte(byte(c))
		}
		p.next()
	}
}

func (p *parser) table(depth int) *Table {
	line, col := p.line, p.col
	p.next() // '{'
	t := NewTable()
	n := 0
	for {
		p.skipSpace()
		if p.err != nil {
			return nil
		}
		if p.cur == '}' {
			p.next()
			return t
		}
		if p.cur < 0 {
			p.fail(line, col, "unfinished table")
			return nil
		}
		fl, fc := p.line, p.col
		var key, val any
		positional := false
		switch {
		case p.cur == '[':
			if _, ok := p.longOpen(); ok {
				p.fail(fl, fc, "long string as a table field without a key")
				return nil
			}
			p.next()
			key = p.value(depth)
			p.skipSpace()
			if p.err != nil {
				return nil
			}
			if p.cur != ']' {
				p.fail(p.line, p.col, "expected ']'")
				return nil
			}
			p.next()
			p.skipSpace()
			if p.cur != '=' {
				p.fail(p.line, p.col, "expected '=' after the key")
				return nil
			}
			p.next()
			val = p.value(depth)
		case isNameStart(p.cur):
			// `name = value`, or a positional true/false/nil.
			ahead, _ := p.r.Peek(32)
			word := string(rune(p.cur))
			for _, b := range ahead {
				if !(isNameStart(int(b)) || isDigit(int(b))) {
					break
				}
				word += string(b)
			}
			if word == "true" || word == "false" || word == "nil" {
				positional = true
				val = p.value(depth)
				break
			}
			key = p.name()
			p.skipSpace()
			if p.cur != '=' {
				p.fail(p.line, p.col, fmt.Sprintf("expected '=' after %s", key))
				return nil
			}
			p.next()
			val = p.value(depth)
		default:
			positional = true
			val = p.value(depth)
		}
		if p.err != nil {
			return nil
		}
		if positional {
			n++
			key = float64(n)
		} else {
			switch k := key.(type) {
			case nil:
				p.fail(fl, fc, "table key is nil")
				return nil
			case float64:
				if math.IsNaN(k) {
					p.fail(fl, fc, "table key is NaN")
					return nil
				}
			case *Table:
				p.fail(fl, fc, "table key is a table")
				return nil
			}
		}
		t.Set(key, val)
		p.skipSpace()
		if p.err != nil {
			return nil
		}
		switch p.cur {
		case ',', ';':
			p.next()
		case '}':
		default:
			p.fail(p.line, p.col, "expected ',' or '}' in table")
			return nil
		}
	}
}
