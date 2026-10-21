# Plain loops over List[Int]: does Mojo emit SIMD code? (It does not.)
# Explained in notes/simd-codegen.md.
#
#   ./build.sh -r L01/sortsearch.mojo
#
# Inspect the assembly (count vector registers per function):
#   mkdir -p build/L01
#   mojo build --emit asm -o build/L01/sortsearch.s L01/sortsearch.mojo
#   mojo build -D ASSERT=none --emit asm -o build/L01/sortsearch_nochk.s L01/sortsearch.mojo
#   grep -c '%[xyz]mm' build/L01/sortsearch.s build/L01/sortsearch_nochk.s

from std.sys import size_of

@no_inline
def insertion_sort(mut data: List[Int]):
    for i in range(1, len(data)):
        var key = data[i]
        var j = i - 1
        while j >= 0 and data[j] > key:
            data[j + 1] = data[j]
            j -= 1
        data[j + 1] = key

@no_inline
def linear_search(data: List[Int], target: Int) -> Int:
    for i in range(len(data)):
        if data[i] == target:
            return i
    return -1

@no_inline
def sum_all(data: List[Int]) -> Int:
    var total = 0
    for i in range(len(data)):
        total += data[i]
    return total

def main():
    print("Array[Int, 8] size:", size_of[Array[Int, 8]]())
    var data: List[Int] = [5, 3, 9, 1, 7, 2, 8, 6, 4, 0]
    insertion_sort(data)
    print(data)
    print("index of 7:", linear_search(data, 7), " sum:", sum_all(data))
