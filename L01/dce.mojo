# Which functions end up in the binary?
#
#   mojo build -o dce L01/dce.mojo     -> prints "comptime_used ran" (compiler)
#   ./dce                              -> prints A = 1, runtime_called, rt = 4
#   nm dce | grep -E "comptime_|never_called|runtime_called"
#                                      -> only dce::runtime_called()
#
# @no_inline keeps each function from vanishing just because it was inlined.

@no_inline
def comptime_used() -> Int:
    print("comptime_used ran")
    return 1

@no_inline
def comptime_unused() -> Int:
    print("comptime_unused ran")
    return 2

@no_inline
def never_called() -> Int:
    print("never_called")
    return 3

@no_inline
def runtime_called() -> Int:
    print("runtime_called")
    return 4

def main():
    comptime A = comptime_used()
    comptime B = comptime_unused()
    print("A =", A)
    print("rt =", runtime_called())
