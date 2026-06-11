from jsonette.parser import Parser
from jsonette.document import Document


def test_n_incomplete_false() -> Bool:
    """Reject: n_incomplete_false.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(102))
    data.append(UInt8(97))
    data.append(UInt8(108))
    data.append(UInt8(115))
    data.append(UInt8(93))
    try:
        var parser = Parser()
        _ = parser.parse(data)
        print("FAIL (unexpected accept): n_incomplete_false.json")
        return False
    except:
        return True


def test_n_incomplete_null() -> Bool:
    """Reject: n_incomplete_null.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(110))
    data.append(UInt8(117))
    data.append(UInt8(108))
    data.append(UInt8(93))
    try:
        var parser = Parser()
        _ = parser.parse(data)
        print("FAIL (unexpected accept): n_incomplete_null.json")
        return False
    except:
        return True


def test_n_incomplete_true() -> Bool:
    """Reject: n_incomplete_true.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(116))
    data.append(UInt8(114))
    data.append(UInt8(117))
    data.append(UInt8(93))
    try:
        var parser = Parser()
        _ = parser.parse(data)
        print("FAIL (unexpected accept): n_incomplete_true.json")
        return False
    except:
        return True


def test_n_number() -> Bool:
    """Reject: n_number_++.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(43))
    data.append(UInt8(43))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(51))
    data.append(UInt8(52))
    data.append(UInt8(93))
    try:
        var parser = Parser()
        _ = parser.parse(data)
        print("FAIL (unexpected accept): n_number_++.json")
        return False
    except:
        return True


def test_n_string_invalid_utf_8_in_escape() -> Bool:
    """Reject: n_string_invalid-utf-8-in-escape.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(229))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        var parser = Parser()
        _ = parser.parse(data)
        print("FAIL (unexpected accept): n_string_invalid-utf-8-in-escape.json")
        return False
    except:
        return True


def test_n_string_leading_uescaped_thinspace() -> Bool:
    """Reject: n_string_leading_uescaped_thinspace.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(50))
    data.append(UInt8(48))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(115))
    data.append(UInt8(100))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        var parser = Parser()
        _ = parser.parse(data)
        print("FAIL (unexpected accept): n_string_leading_uescaped_thinspace.json")
        return False
    except:
        return True


def test_n_structure_U_2060_word_joined() -> Bool:
    """Reject: n_structure_U+2060_word_joined.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(226))
    data.append(UInt8(129))
    data.append(UInt8(160))
    data.append(UInt8(93))
    try:
        var parser = Parser()
        _ = parser.parse(data)
        print("FAIL (unexpected accept): n_structure_U+2060_word_joined.json")
        return False
    except:
        return True


def test_n_structure_array_trailing_garbage() -> Bool:
    """Reject: n_structure_array_trailing_garbage.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(93))
    data.append(UInt8(120))
    try:
        var parser = Parser()
        _ = parser.parse(data)
        print("FAIL (unexpected accept): n_structure_array_trailing_garbage.json")
        return False
    except:
        return True


def test_n_structure_array_with_extra_array_close() -> Bool:
    """Reject: n_structure_array_with_extra_array_close.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(93))
    data.append(UInt8(93))
    try:
        var parser = Parser()
        _ = parser.parse(data)
        print("FAIL (unexpected accept): n_structure_array_with_extra_array_close.json")
        return False
    except:
        return True


def test_n_structure_array_with_unclosed_string() -> Bool:
    """Reject: n_structure_array_with_unclosed_string.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(115))
    data.append(UInt8(100))
    data.append(UInt8(93))
    try:
        var parser = Parser()
        _ = parser.parse(data)
        print("FAIL (unexpected accept): n_structure_array_with_unclosed_string.json")
        return False
    except:
        return True


def main() raises:
    var passed = 0
    var failed = 0

    if test_n_incomplete_false():
        passed += 1
    else:
        failed += 1

    if test_n_incomplete_null():
        passed += 1
    else:
        failed += 1

    if test_n_incomplete_true():
        passed += 1
    else:
        failed += 1

    if test_n_number():
        passed += 1
    else:
        failed += 1

    if test_n_string_invalid_utf_8_in_escape():
        passed += 1
    else:
        failed += 1

    if test_n_string_leading_uescaped_thinspace():
        passed += 1
    else:
        failed += 1

    if test_n_structure_U_2060_word_joined():
        passed += 1
    else:
        failed += 1

    if test_n_structure_array_trailing_garbage():
        passed += 1
    else:
        failed += 1

    if test_n_structure_array_with_extra_array_close():
        passed += 1
    else:
        failed += 1

    if test_n_structure_array_with_unclosed_string():
        passed += 1
    else:
        failed += 1

    print(String("test_reject: ") + String(passed) + String(" passed, ") + String(failed) + String(" failed out of ") + String(10))
    if failed > 0:
        raise Error("Some reject tests failed")
