# Radix sort benchmark

This benchmark compares `mojo_bio.radix_sort` with the C radix sorter from
cgranges. See [../NOTICE.md](../NOTICE.md) for attribution.

Both sides generate the same 16-byte records (UInt64 key, UInt64 payload) with
xorshift seed `0x4D595DF4D0F33173`. Each owns separate correctly typed storage;
records do not cross the FFI boundary. They run in the same process, time only
sorting with Mojo's monotonic clock, exclude memcpy resets, and alternate which
implementation runs first. The warmup verifies Mojo ordering, payload relation,
sum and xor, and C ordering. Timed runs consume three-position checksums and
require equal accumulated checksums. These checks are not a proof of complete
permutation preservation; the library tests independently compare every key
and verify every record identity instead.

Each round takes 1,000, 200, 20, and 6 samples respectively at 1,024, 16,384,
262,144, and 1,048,576 records. The runner reports the median of all samples,
not the median of per-round medians. C uses `-O3 -march=native`; Mojo uses
`-O3 --march native`. Compiler choice is part of this comparison.

## Reproduce

```sh
pixi run bench --rounds 5 --cpu 0
# Choose an available CPU from `taskset -pc $$`, or omit --cpu.
# Optional, when Clang is installed:
pixi run bench --rounds 5 --cpu 0 --cc clang
# Direct invocation (runner accepts a shell-style Mojo command):
python3 bench/run_mojo_radix_sort_bench.py --rounds 5 --cpu 0 --mojo 'pixi run mojo'
```

Requires Python 3, a C compiler, and Linux `taskset` if `--cpu` is used. Build
objects/executables live in a temporary directory that the runner removes.
`--march` defaults to `native`; set it explicitly for other comparisons.

## Local orb measurement, 2026-11-10

Linux x86-64 orb, four visible vCPUs, CPU reported as
`Intel(R) Xeon(R) Processor @ 2.60GHz`; pinned to guest CPU 0.
Mojo `1.2.0 (2016d0cd)`, GCC `12.2.0` (Debian 12.2.0-14+deb12u1).
Command: `pixi run bench --rounds 5 --cpu 0`.

| Items | C median | Mojo median | Mojo/C | C ns/item | Mojo ns/item | Samples each |
|---:|---:|---:|---:|---:|---:|---:|
| 1,024 | 0.008 ms | 0.008 ms | 0.989x | 8.06 | 7.97 | 5,000 |
| 16,384 | 0.414 ms | 0.486 ms | 1.175x | 25.24 | 29.67 | 1,000 |
| 262,144 | 9.270 ms | 9.283 ms | 1.001x | 35.36 | 35.41 | 100 |
| 1,048,576 | 68.823 ms | 63.163 ms | 0.918x | 65.63 | 60.24 | 30 |

Mojo was 17.5% slower at 16K, approximately tied at 1K and 256K, and 8.2%
faster at 1M in this run. A virtualized shared host and guest CPU affinity do
not isolate physical-core contention. This is not a cross-language speed
claim or a replacement for common-host comparisons.
Clang was not installed, so no Clang result is reported.

## Common-host measurement, 2026-11-10

AMD Ryzen 9 3950X, Linux x86-64, pinned CPU 0, Mojo 1.2.0. Both runs use the
same protocol above: five rounds, native CPU, and no concurrent test/build work.
Commands: `pixi run bench --rounds 5 --cpu 0 --output results/gcc.json` and
the same command with `--cc clang --output results/clang.json`.
The JSON records raw samples, compiler versions, flags, and source hashes.

| Items | Mojo/GCC time | Mojo/Clang time |
| ---: | ---: | ---: |
| 1,024 | 0.970× | 1.153× |
| 16,384 | 1.179× | 1.250× |
| 262,144 | 0.941× | 1.104× |
| 1,048,576 | 0.939× | 1.074× |

Lower is better. Mojo is competitive with GCC in these workloads but loses
to Clang throughout; the largest observed gap is 25% at 16K. These are sorting
times for this specific record type and distribution, not a universal claim.

The benchmark covers only trivial UInt64 records, not signed widths or
owning payload performance.
