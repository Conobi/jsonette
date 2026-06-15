"""DOM redesign migration safety: deep navigation reads values matching python json.loads.

Oracle commands generated the embedded expected constants:
    python3 -c "import json; d=json.load(open('tests/fixtures/corpus/canada.json')); print(d['type'], d['features'][0]['geometry']['type'])"
        -> FeatureCollection Polygon
    python3 -c "import json; d=json.load(open('tests/fixtures/corpus/twitter.json')); print(d['search_metadata']['count'], d['statuses'][0]['id'])"
        -> 100 505874924095815681
    python3 -c "import json; d=json.load(open('tests/fixtures/corpus/citm_catalog.json')); k=next(iter(d['areaNames'])); print(repr(d['areaNames'][k]))"
        -> 'Arrière-scène central'
"""
from std.testing import assert_equal
from jsonette.document import parse


def _read(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var c = f.read()
    f.close()
    var b = List[UInt8]()
    for x in c.as_bytes():
        b.append(x)
    return b^


def test_canada() raises:
    var doc = parse(_read(String("tests/fixtures/corpus/canada.json")))
    assert_equal(doc.root().field("type").get_string(), String("FeatureCollection"))
    var gt = doc.root().field("features").elem(0).field("geometry").field("type")
    assert_equal(gt.get_string(), String("Polygon"))


def test_twitter() raises:
    var doc = parse(_read(String("tests/fixtures/corpus/twitter.json")))
    var sm = doc.root().field("search_metadata")
    assert_equal(sm.field("count").get_uint(), UInt64(100))
    # statuses[0].id (505874924095815681) is non-negative -> tape encodes UINT64.
    var sid = doc.root().field("statuses").elem(0).field("id")
    assert_equal(sid.get_uint(), UInt64(505874924095815681))


def test_citm() raises:
    var doc = parse(_read(String("tests/fixtures/corpus/citm_catalog.json")))
    var area_names = doc.root().field("areaNames")
    # First (key, value) entry in document order; value carries the same gen.
    var first_value = String("")
    for entry in area_names.fields():
        first_value = entry.value().get_string()
        break
    assert_equal(first_value, String("Arrière-scène central"))


def main() raises:
    test_canada()
    test_twitter()
    test_citm()
    print("test_dom_differential: all passed")
