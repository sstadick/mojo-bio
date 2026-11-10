from mojo_bio import radix_sort
from std.testing import assert_equal


@fieldwise_init
struct Read(Copyable, Movable):
    var position: Int32
    var name: String


def position(reading: Read) -> Int32:
    return reading.position


def main() raises:
    var values: List[Int16] = [500, -1, 256, -32768, 0, 32767]
    radix_sort(Span(values))
    assert_equal(values[0], Int16(-32768))
    assert_equal(values[5], Int16(32767))
    var reads = [Read(42, "later"), Read(-5, "earlier")]
    radix_sort[key=position](Span(reads))
    assert_equal(reads[0].name, "earlier")
    print("sorted signed integers and records; payloads preserved")
