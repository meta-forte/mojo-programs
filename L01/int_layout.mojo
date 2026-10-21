# Memory layout of Int, and SIMD (vector) operations on a plain Int.
# Explained in notes/int-type.md.
#
#   ./build.sh -r L01/int_layout.mojo

from std.sys import size_of, align_of

def main():
    print("size/align Int:", size_of[Int](), align_of[Int]())
    print("size/align SIMD[int,4]:", size_of[SIMD[DType.int, 4]](), align_of[SIMD[DType.int, 4]]())
    print("Array[Int, 10] bytes:", size_of[Array[Int, 10]]())
    var arr = Array[Int, 3](fill=7)
    var p0 = Int(Pointer(to=arr[0]))
    var p1 = Int(Pointer(to=arr[1]))
    print("stride between elements:", p1 - p0)
    var n: Int = 5
    print("raw bytes of n == the value:", Pointer(to=n).unsafe_bitcast[Int64]()[] == 5)

    var v = SIMD[DType.int, 4](1, 2, 3, 4)
    print("v + n (scalar broadcast):", v + n)
    print("n.reduce_add/max:", n.reduce_add(), n.reduce_max())
    print("n.join(n):", n.join(n))
    print("SIMD[int,4](n) splat:", SIMD[DType.int, 4](n))
    print("n.cast[float32]:", n.cast[DType.float32]())
    print("n[0]:", n[0])
