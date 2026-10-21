# SIMD code generation and target CPUs

When does Mojo emit SIMD (vector) instructions, and what happens on CPUs with
fewer vector features? Companion to [int-type.md](int-type.md) and
[dtype.md](dtype.md). Checked with Mojo 1.1.0 on an Intel Core i7-14700
(Raptor Lake, AVX2, no AVX-512), using the assembly from
`mojo build --emit asm`. Sources: the compiler source (`mojo-src/compiler/`),
`mojo-src/docs/requirements.mdx`, `mojo-src/docs/tools/feature-toggles.mdx`,
`notes/mojo-release-notes/v1.0.0b1.md`.

Test programs (their headers have the commands used below):

- `L01/sortsearch.mojo`: plain sort, search and sum loops.
- `L01/simd_search.mojo`: the same work with explicit SIMD.
- `L01/autovec.mojo`: what Mojo vectorizes without being asked.
- `L01/autovec_slp.mojo`: the straight-line (SLP) vectorizer.
- `L01/add1024.mojo`: adding two 1024-element arrays, four ways, timed.

## 1. An `Int` array is not a SIMD vector

`Array[Int, 8]` and `List[Int]` are plain contiguous memory holding 8 bytes
per element (`size_of[Array[Int, 8]]()` is 64). Each element is a 1-lane
`SIMD` (see [int-type.md](int-type.md)), but the array as a whole is not a
vector type. You get vector operations only when you load several elements
into a wider `SIMD[DType.int, N]` yourself.

## 2. Plain loops are not vectorized

`L01/sortsearch.mojo` has an insertion sort, a linear search and a sum loop
over `List[Int]`. Vector registers used per function:

| Build | insertion_sort | linear_search | sum_all |
|---|---|---|---|
| Default (bounds checks on) | 0 xmm/ymm, 74 instrs | 0, 45 instrs | 0, 39 instrs |
| `-D ASSERT=none` | 0, 31 instrs | 0, 15 instrs | 0, 9 instrs |
| `-D ASSERT=none --target-cpu x86-64` | 0, 31 instrs | 0, 15 instrs | 0, 9 instrs |

There are two reasons.

### Reason 1: bounds checks

Bounds checking is on by default for all collections on CPU since 1.0
(`-D ASSERT=safe`). Every `data[i]` compiles to a compare and a branch to the
abort path:

```
cmpq   %rsi, %r10        # i < len?
jae    .LBB2_5           # no: abort with an out-of-bounds message
addq   (%rdi,%r10,8), %rax
```

A loop that may stop partway through cannot be vectorized. `-D ASSERT=none`
removes all asserts, including the bounds checks (see
`mojo-src/docs/tools/feature-toggles.mdx`).

### Reason 2: Mojo does not run LLVM's loop vectorizer

Even without bounds checks, `sum_all` stays a scalar loop:

```
.LBB2_2:
    addq   (%rdi,%rcx,8), %rax
    incq   %rcx
    cmpq   %rcx, %rsi
    jne    .LBB2_2
```

`clang -O2` would vectorize this loop. Mojo builds its own LLVM optimization
pipeline in
`mojo-src/compiler/Mojo/lib/Compiler/ObjectCompiler/LLVMPassesPipeline.cpp`.
It adds `SLPVectorizerPass`, which only combines straight-line code (for
example, four neighbouring scalar adds into one vector add). `LoopVectorizePass`
appears nowhere in the compiler source. So **Mojo never runs LLVM's loop
vectorizer**: a loop is never turned into a vector loop. The design expects
you to write explicit `SIMD` code or use helpers like `vectorize`. (Two
exceptions in the next section: fill loops become `memset` calls, and
straight-line code can be combined.)

Neither the compiler source nor the docs say why the loop vectorizer is left
out; nearby comments in the pipeline still mention it. A guess, not
confirmed by any source: Mojo aims for "predictable performance semantics"
(`docs/vision.mdx`), and loop auto-vectorization is known for unpredictable
results, where a small code change silently turns it off. Explicit `SIMD` and
`vectorize` give that control to the programmer instead. It also keeps
compile times down.

## 3. What Mojo does vectorize without being asked

Tested with `-D ASSERT=none` (`L01/autovec.mojo`, `L01/autovec_slp.mojo`):

| Code | Result |
|---|---|
| Plain sum, search, sort loops | **scalar**: no loop vectorizer |
| Plain copy loop (`d[i] = s[i]`), even between two separate lists | **scalar** |
| Plain fill loop (`d[i] = 0`) | turned into a call to glibc's **`memset`** (`jmp memset@PLT`), which uses AVX2 |
| Scaling loop (`d[i] = d[i] * 3`) | **scalar** |
| Four adds on neighbouring elements, straight-line code, loads before stores | **one `vpaddq` on `ymm`** |
| Same four adds, but values passed in as `Array` arguments | scalar: the values arrive in separate integer registers |
| `List.copy()` | **vector** (`vmovups ymm`): the stdlib copies with SIMD |
| `String.find()` | **vector** (`vpcmpeqb`, `vpmovmskb`): the stdlib search uses SIMD |

Three kinds of optimization are at work:

1. **The straight-line (SLP) vectorizer** combines neighbouring identical
   operations outside loops into one vector instruction:

   ```
   slp_add4:  vmovdqu (%rsi), %ymm0
              vpaddq  (%rdi), %ymm0, %ymm0
              vmovdqu %ymm0, (%rdi)
   ```

   It needs the code shaped for it. With `Array` arguments the four values
   arrived in separate integer registers and stayed scalar.

2. **The loop-idiom pass** (`LoopIdiomRecognizePass`, also in Mojo's
   pipeline) spots loops that only fill memory and replaces them with a
   `memset` call, so the C library's vectorized code runs. It did not turn
   the copy loop into `memcpy`, even for two separate lists. It appears the
   compiler can't prove the two buffers don't overlap.

3. **The stdlib does the vectorizing for you.** Most of the vector speed in a
   Mojo program comes from library code written with explicit SIMD:
   - copying (`unsafe_memcpy`, used by `List.copy()` and `String`)
   - searching (`_memchr` and `_memmem` in `string_span.mojo`, behind
     `String.find`)
   - UTF-8 validation (`_utf8.mojo`)

## 4. Why `Int` is `SIMD[DType.int, 1]` if loops stay scalar

The type describes what an `Int` is, not how it's compiled. A 1-lane `SIMD`
compiles to an ordinary integer instruction (see [int-type.md](int-type.md)),
so the definition costs nothing. What it buys is that **one function body
can handle the vector part and the leftover part of a loop**. The stdlib's
own `vectorize` (`std/algorithm/backend/vectorize.mojo`) works like this:

```mojo
for i in range(0, simd_end, simd_width):
    closure[simd_width](i)        # main part: width 8, 16, 32 ...
for i in range(simd_end, size):
    closure[1](i)                 # leftover elements: width 1 = a plain scalar
```

The closure is written once, as `def copy[width: Int](offset: Int)`. It's
compiled twice: with `width = 32` for the main part, and with `width = 1`,
where every `SIMD[dtype, width]` in it is just `Int`, `UInt8` and so on. If
scalars were a separate type, every such routine would need two versions.
Before Mojo 1.0 that was the case: `Int` was its own struct, and the stdlib
carried duplicate `Int` overloads. The 1.1 release notes describe removing
those for this reason.

So the design is: **the type system treats every number as a vector, so
vector code is easy to write; the compiler only emits vector instructions
where you ask for vectors.**

## 5. Comparison with C's `memcpy`

glibc's `memcpy` isn't auto-vectorized by the compiler either. It is
hand-written assembly with several versions (SSE2, AVX2, AVX-512). The C
library picks one at program start, based on the CPU it finds.

Mojo takes a different route. `unsafe_memcpy` is ordinary Mojo code in
`std/memory/memory.mojo` (`_memcpy_impl`):

- sizes under 5 bytes are copied one byte at a time
- sizes up to 16 bytes use 4- or 8-byte loads
- larger copies use `vectorize[32](n, copy)`, 32 bytes at a time

It is inlined and compiled for your target CPU, so on this machine it uses
`ymm` registers. The library is written by hand, just in Mojo instead of
assembly, and that `vectorize` loop is exactly where `closure[1]`, and so
`Int` being `SIMD[DType.int, 1]`, matters.

## 6. Explicit SIMD does use vector registers

`L01/simd_search.mojo` does the sum and the search 4 Ints at a time:

```mojo
comptime W = 4      # 4 x 64-bit Int = 256 bits (one AVX2 register)

var p = data.unsafe_ptr()
while i + W <= n:
    var hits = p.unsafe_load[width=W](i).eq(SIMD[DType.int, W](target))
    if hits.reduce_or():                   # any lane matched?
        ...
    i += W
# then finish the leftover elements one at a time
```

On the host CPU the search uses `vpcmpeqq` (compare 4 lanes),
`vmovmskpd` (collect the lane results into a bit mask) and `ymm` registers,
and the sum uses `vpaddq`. `unsafe_load` skips bounds checks, so the loop is
responsible for staying inside the list.

Sorting is harder to vectorize by hand. The stdlib `sort()` is a normal
comparison sort.

## 7. Adding two 1024-element arrays

**By default the addition is not vectorized.** A plain loop like
`c[i] = a[i] + b[i]` adds one element at a time. You get vector addition only
by asking for it. `L01/add1024.mojo` times four versions, each run 200,000
times (stable across repeated runs):

| Version | Default build | `-D ASSERT=none` | Vector instructions? |
|---|---|---|---|
| `List` plain loop | **~2,000 to 2,600 ns** | 185 ns | no (`addq`) |
| `Array[Int, 1024]` plain loop | 180 ns | 180 ns | no (`addq`) |
| `vectorize[4]` (stdlib helper) | **60 ns** | 60 ns | yes (`vpaddq ymm`) |
| Hand-written SIMD loop | 105 ns | 105 ns | yes (`vpaddq ymm`) |

That's about 3x faster vectorized than a scalar loop without bounds checks,
and about 40x faster than the default `List` loop.

What the table shows:

1. **No vector instructions unless you ask.** Both plain loops compile to one
   scalar `addq` per element, even with bounds checks off, because Mojo has no
   loop vectorizer (section 2). The data layout doesn't matter: a `List` and an
   `Array` are both plain memory, and neither is a SIMD vector.
2. **Bounds checks make the default `List` loop very slow.** Each of the three
   accesses (`a[i]`, `b[i]`, `c[i]`) does a compare and branch. Before each
   one, the compiler also writes 6 values to the stack, the source-location
   details for the error message. That is 18 extra stores per element:

   ```
   movq   $6, 16(%rsp)        # these 6 stores are repeated
   movq   %r14, 8(%rsp)       # before each of the 3 checks,
   movq   %rbx, 24(%rsp)      # on every element
   movq   $39, 40(%rsp)
   movq   %r15, 32(%rsp)
   movq   %rbx, 48(%rsp)
   cmpq   %rsi, %r9           # i < len(a)?
   jae    .LBB0_7             # no: abort
   ```

3. **`Array[Int, 1024]` doesn't pay for bounds checks.** The size is known at
   compile time, so the compiler proves `i < 1024` and removes the checks.
   How to avoid bounds-check cost in general: [bounds-checks.md](bounds-checks.md).
4. **`vectorize` beat the hand-written SIMD loop.** Both use the same `vpaddq`
   on `ymm`. `vectorize` computes the end of the vector part (`n & -4`) once,
   giving a 6-instruction loop:

   ```
   .LBB2_2:
       vmovdqu  (%rsi,%r10,8), %ymm0
       vpaddq   (%rax,%r10,8), %ymm0, %ymm0
       vmovdqu  %ymm0, (%rdi,%r10,8)
       addq     $4, %r10
       cmpq     %r9, %r10
       jl       .LBB2_2
   ```

   The hand-written `while i + W <= n:` loop took 7, including an extra
   register move. One extra instruction doesn't obviously explain 105 vs 60 ns;
   the CPU may handle the loop shape differently. The exact cause can't be
   pinned down from the assembly alone. In practice: prefer `vectorize` over a
   hand-rolled loop.

The vectorized version:

```mojo
from std.algorithm import vectorize

def add_vectorize(mut c: List[Int], a: List[Int], b: List[Int]):
    var pa = a.unsafe_ptr()
    var pb = b.unsafe_ptr()
    var pc = c.unsafe_ptr()
    def step[width: Int](i: Int) {imm}:
        pc.unsafe_store(i, pa.unsafe_load[width=width](i) + pb.unsafe_load[width=width](i))
    vectorize[4](len(a), step)
```

`width` is 4 for the main loop and 1 for any leftover elements (1024 divides
evenly, so there are none here). `{imm}` captures the pointers immutably.
With `unsafe_ptr`/`unsafe_load` the code skips bounds checks entirely, so it's
up to you that `a`, `b` and `c` are all at least `len(a)` long.

## 8. Which CPU does `mojo build` target?

**The host CPU, by default.** `mojo build --print-effective-target file.mojo`
shows it:

```
--target-triple x86_64-unknown-linux-gnu
--target-cpu raptorlake
--target-features +adx,+aes,+avx,+avx2,+avxvnni,+bmi,+bmi2,...,+sse4.2,...
```

So a default build may use every instruction this CPU has. Target options from
`mojo build --help`: `--target-cpu`, `--target-features`, `--target-triple`,
`--march`, `--mcpu`, `--mtune`, `--print-supported-cpus`.

The same `simd_search.mojo` built for three targets:

| Build | Vector registers | Instructions | Ran correctly? |
|---|---|---|---|
| Host (`raptorlake`) | `ymm` (AVX2, 256-bit) | `vpaddq`, `vpcmpeqq`, `vmovmskpd` | yes |
| `--target-cpu x86-64` | `xmm` only (SSE2, 128-bit) | `paddq`, `pcmpeqd`, `movmskps` | yes |
| `--target-features "-sse,-sse2,-mmx"` | none | plain `addq` | yes |

The compiler splits each `SIMD` operation into what the target supports:

- On SSE2, one 256-bit add becomes two 128-bit adds. SSE2 has no 64-bit
  compare (`pcmpeqq`), so the compiler builds it from 32-bit compares
  (`pcmpeqd`).
- With all vector features off, the 4-lane code becomes ordinary scalar
  instructions. So `SIMD` code never needs vector hardware to work; it is just
  slower without it.

## 9. Running on a CPU without the instructions

A host-tuned binary can contain AVX2 instructions. On a CPU without AVX2, the
first such instruction stops the program with "Illegal instruction"
(`SIGILL`). This was not demonstrated here: no older CPU or emulator (`qemu`,
Intel SDE) was available.

A CPU with no vector unit at all is not a concern on Mojo's platforms: every
x86-64 CPU has SSE2 and every ARM64 CPU has NEON.

### The runtime libraries set a floor

Every Mojo program loads Modular's prebuilt runtime libraries (`ldd` on a
binary):

| Library | Size | `ymm` instructions | AVX2-only instructions |
|---|---|---|---|
| `libKGENCompilerRTShared.so` | 1.3 MB | 3675 | 328 |
| `libAsyncRTRuntimeGlobals.so` | 672 KB | 1996 | 226 |
| `libMSupportGlobals.so` | 52 KB | 283 | 44 |

("AVX2-only" counts `vpbroadcast`, `vperm`, `vpgather`, `vinserti128` and
`vextracti128`.) `mojo-src/docs/requirements.mdx` says Mojo needs an
**x86-64-v3** CPU (Haswell-class, about 2013 or newer: AVX, AVX2, BMI1, BMI2,
F16C, FMA, LZCNT, MOVBE, XSAVE), or ARM64 Neoverse N1 or newer, or Apple
silicon.

So a `--target-cpu x86-64` build contains no AVX in your own code
(`objdump` found none in the executable), but it may still fail on a pre-2013
CPU because of the libraries. Whether the libraries check the CPU before
using those instructions was not tested.

## 10. Separate binaries?

- **For your own machine:** no. The default (host CPU) build is the fastest
  for it.
- **To run elsewhere:** build for the oldest CPU you need to support:
  - `--target-cpu x86-64-v3` matches Mojo's official minimum.
  - `--target-cpu x86-64` is the most compatible for your own code, but see
    the runtime library floor above.
  - Ship two builds (for example `x86-64-v3` and one with AVX-512) only if
    speed on newer CPUs matters.

## Summary

- An `Int` array is plain memory, not a SIMD vector.
- Plain loops (sort, search, sum) compile to scalar code. Bounds checks block
  vectorization, and even without them Mojo does not run LLVM's loop
  vectorizer. Write explicit `SIMD` code for vector speed.
- Mojo does vectorize a little on its own: fill loops become (vectorized)
  `memset` calls, and the straight-line (SLP) vectorizer combines neighbouring
  operations outside loops. Most vector speed comes from stdlib code written
  with explicit SIMD (`memcpy`, `String.find`, UTF-8 validation).
- `Int` is `SIMD[DType.int, 1]` so one generic function can serve both the
  vector part (`width = N`) and the leftover part (`width = 1`) of a loop, as
  in `vectorize`. It costs nothing: width 1 compiles to scalar code.
- Adding two 1024-element Int arrays: a plain loop is scalar (180 ns
  unchecked, ~2,000+ ns for a bounds-checked `List`); `vectorize[4]` takes
  60 ns. Fixed-size `Array` loops get their bounds checks removed for free.
- `mojo build` targets the host CPU by default. Use `--target-cpu` for
  portable binaries.
- `SIMD` code works on any target; the compiler splits it into narrower or
  scalar instructions.
- Mojo's runtime libraries need an x86-64-v3 (AVX2) CPU, whatever target you
  compile your own code for.
