"""Tape-free decode: flat struct with leaf fields, hash dispatch, required-field enforcement."""
from std.testing import assert_equal, assert_true
from std.memory import bitcast
from jsonette.serialize.direct_decode import decode_direct


struct Flat(Copyable, Movable, Defaultable):
    var name: String
    var count: Int64
    var ratio: Float64
    var flag: Bool
    def __init__(out self):
        self.name = String(""); self.count = 0; self.ratio = 0.0; self.flag = False


def test_flat_leaves() raises:
    var f = decode_direct[Flat](String('{"name":"jsonette","count":42,"ratio":1.5,"flag":true}'))
    assert_equal(f.name, String("jsonette"))
    assert_equal(f.count, Int64(42))
    assert_true(f.ratio > 1.49 and f.ratio < 1.51, "ratio")
    assert_true(f.flag, "flag")


def main() raises:
    test_flat_leaves()
    print("test_direct_decode: all passed")
