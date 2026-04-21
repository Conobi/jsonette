struct Value:
    """Lightweight tape index view into a Document."""
    var _idx: Int

    def __init__(out self, idx: Int):
        self._idx = idx
