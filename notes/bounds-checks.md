# Bounds checks: cost and how to avoid them

Bounds checks can slow a loop down a lot. How do you design programs that
don't need them, and can they be turned off for one function, loop or
package? Companion to [simd-codegen.md](simd-codegen.md) (section 7 has the
first measurements). Checked with Mojo 1.1.0 on an Intel Core i7-14700.
Sources: `mojo-src/stdlib/std/collections/list.mojo`, `check_bounds.mojo`,
`mojo-src/docs/tools/feature-toggles.mdx`,
`notes/mojo-release-notes/v1.0.0b1.md`.

Test programs:

- `L01/bounds.mojo`: five versions, timed, with a check count for each.
- `L01/bounds_switch.mojo`: a project-specific compile-time switch.

## Short answer

You can design for this, but Mojo has no way to switch off bounds checks for
just a function, loop or package. You choose unchecked access at each access,
at the type level, or for the whole build. Combined with checking the data
once up front, that gets the full speed.

## How a bounds check works

Since Mojo 1.0, bounds checking is on by default for all collections on CPU
(off on GPU). `List.__getitem__` is ordinary library code:

```mojo
def __getitem__(ref self, idx: Int, /) -> ref[...] Self.T:
    check_bounds(idx, len(self))
    return self.unsafe_get(index(idx))
```

and `check_bounds` (`collections/check_bounds.mojo`) is a tagged assertion:

```mojo
debug_assert[assert_mode=_AssertMode[cpu_default]](
    UInt(index(idx)) < UInt(size),
    "index ", index(idx), " is out of bounds, valid range is 0 to ", size - 1,
    location=...,
)
```

`-D ASSERT` decides which assertions run (`feature-toggles.mdx`):

| Value | Effect |
|---|---|
| `safe` (default) | only assertions tagged `assert_mode="safe"`, such as normal bounds checks |
| `none` | no assertions at all |
| `all` | every assertion, including checks that are off by default |
| `warn` | every assertion, but print a warning instead of aborting |

### Why they are so expensive here

A single compare-and-branch would be cheap. But before each check, the
compiler stores six values for the error message (string pointers and
lengths for the source location), every time through the loop:

```
movq   $6, 16(%rsp)        # these 6 stores are repeated
movq   %r14, 8(%rsp)       # before every check,
movq   %rbx, 24(%rsp)      # on every element
movq   $39, 40(%rsp)
movq   %r15, 32(%rsp)
movq   %rbx, 48(%rsp)
cmpq   %rsi, %r9           # i < len?
jae    .LBB0_7             # no: abort
```

With three accesses per element (`c[i] = a[i] + b[i]`) that is 18 extra
stores per element.

## Measurements

`L01/bounds.mojo`, 1024-element `List[Int]`s, default build (bounds checks
on):

| Version | ns per call | Checks left in the loop |
|---|---|---|
| `add_checked`: plain `c[i] = a[i] + b[i]` | 2,570 | 3 per element |
| `add_validated`: compare the 3 lengths once, then the same loop | 791 | 1 |
| `add_unsafe_get`: compare lengths once, then `unsafe_get` | **206** | 0 |
| `sum_indexed`: `for i in range(len(a)): s += a[i]` | 786 | 1 |
| `sum_iter`: `for x in a: s += x` | **193** | 0 |

## Can the compiler drop the checks on its own?

Only partly. The optimizer can remove a check when it can prove the condition
holds:

- **Validating up front helped.** After
  `if len(b) != n or len(c) != n: abort(...)`, two of the three checks
  disappeared (2,570 to 791 ns).
- **It doesn't remove everything.** Even `sum_indexed`, where `i` runs over
  `range(len(a))`, kept its check. The comparison is unsigned while the loop
  counts to a signed `max(len, 0)`. A guess: the optimizer doesn't connect
  the two.
- **Fixed sizes work fully.** `Array[Int, 1024]` with a constant loop bound
  had all checks removed (simd-codegen.md, section 7).

## The controls you have

| Scope | How | Measured or verified |
|---|---|---|
| **Single access** | `list.unsafe_get(i)`, which returns a reference, so `c.unsafe_get(i) = ...` works too. `Array` and `Span` have `unsafe_get` as well. Or use `ptr = list.unsafe_ptr()` with `ptr[unsafe_offset=i]` / `ptr.unsafe_load[width=W](i)` | 206 ns, 0 checks |
| **No index at all** | `for x in list:` (or `zip`) | 193 ns, 0 checks |
| **Your own collection type** | call `check_bounds[cpu_default=False](i, size)` in its `__getitem__`: off by default, on with `-D ASSERT=all` | the same mechanism `unsafe_get` uses |
| **Your own switch** | `comptime UNCHECKED = is_defined["FASTADD"]()`, then `comptime if UNCHECKED:` chooses the checked or unchecked loop. Build with `-D FASTADD` | 3 checks normally, 0 with `-D FASTADD` |
| **Whole program** | `-D ASSERT=none` | turns off every assertion, stdlib included |

There is no decorator, and no per-function, per-loop or per-package option.
`-D ASSERT` applies to the whole build, including the stdlib. The
project-specific switch is the closest you get to per-package control: you
define it yourself and use it only where you choose.

### The project switch (`L01/bounds_switch.mojo`)

```mojo
from std.sys import is_defined

# Our own switch, independent of -D ASSERT: build with -D FASTADD to skip checks.
comptime UNCHECKED = is_defined["FASTADD"]()

def add(mut c: List[Int], a: List[Int], b: List[Int]):
    comptime if UNCHECKED:
        for i in range(len(a)):
            c.unsafe_get(i) = a.unsafe_get(i) + b.unsafe_get(i)
    else:
        for i in range(len(a)):
            c[i] = a[i] + b[i]
```

Only the chosen branch is compiled. `std.sys` also has `get_defined_bool`,
`get_defined_int` and `get_defined_string` for switches with values.

## `unsafe_get` still has a safety net

`List.unsafe_get` is not completely unchecked:

```mojo
def unsafe_get(ref self, idx: Int) -> ref[...] Self.T:
    check_bounds[cpu_default=False](idx, len(self))
    return self._unsafe_interior_ptr().unsafe_offset(idx)[]
```

`cpu_default=False` means the check is off by default but turned on by
`-D ASSERT=all`. Tested with an out-of-range `unsafe_get`:

| Build | Result |
|---|---|
| default | silently read garbage (`read: 0`): undefined behaviour, the result is unpredictable |
| `-D ASSERT=all` | `Assert Error: index 8 is out of bounds, valid range is 0 to 2`, with the source line |

Raw pointer access (`unsafe_ptr()`, `unsafe_offset`, `unsafe_load`) has no
such safety net.

## Recommended pattern

1. **Check once at the boundary.** Validate lengths, ranges and invariants
   when the data comes in, or at the start of the hot function, and abort or
   raise with a clear message.
2. **Use unchecked access only inside that function**, right after the
   validation, so the reasoning is local and easy to review.
3. **Prefer forms that don't need an index:** `for x in list`, `zip`,
   fixed-size `Array`, or `vectorize` with pointers.
4. **Keep a checked test build.** Run tests with `-D ASSERT=all` (which also
   turns `unsafe_get`'s check back on) and ship the default build.

Example of steps 1 and 2 (`add_unsafe_get` in `L01/bounds.mojo`):

```mojo
def add_unsafe_get(mut c: List[Int], a: List[Int], b: List[Int]):
    var n = len(a)
    if len(b) != n or len(c) != n:
        abort("add_unsafe_get: length mismatch")
    for i in range(n):
        c.unsafe_get(i) = a.unsafe_get(i) + b.unsafe_get(i)
```

## Summary

- A bounds check is library code (`check_bounds` in `List.__getitem__`), on
  by default on CPU, controlled by `-D ASSERT` for the whole build.
- It is expensive in Mojo 1.1 because the error message details are stored
  before every check: a bounds-checked `List` loop was 12x slower than the
  unchecked version.
- The compiler removes checks only when it can prove them: fully for
  fixed-size `Array` loops, partly after validating lengths, not at all for a
  plain `range(len(a))` loop.
- There is no per-function, per-loop or per-package switch. Use `unsafe_get`
  or pointers per access, `for x in list` to avoid indexes, `check_bounds[
  cpu_default=False]` in your own types, or your own `is_defined` switch.
- Validate once, then go unchecked in a small reviewed function, and test
  with `-D ASSERT=all`.
