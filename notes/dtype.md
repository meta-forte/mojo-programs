# `DType`: element types from Mojo down to machine code

Companion to [data-types.md](data-types.md#simd-vectors-no-go-equivalent) and
[int-type.md](int-type.md). Sources: the stdlib
(`mojo-src/stdlib/std/builtin/dtype.mojo`), the compiler sources
(`mojo-src/compiler/`, extracted from `modular-v26.6.0.zip`), and test programs
run with Mojo 1.1.0 (`L01/dtype_rt.mojo`, `L01/dtype_ir.mojo`).

## Three levels

`DType` exists at three levels:

1. **In the compiler: a C++ class.**
   - `mojo-src/compiler/Support/include/Support/ML/DType.h` defines
     `class DType` with one field, `Cases value`, a `uint8_t` enum. The file
     contains `static_assert(sizeof(DType) == 1, "DType should not grow")`.
   - `mojo-src/compiler/Mojo/include/Mojo/KGENDialect/KGENDType.h` extends it
     as `KGENDType` and adds three Mojo-only cases: `address`, `index`
     (signed, pointer-sized) and `uindex`.
   - It lives in the shared `Support` library, not in the parser, because
     Modular's MAX graph compiler uses the same class ("KGEN dtype is always
     compatible with GraphCompiler's DType").
2. **In MLIR: a type, `!kgen.dtype`.** Defined in
   `Mojo/include/Mojo/KGENDialect/KGENTypes.td` with the summary "8-bit integer
   DType type". Each value is an attribute such as
   `#kgen.dtype.constant<si8>`.
3. **In Mojo: a library struct.** `std/builtin/dtype.mojo` defines
   `struct DType` with one field, `var _mlir_value: __mlir_type.`!kgen.dtype``.
   Names like `DType.int8` are `comptime` constants that wrap those attributes.
   As with `Int`, the language itself has no built-in `DType`; the stdlib
   builds it from compiler-level pieces.

It is 1 byte in Mojo too: `size_of[DType]()` returns `1`. It can be used at
runtime as well: `L01/dtype_rt.mojo` puts dtypes in a `List[DType]` and calls
`is_signed()` and `is_floating_point()` on them in a loop. Bit widths are
different: `bit_width_of[...]()` (from `std.sys`) takes the dtype as a
compile-time parameter.

## The one-byte encoding

The byte's bits say what kind of type it is (from `DType.h`):

| Bit | Meaning |
|---|---|
| 7 (`0x80`) | integer |
| 6 (`0x40`) | float |
| 5 (`0x20`) | complex |
| 1 to 4 | integers: log2 of the width (8 bits = 3, 16 = 4, 32 = 5, ...) |
| 0 (`0x01`) | signed |

So `si8 = (3 << 1) | 0x80 | 1 = 0x87`, `ui8 = 0x86`, `si32 = 0x8B` and
`si64 = 0x8D`. Floats are numbered instead: `f16 = 15 | 0x40`,
`f32 = 17 | 0x40`, and so on. `bool = 1`. The Mojo stdlib copies these masks
(`_mIsSigned = 1`, `_mIsInteger = 128`, `_mIsFloat = 64` in `dtype.mojo`).
That is why `is_signed()` and `is_integral()` are a single bit test.

The full list of Mojo names and their compiler spellings:

| Mojo | Compiler | Mojo | Compiler |
|---|---|---|---|
| `DType.bool` | `bool` | `DType.int` / `DType.uint` | `index` / `uindex` |
| `DType.int8` / `uint8` | `si8` / `ui8` | `DType.int16` / `uint16` | `si16` / `ui16` |
| `DType.int32` / `uint32` | `si32` / `ui32` | `DType.int64` / `uint64` | `si64` / `ui64` |
| `DType.int128` / `uint128` | `si128` / `ui128` | `DType.int256` / `uint256` | `si256` / `ui256` |
| `DType.float16` | `f16` | `DType.bfloat16` | `bf16` |
| `DType.float32` | `f32` | `DType.float64` | `f64` |
| `DType.float8_e4m3fn` etc. | `f8e4m3fn` etc. | `DType.float4_e2m1fn` | `f4e2m1fn` |

## Matching MLIR and LLVM types

A dtype is a value that describes an element type; the data itself has a
separate type at each stage of compilation:

| Stage | 8-bit signed | 16-bit unsigned | 32-bit signed | `Int` | `Bool` |
|---|---|---|---|---|---|
| Mojo | `Int8` | `UInt16` | `Int32` | `Int` | `Bool` |
| dtype value | `si8` | `ui16` | `si32` | `index` | `bool` |
| KGEN data type | `!kgen.scalar<si8>` | `!kgen.scalar<ui16>` | `!kgen.scalar<si32>` | `!kgen.scalar<index>` | |
| MLIR built-in type (`getEquivalentBuiltinType`) | `si8` | `ui16` | `si32` | `index` | `i1` |
| LLVM IR (verified) | `i8` | `i16` | `i32` | `i64` | `i1` |

How to read the table:

- **`!kgen.scalar<si8>` is shorthand for `!kgen.simd<1, si8>`.**
  `!kgen.simd<length, dtype>` is the MLIR type behind Mojo's `SIMD` struct
  (`KGEN_SIMDType` in `KGENTypes.td`). `SIMD[DType.float32, 8]` becomes
  `!kgen.simd<8, f32>`, and that becomes `<8 x float>` in LLVM.
- **The MLIR built-in integer types keep signedness** (`si8` vs `ui8`). The
  mapping code in `Mojo/lib/KGENDialect/KGENDType.cpp` says so explicitly:
  `IntegerType::get(ctx, width, isSInt() ? Signed : Unsigned)`.
- **LLVM integers have no sign** (`i8`, `i16`). Signedness moves to the
  operations, such as `sdiv` vs `udiv`. That's how `Int8` and `UInt8` both end
  up as `i8`.
- **`index` takes the target's pointer width.** It resolves through
  `resolveIndexBitWidth()` and defaults to 64. That is why `Int` is 64-bit
  here, but would be 32-bit on a 32-bit target.
- **Floats map the same way**: `f16`, `bf16`, `f32`, `f64`, and the float8
  formats to their MLIR float types.

The LLVM row comes from compiling small `add` functions with
`mojo build --emit llvm` (`L01/dtype_ir.mojo`):

```
i8          add_i8(SIMD[DType.int8, 1],   SIMD[DType.int8, 1])      ->  %3 = add i8 %0, %1
i16         add_u16(SIMD[DType.uint16, 1], SIMD[DType.uint16, 1])
i32         add_i32(SIMD[DType.int32, 1],  SIMD[DType.int32, 1])
i64         add_int(SIMD[DType.int, 1],    SIMD[DType.int, 1])
<8 x float> add_f32x8(SIMD[DType.float32, 8], SIMD[DType.float32, 8]) ->  fadd contract <8 x float>
i1          add_bool(Bool, Bool)
```

## The compilation path

From the compiler's own walkthrough
(`mojo-src/compiler/Mojo/docs/compiler/MojoCompilerWalkthrough.md`):

**Mojo source -> `lit` dialect (parser output) -> `kgen` dialect (generic
code) -> elaboration (generics made concrete) -> `pop` dialect operations ->
`llvm` dialect -> LLVM IR -> machine code.**

The walkthrough's KGEN-to-LLVM table: `!kgen.scalar<f32>` -> `f32`,
`!kgen.simd<4, f32>` -> `<4 x f32>`, `!kgen.pointer<T>` -> `ptr`,
`!pop.array<4, T>` -> `[4 x T]`, struct types -> LLVM struct types.

## Test programs

- `L01/dtype_rt.mojo`: `DType` size and runtime use
  (`./build.sh -r L01/dtype_rt.mojo`).
- `L01/dtype_ir.mojo`: the LLVM type for each width. Emit the IR with
  `mojo build --emit llvm -o build/L01/dtype_ir.ll L01/dtype_ir.mojo`.

`L01/dtype_rt.mojo` output (Mojo 1.1.0):

```
size_of[DType]: 1
int8  integral: True  signed: True  float: False
uint16  integral: True  signed: False  float: False
int32  integral: True  signed: True  float: False
int  integral: True  signed: True  float: False
float32  integral: False  signed: True  float: True
bool  integral: False  signed: False  float: False
bits int8/uint16/int32/int/float32: 8 16 32 64 32
v.dtype: float16  v: [1.5, 1.5, 1.5, 1.5]
```
