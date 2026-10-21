# The straight-line (SLP) vectorizer, and a copy loop between two lists.
# Explained in notes/simd-codegen.md, section 3.
#
#   ./build.sh -r -D ASSERT=none L01/autovec_slp.mojo
#
# Inspect the assembly:
#   mkdir -p build/L01
#   mojo build -D ASSERT=none --emit asm -o build/L01/autovec_slp.s L01/autovec_slp.mojo
#   grep -A5 '^"autovec_slp::slp_add4' build/L01/autovec_slp.s
#
# Expected: slp_add4 is one vpaddq on a ymm register; copy_lists stays a
# scalar loop (not turned into memcpy).

@no_inline
def slp_add4(a: Pointer[Int, MutAnyOrigin], b: Pointer[Int, MutAnyOrigin]):
    # All loads first, then all stores: straight-line code the SLP vectorizer can combine.
    var x0 = a[unsafe_offset=0]; var x1 = a[unsafe_offset=1]
    var x2 = a[unsafe_offset=2]; var x3 = a[unsafe_offset=3]
    var y0 = b[unsafe_offset=0]; var y1 = b[unsafe_offset=1]
    var y2 = b[unsafe_offset=2]; var y3 = b[unsafe_offset=3]
    a[unsafe_offset=0] = x0 + y0
    a[unsafe_offset=1] = x1 + y1
    a[unsafe_offset=2] = x2 + y2
    a[unsafe_offset=3] = x3 + y3

@no_inline
def copy_lists(mut dst: List[Int], src: List[Int]):
    # Two different lists: the compiler knows they don't overlap.
    var d = dst.unsafe_ptr()
    var s = src.unsafe_ptr()
    for i in range(len(src)):
        d[unsafe_offset=i] = s[unsafe_offset=i]

def main():
    var a: List[Int] = [1, 2, 3, 4]
    var b: List[Int] = [10, 20, 30, 40]
    slp_add4(a.unsafe_ptr().as_unsafe_any_origin(), b.unsafe_ptr().as_unsafe_any_origin())
    var c: List[Int] = [0, 0, 0, 0]
    copy_lists(c, a)
    print(a, c)
