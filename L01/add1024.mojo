# Adding two 1024-element Int arrays: plain loops vs vectorize vs hand-written
# SIMD, timed. Explained in notes/simd-codegen.md ("Adding two 1024-element
# arrays").
#
#   ./build.sh -r L01/add1024.mojo                    # default: bounds checks on
#   ./build.sh -r -D ASSERT=none L01/add1024.mojo     # bounds checks off
#
# Assembly (vpaddq appears only in add_vectorize and add_simd_loop):
#   mkdir -p build/L01 && mojo build --emit asm -o build/L01/add1024.s L01/add1024.mojo
#   for f in add_list_loop add_array_loop add_vectorize add_simd_loop; do
#     echo "$f: $(awk "/^\"add1024::$f\\(/,/^.Lfunc_end/" build/L01/add1024.s | grep -c vpaddq)"
#   done

from std.algorithm import vectorize
from std.benchmark import keep
from std.time import perf_counter_ns

comptime N = 1024
comptime REPS = 200_000

@no_inline
def add_list_loop(mut c: List[Int], a: List[Int], b: List[Int]):
    # The obvious way: one element at a time.
    for i in range(len(a)):
        c[i] = a[i] + b[i]

@no_inline
def add_array_loop(mut c: Array[Int, N], a: Array[Int, N], b: Array[Int, N]):
    # Same, on fixed-size arrays (trip count known at compile time).
    for i in range(N):
        c[i] = a[i] + b[i]

@no_inline
def add_vectorize(mut c: List[Int], a: List[Int], b: List[Int]):
    # stdlib vectorize: 4 Ints (one ymm register) per step, leftovers at width 1.
    var pa = a.unsafe_ptr()
    var pb = b.unsafe_ptr()
    var pc = c.unsafe_ptr()
    def step[width: Int](i: Int) {imm}:
        pc.unsafe_store(i, pa.unsafe_load[width=width](i) + pb.unsafe_load[width=width](i))
    vectorize[4](len(a), step)

@no_inline
def add_simd_loop(mut c: List[Int], a: List[Int], b: List[Int]):
    # Explicit SIMD loop, no helper.
    comptime W = 4
    var pa = a.unsafe_ptr()
    var pb = b.unsafe_ptr()
    var pc = c.unsafe_ptr()
    var n = len(a)
    var i = 0
    while i + W <= n:
        pc.unsafe_store(i, pa.unsafe_load[width=W](i) + pb.unsafe_load[width=W](i))
        i += W
    while i < n:
        pc[unsafe_offset=i] = pa[unsafe_offset=i] + pb[unsafe_offset=i]
        i += 1

def main():
    var a: List[Int] = []
    var b: List[Int] = []
    var c: List[Int] = []
    var aa = Array[Int, N](fill=0)
    var bb = Array[Int, N](fill=0)
    var cc = Array[Int, N](fill=0)
    for i in range(N):
        a.append(i)
        b.append(2 * i)
        c.append(0)
        aa[i] = i
        bb[i] = 2 * i

    var t0 = perf_counter_ns()
    for _ in range(REPS):
        add_list_loop(c, a, b)
        keep(c)
    var t1 = perf_counter_ns()
    for _ in range(REPS):
        add_array_loop(cc, aa, bb)
        keep(cc)
    var t2 = perf_counter_ns()
    for _ in range(REPS):
        add_vectorize(c, a, b)
        keep(c)
    var t3 = perf_counter_ns()
    for _ in range(REPS):
        add_simd_loop(c, a, b)
        keep(c)
    var t4 = perf_counter_ns()

    print("check:", c[N - 1], cc[N - 1], "(expect", 3 * (N - 1), ")")
    print("ns per 1024-element add:")
    print("  List plain loop :", (t1 - t0) // REPS)
    print("  Array plain loop:", (t2 - t1) // REPS)
    print("  vectorize[4]    :", (t3 - t2) // REPS)
    print("  explicit SIMD   :", (t4 - t3) // REPS)
