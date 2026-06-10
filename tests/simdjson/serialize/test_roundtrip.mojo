from std.testing import assert_equal, assert_true, assert_false
from simdjson.parser import Parser
from simdjson.serialize.tape_writer import to_string, to_json
from simdjson.serialize.roundtrip import tapes_equal


def _bytes(s: String) -> List[UInt8]:
    var b = List[UInt8]()
    for x in s.as_bytes():
        b.append(x)
    return b^


def _emit(s: String) raises -> String:
    var p = Parser()
    var doc = p.parse(_bytes(s))
    return to_string(doc)


def test_scalars_and_containers() raises:
    assert_equal(_emit(String('{"a":1,"b":[2,3.5,true,null,"x"],"c":-42,"d":{}}')),
                 String('{"a":1,"b":[2,3.5,true,null,"x"],"c":-42,"d":{}}'))
    assert_equal(_emit(String("[]")), String("[]"))
    assert_equal(_emit(String("{}")), String("{}"))
    assert_equal(_emit(String("42")), String("42"))
    assert_equal(_emit(String('"hi"')), String('"hi"'))
    assert_equal(_emit(String("true")), String("true"))
    assert_equal(_emit(String("null")), String("null"))
    assert_equal(_emit(String("18446744073709551615")), String("18446744073709551615"))
    assert_equal(_emit(String("[[1],[2,[3]]]")), String("[[1],[2,[3]]]"))


def test_pretty() raises:
    var p = Parser()
    var doc = p.parse(_bytes(String('{"a":[1,2]}')))
    var expected = String('{') + chr(10) + '  "a": [' + chr(10) + '    1,' + chr(10) + '    2' + chr(10) + '  ]' + chr(10) + '}'
    assert_equal(to_json[pretty=True](doc), expected)


def test_tapes_equal_smoke() raises:
    var p1 = Parser()
    var d1 = p1.parse(_bytes(String('{"a":1}')))
    var p2 = Parser()
    var d2 = p2.parse(_bytes(String('{"a":1}')))
    var p3 = Parser()
    var d3 = p3.parse(_bytes(String('{"a":2}')))
    assert_true(tapes_equal(d1, d2))
    assert_false(tapes_equal(d1, d3))


def main() raises:
    test_scalars_and_containers()
    test_pretty()
    test_tapes_equal_smoke()
    print("test_roundtrip: basic passed")
