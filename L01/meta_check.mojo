def fib(n: Int) -> Int:
    var a = 0
    var b = 1
    for _ in range(n):
        var t = a + b
        a = b
        b = t
    return a

def primes_upto(n: Int) -> List[Int]:
    var out: List[Int] = []
    for i in range(2, n + 1):
        var is_p = True
        for d in range(2, i):
            if i % d == 0:
                is_p = False
                break
        if is_p:
            out.append(i)
    return out^

def describe[T: AnyType]() -> String:
    comptime if conforms_to(T, Writable):
        return String(reflect[T].name(), " is Writable")
    else:
        return String(reflect[T].name(), " is not Writable")

@fieldwise_init
struct Point:
    var x: Int
    var y: Float64

def show_fields[T: AnyType]():
    comptime names = reflect[T].field_names()
    comptime types = reflect[T].field_types()
    comptime for i in range(reflect[T].field_count()):
        comptime name = names[i]
        print("  ", name, ":", reflect[types[i]].name())

def main():
    comptime F30 = fib(30)                      # ran by the compiler
    comptime PRIMES = primes_upto(30)           # heap List built at compile time
    print("fib(30) =", F30)
    print("primes:", materialize[PRIMES]())
    print(describe[Int]())
    print(describe[Point]())
    show_fields[Point]()
