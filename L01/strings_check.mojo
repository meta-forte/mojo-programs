from std.sys import size_of
from std.ffi import external_call, c_char, c_size_t

def main():
    print("size_of[String]:", size_of[String]())
    print("INLINE_CAPACITY:", String.INLINE_CAPACITY)

    var lit = "Hello"                      # static constant, no allocation
    print("literal capacity:", lit.capacity_bytes())

    var a = String("short")
    a += "!"                                # becomes inline (SSO)
    print("inline cap:", a.capacity_bytes(), "ptr inside value:",
          Int(a.unsafe_ptr()) == Int(Pointer(to=a).unsafe_bitcast[Byte]()))

    var big = String("x") * 40              # heap, ref-counted
    var big2 = big                          # copy shares the buffer
    print("shared buffer:", Int(big.unsafe_ptr()) == Int(big2.unsafe_ptr()))
    big2 += "y"                             # copy-on-write
    print("after +=, shared:", Int(big.unsafe_ptr()) == Int(big2.unsafe_ptr()))

    var p_before = Int(big.unsafe_ptr())
    big += "z"                              # unique owner, may grow in place
    print("unique += same buffer:", Int(big.unsafe_ptr()) == p_before,
          "cap:", big.capacity_bytes())

    var c = big + "!"                       # + makes a new String
    print("+ new buffer:", Int(c.unsafe_ptr()) != Int(big.unsafe_ptr()))

    # In-place byte edit
    var s = String("hello")
    s.unsafe_as_bytes_mut()[0] = Byte(ord("H"))
    print(s)

    # Mojo -> C and C -> Mojo
    var name: String = "Mojo strings"
    var n = external_call["strlen", c_size_t](name.as_c_string_span())
    print("strlen:", n)
    var cp = external_call["strdup", Pointer[c_char, MutUntrackedOrigin]](
        name.as_c_string_span())
    var back = String(unsafe_from_utf8_ptr=cp)
    print("from C:", back)
    external_call["free", NoneType](cp.unsafe_bitcast[NoneType]())
