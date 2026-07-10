"""Tape: the flat, depth-first value array Stage 2 builds and `Value` views.

The tape is a `List[UInt64]` where each element packs an 8-bit type tag in the
high byte and a 56-bit payload in the low bytes (`make_tape_entry` /`tape_tag` /
`tape_payload` encode and decode this). Scalars that need a full 64-bit word
(ints, floats) occupy a second raw element written by `append_raw`. The tag
constants below are the simdjson tape tags, deliberately chosen to equal the
ASCII byte that opens each JSON value (`{`, `[`, `"`, `t`, `f`, `n`) so Stage 2
can dispatch on the structural byte directly; the numeric tags (`l`/`u`/`d`) and
`TAG_ROOT` (`r`) follow simdjson's lettering.

A `TAG_STRING` payload comes in two variants, discriminated by bit 55:
  * raw span (bit 55 set): bits 0..31 = offset of the content in the parser's
    padded input, bits 32..54 = content length. Used for escape-free strings,
    which need no unescaping and hence no copy at all.
  * buffer entry (bit 55 clear): offset into the separate `string_buf`, which
    holds `[u32 len LE][content][NUL]` for strings that required unescaping.
Both backing Lists are owned by the `Parser` and reused across parses, so this
struct holds no allocation logic beyond the optional capacity-preallocating
constructor.
"""

from jsonette._alloc_count import record_alloc

comptime TAG_ROOT = UInt8(0x72)
comptime TAG_OBJECT_OPEN = UInt8(0x7B)
comptime TAG_OBJECT_CLOSE = UInt8(0x7D)
comptime TAG_ARRAY_OPEN = UInt8(0x5B)
comptime TAG_ARRAY_CLOSE = UInt8(0x5D)
comptime TAG_STRING = UInt8(0x22)
comptime TAG_INT64 = UInt8(0x6C)
comptime TAG_UINT64 = UInt8(0x75)
comptime TAG_FLOAT64 = UInt8(0x64)
comptime TAG_TRUE = UInt8(0x74)
comptime TAG_FALSE = UInt8(0x66)
comptime TAG_NULL = UInt8(0x6E)

# Raw-span string payload encoding (see module docstring). The 23-bit length
# field caps raw spans at ~8 MiB; longer escape-free strings fall back to the
# string_buf copy path.
comptime RAW_STRING_FLAG: UInt64 = UInt64(1) << 55
comptime RAW_STRING_MAX_LEN: Int = 0x7FFFFF


@always_inline("nodebug")
def make_raw_string_payload(offset: Int, length: Int) -> UInt64:
    """Pack a raw-span string payload. `length` must be <= RAW_STRING_MAX_LEN."""
    return RAW_STRING_FLAG | (UInt64(length) << 32) | UInt64(offset)


@always_inline("nodebug")
def is_raw_string(payload: UInt64) -> Bool:
    """True iff this TAG_STRING payload is a raw input span (not a string_buf offset)."""
    return (payload & RAW_STRING_FLAG) != 0


@always_inline("nodebug")
def raw_string_offset(payload: UInt64) -> Int:
    """Content start offset (into the parser's padded input) of a raw-span payload."""
    return Int(payload & 0xFFFFFFFF)


@always_inline("nodebug")
def raw_string_length(payload: UInt64) -> Int:
    """Content byte length of a raw-span payload."""
    return Int((payload >> 32) & 0x7FFFFF)


struct Tape(Movable):
    """Flat tape of 64-bit elements plus a string buffer."""

    var elements: List[UInt64]
    var string_buf: List[UInt8]

    def __init__(out self):
        self.elements = List[UInt64]()
        self.string_buf = List[UInt8]()

    def __init__(out self, element_capacity: Int, string_capacity: Int):
        # Use unsafe_uninit_length to avoid zeroing — raw pointer writes fill before read
        # Two heap allocs per parse: the elements list and the string buffer.
        record_alloc()
        self.elements = List[UInt64](unsafe_uninit_length=element_capacity)
        record_alloc()
        self.string_buf = List[UInt8](unsafe_uninit_length=string_capacity)

    def __init__(out self, *, deinit move: Self):
        self.elements = move.elements^
        self.string_buf = move.string_buf^

    @always_inline("nodebug")
    def tag_at(self, idx: Int) -> UInt8:
        """Return the 8-bit type tag of the element at `idx` (its high byte).

        Uses `unsafe_get` (no bounds check): `idx` is a trusted tape offset.
        """
        return UInt8(self.elements.unsafe_get(idx) >> 56)

    @always_inline("nodebug")
    def payload_at(self, idx: Int) -> UInt64:
        """Return the 56-bit payload of the element at `idx` (tag byte masked off).

        Uses `unsafe_get` (no bounds check): `idx` is a trusted tape offset.
        """
        return self.elements.unsafe_get(idx) & 0x00FFFFFFFFFFFFFF

    @always_inline("nodebug")
    def append(mut self, tag: UInt8, payload: UInt64):
        """Append one tagged element, packing `tag` and `payload` into a 64-bit word."""
        self.elements.append(make_tape_entry(tag, payload))

    @always_inline("nodebug")
    def append_raw(mut self, value: UInt64):
        """Append a raw 64-bit word with no tag packing.

        Used for the second element of a number (the full int/float bit pattern),
        which needs all 64 bits and is read in tandem with its preceding tag.
        """
        self.elements.append(value)


@always_inline("nodebug")
def make_tape_entry(tag: UInt8, payload: UInt64) -> UInt64:
    """Pack an 8-bit `tag` (high byte) and a 56-bit `payload` into one tape word.

    The payload is masked to 56 bits, so any high bits the caller passes are
    dropped rather than corrupting the tag.
    """
    return (UInt64(tag) << 56) | (payload & 0x00FFFFFFFFFFFFFF)


@always_inline("nodebug")
def tape_tag(entry: UInt64) -> UInt8:
    """Extract the 8-bit type tag (high byte) from a packed tape `entry`."""
    return UInt8(entry >> 56)


@always_inline("nodebug")
def tape_payload(entry: UInt64) -> UInt64:
    """Extract the 56-bit payload (tag byte masked off) from a packed tape `entry`."""
    return entry & 0x00FFFFFFFFFFFFFF
