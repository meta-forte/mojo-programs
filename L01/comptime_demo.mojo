# Prints "Hello world" while the compiler builds this file, and
# "begin" / "end" when the compiled program runs.
#
#   mojo build L01/comptime_demo.mojo   -> prints: Hello world
#   ./comptime_demo                     -> prints: begin, end
#
# `mojo run` compiles and then runs, so it prints all three lines.
#
# Mojo caches compiled code, keyed on the code itself rather than the file
# text. If the code has not changed since the last compile, the cached result
# is reused and "Hello world" does not appear. Editing only comments or
# whitespace does not count; change actual code to see it again.
#
# The text is printed by the compiler only; it is not stored in the binary.


# An ordinary function. Called from a `comptime` context, the compiler's
# interpreter runs it during compilation, so its print happens at build time.
def compile_time_hello() -> Bool:
    print("Hello world")
    return True


def main():
    # Forces compile_time_hello() to run inside the compiler.
    comptime HELLO_DONE = compile_time_hello()

    # The comptime value must be used, otherwise the compiler never
    # evaluates it and nothing is printed. `comptime if` uses it without
    # adding any runtime code: only the chosen branch is compiled.
    comptime if HELLO_DONE:
        print("begin")
        print("end")
