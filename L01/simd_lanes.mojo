# SIMD lanes: size, alignment, memory layout, and the add instruction for
# 1, 4 and 64 lanes. Explained in notes/int-type.md ("SIMD lanes").
#
#   ./build.sh -r L01/simd_lanes.mojo
#
# Machine code for add1 / add4 / add64:
#   mkdir -p build/L01 && mojo build --emit asm -o build/L01/simd_lanes.s L01/simd_lanes.mojo
#   awk '/^"simd_lanes::add64/,/^.Lfunc_end/' build/L01/simd_lanes.s | grep -c vpaddq   # 16
#
# Lane counts must be a power of 2, at most 2^15. Both of these fail to compile
# with "SIMD vector length must be a power of two between 1 and 2^15":
#   var bad = SIMD[DType.int, 65](1)
#   var bad = SIMD[DType.int, 3](1)

from std.sys import size_of, align_of

@no_inline
def add1(a: SIMD[DType.int, 1], b: SIMD[DType.int, 1]) -> SIMD[DType.int, 1]:
    return a + b

@no_inline
def add4(a: SIMD[DType.int, 4], b: SIMD[DType.int, 4]) -> SIMD[DType.int, 4]:
    return a + b

@no_inline
def add64(a: SIMD[DType.int, 64], b: SIMD[DType.int, 64]) -> SIMD[DType.int, 64]:
    return a + b

def main():
    print("type                    size  align")
    print("SIMD[int8, 1]  ", size_of[SIMD[DType.int8, 1]](), align_of[SIMD[DType.int8, 1]]())
    print("SIMD[int8, 32] ", size_of[SIMD[DType.int8, 32]](), align_of[SIMD[DType.int8, 32]]())
    print("SIMD[int, 1]   ", size_of[SIMD[DType.int, 1]](), align_of[SIMD[DType.int, 1]]())
    print("SIMD[int, 4]   ", size_of[SIMD[DType.int, 4]](), align_of[SIMD[DType.int, 4]]())
    print("SIMD[int, 64]  ", size_of[SIMD[DType.int, 64]](), align_of[SIMD[DType.int, 64]]())
    print("SIMD[f32, 1024]", size_of[SIMD[DType.float32, 1024]](), align_of[SIMD[DType.float32, 1024]]())

    # Lanes are stored one after another, lane 0 at the lowest address.
    var v = SIMD[DType.int, 4](10, 20, 30, 40)
    var p = Pointer(to=v).unsafe_bitcast[Int]()
    print("memory as 4 Ints:", p[unsafe_offset=0], p[unsafe_offset=1], p[unsafe_offset=2], p[unsafe_offset=3])
    var bytes = Pointer(to=v).unsafe_bitcast[UInt8]()
    print("first 9 bytes:", end=" ")
    for i in range(9):
        print(bytes[unsafe_offset=i], end=" ")
    print()
    print(add1(1, 2), add4(1, 2)[0], add64(1, 2)[63])
