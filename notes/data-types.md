# Mojo Data Types (Mojo 1.1.0)

Notes on the data types available in Mojo, checked against the Mojo 1.1.0
compiler and the stdlib source in `modular-v26.6.0.zip`.

## 1. There are no built-in types like in C/C++

In C, `int`, `char`, and `double` are keywords the compiler knows about. Mojo
has none of these. Every type, even `Int` and `Bool`, is an ordinary struct or
alias written in Mojo inside the standard library.

The only things the compiler truly knows are low-level MLIR types (for example
`__mlir_type.i1`). The stdlib wraps those in structs:

```mojo
# std/builtin/bool.mojo
struct Bool(...):
    var _mlir_value: __mlir_type.`!kgen.scalar<bool>`

# std/simd.mojo
struct SIMD[dtype: DType, length: SIMDLength](...)
comptime Scalar = SIMD[...]            # a SIMD vector of length 1
comptime Int = Scalar[DType.int]
comptime Float64 = Scalar[DType.float64]
```

So `Int` is really `SIMD[DType.int, 1]` (explained in [int-type.md](int-type.md)). Every numeric type is the same generic
`SIMD` struct, which is why scalar and vector code share one set of operators
and methods.

### The prelude: why you do not need imports

The file `std/prelude/__init__.mojo` is implicitly imported into every Mojo
file. It re-exports the common types and functions (`Int`, `Float64`, `Bool`,
`String`, `List`, `Dict`, `Array`, `Optional`, `Tuple`, `Span`, `Pointer`,
`print`, `len`, `range`, `min`, `max`, `abs`, `sort`, and so on).

Anything not in the prelude needs a fully qualified import, for example:

```mojo
from std.collections import Set, Deque
from std.math import sqrt
```

### Literals

The compiler gives literals compile-time library types, which become a default
runtime type when stored in a variable:

| Literal      | Literal type    | Default type when stored in a `var`  |
|--------------|-----------------|--------------------------------------|
| `42`         | `IntLiteral`    | `Int`                                |
| `3.14`       | `FloatLiteral`  | `Float64`                            |
| `"hi"`       | `StringLiteral` | `String`                             |
| `True`       | `Bool`          | `Bool`                               |
| `[1, 2, 3]`  | list literal    | `Array[Int, 3]` (not `List`)         |
| `{"a": 1}`   | dict literal    | `Dict[String, Int]`                  |
| `{1, 2}`     | set literal     | `Set[Int]`                           |
| `(1, "a")`   | tuple literal   | a `Tuple` of the element types       |

## 2. Numeric types

### Integers (Go comparison)

All of these are in the prelude. Each is an alias for `Scalar[DType.xxx]`.

| Mojo      | Go equivalent | Bits | Range                                  |
|-----------|---------------|------|----------------------------------------|
| `Int8`    | `int8`        | 8    | -128 to 127                            |
| `UInt8`   | `uint8`       | 8    | 0 to 255                               |
| `Int16`   | `int16`       | 16   | -32768 to 32767                        |
| `UInt16`  | `uint16`      | 16   | 0 to 65535                             |
| `Int32`   | `int32`       | 32   | about -2.1e9 to 2.1e9                  |
| `UInt32`  | `uint32`      | 32   | 0 to about 4.3e9                       |
| `Int64`   | `int64`       | 64   | about -9.2e18 to 9.2e18                |
| `UInt64`  | `uint64`      | 64   | 0 to about 1.8e19                      |
| `Int128`  | (none)        | 128  | signed 128-bit                         |
| `UInt128` | (none)        | 128  | unsigned 128-bit                       |
| `Int256`  | (none)        | 256  | signed 256-bit                         |
| `UInt256` | (none)        | 256  | unsigned 256-bit                       |
| `Int`     | `int`         | platform word size (64 on 64-bit machines) | default integer type |
| `UInt`    | `uint`        | platform word size   | default unsigned type   |
| `Byte`    | `byte`        | 8    | alias for `UInt8`                      |

Use `Int` for counts, indexes, and general integers. Use fixed-width types when
the size matters (file formats, FFI, GPU kernels). In Mojo 1.x, `Int` and
`UInt` cannot be passed to GPU kernels; use `Int32`/`Int64` there.

Limits are available as `Int8.MIN`, `Int8.MAX`, `UInt16.MAX`, and so on.

### Floating point

| Mojo       | Go equivalent | Bits | Notes                                  |
|------------|---------------|------|----------------------------------------|
| `Float16`  | (none)        | 16   | IEEE half precision                    |
| `BFloat16` | (none)        | 16   | "brain float", common in ML            |
| `Float32`  | `float32`     | 32   | IEEE single precision                  |
| `Float64`  | `float64`     | 64   | IEEE double; default for float literals |

ML-oriented low-precision formats (mainly for GPU and model weights):
`Float8_e4m3fn`, `Float8_e4m3fnuz`, `Float8_e5m2`, `Float8_e5m2fnuz`,
`Float8_e8m0fnu`, `Float4_e2m1fn`. A few more exist only as `DType` values
without an alias: `DType.float8_e3m4`, and the experimental
`DType.float6_e2m3fn` / `DType.float6_e3m2fn` (storage only, no arithmetic).

### Complex numbers

Go has `complex64`/`complex128`. Mojo has `ComplexSIMD` in `std.complex`, with
aliases such as `ComplexFloat32` and `ComplexFloat64`:

```mojo
from std.complex import ComplexFloat64
var cx = ComplexFloat64(1.0, 2.0)   # cx.re, cx.im
```

### SIMD vectors (no Go equivalent)

Any numeric type can be a vector of a power-of-two length:

```mojo
var v = SIMD[DType.float32, 4](1, 2, 3, 4)
print(v * 2)                       # [2.0, 4.0, 6.0, 8.0]
var w = SIMD[.float32, 4](1.0)     # 1.1: leading-dot shorthand for DType.float32
```

When Mojo emits vector instructions, and how the target CPU affects them:
[simd-codegen.md](simd-codegen.md).

`DType` is the enum of element types: `DType.bool`, `DType.int`, `DType.uint`,
`DType.int8` ... `DType.int256`, `DType.uint8` ... `DType.uint256`,
`DType.float16`, `DType.bfloat16`, `DType.float32`, `DType.float64`, plus the
float8/float6/float4 formats above. How `DType` is built and how each dtype
maps to MLIR and LLVM types: [dtype.md](dtype.md).

### Conversions are explicit

```mojo
var fl: Float64 = 3.9
var n = Int(fl)          # 3 (truncates)
var x = Float64(7)       # 7.0
var small = Int8(Int(-56))
```

Implicit conversion from `Int` to other numeric types is deprecated, so write
the constructor. Note: `Int(3.9)` directly on a float *literal* does not
compile; store it in a `Float64` first.

### C interop types (`std.ffi`)

| Mojo           | C              | Mojo           | C                |
|----------------|----------------|----------------|------------------|
| `c_char`       | `char` (Int8)  | `c_uchar`      | `unsigned char`  |
| `c_short`      | `short`        | `c_ushort`     | `unsigned short` |
| `c_int`        | `int` (Int32)  | `c_uint`       | `unsigned int`   |
| `c_long`       | `long`         | `c_ulong`      | `unsigned long`  |
| `c_long_long`  | `long long`    | `c_ulong_long` | `unsigned long long` |
| `c_float`      | `float`        | `c_double`     | `double`         |
| `c_size_t`     | `size_t` (UInt)| `c_ssize_t`    | `ssize_t` (Int)  |

## 3. Boolean

| Mojo   | Go     | Notes                                  |
|--------|--------|----------------------------------------|
| `Bool` | `bool` | Values `True` / `False` (capitalized). Operators `and`, `or`, `not`. |

`SIMD[DType.bool, N]` is a vector of booleans (the result of comparing two
vectors). `BitSet[N]` (in `std.collections`) is a compact fixed-size set of
bits.

## 4. Character types

Mojo has no `char` type. Strings are UTF-8, and "a character" can mean three
different things:

| Concept         | Mojo type                      | Go equivalent |
|-----------------|--------------------------------|---------------|
| One byte        | `Byte` (= `UInt8`)             | `byte`        |
| Unicode code point | `Codepoint`                 | `rune`        |
| User-perceived character (grapheme, e.g. an emoji with modifiers) | a `StringSpan` slice | (none built in) |

```mojo
var cp = Codepoint.ord("é")
print(cp, cp.to_u32())       # é 233
print(chr(233), ord("A"))    # é 65
```

## 5. String types

| Mojo            | Ownership    | Notes                                         |
|-----------------|--------------|-----------------------------------------------|
| `String`        | owned, growable, heap | The normal string type. Like Go `string` but mutable. |
| `StringLiteral` | compile-time constant | Type of `"..."` literals. Becomes a `String` when stored in a `var`. |
| `StaticString`  | borrowed view of static data | Alias for `StringSpan[ImmStaticOrigin]`. Good for constant strings in signatures. |
| `StringSpan`    | borrowed view (no copy) | Renamed from `StringSlice` in 1.0. Like a Go substring sharing memory. |
| `ImmStringSpan` / `MutStringSpan` | borrowed view | Immutable / mutable variants. |
| `CStringSpan`   | borrowed, nul-terminated | For C interop (`std.ffi`). |
| `TString`       | template | Result of `t"Hello {name}"` template strings. |

```mojo
var lit = "hello"                     # stored in a var, becomes a String
var s = String("héllo, ") + "world"   # String
comptime K = "key"                    # stays a StringLiteral (compile-time)
var st: StaticString = "static"
var span = StringSpan(s)              # view into s, no copy
```

Length and indexing (Mojo 1.x):

```mojo
s.byte_length()          # 13  (bytes)
s.count_codepoints()     # 12  (Unicode code points)
s.count_graphemes()      # user-visible characters
s[byte=0]                # index by byte offset
s[codepoint=1:2]         # "é"
s[grapheme=0]            # first visible character
for ch in s:             # iterates graphemes by default
for cp in s.codepoints(): ...
for b in s.bytes(): ...
```

`len(s)` is deprecated for strings because "length" is ambiguous for UTF-8.

## 6. Arrays and lists

| Mojo            | Go equivalent    | Notes                                     |
|-----------------|------------------|-------------------------------------------|
| `Array[T, N]`   | `[N]T` (fixed array) | Fixed length, stored inline (no heap). Renamed from `InlineArray` in 1.0. Default type of `[1, 2, 3]`. |
| `List[T]`       | `[]T` (slice)    | Growable, heap-allocated. `append`, `pop`, `insert`, `extend`. |
| `Span[T]`       | `[]T` view       | Non-owning view into a `List`/`Array`/memory. Also `ImmSpan`, `MutSpan`. |
| `SIMD[dtype, N]`| (none)           | Fixed-size numeric vector for SIMD math.  |
| `Deque[T]`      | (none)           | Double-ended queue (`std.collections`).   |
| `LinkedList[T]` | `container/list` | Doubly linked list (`std.collections`).   |
| `BinaryHeap[T]` | `container/heap` | Max-heap (`std.collections`).             |
| `Tuple[...]`    | (none)           | Fixed, mixed types: `(1, "two", 3.0)`.    |

```mojo
var arr = [1, 2, 3]                       # Array[Int, 3]
var zeros = Array[Float64, 3](fill=0.0)
var lst: List[Int] = [1, 2, 3]            # need the annotation to get a List
lst.append(4)
print(lst[len(lst) - 1])                  # 4; negative indexes like lst[-1] are a compile error
var sp = Span(lst)                        # view, no copy
var tup = (1, "two", 3.0)
print(tup[1])                             # two
```

Bounds checking is on by default on CPU. Slices out of range abort instead of
clamping.

## 7. Maps and sets

| Mojo              | Go equivalent        | Notes                                  |
|-------------------|----------------------|----------------------------------------|
| `Dict[K, V]`      | `map[K]V`            | Hash map, keeps insertion order (Go maps do not). In the prelude. |
| `Set[T]`          | `map[T]struct{}`     | Hash set (`std.collections`).          |
| `Counter[T]`      | (none)               | Counts occurrences, like Python's `Counter`. |
| `StringDict[V]`   | `map[string]V`       | String-keyed dict, used for `**kwargs`. |
| `BitSet[N]`       | (none)               | Fixed-size set of bit flags.           |

Keys must be `Hashable` and `Equatable` (the `KeyElement` trait).

```mojo
from std.collections import Set, Counter

var d: Dict[String, Int] = {"a": 1, "b": 2}
d["c"] = 3
for item in d.items():
    print(item.key, item.value)
var s: Set[Int] = {1, 2, 2, 3}             # len 3
var c = Counter[String](["a", "a", "b"])   # c["a"] == 2
```

## 8. Other useful types

| Mojo                 | Go equivalent        | Notes                                 |
|----------------------|----------------------|---------------------------------------|
| `Optional[T]`        | pointer or `(v, ok)` | A value or `None`: `opt.or_else(-1)`, `opt.value()`. |
| `Variant[A, B, ...]` | interface / sum type | Tagged union (`std.utils`): `v.isa[Int]()`, `v[String]`. |
| `NoneType`           | (none)               | Type of `None`.                       |
| `Error`              | `error`              | Default error type for `raises`.      |
| `Pointer[T]`         | `*T`                 | Pointer type (unified with `UnsafePointer` in 1.0). |
| `OwnedPointer[T]`    | (none)               | Single-owner heap box, like C++ `unique_ptr`. |
| `ArcPointer[T]`      | (none)               | Reference-counted pointer, like C++ `shared_ptr`. |

## 9. Quick reference: which module?

| In the prelude (no import) | Needs an import |
|----------------------------|-----------------|
| All integer and float types, `SIMD`, `Scalar`, `DType`, `Byte` | `Set`, `Deque`, `LinkedList`, `BinaryHeap`, `BitSet`, `Counter` from `std.collections` |
| `Bool`, `String`, `StringSpan`, `StaticString`, `StringLiteral`, `Codepoint` | `Variant` from `std.utils` |
| `List`, `Array`, `Dict`, `Optional`, `Tuple`, `Span` | `ComplexFloat64` etc. from `std.complex` |
| `Pointer`, `Error`, `NoneType` | `c_int` etc. from `std.ffi`; `OwnedPointer`, `ArcPointer` from `std.memory` |
