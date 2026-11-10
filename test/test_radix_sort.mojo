from mojo_bio import insert_sort, radix_sort
from std.testing import assert_equal, assert_true, TestSuite


def next_random(mut state: UInt64) -> UInt64:
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state


def check_width[dtype: DType]() raises:
    comptime T = SIMD[dtype, 1]
    # Both sides of the top-level and recursive insertion-sort cutoff.
    for count in [0, 1, 2, 63, 64, 65, 129, 300, 2049]:
        for pattern in range(6):
            var values = List[T]()
            var state = UInt64(0x4D595DF4D0F33173)
            for i in range(count):
                var value: T
                if pattern == 0:
                    value = T(next_random(state))
                elif pattern == 1:
                    value = T((i * 73) % 17 - 8)
                elif pattern == 2:
                    value = T(count - i)
                elif pattern == 3:
                    value = T(i)
                elif pattern == 4:
                    value = T(-1)
                else:
                    # Mostly common upper bytes: forces recursive refinement.
                    value = T(0x12340000 + (count - i) % 257)
                values.append(value)
            var expected = values.copy()
            sort(expected)
            radix_sort(Span(values))
            assert_equal(values, expected)
            if count <= 65:
                var insertion = expected.copy()
                # Reverse the reference, retaining duplicates.
                for i in range(count):
                    insertion[i] = expected[count - i - 1]
                insert_sort(Span(insertion))
                assert_equal(insertion, expected)


def test_all_integer_widths_against_comparison_sort() raises:
    check_width[DType.int8]()
    check_width[DType.uint8]()
    check_width[DType.int16]()
    check_width[DType.uint16]()
    check_width[DType.int32]()
    check_width[DType.uint32]()
    check_width[DType.int64]()
    check_width[DType.uint64]()


def check_boundaries[
    dtype: DType
](minimum: SIMD[dtype, 1], maximum: SIMD[dtype, 1]) raises:
    comptime T = SIMD[dtype, 1]
    var input: List[T] = [
        maximum,
        T(0),
        minimum,
        T(1),
        T(-1),
        minimum + T(1),
        maximum - T(1),
    ]
    for repeats in [1, 10, 40]:
        var values = List[T]()
        for _ in range(repeats):
            for item in input:
                values.append(item)
        var expected = values.copy()
        sort(expected)
        radix_sort(Span(values))
        assert_equal(values, expected)
        assert_equal(values[0], minimum)
        assert_equal(values[len(values) - 1], maximum)


def test_explicit_extrema() raises:
    check_boundaries(Int8(-128), Int8(127))
    check_boundaries(UInt8(0), UInt8(255))
    check_boundaries(Int16(-32768), Int16(32767))
    check_boundaries(UInt16(0), UInt16(65535))
    check_boundaries(Int32(-2147483648), Int32(2147483647))
    check_boundaries(UInt32(0), UInt32(0xFFFFFFFF))
    check_boundaries(Int64(-9223372036854775808), Int64(9223372036854775807))
    check_boundaries(UInt64(0), UInt64(0xFFFFFFFFFFFFFFFF))


@fieldwise_init
struct Item[dtype: DType](Copyable):
    var key: SIMD[Self.dtype, 1]
    var id: Int
    var payload: String


def item_key[dtype: DType](item: Item[dtype]) -> SIMD[dtype, 1]:
    return item.key


def check_records[dtype: DType]() raises:
    for count in [0, 1, 63, 64, 65, 300, 1025]:
        var records = List[Item[dtype]]()
        var keys = List[SIMD[dtype, 1]]()
        for i in range(count):
            var key = SIMD[dtype, 1]((i * 73) % 301 - 150)
            records.append(Item[dtype](key, i, String(i)))
            keys.append(key)
        var expected = keys.copy()
        sort(expected)
        radix_sort[key=item_key[dtype]](Span(records))
        var seen = List[Bool](length=count, fill=False)
        for i in range(count):
            assert_equal(records[i].key, expected[i])
            var id = records[i].id
            assert_true(id >= 0 and id < count)
            assert_true(not seen[id])
            seen[id] = True
            assert_equal(records[i].key, keys[id])
            assert_equal(records[i].payload, String(id))


def test_keyed_owned_payloads_all_widths() raises:
    check_records[DType.int8]()
    check_records[DType.uint8]()
    check_records[DType.int16]()
    check_records[DType.uint16]()
    check_records[DType.int32]()
    check_records[DType.uint32]()
    check_records[DType.int64]()
    check_records[DType.uint64]()


def test_insertion_stability() raises:
    var records = List[Item[DType.int16]]()
    for i in range(130):
        records.append(Item[DType.int16](Int16((i * 7) % 5 - 2), i, String(i)))
    insert_sort[key=item_key[DType.int16]](Span(records))
    for i in range(len(records)):
        assert_equal(records[i].payload, String(records[i].id))
        if i > 0:
            assert_true(records[i - 1].key <= records[i].key)
            if records[i - 1].key == records[i].key:
                assert_true(records[i - 1].id < records[i].id)


def test_subspan_does_not_touch_neighbors() raises:
    var values = List[Int32]()
    values.append(123456)
    for i in range(300):
        values.append(Int32(299 - i))
    values.append(-654321)
    radix_sort(Span(values)[1:301])
    assert_equal(values[0], Int32(123456))
    assert_equal(values[301], Int32(-654321))
    for i in range(300):
        assert_equal(values[i + 1], Int32(i))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
