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

    def __init__(out self, *, deinit take: Self):
        self.elements = take.elements^
        self.string_buf = take.string_buf^

    @always_inline("nodebug")
    def tag_at(self, idx: Int) -> UInt8:
        return UInt8(self.elements.unsafe_get(idx) >> 56)

    @always_inline("nodebug")
    def payload_at(self, idx: Int) -> UInt64:
        return self.elements.unsafe_get(idx) & 0x00FFFFFFFFFFFFFF

    @always_inline("nodebug")
    def append(mut self, tag: UInt8, payload: UInt64):
        self.elements.append(make_tape_entry(tag, payload))

    @always_inline("nodebug")
    def append_raw(mut self, value: UInt64):
        self.elements.append(value)


@always_inline("nodebug")
def make_tape_entry(tag: UInt8, payload: UInt64) -> UInt64:
    return (UInt64(tag) << 56) | (payload & 0x00FFFFFFFFFFFFFF)


@always_inline("nodebug")
def tape_tag(entry: UInt64) -> UInt8:
    return UInt8(entry >> 56)


@always_inline("nodebug")
def tape_payload(entry: UInt64) -> UInt64:
    return entry & 0x00FFFFFFFFFFFFFF
