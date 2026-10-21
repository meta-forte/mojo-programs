# Explicit SIMD sum and search over List[Int], 4 Ints per step.
# Explained in notes/simd-codegen.md.
#
#   ./build.sh -r L01/simd_search.mojo
#
# Compare the machine code for different target CPUs:
#   mkdir -p build/L01
#   mojo build --emit asm -o build/L01/simd_host.s L01/simd_search.mojo
#   mojo build --target-cpu x86-64 --emit asm -o build/L01/simd_base.s L01/simd_search.mojo
#   mojo build --target-cpu x86-64 --target-features "-sse,-sse2,-mmx" \
#       --emit asm -o build/L01/simd_nosimd.s L01/simd_search.mojo
#   grep -c '%ymm' build/L01/simd_*.s     # ymm (AVX2) only in the host build

comptime W = 4      # lanes per step: 4 x 64-bit Int = 256 bits (one AVX2 register)

@no_inline
def simd_sum(data: List[Int]) -> Int:
    var p = data.unsafe_ptr()
    var n = len(data)
    var acc = SIMD[DType.int, W](0)
    var i = 0
    while i + W <= n:
        acc += p.unsafe_load[width=W](i)      # 4 Ints in one load and one add
        i += W
    var total = acc.reduce_add()
    while i < n:                               # leftover elements, one at a time
        total += data[i]
        i += 1
    return total

@no_inline
def simd_search(data: List[Int], target: Int) -> Int:
    var p = data.unsafe_ptr()
    var n = len(data)
    var i = 0
    while i + W <= n:
        var hits = p.unsafe_load[width=W](i).eq(SIMD[DType.int, W](target))
        if hits.reduce_or():                   # any lane matched?
            for k in range(W):
                if hits[k]:
                    return i + k
        i += W
    while i < n:
        if data[i] == target:
            return i
        i += 1
    return -1

def main():
    var data: List[Int] = []
    for i in range(1000):
        data.append(i * 3)
    print("sum:", simd_sum(data), " index of 2997:", simd_search(data, 2997), " missing:", simd_search(data, 5))
