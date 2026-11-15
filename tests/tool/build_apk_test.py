"""验证正式打包入口的缓存策略与阶段顺序，不调用真实编译器。"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
COMMAND = '''#!/usr/bin/env python3
import json, os, shutil, sys
from pathlib import Path
name = Path(sys.argv[0]).name
root = Path(os.environ['SPECTACULAR_TEST_ROOT'])
with Path(os.environ['SPECTACULAR_TEST_COMMAND_LOG']).open('a') as log:
    log.write(json.dumps([name, *sys.argv[1:]]) + '\\n')
if name == 'gradlew':
    apk = root / 'apps/reader_mobile/build/app/outputs/flutter-apk/app-release.apk'
    apk.parent.mkdir(parents=True, exist_ok=True)
    apk.write_bytes(b'APK test fixture')
if name == 'cp' and Path(sys.argv[-1]).resolve().is_relative_to(root):
    shutil.copyfile(sys.argv[1], sys.argv[-1])
'''


class ApkBuildTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="spectacular-build-test-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        app = self.root / "apps/reader_mobile"
        (app / ".dart_tool").mkdir(parents=True)
        (app / ".dart_tool/package_config.json").write_text("{}")
        (app / "android").mkdir()
        tool = self.root / "tool"
        tool.mkdir()
        shutil.copyfile(ROOT / "tool/build_apk.sh", tool / "build_apk.sh")
        shutil.copyfile(ROOT / "tool/generate_release_plugins.dart",
                        tool / "generate_release_plugins.dart")
        binary = self.root / "sdk/bin"
        binary.mkdir(parents=True)
        for name in ("flutter", "dart", "cp"):
            self.command(binary / name)
        self.command(app / "android/gradlew")
        self.log = self.root / "commands.jsonl"
        self.env = os.environ | {
            "PATH": f"{binary}:{os.environ['PATH']}",
            "SPECTACULAR_TEST_ROOT": str(self.root),
            "SPECTACULAR_TEST_COMMAND_LOG": str(self.log),
        }

    def command(self, path):
        path.write_text(COMMAND)
        path.chmod(0o755)

    def build(self, *args):
        result = subprocess.run(["bash", "tool/build_apk.sh", *args],
                                cwd=self.root, env=self.env, capture_output=True,
                                text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_cached_build_uses_arm64_configuration_plugins_then_offline_gradle(self):
        commands = self.build()
        self.assertEqual([command[0] for command in commands[:3]],
                         ["flutter", "dart", "gradlew"])
        self.assertIn("--no-pub", commands[0])
        self.assertIn("--config-only", commands[0])
        self.assertIn("--target-platform=android-arm64", commands[0])
        self.assertIn("--offline", commands[2])
        self.assertIn("-Ptarget-platform=android-arm64", commands[2])
        self.assertTrue((self.root / "apps/reader_mobile/dist/"
                         "spectacular-reader-release.apk").is_file())

    def test_missing_dart_configuration_first_uses_local_cache(self):
        (self.root / "apps/reader_mobile/.dart_tool/package_config.json").unlink()
        commands = self.build()
        self.assertEqual(commands[0], ["flutter", "pub", "get", "--offline"])

    def test_downloads_require_explicit_option_and_invalid_options_do_not_build(self):
        commands = self.build("--allow-downloads")
        self.assertEqual(commands[0], ["flutter", "pub", "get"])
        gradle = next(command for command in commands if command[0] == "gradlew")
        self.assertNotIn("--offline", gradle)
        self.log.unlink()
        result = subprocess.run(["bash", "tool/build_apk.sh", "--unknown"],
                                cwd=self.root, env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
