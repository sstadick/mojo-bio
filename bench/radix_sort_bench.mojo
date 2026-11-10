from mojo_bio import radix_sort as bio_radix_sort
from std.ffi import external_call
from std.memory import unsafe_memcpy
from std.memory.alloc import unsafe_alloc
from std.testing import assert_equal, assert_true
from std.time import monotonic


@fieldwise_init
struct Record(ImplicitlyCopyable):
    var key: UInt64
    var payload: UInt64


comptime RecordPtr = Pointer[mut=True, Record, MutUntrackedOrigin]


def record_key(record: Record) -> UInt64:
    return record.key


@always_inline
def radix_sort(begin: RecordPtr, length: Int):
    bio_radix_sort[key=record_key](Span(unsafe_ptr=begin, length=length))


@always_inline("nodebug")
def next_random(mut state: UInt64) -> UInt64:
    var value = state
    value ^= value << 13
    value ^= value >> 7
    value ^= value << 17
    state = value
    return value


def reset(source: RecordPtr, work: RecordPtr, length: Int):
    unsafe_memcpy(dest=work, src=source, count=length)


def run_case(length: Int, repetitions: Int) raises:
    var source = unsafe_alloc[Record](length)
    var work = unsafe_alloc[Record](length)
    var state = UInt64(0x4D595DF4D0F33173)
    var source_sum = UInt64(0)
    var source_xor = UInt64(0)
    for i in range(length):
        var key = next_random(state)
        var record = Record(key, key ^ UInt64(0x9E3779B97F4A7C15))
        source.unsafe_offset(i).unsafe_write(record)
        work.unsafe_offset(i).unsafe_write(record)
        source_sum += key
        source_xor ^= key

    reset(source, work, length)
    radix_sort(work, length)
    var output_sum = UInt64(0)
    var output_xor = UInt64(0)
    for i in range(length):
        var record = work[unsafe_offset=i]
        assert_equal(record.payload, record.key ^ UInt64(0x9E3779B97F4A7C15))
        output_sum += record.key
        output_xor ^= record.key
        if i != 0:
            assert_true(work[unsafe_offset=i - 1].key <= record.key)
    assert_equal(output_sum, source_sum)
    assert_equal(output_xor, source_xor)

    external_call["c_setup", NoneType](length)
    external_call["c_reset", NoneType]()
    external_call["c_radix_sort", NoneType]()
    assert_true(external_call["c_validate", Bool]())

    var mojo_checksum = UInt64(0)
    var c_checksum = UInt64(0)
    for repetition in range(repetitions):
        if repetition % 2 == 0:
            reset(source, work, length)
            var start = monotonic()
            radix_sort(work, length)
            var elapsed = monotonic() - start
            mojo_checksum += (
                work[].key
                ^ work[unsafe_offset=length // 2].payload
                ^ work[unsafe_offset=length - 1].key
            )
            print("mojo,", length, ",", elapsed, sep="")

            external_call["c_reset", NoneType]()
            start = monotonic()
            external_call["c_radix_sort", NoneType]()
            elapsed = monotonic() - start
            c_checksum += external_call["c_checksum", UInt64]()
            print("c,", length, ",", elapsed, sep="")
        else:
            external_call["c_reset", NoneType]()
            var start = monotonic()
            external_call["c_radix_sort", NoneType]()
            var elapsed = monotonic() - start
            c_checksum += external_call["c_checksum", UInt64]()
            print("c,", length, ",", elapsed, sep="")

            reset(source, work, length)
            start = monotonic()
            radix_sort(work, length)
            elapsed = monotonic() - start
            mojo_checksum += (
                work[].key
                ^ work[unsafe_offset=length // 2].payload
                ^ work[unsafe_offset=length - 1].key
            )
            print("mojo,", length, ",", elapsed, sep="")

    assert_equal(mojo_checksum, c_checksum)
    external_call["c_teardown", NoneType]()
    source.unsafe_free()
    work.unsafe_free()


def main() raises:
    run_case(1024, 1000)
    run_case(16384, 200)
    run_case(262144, 20)
    run_case(1048576, 6)
