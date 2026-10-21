# Strings in Mojo 1.1

Sources: `mojo-src/stdlib/std/collections/string/string.mojo`,
`mojo-src/stdlib/std/ffi/cstring.mojo`, `mojo-src/stdlib/std/builtin/string_literal.mojo`,
`mojo-src/docs/manual/c-ffi.mdx`. All behavior below was checked by compiling
and running a test program with the installed Mojo 1.1.0 (output at the end).

## 1. How strings are stored

There are a few string types:

| Type | Owns data? | Notes |
|------|-----------|-------|
| `StringLiteral` | static | Compile-time value. Data lives in the binary's read-only section, always NUL-terminated. `var s = "x"` materializes it into a `String`. |
| `String` | yes | The main runtime type. Mutable, UTF-8, value semantics with copy-on-write. |
| `StringSpan` (was `StringSlice`) | no | A view (pointer + length) into someone else's UTF-8 bytes. Can be mutable or immutable. `StaticString` is an immutable span with static origin. |
| `CStringSpan` (in `std.ffi`) | no | A view onto a NUL-terminated `const char*`. Just a pointer. |

Text is always **UTF-8**. A `String` is **length-prefixed**, not
NUL-terminated: it stores its byte length explicitly, so it may contain
interior NUL bytes and does not normally keep a trailing `\0`.

`byte_length()` gives bytes, `count_codepoints()` gives Unicode codepoints
(`len(String)` is deprecated in 1.1).

## 2. Internal memory layout of `String`

`size_of[String]()` is **24 bytes** (3 machine words on 64-bit). The struct
has exactly three fields:

```mojo
var _ptr_or_data: Pointer[UInt8, MutUntrackedOrigin]  # word 0
var _len_or_data: Int                                  # word 1
var _capacity_or_data: Int                             # word 2 (top bits are flags)
```

The top bits of the capacity word hold flags:

| Bit (64-bit) | Flag | Meaning |
|--------------|------|---------|
| 63 | `FLAG_IS_INLINE` | Short-string optimization: the bytes live inside the 24-byte value itself |
| 62 | `FLAG_IS_REF_COUNTED` | Points to a heap buffer with an atomic refcount header |
| 61 | `FLAG_HAS_NUL_TERMINATOR` | The byte just past the end is known to be `\0` |
| 56..60 | inline length | 5-bit length, used only in inline mode |

Depending on the flags, a `String` is in one of three representations:

### a) Static (no flags, or only NUL flag)

Made from a `StringLiteral` or `StaticString`. The pointer points directly
at the constant data in the binary. **No allocation, no copy.** A literal
also sets `FLAG_HAS_NUL_TERMINATOR`, because literals are stored with a
trailing `\0`. Capacity reports as the length. The first mutation copies the
data into inline or heap storage.

### b) Inline / SSO (`FLAG_IS_INLINE`)

Up to **23 bytes** (`INLINE_CAPACITY = 3 * 8 - 1`) are stored inside the
24-byte struct itself. The last byte holds the flags and the 5-bit length.
`unsafe_ptr()` then returns the address of the `String` value itself. No heap
allocation at all.

```
 byte: 0                                 22   23
      [ UTF-8 data ........................ ][flags|len]
```

### c) Heap, reference counted (`FLAG_IS_REF_COUNTED`)

For longer strings. `_alloc(capacity)` allocates `capacity + 8` bytes:

```
          heap block
          +----------------+---------------------------------+
          | Atomic[Int]    | UTF-8 bytes ...   [spare cap]   |
          | refcount (8 B) |                                 |
          +----------------+---------------------------------+
                           ^
 String._ptr_or_data ------+   (points AFTER the header)
 String._len_or_data   = byte length
 String._capacity_or_data = capacity / 8  | flags
```

Capacity is stored in units of 8 bytes (`(cap + 7) >> 3`), which leaves room
for the flag bits.

## 3. Is there an object header?

**Not in the Python/Java sense.** A `String` value is a plain 24-byte struct:
no type pointer, no vtable, no GC header. It lives wherever you put it (stack,
inside another struct, inside a `List`).

The only "header" is the **8-byte atomic reference count placed in front of
the heap buffer**, and only in the heap representation. Static and inline
strings have no header at all. The pointer stored in the `String` skips past
the refcount, so it points straight at the first UTF-8 byte.

## 4. Are strings immutable?

**No. `String` is mutable** (the stdlib docstring says "Always mutable").
`var s = "Hello"; s += " World"` changes `s`.

What *is* immutable:

- `StringLiteral` and `comptime` strings (`comptime G = "x"`; assigning to
  `G` is a compile error).
- A `String` declared with `def f(s: String)` (default `imm` convention)
  cannot be modified inside `f`. Use `mut s: String` to modify the caller's
  string, or `var s: String` to get an owned copy.
- Immutable `StringSpan`s / `StaticString`.

`String` has **value semantics**: `var b = a` gives `b` its own logical
string. It is implemented with **copy-on-write**: copying a heap string only
bumps the refcount (both point to the same buffer); the real copy happens the
first time one of them is mutated. Copying an inline string copies 24 bytes;
copying a static string copies the pointer.

## 5. Does concatenation create a new String?

It depends on the operator:

- **`a + b` always creates a new `String`.** `_add` allocates a result of
  `len(a) + len(b)` bytes (inline if it fits in 23 bytes, else heap) and
  `memcpy`s both sides into it. `a` and `b` are untouched.
- **`a += b` appends in place** (`__iadd__` -> `_iadd`). It calls
  `unsafe_ptr_mut(new_len)`, which:
  - keeps the same buffer if `a` is the unique owner and has capacity,
  - reallocates if capacity is too small (growth at least **doubles**, so
    repeated `+=` is amortized O(1)),
  - copies first if the buffer is shared (copy-on-write) or static.
- `append(codepoint)`, `write(...)` / `write_string(...)` (String is a
  `Writer`), `resize()` and `reserve_bytes()` also work in place.

So for building strings in a loop, use `+=`, `write()`, or a t-string, not
repeated `a = a + b`. Call `reserve_bytes(n)` first if you know the size.

## 6. Can strings be modified in place?

Yes, with some care:

| Operation | In place? |
|-----------|-----------|
| `+=`, `append()`, `write()`, `resize()`, `reserve_bytes()` | Yes (may realloc) |
| `s.unsafe_as_bytes_mut()[i] = b` | Yes, byte-level. You must keep the string valid UTF-8 |
| `s.unsafe_ptr_mut()` | Yes, raw pointer to a unique, writable buffer |
| `replace()`, `upper()`, `lower()`, `strip()`, slicing, `+` | No, they return a new `String` (or a span view for slicing / strip) |

There is no `s[i] = ...` (`String` has no `__setitem__`), because
"character i" is not a fixed byte offset in UTF-8.

Any mutating call first makes the buffer **unique and writable**: a static
string gets copied, a shared heap buffer gets copied (COW), and the
NUL-terminator flag is cleared because the old terminator may be overwritten.

## 7. Passing strings to C (NUL-terminated `char*`)

Use **`as_c_string_span()`**, which returns a `CStringSpan` (a typed,
non-owning `const char*`):

```mojo
from std.ffi import external_call, c_size_t

var name: String = "Mojo strings"
var n = external_call["strlen", c_size_t](name.as_c_string_span())   # 12
```

What it does (`string.mojo`):

1. If `FLAG_HAS_NUL_TERMINATOR` is already set (for example a string fresh
   from a literal), it just returns a pointer. Zero cost.
2. Otherwise it calls `unsafe_ptr_mut(capacity = len + 1)` to get a unique
   buffer with one spare byte, writes `0` after the last byte, and sets the
   flag. The NUL is **not** counted in `byte_length()`.

Consequences:

- The method takes **`mut self`**, so the string must be a mutable `var`.
- It may reallocate / move the buffer, so call it once and reuse the result.
- The `CStringSpan` carries the string's origin, so the compiler keeps the
  `String` alive while the span is in use.
- Interior NUL bytes are not checked here; C will see the string truncated
  at the first `\0`. (`CStringSpan(span)` from a span does check and raises.)
- String literals: `"libm.so.6".as_c_string_span()` is resolved at compile
  time with no runtime work.
- `external_call()` rejects a raw `String` argument at compile time; always
  pass `as_c_string_span()`.

## 8. Converting C strings to Mojo strings

**Copying (owned `String`), NUL-terminated pointer:**

```mojo
var s = String(unsafe_from_utf8_ptr=c_ptr)   # c_ptr: Pointer[c_char or UInt8, _]
```

This wraps the pointer in a `CStringSpan`, finds the length with `strlen`,
and copies the bytes into a new `String` (inline or heap). It is "unsafe"
because the bytes must be valid UTF-8 and must be NUL-terminated. After the
copy the C memory can be freed.

**When the length is known, or you want UTF-8 validation:**

```mojo
var span = Span(unsafe_ptr=ptr.unsafe_bitcast[Byte](), length=Int(len))
String(from_utf8=span)          # validates, raises on bad UTF-8
String(from_utf8_lossy=span)    # replaces bad sequences with U+FFFD
String(unsafe_from_utf8=span)   # no validation
```

**Non-copying view:** keep it as a `CStringSpan(unsafe_from_ptr=ptr)` and
use `.as_bytes()` / `.as_bytes_with_nul()` or convert to a `StringSpan`
(`StringSlice(unsafe_from_utf8=cstr_span)`). No allocation, but you must keep
the C memory alive.

**Ownership:** Mojo never frees memory that C returned. If C allocated it
(`strdup`, `getline`, ...) call C's `free` yourself after copying.

Full round trip (verified):

```mojo
from std.ffi import external_call, c_char

var name: String = "Mojo strings"
var cp = external_call["strdup", Pointer[c_char, MutUntrackedOrigin]](
    name.as_c_string_span())
var back = String(unsafe_from_utf8_ptr=cp)       # copies
external_call["free", NoneType](cp.unsafe_bitcast[NoneType]())
print(back)                                      # Mojo strings
```

For functions that can return `NULL`, declare the return type as
`Optional[Pointer[c_char, ...]]` or `Optional[CStringSpan[...]]`, since
Mojo pointers are non-null.

## 9. Verification run (Mojo 1.1.0)

Test program checked each claim above:

```
size_of[String]: 24
INLINE_CAPACITY: 23
literal capacity: 5                      <- static, points at the literal, no alloc
inline cap: 23 ptr inside value: True    <- SSO: data lives inside the struct
shared buffer: True                      <- copy shares the heap buffer
after +=, shared: False                  <- copy-on-write on mutation
unique += same buffer: True cap: 48      <- unique owner appends in place
+ new buffer: True                       <- a + b allocates a new String
Hello                                    <- unsafe_as_bytes_mut()[0] = 'H'
strlen: 12                               <- as_c_string_span() to C
from C: Mojo strings                     <- String(unsafe_from_utf8_ptr=...)
```

## Summary

- `String` = 24-byte value: static pointer, inline (<= 23 bytes), or
  refcounted heap buffer. UTF-8, length-prefixed.
- No object header; heap strings have an 8-byte atomic refcount in front of
  the data.
- Mutable, value semantics, copy-on-write.
- `+` makes a new string; `+=` / `write` / `append` mutate in place with
  amortized doubling growth.
- In-place byte edits via `unsafe_as_bytes_mut()` / `unsafe_ptr_mut()`;
  no `s[i] = c`.
- To C: `s.as_c_string_span()` (adds a `\0` lazily, needs `mut`).
- From C: `String(unsafe_from_utf8_ptr=p)` copies; `CStringSpan` views
  without copying.
