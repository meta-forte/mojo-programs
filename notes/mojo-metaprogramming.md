# Metaprogramming and Generics in Mojo 1.1

Sources: `mojo-src/docs/manual/metaprogramming/` (index, comptime-evaluation,
materialization, reflection, constraints), `mojo-src/docs/manual/generics.mdx`,
`mojo-src/docs/manual/parameters/index.mdx`, `mojo-src/docs/manual/traits.mdx`,
`mojo-src/docs/roadmap.mdx`. Key claims verified with Mojo 1.1.0 using
`L01/meta_check.mojo` (output at the end).

## 1. Compile-time code execution

Yes. Mojo can run ordinary Mojo code at compile time, much like Jai's
`#run`. It is not as unrestricted as Jai, though, and the compiler cannot
change your program's code while it runs.

Anything marked with `comptime` is evaluated by the compiler. That includes
`comptime` values, `comptime if`, `comptime for` and parameter values in
`[...]`. The function you call is a normal `def`; you don't need a special
"constexpr" version:

```mojo
def fib(n: Int) -> Int: ...                 # plain runtime function
def primes_upto(n: Int) -> List[Int]: ...   # allocates a heap List

comptime F30 = fib(30)               # computed by the compiler: 832040
comptime PRIMES = primes_upto(30)    # List built during compilation
print(materialize[PRIMES]())         # copied into the runtime program
```

In the test build, neither `fib` nor `primes_upto` appeared in the binary
(`nm` found no symbols), because only their results were needed.

### How it works

The compiler has three stages:

1. **Parser:** turns the code into IR and type-checks it. Very simple
   expressions like `2 + 3` are constant-folded here.
2. **Elaborator:** replaces parameters with concrete values and produces
   concrete versions of generic functions and structs.
3. **Interpreter:** when the elaborator hits a call that must run at compile
   time, the interpreter makes sure that function has been elaborated,
   runs it like a small separate program, and puts the result back into
   the code.

Because a function is fully elaborated before it is interpreted, a failing
`comptime assert` stops compilation before any part of that function runs,
even code written before the assertion.

### Compared with Jai's `#run`

- **Allowed:** loops, recursion, heap allocation, `List`, `Dict`, `String`
  and user structs.
- **Not allowed at compile time:**
  - file I/O
  - calls into C libraries
  - functions that can `raise`
  - GPU code (compile-time parts of GPU code run on the CPU)
- **No code generation from strings:** compile-time code can compute values
  and types and choose which code gets compiled. It cannot build new code as
  text or rewrite the syntax tree. There are no macros and no `#insert`.
- **Moving values to runtime (materialization):** simple values like `Int`
  are copied into the program automatically. Values that own heap memory,
  like `List`, must be copied explicitly with `materialize[...]()`.
  Otherwise the compiler reports "cannot materialize comptime value ...
  because it is not 'ImplicitlyCopyable'".

## 2. How metaprogramming works

The same Mojo language is used at compile time and at runtime.
Metaprogramming is built from these pieces:

| Feature | What it does |
|---|---|
| `comptime X = expr` | A compile-time constant, a type alias, or a parameterized alias such as `comptime Pair[T: ...] = ...` |
| `comptime if` | Only the chosen branch is compiled at all |
| `comptime for` | The loop is fully unrolled, with the loop variable as a constant |
| Parameters `[...]` | Compile-time inputs to functions and structs. They can be types or values, e.g. `SIMD[DType.float32, 8]` |
| Traits | Describe what a type must provide, checked at compile time |
| `where` clauses, `comptime assert` | Compile-time conditions; failing one is a compile error |
| `conforms_to(T, Trait)` | Asks at compile time whether `T` has a trait, then lets you use that trait in that branch |
| Reflection `reflect[T]` | Gives `.name()`, `.field_count()`, `.field_names()`, `.field_types()` |
| `rebind[T](x)` | Tells the compiler two generic types are the same after elaboration (needed inside `comptime if` branches) |

A function cannot return a type as a value (`def f() -> AnyType` is not
allowed), but a `comptime` alias can be a type:

```mojo
comptime TwoOfAKind[dt: DType] = SIMD[dt, 2]
comptime StringKeyDict[V: Copyable & Deinitable] = Dict[String, V]
```

### Compile-time trait checks

```mojo
def describe[T: AnyType]() -> String:
    comptime if conforms_to(T, Writable):
        return String(reflect[T].name(), " is Writable")
    else:
        return String(reflect[T].name(), " is not Writable")
```

### Reflection with `comptime for`

Reflection and `comptime for` together give you code that adapts to a
struct's fields:

```mojo
def show_fields[T: AnyType]():
    comptime names = reflect[T].field_names()
    comptime types = reflect[T].field_types()
    comptime for i in range(reflect[T].field_count()):
        comptime name = names[i]        # bind as comptime, see note below
        print("  ", name, ":", reflect[types[i]].name())
```

Note: writing `names[i]` directly inside `print` fails, because it tries to
materialize the whole `Array` of names at runtime. Binding the single element
to a `comptime` first fixes it.

The stdlib uses the same technique to give structs default `==`, hashing and
printing (`Equatable`, `Hashable`, `Writable`) without extra code.
Reflection has no runtime cost. The docs mark it as new and still
incomplete.

## 3. Generics at compile time and at runtime

### At compile time

- Generic parameters go in `[]`, runtime arguments in `()`. The syntax always
  shows which is which.
- Parameters can be types (`T: Comparable`) or values
  (`threshold: T`, `size: Int`).
- The generic body is type-checked once, using only the traits you required,
  before any specialization. That is unlike C++ templates, which are checked
  again for each type. Using an operation not covered by the trait bounds is
  a compile error.
- The elaborator then creates one concrete copy of the code for each set of
  parameters used. `all_equal[Int]` and `all_equal[String]` become two
  separate functions (monomorphization).
- Value parameters work the same way. A `matmul[M, N, K]` can choose a
  different algorithm with `comptime if` depending on the sizes.

```mojo
def count_above[
    T: Comparable & ImplicitlyCopyable & Deinitable, threshold: T
](values: List[T]) -> Int:
    ...
```

### At runtime

- Only concrete, specialized code is left. A trait method call is a direct
  call, often inlined.
- There are no vtables, boxing or runtime type checks. A `List[Int]` holds
  plain 8-byte integers, not pointers to objects.
- Structs have no runtime dispatch at all. Runtime polymorphism through
  traits (trait objects or "existentials") is not available yet; the roadmap
  lists it as future work.
- For runtime choice between types, use `Variant[A, B, ...]` (a tagged
  union) or plain function pointers.

## 4. Is generic information removed at runtime, as in Java?

The result looks similar but the mechanism is the opposite.

- **Java:** keeps one shared copy of the generic code and erases `T` to
  `Object`. You get casts and boxing, and `List<int>` is not possible.
- **Mojo:** never erases `T`. It makes a separate copy of the code for each
  `T`, so the full type information is used to generate exact code.

What reaches the final binary is plain machine code, with no type metadata
or runtime reflection. A type name only appears in the binary if you ask for
it, for example with `reflect[T].name()`, and then only as a constant string.

| | Java | C++ templates | Rust | Mojo |
|---|---|---|---|---|
| Strategy | Type erasure | Monomorphization | Monomorphization | Monomorphization |
| Generic body checked | Once | Per instantiation | Once (trait bounds) | Once (trait bounds) |
| Value parameters | No | Yes | Const generics | Yes, any comptime value |
| Primitive element types | Boxed | Unboxed | Unboxed | Unboxed |
| Runtime dynamic dispatch | Yes | Virtual functions | `dyn Trait` | Not yet (roadmap) |

**Trade-offs (the same as C++ and Rust):**

- You get zero runtime cost and full specialization.
- In exchange, binaries are larger and compiles are slower, especially with
  `comptime for` unrolling.
- You cannot pick a generic type based on runtime data.

## 5. Printing at compile time

Mojo has no dedicated compile-time print (nothing like Jai's `#run print`
or a `static_print`), and the docs do not mention one. But a plain `print`
inside a function works when that function is evaluated by the compiler's
interpreter. The output goes to the compiler's stdout during the build.
(The docs list file I/O as not allowed at compile time; printing to stdout
is the exception that works.)

Example: `L01/comptime_demo.mojo`

```mojo
def compile_time_hello() -> Bool:
    print("Hello world")
    return True

def main():
    comptime HELLO_DONE = compile_time_hello()   # runs inside the compiler
    comptime if HELLO_DONE:
        print("begin")
        print("end")
```

```
$ mojo build L01/comptime_demo.mojo     $ ./comptime_demo
Hello world                             begin
                                        end
```

Findings (verified with Mojo 1.1.0):

1. **The `comptime` value must be used.** If nothing uses it, the compiler
   never evaluates the expression, so the function never runs and nothing is
   printed. A `comptime _x = say_hello()` that is never referenced printed
   nothing. Using the value in a `comptime if` forces evaluation without
   adding any runtime code.
2. **The text is not in the binary.** `strings comptime_demo | grep "Hello
   world"` finds nothing. The print happens only inside the compiler.
3. **`mojo run` = compile + run.** On a fresh compile it prints all three
   lines: `Hello world` (compiler), then `begin`, `end` (program).
4. **Compiled code is cached.** If the code has not changed, Mojo reuses the
   cached compile and the compile-time print does not appear. The cache is
   keyed on the compiled code, not the file text:

   | Edit to the source | Recompiled? | "Hello world" shown? |
   |---|---|---|
   | None | No | No |
   | Comment added | No | No |
   | Whitespace inside code, e.g. `print("end" )` | No | No |
   | Real code change, e.g. `print("end!")` | Yes | Yes |
   | Same code, different file name (module name changes) | Yes | Yes |

   The cache lives in `~/.cache/modular/.mojo_cache` (under
   `$XDG_CACHE_HOME` if set), separate from the output file. Deleting the
   executable does not bring the message back:

   | Build of unchanged `L01/dce.mojo` | Compile-time print shown? |
   |---|---|
   | Deleted the executable, rebuilt | No |
   | Built to a new output name (`-o other`) | No |
   | Built with an empty cache folder (`XDG_CACHE_HOME=<empty dir>`) | Yes |

   To see the compile-time print again, do one of these:

   - Make a real code change (comments and whitespace don't count).
   - Build with a temporary empty cache, leaving the real cache alone:
     `XDG_CACHE_HOME=$(mktemp -d) mojo build L01/dce.mojo`
   - Delete `~/.cache/modular/.mojo_cache`. Mojo rebuilds it as needed; the
     next build of every program just takes longer.

   So compile-time prints are fine for debugging metaprograms, but do not
   rely on them as build output that always appears.

**Alternative: a compiler warning.** Calling a function marked
`@deprecated("msg")` from a `comptime` expression makes the compiler emit
`warning: msg` with the source location. This goes to the diagnostics stream
instead of stdout:

```mojo
@deprecated("Hello world")
def hello_world_at_compile_time() -> Int:
    return 1

def main():
    comptime y = hello_world_at_compile_time()
```

```
ct2.mojo:13:18: warning: Hello world
    comptime y = hello_world_at_compile_time()
                 ^~~~~~~~~~~~~~~~~~~~~~~~~~~
```

The message must be a fixed string, so this cannot print computed values;
use `print` for those. For a message that should stop the build, use
`comptime assert cond, "msg"`, which only reports when the condition fails.

## 6. Which functions end up in the binary?

A function used only at compile time is **not** part of the binary, whether
or not its result is used. A function whose `comptime` result is never used
does not even run.

Test: `L01/dce.mojo`. All four functions are marked `@no_inline`, so none
can disappear just by being inlined:

```mojo
def main():
    comptime A = comptime_used()      # result printed below
    comptime B = comptime_unused()    # result never used
    print("A =", A)
    print("rt =", runtime_called())   # normal runtime call
    # never_called() is not called anywhere
```

| Function | How it's used | Ran during build? | In binary? |
|---|---|---|---|
| `comptime_used` | `comptime A = comptime_used()`, and `A` is printed | Yes | **No** |
| `comptime_unused` | `comptime B = comptime_unused()`, `B` never used | No | **No** |
| `never_called` | not called anywhere | No | **No** |
| `runtime_called` | called normally in `main` | No (runs when the program runs) | **Yes** (`dce::runtime_called()`) |

Checked with `nm` (symbols) and `strings` (text in the binary). The results
were the same in a debug build (`mojo build -O0`), which shows the compiler
never generates the unused functions at all; they are not added and then
optimized away.

Why it works this way:

- **Only reachable code is compiled.** Mojo starts from `main` and compiles
  only what the program actually calls at runtime. A function nothing
  reaches never becomes machine code.
- **Compile-time use doesn't put a function in the binary.** When a
  `comptime` value needs a function, the compiler compiles that function for
  its own interpreter, runs it, and keeps only the result. For
  `comptime_used`, only the constant `1` reached the binary; the string
  `"comptime_used ran"` is not there either.
- **Unused `comptime` values are never evaluated.** So `comptime_unused` did
  not run during the build and does not appear anywhere.

A function used both ways, at compile time and in a normal runtime call, is
included because of the runtime call.

## 7. Verification run (Mojo 1.1.0)

`L01/meta_check.mojo` output:

```
fib(30) = 832040                                  <- computed at compile time
primes: [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]      <- List built at compile time
SIMD[DType.int, 1] is Writable                    <- conforms_to check (Int)
meta_check.Point is not Writable                  <- conforms_to check (struct)
   x : SIMD[DType.int, 1]                         <- reflection over fields
   y : SIMD[DType.float64, 1]
```

## Summary

- Compile-time execution: yes, ordinary `def` functions run in a compiler
  interpreter wherever `comptime` requires a value. No I/O, FFI or raising
  functions. No code generation from text.
- Metaprogramming: `comptime` values and control flow, parameters, traits,
  `where` / `comptime assert`, `conforms_to`, and compile-time reflection.
- Generics: checked once against trait bounds, then specialized for each
  concrete type or value.
- Runtime: only concrete code remains. No erasure-style shared code, no
  boxing, no vtables. Dynamic traits are on the roadmap.
- Compile-time printing: plain `print` in a function evaluated through a
  used `comptime` value prints during the build, but only when the code is
  actually recompiled (not cached). `@deprecated("msg")` gives a warning
  instead.
- Binary contents: functions used only at compile time, and functions never
  called, are not compiled into the binary (even at `-O0`). Only the
  `comptime` results that the program uses are embedded.
