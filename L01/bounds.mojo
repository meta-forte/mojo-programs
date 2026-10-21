# Ways to avoid bounds-check cost on List[Int], timed: plain indexing, length
# validation up front, unsafe_get, and iterating without an index.
# Explained in notes/bounds-checks.md.
#
#   ./build.sh -r L01/bounds.mojo
#
# Count the bounds checks left in each function:
#   mkdir -p build/L01 && mojo build --emit asm -o build/L01/bounds.s L01/bounds.mojo
#   for f in add_checked add_validated add_unsafe_get sum_indexed sum_iter; do
#     echo "$f: $(awk "/^\"bounds::$f\\(/,/^.Lfunc_end/" build/L01/bounds.s | grep -c _debug_assert_fail)"
#   done
#   # expected: 3 1 0 1 0

from std.benchmark import keep
from std.os import abort
from std.time import perf_counter_ns

comptime N = 1024
comptime REPS = 200_000

@no_inline
def add_checked(mut c: List[Int], a: List[Int], b: List[Int]):
    # Baseline: three bounds checks per element.
    for i in range(len(a)):
        c[i] = a[i] + b[i]

@no_inline
def add_validated(mut c: List[Int], a: List[Int], b: List[Int]):
    # Check the lengths once, then loop to n. Can the compiler drop the checks?
    var n = len(a)
    if len(b) != n or len(c) != n:
        abort("add_validated: length mismatch")
    for i in range(n):
        c[i] = a[i] + b[i]

@no_inline
def add_unsafe_get(mut c: List[Int], a: List[Int], b: List[Int]):
    # Validate once, then unchecked element access.
    var n = len(a)
    if len(b) != n or len(c) != n:
        abort("add_unsafe_get: length mismatch")
    for i in range(n):
        c.unsafe_get(i) = a.unsafe_get(i) + b.unsafe_get(i)

@no_inline
def sum_indexed(a: List[Int]) -> Int:
    var s = 0
    for i in range(len(a)):
        s += a[i]
    return s

@no_inline
def sum_iter(a: List[Int]) -> Int:
    # Iterating the list directly: no index, so nothing to check.
    var s = 0
    for x in a:
        s += x
    return s

def main():
    var a: List[Int] = []
    var b: List[Int] = []
    var c: List[Int] = []
    for i in range(N):
        a.append(i)
        b.append(2 * i)
        c.append(0)

    var t0 = perf_counter_ns()
    for _ in range(REPS):
        add_checked(c, a, b)
        keep(c)
    var t1 = perf_counter_ns()
    for _ in range(REPS):
        add_validated(c, a, b)
        keep(c)
    var t2 = perf_counter_ns()
    for _ in range(REPS):
        add_unsafe_get(c, a, b)
        keep(c)
    var t3 = perf_counter_ns()
    var s1 = 0
    for _ in range(REPS):
        s1 += sum_indexed(a)
        keep(s1)
    var t4 = perf_counter_ns()
    var s2 = 0
    for _ in range(REPS):
        s2 += sum_iter(a)
        keep(s2)
    var t5 = perf_counter_ns()

    print("check:", c[N - 1], s1 == s2)
    print("ns per call (1024 elements):")
    print("  add_checked    :", (t1 - t0) // REPS)
    print("  add_validated  :", (t2 - t1) // REPS)
    print("  add_unsafe_get :", (t3 - t2) // REPS)
    print("  sum_indexed    :", (t4 - t3) // REPS)
    print("  sum_iter       :", (t5 - t4) // REPS)
