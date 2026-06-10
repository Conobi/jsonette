from std.testing import assert_equal, assert_true, assert_false
from simdjson.parser import Parser
from simdjson.serialize.tape_writer import to_string, to_json
from simdjson.serialize.roundtrip import tapes_equal


def _bytes(s: String) -> List[UInt8]:
    var b = List[UInt8]()
    for x in s.as_bytes():
        b.append(x)
    return b^


def read_file(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


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


def _assert_roundtrips(path: String) raises:
    var data = read_file(path)
    var p1 = Parser()
    var d1 = p1.parse(data)
    var emitted = to_string(d1)
    var p2 = Parser()
    var d2 = p2.parse(_bytes(emitted))
    assert_true(tapes_equal(d1, d2), msg=String("round-trip tape mismatch: ") + path)


def test_corpus_roundtrip() raises:
    _assert_roundtrips(String("tests/fixtures/corpus/twitter.json"))
    _assert_roundtrips(String("tests/fixtures/corpus/canada.json"))
    _assert_roundtrips(String("tests/fixtures/corpus/citm_catalog.json"))


def test_accept_vectors_roundtrip() raises:
    # Representative y_ Seriot accept vectors covering
    # escapes / unicode / surrogate pairs / multi-byte UTF-8 /
    # numbers / exponents / heterogeneous arrays / nested objects.
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_string_allowed_escapes.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_string_unicode_escaped_double_quote.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_string_surrogates_U+1D11E_MUSICAL_SYMBOL_G_CLEF.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_string_1_2_3_bytes_UTF-8_sequences.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_string_nbsp_uescaped.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_number_real_exponent.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_number_real_capital_e_neg_exp.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_object_extreme_numbers.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_array_heterogeneous.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_object_string_unicode.json"))
    # Security-relevant byte ranges: embedded NUL, DEL, escaped control,
    # NUL-in-key — regression guards for the encoder's string serialisation.
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_string_null_escape.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_string_backslash_and_u_escaped_zero.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_string_escaped_control_character.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_string_unescaped_char_delete.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_string_with_del_character.json"))
    _assert_roundtrips(String("tests/fixtures/test_vectors/y_object_escaped_null_in_key.json"))


def main() raises:
    test_scalars_and_containers()
    test_pretty()
    test_tapes_equal_smoke()
    test_corpus_roundtrip()
    test_accept_vectors_roundtrip()
    print("test_roundtrip: basic passed")
