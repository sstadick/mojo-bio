# SPDX-License-Identifier: MIT
# Adapted from Heng Li's cgranges / klib radix sort, via Seth's gooslapper
# and its Mojo benchmark prototype. See LICENSE and NOTICE.md.
"""In-place sorting of scalar integers and integer-keyed records."""

from std.sys import size_of

comptime _MIN_SIZE = 64
comptime _RADIX_BITS = 8
comptime _BUCKET_COUNT = 1 << _RADIX_BITS


@fieldwise_init
struct _Bucket(ImplicitlyCopyable):
    var begin: Int
    var end: Int


@always_inline
def _identity[T: ImplicitlyCopyable](value: T) -> T:
    return value


@always_inline("nodebug")
def _digit[dtype: DType](key: SIMD[dtype, 1], shift: Int) -> Int:
    # Only the key-width low bits are visited, so sign extension is irrelevant.
    var bits = UInt64(key)
    comptime if dtype.is_signed():
        bits ^= UInt64(1) << UInt64(size_of[SIMD[dtype, 1]]() * 8 - 1)
    return Int((bits >> UInt64(shift)) & 255)


def _insert_sort[
    T: Copyable & Deinitable,
    dtype: DType,
    key: def(T) thin -> SIMD[dtype, 1],
](begin: Pointer[mut=True, T, _], length: Int):
    var end = begin.unsafe_offset(length)
    var current = begin.unsafe_offset(1)
    while current < end:
        if key(current[]) < key(current.unsafe_offset(-1)[]):
            var temporary = current[].copy()
            var destination = current
            while destination > begin and key(temporary) < key(
                destination.unsafe_offset(-1)[]
            ):
                destination[] = destination.unsafe_offset(-1)[].copy()
                destination = destination.unsafe_offset(-1)
            destination[] = temporary^
        current = current.unsafe_offset(1)


@no_inline
def _radix_sort_inner[
    T: Copyable & Deinitable,
    dtype: DType,
    key: def(T) thin -> SIMD[dtype, 1],
](begin: Pointer[mut=True, T, _], length: Int, shift: Int):
    var buckets = Array[_Bucket, _BUCKET_COUNT](uninitialized=True)
    var bucket_ptr = buckets.unsafe_ptr()
    var bucket_end = bucket_ptr.unsafe_offset(_BUCKET_COUNT)

    var bucket = bucket_ptr
    while bucket != bucket_end:
        bucket.unsafe_write(_Bucket(0, 0))
        bucket = bucket.unsafe_offset(1)

    var item = begin
    var end = begin.unsafe_offset(length)
    while item != end:
        var digit_bucket = bucket_ptr.unsafe_offset(_digit(key(item[]), shift))
        digit_bucket[].end += 1
        item = item.unsafe_offset(1)

    bucket = bucket_ptr.unsafe_offset(1)
    while bucket != bucket_end:
        var previous_end = bucket.unsafe_offset(-1)[].end
        bucket[].end += previous_end
        bucket[].begin = previous_end
        bucket = bucket.unsafe_offset(1)

    # Cycle whole records into buckets, retaining payload/key associations.
    bucket = bucket_ptr
    while bucket != bucket_end:
        if bucket[].begin != bucket[].end:
            var target = bucket_ptr.unsafe_offset(
                _digit(key(begin[unsafe_offset=bucket[].begin]), shift)
            )
            if target != bucket:
                var temporary = begin[unsafe_offset=bucket[].begin].copy()
                while True:
                    var displaced = begin[unsafe_offset=target[].begin].copy()
                    begin[unsafe_offset=target[].begin] = temporary^
                    target[].begin += 1
                    temporary = displaced^
                    target = bucket_ptr.unsafe_offset(
                        _digit(key(temporary), shift)
                    )
                    if target == bucket:
                        break
                begin[unsafe_offset=bucket[].begin] = temporary^
            bucket[].begin += 1
        else:
            bucket = bucket.unsafe_offset(1)

    bucket_ptr[].begin = 0
    bucket = bucket_ptr.unsafe_offset(1)
    while bucket != bucket_end:
        bucket[].begin = bucket.unsafe_offset(-1)[].end
        bucket = bucket.unsafe_offset(1)

    if shift != 0:
        bucket = bucket_ptr
        while bucket != bucket_end:
            var count = bucket[].end - bucket[].begin
            if count > _MIN_SIZE:
                _radix_sort_inner[T, dtype, key](
                    begin.unsafe_offset(bucket[].begin),
                    count,
                    shift - _RADIX_BITS,
                )
            elif count > 1:
                _insert_sort[T, dtype, key](
                    begin.unsafe_offset(bucket[].begin), count
                )
            bucket = bucket.unsafe_offset(1)


@always_inline
def insert_sort[
    T: Copyable & Deinitable,
    dtype: DType,
    //,
    key: def(T) thin -> SIMD[dtype, 1],
](values: Span[mut=True, T, _]):
    """Stably sort a mutable span by a non-raising, deterministic integer key.

    Equal keys retain their input order. Complete records, including owned
    payloads, are copied/moved. The key function must not mutate the input.

    ```mojo {doctest="stable_key" global=true}
    from mojo_bio import insert_sort
    from std.testing import assert_equal

    def low_byte(value: UInt16) -> UInt16:
        return value & 255

    def main() raises:
        var values: List[UInt16] = [0x102, 0x001, 0x202]
        insert_sort[key=low_byte](Span(values))
        var expected: List[UInt16] = [0x001, 0x102, 0x202]
        assert_equal(values, expected)
    ```
    """
    comptime assert (
        dtype.is_integral() and size_of[SIMD[dtype, 1]]() <= 8
    ), "Expected an 8/16/32/64-bit integer key"
    if len(values) > 1:
        var begin = values.unsafe_ptr()
        _insert_sort[T, dtype, key](begin, len(values))


@always_inline
def insert_sort[dtype: DType](values: Span[mut=True, SIMD[dtype, 1], _]):
    """Stably sort scalar integers in ascending numeric order, in place.

    ```mojo {doctest="insertion" global=true}
    from mojo_bio import insert_sort
    from std.testing import assert_equal

    def main() raises:
        var values: List[Int32] = [4, -1, 3, -1]
        insert_sort(Span(values))
        var expected: List[Int32] = [-1, -1, 3, 4]
        assert_equal(values, expected)
    ```
    """
    insert_sort[key=_identity[SIMD[dtype, 1]]](values)


@always_inline
def radix_sort[
    T: Copyable & Deinitable,
    dtype: DType,
    //,
    key: def(T) thin -> SIMD[dtype, 1],
](values: Span[mut=True, T, _]):
    """Sort records in place by a signed/unsigned 8/16/32/64-bit integer key.

    This sort is NOT stable: equal-key records may change order. Empty spans
    are accepted.
    The key must be deterministic, non-raising, and must not mutate the input.
    Records must be Copyable and Deinitable; payloads remain attached to keys.

    ```mojo {doctest="radix_key" global=true}
    from mojo_bio import radix_sort
    from std.testing import assert_equal

    def low_byte(value: UInt16) -> UInt16:
        return value & 255

    def main() raises:
        var values: List[UInt16] = [0x102, 0x001, 0x100]
        radix_sort[key=low_byte](Span(values))
        var expected: List[UInt16] = [0x100, 0x001, 0x102]
        assert_equal(values, expected)
    ```
    """
    comptime assert (
        dtype.is_integral() and size_of[SIMD[dtype, 1]]() <= 8
    ), "Expected an 8/16/32/64-bit integer key"
    if len(values) <= _MIN_SIZE:
        insert_sort[key=key](values)
    else:
        var begin = values.unsafe_ptr()
        _radix_sort_inner[T, dtype, key](
            begin, len(values), size_of[SIMD[dtype, 1]]() * 8 - _RADIX_BITS
        )


@always_inline
def radix_sort[dtype: DType](values: Span[mut=True, SIMD[dtype, 1], _]):
    """Sort scalar integers in ascending numeric order, in place (unstable).

    ```mojo {doctest="radix_integers" global=true}
    from mojo_bio import radix_sort
    from std.testing import assert_equal

    def main() raises:
        var values: List[Int16] = [500, -1, 256, -32768, 0, 32767]
        radix_sort(Span(values))
        var expected: List[Int16] = [-32768, -1, 0, 256, 500, 32767]
        assert_equal(values, expected)
    ```
    """
    radix_sort[key=_identity[SIMD[dtype, 1]]](values)
