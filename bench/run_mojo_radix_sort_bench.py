#!/usr/bin/env python3
"""Build and compare the Mojo radix sort with the cgranges C reference."""

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import statistics
import subprocess
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--cpu", type=int, help="pin each run with taskset")
    parser.add_argument(
        "--mojo",
        default=os.environ.get("MOJO", "mojo"),
        help="Mojo command; shell-style arguments are allowed (default: mojo)",
    )
    parser.add_argument("--cc", default=os.environ.get("CC", "gcc"))
    parser.add_argument("--march", default="native")
    parser.add_argument("--output", type=Path, help="save raw samples and environment as JSON")
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    if args.cpu is not None and shutil.which("taskset") is None:
        parser.error("--cpu requires taskset")
    if args.output and args.output.exists():
        parser.error("output already exists; preserve previous measurements")

    root = Path(__file__).resolve().parent.parent
    source = root / "bench" / "radix_sort_bench.mojo"
    reference = root / "bench" / "radix_sort_reference.c"
    mojo = shlex.split(args.mojo)
    if not mojo:
        parser.error("--mojo must not be empty")
    samples: dict[tuple[str, int], list[int]] = {}

    with tempfile.TemporaryDirectory(prefix="gooslapper-mojo-radix-bench-") as tmp:
        tmp_path = Path(tmp)
        reference_object = tmp_path / "radix-sort-reference.o"
        executable = tmp_path / "radix-sort-bench"
        subprocess.run(
            [
                args.cc,
                "-O3",
                f"-march={args.march}",
                "-c",
                str(reference),
                "-o",
                str(reference_object),
            ],
            cwd=root,
            check=True,
        )
        subprocess.run(
            [
                *mojo,
                "build",
                "-O3",
                "-I",
                str(root / "src"),
                "--march",
                args.march,
                str(source),
                "-Xlinker",
                str(reference_object),
                "-o",
                str(executable),
            ],
            cwd=root,
            check=True,
        )

        command = [str(executable)]
        if args.cpu is not None:
            command = ["taskset", "-c", str(args.cpu), *command]
        for _ in range(args.rounds):
            result = subprocess.run(
                command, cwd=root, check=True, text=True, capture_output=True
            )
            for implementation, count, elapsed in csv.reader(result.stdout.splitlines()):
                samples.setdefault((implementation, int(count)), []).append(int(elapsed))

    print("| Items | C median | Mojo median | Mojo/C | C ns/item | Mojo ns/item | Samples each |")
    print("|---:|---:|---:|---:|---:|---:|---:|")
    counts = sorted(count for implementation, count in samples if implementation == "c")
    for count in counts:
        c = samples["c", count]
        mojo_samples = samples["mojo", count]
        c_median = statistics.median(c)
        mojo_median = statistics.median(mojo_samples)
        print(
            f"| {count:,} | {c_median / 1e6:.3f} ms | {mojo_median / 1e6:.3f} ms | "
            f"{mojo_median / c_median:.3f}x | {c_median / count:.2f} | "
            f"{mojo_median / count:.2f} | {len(c)} |"
        )

    if args.output:
        report = {
            "platform": platform.platform(), "cpu": args.cpu,
            "mojo": subprocess.check_output([*mojo, "--version"], text=True).strip(),
            "cc": subprocess.check_output([args.cc, "--version"], text=True).strip(),
            "optimization": "-O3", "march": args.march, "rounds": args.rounds,
            "sources": {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in (source, reference, root / "src/mojo_bio/radix_sort.mojo")},
            "samples_ns": {f"{implementation}/{count}": values
                           for (implementation, count), values in samples.items()},
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
