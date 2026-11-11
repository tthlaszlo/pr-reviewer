"""Exercise the macOS Bash 3.2 entry point without invoking Xcode."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BuildScriptTests(unittest.TestCase):
    def arguments(self, client_id):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            fake = temporary / "xcodebuild"
            fake.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$AI_BUDDY_TEST_ARGS"\n')
            fake.chmod(0o755)
            output = temporary / "arguments"
            env = dict(os.environ, PATH=f"{temporary}:{os.environ['PATH']}",
                       AI_BUDDY_TEST_ARGS=str(output))
            env.pop("GITHUB_CLIENT_ID", None)
            if client_id is not None:
                env["GITHUB_CLIENT_ID"] = client_id
            subprocess.run(["/bin/bash", str(ROOT / "scripts/build-app.sh")],
                           env=env, check=True, capture_output=True)
            return output.read_text().splitlines()

    def test_build_without_optional_client_id(self):
        arguments = self.arguments(None)
        self.assertIn("ARCHS=arm64", arguments)
        self.assertEqual(arguments[-1], "build")
        self.assertFalse(any(value.startswith("GITHUB_CLIENT_ID=") for value in arguments))

    def test_client_id_is_passed_as_one_build_setting(self):
        arguments = self.arguments("public-test-id")
        self.assertEqual(arguments.count("GITHUB_CLIENT_ID=public-test-id"), 1)


if __name__ == "__main__":
    unittest.main()
