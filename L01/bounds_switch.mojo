# A project-specific compile-time switch for unchecked access, independent of
# -D ASSERT. Explained in notes/bounds-checks.md.
#
#   ./build.sh -r L01/bounds_switch.mojo               # checked build
#   ./build.sh -r -D FASTADD L01/bounds_switch.mojo    # unchecked build
#
# Bounds checks left in add():
#   mkdir -p build/L01
#   mojo build --emit asm -o build/L01/bounds_switch.s L01/bounds_switch.mojo
#   awk '/^"bounds_switch::add\(/,/^.Lfunc_end/' build/L01/bounds_switch.s | grep -c _debug_assert_fail   # 3
#   (add -D FASTADD to the build command: 0)

from std.sys import is_defined

# Our own switch, independent of -D ASSERT: build with -D FASTADD to skip checks.
comptime UNCHECKED = is_defined["FASTADD"]()

@no_inline
def add(mut c: List[Int], a: List[Int], b: List[Int]):
    comptime if UNCHECKED:
        for i in range(len(a)):
            c.unsafe_get(i) = a.unsafe_get(i) + b.unsafe_get(i)
    else:
        for i in range(len(a)):
            c[i] = a[i] + b[i]

def main():
    var a: List[Int] = [1, 2, 3]
    var b: List[Int] = [10, 20, 30]
    var c: List[Int] = [0, 0, 0]
    add(c, a, b)
    print("unchecked build:" if UNCHECKED else "checked build:", c)
