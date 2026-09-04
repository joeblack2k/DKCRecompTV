#!/usr/bin/env python3
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "tvos" / "preflight.sh"
DEVELOPER_DIR = "/Applications/Xcode-27-beta-5.app/Contents/Developer"
V10_SHA256 = "35421a9af9dd011b40b91f792192af9f99c93201d8d394026bdfb42cbf2d8633"
REV1_SHA256 = "b79c2bb86f6fc76e1fc61c62fc16d51c664c381e58bc2933be643bbc4d8b610c"
FORBIDDEN_TRACKED = re.compile(
    r"(^|/)(private|generated|src/gen|build(?:-[^/]*)?|DerivedData|versions)"
    r"(/|$)|\.(?:rom|sfc|smc|swc|sav|srm|app|ipa|xcarchive|xcresult|dSYM)$",
    re.IGNORECASE,
)


class TvOSPreflightTests(unittest.TestCase):
    def test_preflight_and_source_boundary(self):
        self.assertTrue(SCRIPT.stat().st_mode & stat.S_IXUSR)

        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            bin_dir = temporary_root / "bin"
            sdk_dir = temporary_root / "sdk"
            bin_dir.mkdir()
            sdk_dir.mkdir()
            v10 = temporary_root / "v10.sfc"
            rev1 = temporary_root / "rev1.sfc"
            v10.write_bytes(b"synthetic v1.0 placeholder")
            rev1.write_bytes(b"synthetic Rev 1 placeholder")

            stubs = {
                "xcodebuild": (
                    "#!/bin/sh\n"
                    "printf '%s\\n' 'Xcode 27.0' 'Build version 27A5237l'\n"
                ),
                "xcrun": (
                    "#!/bin/sh\n"
                    "case \"$*\" in\n"
                    "  *--show-sdk-version*) printf '27.0\\n' ;;\n"
                    "  *--show-sdk-path*) printf '%s\\n' \"$TVOS_TEST_SDK_PATH\" ;;\n"
                    "  *) exit 1 ;;\n"
                    "esac\n"
                ),
                "stat": "#!/bin/sh\nprintf '4194304\\n'\n",
                "realpath": "#!/bin/sh\nprintf '%s\\n' \"$1\"\n",
                "shasum": (
                    "#!/bin/sh\n"
                    "case \"$4\" in\n"
                    f"  *v10.sfc) printf '%s  %s\\n' '{V10_SHA256}' \"$4\" ;;\n"
                    f"  *rev1.sfc) printf '%s  %s\\n' '{REV1_SHA256}' \"$4\" ;;\n"
                    "  *) exit 1 ;;\n"
                    "esac\n"
                ),
            }
            for name, content in stubs.items():
                stub = bin_dir / name
                stub.write_text(content, encoding="utf-8")
                stub.chmod(0o755)

            def run(*arguments, rom_env=None):
                environment = os.environ.copy()
                environment["DEVELOPER_DIR"] = DEVELOPER_DIR
                environment["PATH"] = (
                    str(bin_dir) + os.pathsep + environment["PATH"]
                )
                environment["TVOS_TEST_SDK_PATH"] = str(sdk_dir)
                environment.pop("DKC2_ROM", None)
                if rom_env is not None:
                    environment["DKC2_ROM"] = str(rom_env)
                return subprocess.run(
                    [str(SCRIPT), *arguments],
                    cwd=ROOT,
                    env=environment,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                )

            toolchain = run("--toolchain-only")
            self.assertEqual(toolchain.returncode, 0, toolchain.stdout)
            self.assertIn("Xcode 27.0", toolchain.stdout)
            self.assertIn("ROM check skipped", toolchain.stdout)

            missing = run()
            self.assertEqual(missing.returncode, 64, missing.stdout)
            self.assertIn("ROM path required", missing.stdout)

            inside = run(str(SCRIPT))
            self.assertNotEqual(inside.returncode, 0)
            self.assertIn("ROM must remain outside the repository", inside.stdout)

            accepted_v10 = run(str(v10))
            self.assertEqual(accepted_v10.returncode, 0, accepted_v10.stdout)
            self.assertIn("DKC2 USA v1.0", accepted_v10.stdout)
            self.assertIn(V10_SHA256, accepted_v10.stdout)

            accepted_rev1 = run(rom_env=rev1)
            self.assertEqual(accepted_rev1.returncode, 0, accepted_rev1.stdout)
            self.assertIn("DKC2 USA Rev 1/v1.1", accepted_rev1.stdout)
            self.assertIn(REV1_SHA256, accepted_rev1.stdout)

        tracked = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=ROOT,
            check=True,
            stdout=subprocess.PIPE,
        ).stdout.decode().split("\0")
        self.assertEqual(
            [path for path in tracked if path and FORBIDDEN_TRACKED.search(path)],
            [],
        )
        for candidate in (
            "private/game.sfc",
            "generated/game.c",
            "src/gen/game.c",
            "tvos/build/Game.app/Info.plist",
            "Game.ipa",
            "Game.xcarchive/Info.plist",
            "profile.mobileprovision",
        ):
            self.assertEqual(
                subprocess.run(
                    ["git", "check-ignore", "--no-index", "-q", "--", candidate],
                    cwd=ROOT,
                ).returncode,
                0,
                candidate,
            )


if __name__ == "__main__":
    unittest.main()
