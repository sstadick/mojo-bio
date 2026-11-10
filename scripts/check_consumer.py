#!/usr/bin/env python3
"""Build a local conda artifact and exercise it in a fresh consumer, without -I."""

import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import tomllib


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    channels = json.dumps(tomllib.loads((root / "pixi.toml").read_text())["workspace"]["channels"])
    pixi = shutil.which("pixi")
    if pixi is None:
        raise SystemExit("pixi must be on PATH")
    with tempfile.TemporaryDirectory(prefix="mojo-bio-consumer-") as temporary:
        work = Path(temporary)
        output = work / "packages"
        subprocess.run([pixi, "publish", "--path", ".", "--target-dir", str(output)], cwd=root, check=True)
        package, = output.glob("*.conda")
        digest = hashlib.sha256(package.read_bytes()).hexdigest()
        consumer = work / "consumer"
        consumer.mkdir()
        target = {("Linux", "x86_64"): "linux-64", ("Linux", "aarch64"): "linux-aarch64",
                  ("Darwin", "arm64"): "osx-arm64"}[(platform.system(), platform.machine())]
        (consumer / "pixi.toml").write_text(
            '[workspace]\nname = "bio-consumer"\n'
            f'channels = {channels}\n'
            f'platforms = ["{target}"]\n'
            '[dependencies]\nmojo-bio = { url = '
            + json.dumps(package.as_uri()) + f', sha256 = "{digest}" }}\n'
        )
        shutil.copyfile(root / "test/test_radix_sort.mojo", consumer / "test.mojo")
        shutil.copyfile(root / "examples/sort.mojo", consumer / "example.mojo")
        env = os.environ.copy()
        env.pop("MOJO_PATH", None)
        env.pop("MOJO_INCLUDE_PATH", None)
        env.pop("PIXI_WORKSPACE_MANIFEST", None)
        env.pop("PIXI_PROJECT_MANIFEST", None)
        env.pop("MODULAR_MOJO_IMPORT_PATH", None)
        for source in ("test.mojo", "example.mojo"):
            subprocess.run(
                [pixi, "run", "--manifest-path", str(consumer / "pixi.toml"),
                 "mojo", "run", "-D", "ASSERT=all", source], cwd=consumer, env=env, check=True
            )
        installed = consumer / ".pixi/envs/default/lib/mojo/mojo_bio.mojoc"
        assert installed.is_file(), "Consumer must use the installed compiled module"
        print("PASS: clean consumer ran all tests and example from the installed conda artifact, without -I")


if __name__ == "__main__":
    main()
