# What does Mojo vectorize without being asked? Loops, a fill loop, List.copy()
# and String.find(). Explained in notes/simd-codegen.md, section 3.
#
#   ./build.sh -r -D ASSERT=none L01/autovec.mojo
#
# Inspect the assembly:
#   mkdir -p build/L01
#   mojo build -D ASSERT=none --emit asm -o build/L01/autovec.s L01/autovec.mojo
#   grep -A12 '^"autovec::fill_loop' build/L01/autovec.s   # ends in: jmp memset@PLT
#   awk '/^"autovec::find_in/,/^.Lfunc_end/' build/L01/autovec.s | grep -E 'vpcmpeqb|vpmovmskb'
#
# Expected: slp_add4, copy_loop, scale_loop scalar; fill_loop -> memset call;
# copy_list and find_in use ymm registers (stdlib code written with SIMD).

@no_inline
def slp_add4(mut a: Array[Int, 4], b: Array[Int, 4]):
    # Straight-line code, no loop: 4 independent adds on neighbouring elements.
    a[0] += b[0]
    a[1] += b[1]
    a[2] += b[2]
    a[3] += b[3]

@no_inline
def copy_loop(dst: Pointer[Int, MutAnyOrigin], src: Pointer[Int, MutAnyOrigin], n: Int):
    for i in range(n):
        dst[unsafe_offset=i] = src[unsafe_offset=i]

@no_inline
def fill_loop(dst: Pointer[Int, MutAnyOrigin], n: Int):
    for i in range(n):
        dst[unsafe_offset=i] = 0

@no_inline
def scale_loop(dst: Pointer[Int, MutAnyOrigin], n: Int):
    for i in range(n):
        dst[unsafe_offset=i] = dst[unsafe_offset=i] * 3

@no_inline
def copy_list(src: List[Int]) -> List[Int]:
    return src.copy()

@no_inline
def find_in(s: String) -> Int:
    return s.find("needle")

def main():
    var a = Array[Int, 4](fill=1)
    var b = Array[Int, 4](fill=2)
    slp_add4(a, b)
    var src: List[Int] = [1, 2, 3, 4, 5, 6, 7, 8]
    var dst: List[Int] = [0, 0, 0, 0, 0, 0, 0, 0]
    var sp = Pointer(to=src[0]).as_unsafe_any_origin()
    var dp = Pointer(to=dst[0]).as_unsafe_any_origin()
    copy_loop(dp, sp, 8)
    scale_loop(dp, 8)
    var c = copy_list(dst)
    fill_loop(dp, 8)
    print(a[0], a[3], c[7], dst[0], find_in(String("haystack with a needle in it")))
