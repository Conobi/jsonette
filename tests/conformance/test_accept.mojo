from jsonette.document import parse


def test_y_array_arraysWithSpaces() -> Bool:
    """Accept: y_array_arraysWithSpaces.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(91))
    data.append(UInt8(93))
    data.append(UInt8(32))
    data.append(UInt8(32))
    data.append(UInt8(32))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_arraysWithSpaces.json")
        return False


def test_y_array_empty_string() -> Bool:
    """Accept: y_array_empty-string.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_empty-string.json")
        return False


def test_y_array_empty() -> Bool:
    """Accept: y_array_empty.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_empty.json")
        return False


def test_y_array_ending_with_newline() -> Bool:
    """Accept: y_array_ending_with_newline.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_ending_with_newline.json")
        return False


def test_y_array_false() -> Bool:
    """Accept: y_array_false.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(102))
    data.append(UInt8(97))
    data.append(UInt8(108))
    data.append(UInt8(115))
    data.append(UInt8(101))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_false.json")
        return False


def test_y_array_heterogeneous() -> Bool:
    """Accept: y_array_heterogeneous.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(110))
    data.append(UInt8(117))
    data.append(UInt8(108))
    data.append(UInt8(108))
    data.append(UInt8(44))
    data.append(UInt8(32))
    data.append(UInt8(49))
    data.append(UInt8(44))
    data.append(UInt8(32))
    data.append(UInt8(34))
    data.append(UInt8(49))
    data.append(UInt8(34))
    data.append(UInt8(44))
    data.append(UInt8(32))
    data.append(UInt8(123))
    data.append(UInt8(125))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_heterogeneous.json")
        return False


def test_y_array_null() -> Bool:
    """Accept: y_array_null.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(110))
    data.append(UInt8(117))
    data.append(UInt8(108))
    data.append(UInt8(108))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_null.json")
        return False


def test_y_array_with_1_and_newline() -> Bool:
    """Accept: y_array_with_1_and_newline.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(10))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_with_1_and_newline.json")
        return False


def test_y_array_with_leading_space() -> Bool:
    """Accept: y_array_with_leading_space.json."""
    var data = List[UInt8]()
    data.append(UInt8(32))
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_with_leading_space.json")
        return False


def test_y_array_with_several_null() -> Bool:
    """Accept: y_array_with_several_null.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(44))
    data.append(UInt8(110))
    data.append(UInt8(117))
    data.append(UInt8(108))
    data.append(UInt8(108))
    data.append(UInt8(44))
    data.append(UInt8(110))
    data.append(UInt8(117))
    data.append(UInt8(108))
    data.append(UInt8(108))
    data.append(UInt8(44))
    data.append(UInt8(110))
    data.append(UInt8(117))
    data.append(UInt8(108))
    data.append(UInt8(108))
    data.append(UInt8(44))
    data.append(UInt8(50))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_with_several_null.json")
        return False


def test_y_array_with_trailing_space() -> Bool:
    """Accept: y_array_with_trailing_space.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(50))
    data.append(UInt8(93))
    data.append(UInt8(32))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_array_with_trailing_space.json")
        return False


def test_y_number() -> Bool:
    """Accept: y_number.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(51))
    data.append(UInt8(101))
    data.append(UInt8(54))
    data.append(UInt8(53))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number.json")
        return False


def test_y_number_0e_1() -> Bool:
    """Accept: y_number_0e+1.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(48))
    data.append(UInt8(101))
    data.append(UInt8(43))
    data.append(UInt8(49))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_0e+1.json")
        return False


def test_y_number_0e1() -> Bool:
    """Accept: y_number_0e1.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(48))
    data.append(UInt8(101))
    data.append(UInt8(49))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_0e1.json")
        return False


def test_y_number_after_space() -> Bool:
    """Accept: y_number_after_space.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(32))
    data.append(UInt8(52))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_after_space.json")
        return False


def test_y_number_double_close_to_zero() -> Bool:
    """Accept: y_number_double_close_to_zero.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(45))
    data.append(UInt8(48))
    data.append(UInt8(46))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(49))
    data.append(UInt8(93))
    data.append(UInt8(10))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_double_close_to_zero.json")
        return False


def test_y_number_int_with_exp() -> Bool:
    """Accept: y_number_int_with_exp.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(50))
    data.append(UInt8(48))
    data.append(UInt8(101))
    data.append(UInt8(49))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_int_with_exp.json")
        return False


def test_y_number_minus_zero() -> Bool:
    """Accept: y_number_minus_zero.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(45))
    data.append(UInt8(48))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_minus_zero.json")
        return False


def test_y_number_negative_int() -> Bool:
    """Accept: y_number_negative_int.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(45))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(51))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_negative_int.json")
        return False


def test_y_number_negative_one() -> Bool:
    """Accept: y_number_negative_one.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(45))
    data.append(UInt8(49))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_negative_one.json")
        return False


def test_y_number_negative_zero() -> Bool:
    """Accept: y_number_negative_zero.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(45))
    data.append(UInt8(48))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_negative_zero.json")
        return False


def test_y_number_real_capital_e() -> Bool:
    """Accept: y_number_real_capital_e.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(69))
    data.append(UInt8(50))
    data.append(UInt8(50))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_real_capital_e.json")
        return False


def test_y_number_real_capital_e_neg_exp() -> Bool:
    """Accept: y_number_real_capital_e_neg_exp.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(69))
    data.append(UInt8(45))
    data.append(UInt8(50))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_real_capital_e_neg_exp.json")
        return False


def test_y_number_real_capital_e_pos_exp() -> Bool:
    """Accept: y_number_real_capital_e_pos_exp.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(69))
    data.append(UInt8(43))
    data.append(UInt8(50))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_real_capital_e_pos_exp.json")
        return False


def test_y_number_real_exponent() -> Bool:
    """Accept: y_number_real_exponent.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(51))
    data.append(UInt8(101))
    data.append(UInt8(52))
    data.append(UInt8(53))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_real_exponent.json")
        return False


def test_y_number_real_fraction_exponent() -> Bool:
    """Accept: y_number_real_fraction_exponent.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(51))
    data.append(UInt8(46))
    data.append(UInt8(52))
    data.append(UInt8(53))
    data.append(UInt8(54))
    data.append(UInt8(101))
    data.append(UInt8(55))
    data.append(UInt8(56))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_real_fraction_exponent.json")
        return False


def test_y_number_real_neg_exp() -> Bool:
    """Accept: y_number_real_neg_exp.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(101))
    data.append(UInt8(45))
    data.append(UInt8(50))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_real_neg_exp.json")
        return False


def test_y_number_real_pos_exponent() -> Bool:
    """Accept: y_number_real_pos_exponent.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(101))
    data.append(UInt8(43))
    data.append(UInt8(50))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_real_pos_exponent.json")
        return False


def test_y_number_simple_int() -> Bool:
    """Accept: y_number_simple_int.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(51))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_simple_int.json")
        return False


def test_y_number_simple_real() -> Bool:
    """Accept: y_number_simple_real.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(51))
    data.append(UInt8(46))
    data.append(UInt8(52))
    data.append(UInt8(53))
    data.append(UInt8(54))
    data.append(UInt8(55))
    data.append(UInt8(56))
    data.append(UInt8(57))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_number_simple_real.json")
        return False


def test_y_object() -> Bool:
    """Accept: y_object.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(115))
    data.append(UInt8(100))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(34))
    data.append(UInt8(115))
    data.append(UInt8(100))
    data.append(UInt8(102))
    data.append(UInt8(34))
    data.append(UInt8(44))
    data.append(UInt8(32))
    data.append(UInt8(34))
    data.append(UInt8(100))
    data.append(UInt8(102))
    data.append(UInt8(103))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(34))
    data.append(UInt8(102))
    data.append(UInt8(103))
    data.append(UInt8(104))
    data.append(UInt8(34))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object.json")
        return False


def test_y_object_basic() -> Bool:
    """Accept: y_object_basic.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(115))
    data.append(UInt8(100))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(34))
    data.append(UInt8(115))
    data.append(UInt8(100))
    data.append(UInt8(102))
    data.append(UInt8(34))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_basic.json")
        return False


def test_y_object_duplicated_key() -> Bool:
    """Accept: y_object_duplicated_key.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(34))
    data.append(UInt8(98))
    data.append(UInt8(34))
    data.append(UInt8(44))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(34))
    data.append(UInt8(99))
    data.append(UInt8(34))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_duplicated_key.json")
        return False


def test_y_object_duplicated_key_and_value() -> Bool:
    """Accept: y_object_duplicated_key_and_value.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(34))
    data.append(UInt8(98))
    data.append(UInt8(34))
    data.append(UInt8(44))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(34))
    data.append(UInt8(98))
    data.append(UInt8(34))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_duplicated_key_and_value.json")
        return False


def test_y_object_empty() -> Bool:
    """Accept: y_object_empty.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_empty.json")
        return False


def test_y_object_empty_key() -> Bool:
    """Accept: y_object_empty_key.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(34))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(48))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_empty_key.json")
        return False


def test_y_object_escaped_null_in_key() -> Bool:
    """Accept: y_object_escaped_null_in_key.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(34))
    data.append(UInt8(102))
    data.append(UInt8(111))
    data.append(UInt8(111))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(98))
    data.append(UInt8(97))
    data.append(UInt8(114))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(32))
    data.append(UInt8(52))
    data.append(UInt8(50))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_escaped_null_in_key.json")
        return False


def test_y_object_extreme_numbers() -> Bool:
    """Accept: y_object_extreme_numbers.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(32))
    data.append(UInt8(34))
    data.append(UInt8(109))
    data.append(UInt8(105))
    data.append(UInt8(110))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(32))
    data.append(UInt8(45))
    data.append(UInt8(49))
    data.append(UInt8(46))
    data.append(UInt8(48))
    data.append(UInt8(101))
    data.append(UInt8(43))
    data.append(UInt8(50))
    data.append(UInt8(56))
    data.append(UInt8(44))
    data.append(UInt8(32))
    data.append(UInt8(34))
    data.append(UInt8(109))
    data.append(UInt8(97))
    data.append(UInt8(120))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(32))
    data.append(UInt8(49))
    data.append(UInt8(46))
    data.append(UInt8(48))
    data.append(UInt8(101))
    data.append(UInt8(43))
    data.append(UInt8(50))
    data.append(UInt8(56))
    data.append(UInt8(32))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_extreme_numbers.json")
        return False


def test_y_object_long_strings() -> Bool:
    """Accept: y_object_long_strings.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(34))
    data.append(UInt8(120))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(91))
    data.append(UInt8(123))
    data.append(UInt8(34))
    data.append(UInt8(105))
    data.append(UInt8(100))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(32))
    data.append(UInt8(34))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(34))
    data.append(UInt8(125))
    data.append(UInt8(93))
    data.append(UInt8(44))
    data.append(UInt8(32))
    data.append(UInt8(34))
    data.append(UInt8(105))
    data.append(UInt8(100))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(32))
    data.append(UInt8(34))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(120))
    data.append(UInt8(34))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_long_strings.json")
        return False


def test_y_object_simple() -> Bool:
    """Accept: y_object_simple.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(91))
    data.append(UInt8(93))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_simple.json")
        return False


def test_y_object_string_unicode() -> Bool:
    """Accept: y_object_string_unicode.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(34))
    data.append(UInt8(116))
    data.append(UInt8(105))
    data.append(UInt8(116))
    data.append(UInt8(108))
    data.append(UInt8(101))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(49))
    data.append(UInt8(102))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(101))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(98))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(52))
    data.append(UInt8(50))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(101))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(52))
    data.append(UInt8(48))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(48))
    data.append(UInt8(32))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(49))
    data.append(UInt8(55))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(53))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(99))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(98))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(53))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(97))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(101))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(102))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(52))
    data.append(UInt8(51))
    data.append(UInt8(48))
    data.append(UInt8(34))
    data.append(UInt8(32))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_string_unicode.json")
        return False


def test_y_object_with_newlines() -> Bool:
    """Accept: y_object_with_newlines.json."""
    var data = List[UInt8]()
    data.append(UInt8(123))
    data.append(UInt8(10))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(34))
    data.append(UInt8(58))
    data.append(UInt8(32))
    data.append(UInt8(34))
    data.append(UInt8(98))
    data.append(UInt8(34))
    data.append(UInt8(10))
    data.append(UInt8(125))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_object_with_newlines.json")
        return False


def test_y_string_1_2_3_bytes_UTF_8_sequences() -> Bool:
    """Accept: y_string_1_2_3_bytes_UTF-8_sequences.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(54))
    data.append(UInt8(48))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(97))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(65))
    data.append(UInt8(66))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_1_2_3_bytes_UTF-8_sequences.json")
        return False


def test_y_string_accepted_surrogate_pair() -> Bool:
    """Accept: y_string_accepted_surrogate_pair.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(68))
    data.append(UInt8(56))
    data.append(UInt8(48))
    data.append(UInt8(49))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(100))
    data.append(UInt8(99))
    data.append(UInt8(51))
    data.append(UInt8(55))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_accepted_surrogate_pair.json")
        return False


def test_y_string_accepted_surrogate_pairs() -> Bool:
    """Accept: y_string_accepted_surrogate_pairs.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(100))
    data.append(UInt8(56))
    data.append(UInt8(51))
    data.append(UInt8(100))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(100))
    data.append(UInt8(101))
    data.append(UInt8(51))
    data.append(UInt8(57))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(100))
    data.append(UInt8(56))
    data.append(UInt8(51))
    data.append(UInt8(100))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(100))
    data.append(UInt8(99))
    data.append(UInt8(56))
    data.append(UInt8(100))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_accepted_surrogate_pairs.json")
        return False


def test_y_string_allowed_escapes() -> Bool:
    """Accept: y_string_allowed_escapes.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(92))
    data.append(UInt8(92))
    data.append(UInt8(47))
    data.append(UInt8(92))
    data.append(UInt8(98))
    data.append(UInt8(92))
    data.append(UInt8(102))
    data.append(UInt8(92))
    data.append(UInt8(110))
    data.append(UInt8(92))
    data.append(UInt8(114))
    data.append(UInt8(92))
    data.append(UInt8(116))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_allowed_escapes.json")
        return False


def test_y_string_backslash_and_u_escaped_zero() -> Bool:
    """Accept: y_string_backslash_and_u_escaped_zero.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_backslash_and_u_escaped_zero.json")
        return False


def test_y_string_backslash_doublequotes() -> Bool:
    """Accept: y_string_backslash_doublequotes.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(34))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_backslash_doublequotes.json")
        return False


def test_y_string_comments() -> Bool:
    """Accept: y_string_comments.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(47))
    data.append(UInt8(42))
    data.append(UInt8(98))
    data.append(UInt8(42))
    data.append(UInt8(47))
    data.append(UInt8(99))
    data.append(UInt8(47))
    data.append(UInt8(42))
    data.append(UInt8(100))
    data.append(UInt8(47))
    data.append(UInt8(47))
    data.append(UInt8(101))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_comments.json")
        return False


def test_y_string_double_escape_a() -> Bool:
    """Accept: y_string_double_escape_a.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(92))
    data.append(UInt8(97))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_double_escape_a.json")
        return False


def test_y_string_double_escape_n() -> Bool:
    """Accept: y_string_double_escape_n.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(92))
    data.append(UInt8(110))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_double_escape_n.json")
        return False


def test_y_string_escaped_control_character() -> Bool:
    """Accept: y_string_escaped_control_character.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_escaped_control_character.json")
        return False


def test_y_string_escaped_noncharacter() -> Bool:
    """Accept: y_string_escaped_noncharacter.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_escaped_noncharacter.json")
        return False


def test_y_string_in_array() -> Bool:
    """Accept: y_string_in_array.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(115))
    data.append(UInt8(100))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_in_array.json")
        return False


def test_y_string_in_array_with_leading_space() -> Bool:
    """Accept: y_string_in_array_with_leading_space.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(32))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(115))
    data.append(UInt8(100))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_in_array_with_leading_space.json")
        return False


def test_y_string_last_surrogates_1_and_2() -> Bool:
    """Accept: y_string_last_surrogates_1_and_2.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(68))
    data.append(UInt8(66))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(68))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_last_surrogates_1_and_2.json")
        return False


def test_y_string_nbsp_uescaped() -> Bool:
    """Accept: y_string_nbsp_uescaped.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(110))
    data.append(UInt8(101))
    data.append(UInt8(119))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(65))
    data.append(UInt8(48))
    data.append(UInt8(108))
    data.append(UInt8(105))
    data.append(UInt8(110))
    data.append(UInt8(101))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_nbsp_uescaped.json")
        return False


def test_y_string_nonCharacterInUTF_8_U_10FFFF() -> Bool:
    """Accept: y_string_nonCharacterInUTF-8_U+10FFFF.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(244))
    data.append(UInt8(143))
    data.append(UInt8(191))
    data.append(UInt8(191))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_nonCharacterInUTF-8_U+10FFFF.json")
        return False


def test_y_string_nonCharacterInUTF_8_U_FFFF() -> Bool:
    """Accept: y_string_nonCharacterInUTF-8_U+FFFF.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(239))
    data.append(UInt8(191))
    data.append(UInt8(191))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_nonCharacterInUTF-8_U+FFFF.json")
        return False


def test_y_string_null_escape() -> Bool:
    """Accept: y_string_null_escape.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_null_escape.json")
        return False


def test_y_string_one_byte_utf_8() -> Bool:
    """Accept: y_string_one-byte-utf-8.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(50))
    data.append(UInt8(99))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_one-byte-utf-8.json")
        return False


def test_y_string_pi() -> Bool:
    """Accept: y_string_pi.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(207))
    data.append(UInt8(128))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_pi.json")
        return False


def test_y_string_reservedCharacterInUTF_8_U_1BFFF() -> Bool:
    """Accept: y_string_reservedCharacterInUTF-8_U+1BFFF.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(240))
    data.append(UInt8(155))
    data.append(UInt8(191))
    data.append(UInt8(191))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_reservedCharacterInUTF-8_U+1BFFF.json")
        return False


def test_y_string_simple_ascii() -> Bool:
    """Accept: y_string_simple_ascii.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(115))
    data.append(UInt8(100))
    data.append(UInt8(32))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_simple_ascii.json")
        return False


def test_y_string_space() -> Bool:
    """Accept: y_string_space.json."""
    var data = List[UInt8]()
    data.append(UInt8(34))
    data.append(UInt8(32))
    data.append(UInt8(34))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_space.json")
        return False


def test_y_string_surrogates_U_1D11E_MUSICAL_SYMBOL_G_CLEF() -> Bool:
    """Accept: y_string_surrogates_U+1D11E_MUSICAL_SYMBOL_G_CLEF.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(68))
    data.append(UInt8(56))
    data.append(UInt8(51))
    data.append(UInt8(52))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(68))
    data.append(UInt8(100))
    data.append(UInt8(49))
    data.append(UInt8(101))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_surrogates_U+1D11E_MUSICAL_SYMBOL_G_CLEF.json")
        return False


def test_y_string_three_byte_utf_8() -> Bool:
    """Accept: y_string_three-byte-utf-8.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(56))
    data.append(UInt8(50))
    data.append(UInt8(49))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_three-byte-utf-8.json")
        return False


def test_y_string_two_byte_utf_8() -> Bool:
    """Accept: y_string_two-byte-utf-8.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(49))
    data.append(UInt8(50))
    data.append(UInt8(51))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_two-byte-utf-8.json")
        return False


def test_y_string_u_2028_line_sep() -> Bool:
    """Accept: y_string_u+2028_line_sep.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(226))
    data.append(UInt8(128))
    data.append(UInt8(168))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_u+2028_line_sep.json")
        return False


def test_y_string_u_2029_par_sep() -> Bool:
    """Accept: y_string_u+2029_par_sep.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(226))
    data.append(UInt8(128))
    data.append(UInt8(169))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_u+2029_par_sep.json")
        return False


def test_y_string_uEscape() -> Bool:
    """Accept: y_string_uEscape.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(54))
    data.append(UInt8(49))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(51))
    data.append(UInt8(48))
    data.append(UInt8(97))
    data.append(UInt8(102))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(51))
    data.append(UInt8(48))
    data.append(UInt8(69))
    data.append(UInt8(65))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(51))
    data.append(UInt8(48))
    data.append(UInt8(98))
    data.append(UInt8(57))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_uEscape.json")
        return False


def test_y_string_uescaped_newline() -> Bool:
    """Accept: y_string_uescaped_newline.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(110))
    data.append(UInt8(101))
    data.append(UInt8(119))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(65))
    data.append(UInt8(108))
    data.append(UInt8(105))
    data.append(UInt8(110))
    data.append(UInt8(101))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_uescaped_newline.json")
        return False


def test_y_string_unescaped_char_delete() -> Bool:
    """Accept: y_string_unescaped_char_delete.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(127))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unescaped_char_delete.json")
        return False


def test_y_string_unicode() -> Bool:
    """Accept: y_string_unicode.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(65))
    data.append(UInt8(54))
    data.append(UInt8(54))
    data.append(UInt8(68))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unicode.json")
        return False


def test_y_string_unicodeEscapedBackslash() -> Bool:
    """Accept: y_string_unicodeEscapedBackslash.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(53))
    data.append(UInt8(67))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unicodeEscapedBackslash.json")
        return False


def test_y_string_unicode_2() -> Bool:
    """Accept: y_string_unicode_2.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(226))
    data.append(UInt8(141))
    data.append(UInt8(130))
    data.append(UInt8(227))
    data.append(UInt8(136))
    data.append(UInt8(180))
    data.append(UInt8(226))
    data.append(UInt8(141))
    data.append(UInt8(130))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unicode_2.json")
        return False


def test_y_string_unicode_U_10FFFE_nonchar() -> Bool:
    """Accept: y_string_unicode_U+10FFFE_nonchar.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(68))
    data.append(UInt8(66))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(68))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(69))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unicode_U+10FFFE_nonchar.json")
        return False


def test_y_string_unicode_U_1FFFE_nonchar() -> Bool:
    """Accept: y_string_unicode_U+1FFFE_nonchar.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(68))
    data.append(UInt8(56))
    data.append(UInt8(51))
    data.append(UInt8(70))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(68))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(69))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unicode_U+1FFFE_nonchar.json")
        return False


def test_y_string_unicode_U_200B_ZERO_WIDTH_SPACE() -> Bool:
    """Accept: y_string_unicode_U+200B_ZERO_WIDTH_SPACE.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(50))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(66))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unicode_U+200B_ZERO_WIDTH_SPACE.json")
        return False


def test_y_string_unicode_U_2064_invisible_plus() -> Bool:
    """Accept: y_string_unicode_U+2064_invisible_plus.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(50))
    data.append(UInt8(48))
    data.append(UInt8(54))
    data.append(UInt8(52))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unicode_U+2064_invisible_plus.json")
        return False


def test_y_string_unicode_U_FDD0_nonchar() -> Bool:
    """Accept: y_string_unicode_U+FDD0_nonchar.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(70))
    data.append(UInt8(68))
    data.append(UInt8(68))
    data.append(UInt8(48))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unicode_U+FDD0_nonchar.json")
        return False


def test_y_string_unicode_U_FFFE_nonchar() -> Bool:
    """Accept: y_string_unicode_U+FFFE_nonchar.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(70))
    data.append(UInt8(69))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unicode_U+FFFE_nonchar.json")
        return False


def test_y_string_unicode_escaped_double_quote() -> Bool:
    """Accept: y_string_unicode_escaped_double_quote.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(92))
    data.append(UInt8(117))
    data.append(UInt8(48))
    data.append(UInt8(48))
    data.append(UInt8(50))
    data.append(UInt8(50))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_unicode_escaped_double_quote.json")
        return False


def test_y_string_utf8() -> Bool:
    """Accept: y_string_utf8.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(226))
    data.append(UInt8(130))
    data.append(UInt8(172))
    data.append(UInt8(240))
    data.append(UInt8(157))
    data.append(UInt8(132))
    data.append(UInt8(158))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_utf8.json")
        return False


def test_y_string_with_del_character() -> Bool:
    """Accept: y_string_with_del_character.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(127))
    data.append(UInt8(97))
    data.append(UInt8(34))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_string_with_del_character.json")
        return False


def test_y_structure_lonely_false() -> Bool:
    """Accept: y_structure_lonely_false.json."""
    var data = List[UInt8]()
    data.append(UInt8(102))
    data.append(UInt8(97))
    data.append(UInt8(108))
    data.append(UInt8(115))
    data.append(UInt8(101))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_structure_lonely_false.json")
        return False


def test_y_structure_lonely_int() -> Bool:
    """Accept: y_structure_lonely_int.json."""
    var data = List[UInt8]()
    data.append(UInt8(52))
    data.append(UInt8(50))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_structure_lonely_int.json")
        return False


def test_y_structure_lonely_negative_real() -> Bool:
    """Accept: y_structure_lonely_negative_real.json."""
    var data = List[UInt8]()
    data.append(UInt8(45))
    data.append(UInt8(48))
    data.append(UInt8(46))
    data.append(UInt8(49))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_structure_lonely_negative_real.json")
        return False


def test_y_structure_lonely_null() -> Bool:
    """Accept: y_structure_lonely_null.json."""
    var data = List[UInt8]()
    data.append(UInt8(110))
    data.append(UInt8(117))
    data.append(UInt8(108))
    data.append(UInt8(108))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_structure_lonely_null.json")
        return False


def test_y_structure_lonely_string() -> Bool:
    """Accept: y_structure_lonely_string.json."""
    var data = List[UInt8]()
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(115))
    data.append(UInt8(100))
    data.append(UInt8(34))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_structure_lonely_string.json")
        return False


def test_y_structure_lonely_true() -> Bool:
    """Accept: y_structure_lonely_true.json."""
    var data = List[UInt8]()
    data.append(UInt8(116))
    data.append(UInt8(114))
    data.append(UInt8(117))
    data.append(UInt8(101))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_structure_lonely_true.json")
        return False


def test_y_structure_string_empty() -> Bool:
    """Accept: y_structure_string_empty.json."""
    var data = List[UInt8]()
    data.append(UInt8(34))
    data.append(UInt8(34))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_structure_string_empty.json")
        return False


def test_y_structure_trailing_newline() -> Bool:
    """Accept: y_structure_trailing_newline.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(34))
    data.append(UInt8(97))
    data.append(UInt8(34))
    data.append(UInt8(93))
    data.append(UInt8(10))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_structure_trailing_newline.json")
        return False


def test_y_structure_true_in_array() -> Bool:
    """Accept: y_structure_true_in_array.json."""
    var data = List[UInt8]()
    data.append(UInt8(91))
    data.append(UInt8(116))
    data.append(UInt8(114))
    data.append(UInt8(117))
    data.append(UInt8(101))
    data.append(UInt8(93))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_structure_true_in_array.json")
        return False


def test_y_structure_whitespace_array() -> Bool:
    """Accept: y_structure_whitespace_array.json."""
    var data = List[UInt8]()
    data.append(UInt8(32))
    data.append(UInt8(91))
    data.append(UInt8(93))
    data.append(UInt8(32))
    try:
        _ = parse(data)
        return True
    except:
        print("FAIL (unexpected reject): y_structure_whitespace_array.json")
        return False


def main() raises:
    var passed = 0
    var failed = 0

    if test_y_array_arraysWithSpaces():
        passed += 1
    else:
        failed += 1

    if test_y_array_empty_string():
        passed += 1
    else:
        failed += 1

    if test_y_array_empty():
        passed += 1
    else:
        failed += 1

    if test_y_array_ending_with_newline():
        passed += 1
    else:
        failed += 1

    if test_y_array_false():
        passed += 1
    else:
        failed += 1

    if test_y_array_heterogeneous():
        passed += 1
    else:
        failed += 1

    if test_y_array_null():
        passed += 1
    else:
        failed += 1

    if test_y_array_with_1_and_newline():
        passed += 1
    else:
        failed += 1

    if test_y_array_with_leading_space():
        passed += 1
    else:
        failed += 1

    if test_y_array_with_several_null():
        passed += 1
    else:
        failed += 1

    if test_y_array_with_trailing_space():
        passed += 1
    else:
        failed += 1

    if test_y_number():
        passed += 1
    else:
        failed += 1

    if test_y_number_0e_1():
        passed += 1
    else:
        failed += 1

    if test_y_number_0e1():
        passed += 1
    else:
        failed += 1

    if test_y_number_after_space():
        passed += 1
    else:
        failed += 1

    if test_y_number_double_close_to_zero():
        passed += 1
    else:
        failed += 1

    if test_y_number_int_with_exp():
        passed += 1
    else:
        failed += 1

    if test_y_number_minus_zero():
        passed += 1
    else:
        failed += 1

    if test_y_number_negative_int():
        passed += 1
    else:
        failed += 1

    if test_y_number_negative_one():
        passed += 1
    else:
        failed += 1

    if test_y_number_negative_zero():
        passed += 1
    else:
        failed += 1

    if test_y_number_real_capital_e():
        passed += 1
    else:
        failed += 1

    if test_y_number_real_capital_e_neg_exp():
        passed += 1
    else:
        failed += 1

    if test_y_number_real_capital_e_pos_exp():
        passed += 1
    else:
        failed += 1

    if test_y_number_real_exponent():
        passed += 1
    else:
        failed += 1

    if test_y_number_real_fraction_exponent():
        passed += 1
    else:
        failed += 1

    if test_y_number_real_neg_exp():
        passed += 1
    else:
        failed += 1

    if test_y_number_real_pos_exponent():
        passed += 1
    else:
        failed += 1

    if test_y_number_simple_int():
        passed += 1
    else:
        failed += 1

    if test_y_number_simple_real():
        passed += 1
    else:
        failed += 1

    if test_y_object():
        passed += 1
    else:
        failed += 1

    if test_y_object_basic():
        passed += 1
    else:
        failed += 1

    if test_y_object_duplicated_key():
        passed += 1
    else:
        failed += 1

    if test_y_object_duplicated_key_and_value():
        passed += 1
    else:
        failed += 1

    if test_y_object_empty():
        passed += 1
    else:
        failed += 1

    if test_y_object_empty_key():
        passed += 1
    else:
        failed += 1

    if test_y_object_escaped_null_in_key():
        passed += 1
    else:
        failed += 1

    if test_y_object_extreme_numbers():
        passed += 1
    else:
        failed += 1

    if test_y_object_long_strings():
        passed += 1
    else:
        failed += 1

    if test_y_object_simple():
        passed += 1
    else:
        failed += 1

    if test_y_object_string_unicode():
        passed += 1
    else:
        failed += 1

    if test_y_object_with_newlines():
        passed += 1
    else:
        failed += 1

    if test_y_string_1_2_3_bytes_UTF_8_sequences():
        passed += 1
    else:
        failed += 1

    if test_y_string_accepted_surrogate_pair():
        passed += 1
    else:
        failed += 1

    if test_y_string_accepted_surrogate_pairs():
        passed += 1
    else:
        failed += 1

    if test_y_string_allowed_escapes():
        passed += 1
    else:
        failed += 1

    if test_y_string_backslash_and_u_escaped_zero():
        passed += 1
    else:
        failed += 1

    if test_y_string_backslash_doublequotes():
        passed += 1
    else:
        failed += 1

    if test_y_string_comments():
        passed += 1
    else:
        failed += 1

    if test_y_string_double_escape_a():
        passed += 1
    else:
        failed += 1

    if test_y_string_double_escape_n():
        passed += 1
    else:
        failed += 1

    if test_y_string_escaped_control_character():
        passed += 1
    else:
        failed += 1

    if test_y_string_escaped_noncharacter():
        passed += 1
    else:
        failed += 1

    if test_y_string_in_array():
        passed += 1
    else:
        failed += 1

    if test_y_string_in_array_with_leading_space():
        passed += 1
    else:
        failed += 1

    if test_y_string_last_surrogates_1_and_2():
        passed += 1
    else:
        failed += 1

    if test_y_string_nbsp_uescaped():
        passed += 1
    else:
        failed += 1

    if test_y_string_nonCharacterInUTF_8_U_10FFFF():
        passed += 1
    else:
        failed += 1

    if test_y_string_nonCharacterInUTF_8_U_FFFF():
        passed += 1
    else:
        failed += 1

    if test_y_string_null_escape():
        passed += 1
    else:
        failed += 1

    if test_y_string_one_byte_utf_8():
        passed += 1
    else:
        failed += 1

    if test_y_string_pi():
        passed += 1
    else:
        failed += 1

    if test_y_string_reservedCharacterInUTF_8_U_1BFFF():
        passed += 1
    else:
        failed += 1

    if test_y_string_simple_ascii():
        passed += 1
    else:
        failed += 1

    if test_y_string_space():
        passed += 1
    else:
        failed += 1

    if test_y_string_surrogates_U_1D11E_MUSICAL_SYMBOL_G_CLEF():
        passed += 1
    else:
        failed += 1

    if test_y_string_three_byte_utf_8():
        passed += 1
    else:
        failed += 1

    if test_y_string_two_byte_utf_8():
        passed += 1
    else:
        failed += 1

    if test_y_string_u_2028_line_sep():
        passed += 1
    else:
        failed += 1

    if test_y_string_u_2029_par_sep():
        passed += 1
    else:
        failed += 1

    if test_y_string_uEscape():
        passed += 1
    else:
        failed += 1

    if test_y_string_uescaped_newline():
        passed += 1
    else:
        failed += 1

    if test_y_string_unescaped_char_delete():
        passed += 1
    else:
        failed += 1

    if test_y_string_unicode():
        passed += 1
    else:
        failed += 1

    if test_y_string_unicodeEscapedBackslash():
        passed += 1
    else:
        failed += 1

    if test_y_string_unicode_2():
        passed += 1
    else:
        failed += 1

    if test_y_string_unicode_U_10FFFE_nonchar():
        passed += 1
    else:
        failed += 1

    if test_y_string_unicode_U_1FFFE_nonchar():
        passed += 1
    else:
        failed += 1

    if test_y_string_unicode_U_200B_ZERO_WIDTH_SPACE():
        passed += 1
    else:
        failed += 1

    if test_y_string_unicode_U_2064_invisible_plus():
        passed += 1
    else:
        failed += 1

    if test_y_string_unicode_U_FDD0_nonchar():
        passed += 1
    else:
        failed += 1

    if test_y_string_unicode_U_FFFE_nonchar():
        passed += 1
    else:
        failed += 1

    if test_y_string_unicode_escaped_double_quote():
        passed += 1
    else:
        failed += 1

    if test_y_string_utf8():
        passed += 1
    else:
        failed += 1

    if test_y_string_with_del_character():
        passed += 1
    else:
        failed += 1

    if test_y_structure_lonely_false():
        passed += 1
    else:
        failed += 1

    if test_y_structure_lonely_int():
        passed += 1
    else:
        failed += 1

    if test_y_structure_lonely_negative_real():
        passed += 1
    else:
        failed += 1

    if test_y_structure_lonely_null():
        passed += 1
    else:
        failed += 1

    if test_y_structure_lonely_string():
        passed += 1
    else:
        failed += 1

    if test_y_structure_lonely_true():
        passed += 1
    else:
        failed += 1

    if test_y_structure_string_empty():
        passed += 1
    else:
        failed += 1

    if test_y_structure_trailing_newline():
        passed += 1
    else:
        failed += 1

    if test_y_structure_true_in_array():
        passed += 1
    else:
        failed += 1

    if test_y_structure_whitespace_array():
        passed += 1
    else:
        failed += 1

    print(String("test_accept: ") + String(passed) + String(" passed, ") + String(failed) + String(" failed out of ") + String(95))
    if failed > 0:
        raise Error("Some accept tests failed")
