# `Int` is `SIMD[DType.int, 1]`

Explains the statement in [data-types.md](data-types.md#1-there-are-no-built-in-types-like-in-cc):
"So `Int` is really `SIMD[DType.int, 1]`." Checked against the stdlib source
(`mojo-src/stdlib/std/simd.mojo`, `builtin/dtype.mojo`), the release notes
(`notes/mojo-release-notes/v1.0.0.md`, `v1.1.0.md`) and a test program run
with Mojo 1.1.0 (see the end of this file).

## The statement

`Int` is not a type of its own. It is just another name for one specific use
of the generic `SIMD` vector type: a vector of one lane holding the
`DType.int` element type. Since Mojo 1.0, the standard library defines it as
two aliases (`std/simd.mojo`, lines 115 and 120):

```mojo
comptime Scalar = SIMD[_, length=1]        # simplified: a SIMD vector with 1 lane
comptime Int    = Scalar[DType.int]        # so Int = SIMD[DType.int, 1]
```

`comptime` here only creates another name for a type, like a C `typedef`. It
does not create a new type. So all three spellings name exactly the same type:

```
Int  ==  Scalar[DType.int]  ==  SIMD[DType.int, 1]
```

## What the pieces mean

`SIMD[dtype, length]` is the one struct behind every numeric type. It has two
compile-time parameters:

- **`dtype`**: the element type, such as `DType.int`, `DType.int64` or
  `DType.float32`.
- **`length`**: the number of lanes. A lane is one slot in the vector.

`SIMD[DType.float32, 4]` is four floats processed together. With
`length = 1` it is just one number, a scalar.

`DType.int` is the machine-word-sized integer, 64 bits on a 64-bit machine.
In `dtype.mojo` it maps to MLIR's `index` type. That is why `Int` is the type
used for counts and indexes.

The struct's only field is the raw hardware value:

```mojo
var _mlir_value: __mlir_type[`!kgen.simd<`, length, `, `, dtype, `>`]
```

So an `Int` is exactly 8 bytes, a plain machine integer with no header, box
or extra fields. `SIMD[DType.int, 4]` is 32 bytes.

## What this means in practice

Each claim was checked with the test program below on Mojo 1.1.0.

| Claim | Result |
|---|---|
| `comptime assert Int == SIMD[DType.int, 1]` | compiles, so they are the same type |
| `reflect[Int].name()` | `SIMD[DType.int, 1]` |
| `size_of[Int]()` | `8` |
| A function written for any `SIMD[dt, w]` accepts an `Int` | `double_it(21)` gives `42` |
| The same function on a 4-lane vector | `[2, 4, 6, 8]` |
| One lane of an int vector is an `Int` | `var k: Int = v[2]` works |
| Vector methods work on `Int` | `n.reduce_add()` works on a plain `Int` |
| `Int == Int64` | **`False`** |

1. **One set of operators and methods.** `+`, `*`, `<`, `abs`, `min` and the
   rest are written once, on `SIMD`. They work the same on a single number
   and on a vector. This is what data-types.md means by "scalar and vector
   code share one set of operators and methods". The 1.1 release notes went
   further and deleted the separate `Int` versions of functions like
   `pop_count()` and `count_leading_zeros()`, because the `SIMD` versions
   already cover `Int`.

2. **Generic numeric code covers `Int` automatically.** A function that takes
   `SIMD[dt, w]` works for `Int`, `Float64`, `UInt8` and any vector of them,
   with no separate overload.

3. **Vectors and scalars fit together.** Indexing one lane of a
   `SIMD[DType.int, N]` gives back an `Int`.

4. **`Int` is not `Int64`.** Both are 64 bits on a 64-bit machine, but their
   element types differ (`DType.int` vs `DType.int64`), so they are different
   types. Use `Int(x)` / `Int64(x)` to convert. The same goes for `UInt` and
   `UInt64`.

5. **It costs nothing at runtime.** A `SIMD` of length 1 compiles to the same
   machine instruction you'd get for a plain integer, so being "a vector of
   one" adds no overhead.

## Memory layout: 8 bytes, no header

An `Int` is a "vector of length 1" only in the type system. In memory and in
machine code it is a plain 64-bit integer. Checked with `L01/int_layout.mojo`:

| Check | Result |
|---|---|
| `size_of[Int]()` / `align_of[Int]()` | 8 / 8 |
| `size_of[Array[Int, 10]]()` | 80, which is exactly 10 x 8 |
| Distance between `arr[0]` and `arr[1]` in memory | 8 bytes |
| Reading an `Int`'s 8 bytes as an `Int64` | gives the same value |

- **No header.** The `SIMD` struct has a single field, the raw hardware
  value. There is no type pointer, length field or reference count. Arrays of
  `Int` are packed tightly, 8 bytes per element.
- **The length is not stored.** The `1` in `SIMD[DType.int, 1]` is a
  compile-time parameter, part of the type. It exists only for the compiler;
  at runtime nothing records that the value is a "vector of length 1".
- **The machine code is scalar.** `L01/int_asm.mojo` compiles `a + b` for
  both types (x86-64 assembly):

```
add_int(SIMD[DType.int, 1], SIMD[DType.int, 1]):    leaq   (%rdi,%rsi), %rax   # normal integer add
add_vec4(SIMD[DType.int, 4], SIMD[DType.int, 4]):   vpaddq %ymm0, %ymm1, %ymm0 # one AVX2 vector add
```

The `Int` version uses ordinary integer registers (`rdi`, `rsi`, `rax`),
exactly what C would produce for `long + long`. Only the 4-lane version uses
vector registers (`ymm`). The function's name in the binary still says
`SIMD[DType.int, 1]`, but the compiler turns a 1-lane vector into a plain
integer.

## Vector operations on a plain `Int`

All the vector methods are available on an `Int`, without making a vector
first. But on one lane they mostly do nothing useful, and they give no
parallelism. Checked with `L01/int_layout.mojo`:

| Operation | Result |
|---|---|
| `v + n` with `v = [1, 2, 3, 4]`, `n = 5` | `[6, 7, 8, 9]`: `n` is copied into every lane |
| `n.reduce_add()`, `n.reduce_max()` | `5`, `5`: summing or taking the max of one lane just returns `n` |
| `n[0]` | `5`: lane 0 is the value itself |
| `n.join(n)` | `[5, 5]`: builds a 2-lane vector |
| `SIMD[DType.int, 4](n)` | `[5, 5, 5, 5]`: fills a 4-lane vector |
| `n.cast[DType.float32]()` | `5.0` |

What the shared type is good for:

1. **One generic function serves both.** Code written for `SIMD[dt, w]`
   handles an `Int` and a `SIMD[DType.int, 8]` with the same source. A common
   pattern: process most of an array 8 lanes at a time, then finish the
   leftover elements one at a time with the same function at `w = 1`.
2. **Scalars mix with vectors.** A plain `Int` can be added to or multiplied
   with a wide vector directly, as in `v + n`. It is copied into every lane,
   so you don't build the wide vector yourself.
3. **Scalar results come out as `Int`.** Reading a lane (`v[2]`) or reducing
   a vector (`v.reduce_add()`) gives an ordinary `Int`.

What it does not do: an `Int` never becomes faster by being a "vector". To
process several numbers at once, you still create a wider
`SIMD[DType.int, N]` yourself, or use helpers like `vectorize`. That is when
the compiler uses vector instructions like `vpaddq` above.

Mojo does not vectorize plain loops automatically. See
[simd-codegen.md](simd-codegen.md) for when vector instructions are used and
how the target CPU affects them.

## Some history

Before Mojo 1.0, `Int` was its own struct in `builtin/int.mojo`, separate
from `SIMD`. Mojo 1.0 made it an alias for `Scalar[DType.int]`, and integer
literals now become that type when stored in a `var`. The 1.0 release notes
say some conversions became stricter as a result.

That is the same pattern as the integer and float tables in section 2 of
data-types.md: `Int8`, `UInt32`, `Float64`, `Byte` and the others are all
`Scalar[DType.xxx]`, so every numeric type in Mojo is one `SIMD` struct with
different parameters. `Bool` is the exception. It is its own struct
(`builtin/bool.mojo`), although `SIMD[DType.bool, N]` exists for vectors of
booleans.

## Test program

Saved as `L01/int_simd.mojo` (run with `./build.sh -r L01/int_simd.mojo`).
The layout and assembly checks above are `L01/int_layout.mojo` and
`L01/int_asm.mojo`.

```mojo
from std.sys import size_of

def double_it[dt: DType, w: SIMDLength](v: SIMD[dt, w]) -> SIMD[dt, w]:
    return v * 2

def main():
    comptime assert Int == SIMD[DType.int, 1], "Int is not SIMD[int, 1]"
    comptime assert Int == Scalar[DType.int], "Int is not Scalar[int]"
    print("same type as Int64:", Int == Int64)
    print("size_of[Int]:", size_of[Int](), " size_of[SIMD[int,4]]:", size_of[SIMD[DType.int, 4]]())
    print("type name:", reflect[Int].name())

    var n: Int = 21
    print("double_it(Int):", double_it(n))                    # generic SIMD fn takes Int
    print("double_it(vec):", double_it(SIMD[DType.int, 4](1, 2, 3, 4)))
    var v = SIMD[DType.int, 4](10, 20, 30, 40)
    var k: Int = v[2]                                         # one lane is an Int
    print("lane 2 as Int:", k, " n.reduce_add():", n.reduce_add())
    print("Int.MAX:", Int.MAX)
    print("Int(Int64) needed:", Int(Int64(5)) + n)
```

Output (Mojo 1.1.0):

```
same type as Int64: False
size_of[Int]: 8  size_of[SIMD[int,4]]: 32
type name: SIMD[DType.int, 1]
double_it(Int): 42
double_it(vec): [2, 4, 6, 8]
lane 2 as Int: 30  n.reduce_add(): 21
Int.MAX: 9223372036854775807
Int(Int64) needed: 26
```
