# Machine code for Int addition vs 4-lane SIMD addition.
# Explained in notes/int-type.md. Emit the assembly into build/:
#
#   mkdir -p build/L01 && mojo build --emit asm -o build/L01/int_asm.s L01/int_asm.mojo
#   grep -A3 "add_int\|add_vec4" build/L01/int_asm.s
#
# Expect "leaq (%rdi,%rsi), %rax" for add_int (plain integer add) and
# "vpaddq %ymm0, %ymm1, %ymm0" for add_vec4 (one AVX2 vector add).

@no_inline
def add_int(a: Int, b: Int) -> Int:
    return a + b

@no_inline
def add_vec4(a: SIMD[DType.int, 4], b: SIMD[DType.int, 4]) -> SIMD[DType.int, 4]:
    return a + b

def main():
    print(add_int(1, 2), add_vec4(SIMD[DType.int, 4](1), SIMD[DType.int, 4](2)))
