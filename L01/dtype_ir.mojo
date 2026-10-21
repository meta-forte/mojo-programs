# The LLVM type each element width becomes. Explained in notes/dtype.md.
#
#   mkdir -p build/L01 && mojo build --emit llvm -o build/L01/dtype_ir.ll L01/dtype_ir.mojo
#   grep "^define .*add_" build/L01/dtype_ir.ll

@no_inline
def add_i8(a: Int8, b: Int8) -> Int8:
    return a + b

@no_inline
def add_u16(a: UInt16, b: UInt16) -> UInt16:
    return a + b

@no_inline
def add_i32(a: Int32, b: Int32) -> Int32:
    return a + b

@no_inline
def add_int(a: Int, b: Int) -> Int:
    return a + b

@no_inline
def add_f32x8(a: SIMD[DType.float32, 8], b: SIMD[DType.float32, 8]) -> SIMD[DType.float32, 8]:
    return a + b

@no_inline
def add_bool(a: Bool, b: Bool) -> Bool:
    return a or b

def main():
    print(add_i8(1, 2), add_u16(1, 2), add_i32(1, 2), add_int(1, 2),
          add_f32x8(SIMD[DType.float32, 8](1), SIMD[DType.float32, 8](2)), add_bool(True, False))
