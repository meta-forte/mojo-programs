# Shows that Int is SIMD[DType.int, 1]. Explained in notes/int-type.md.
#
#   ./build.sh -r L01/int_simd.mojo

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
