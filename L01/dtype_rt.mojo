# DType size and runtime use. Explained in notes/dtype.md.
#
#   ./build.sh -r L01/dtype_rt.mojo

from std.sys import size_of, bit_width_of

def describe(dt: DType):                     # runtime argument, not a parameter
    print(dt, " integral:", dt.is_integral(), " signed:", dt.is_signed(),
          " float:", dt.is_floating_point())

def main():
    print("size_of[DType]:", size_of[DType]())
    var kinds: List[DType] = [DType.int8, DType.uint16, DType.int32, DType.int, DType.float32, DType.bool]
    for dt in kinds:
        describe(dt)
    # Bit widths need the dtype as a compile-time parameter.
    print("bits int8/uint16/int32/int/float32:", bit_width_of[DType.int8](),
          bit_width_of[DType.uint16](), bit_width_of[DType.int32](),
          bit_width_of[DType.int](), bit_width_of[DType.float32]())
    var v = SIMD[DType.float16, 4](1.5)
    print("v.dtype:", v.dtype, " v:", v)
