struct Tape(Movable):
    """Flat tape of 64-bit elements plus a string buffer."""

    var elements: List[UInt64]
    var string_buf: List[UInt8]

    def __init__(out self):
        self.elements = List[UInt64]()
        self.string_buf = List[UInt8]()

    def __init__(out self, *, deinit take: Self):
        self.elements = take.elements^
        self.string_buf = take.string_buf^

    def tag_at(self, idx: Int) -> UInt8:
        return UInt8(self.elements[idx] >> 56)

    def payload_at(self, idx: Int) -> UInt64:
        return self.elements[idx] & 0x00FFFFFFFFFFFFFF

    def append(mut self, tag: UInt8, payload: UInt64):
        self.elements.append(make_tape_entry(tag, payload))

    def append_raw(mut self, value: UInt64):
        self.elements.append(value)


def make_tape_entry(tag: UInt8, payload: UInt64) -> UInt64:
    return (UInt64(tag) << 56) | (payload & 0x00FFFFFFFFFFFFFF)


def tape_tag(entry: UInt64) -> UInt8:
    return UInt8(entry >> 56)


def tape_payload(entry: UInt64) -> UInt64:
    return entry & 0x00FFFFFFFFFFFFFF
