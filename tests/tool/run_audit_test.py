"""验证审计入口覆盖应用包、使用本地依赖并传播失败，不运行实际编译器。"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
PACKAGES = ("packages/reader_core", "packages/reader_ui",
            "packages/epub_toolkit", "apps/reader_mobile")
COMMAND = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with Path(os.environ['SPECTACULAR_AUDIT_LOG']).open('a') as log:
    log.write(json.dumps([Path.cwd().name, *sys.argv[1:]]) + '\\n')
if os.environ.get('SPECTACULAR_AUDIT_FAIL') and 'test' in sys.argv:
    sys.exit(23)
'''


class AuditCommandTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="spectacular-audit-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "tool").mkdir()
        shutil.copyfile(ROOT / "tool/run_audit.sh", self.root / "tool/run_audit.sh")
        for package in PACKAGES:
            test = "test" if package.endswith("epub_toolkit") else "test/audit"
            directory = self.root / package / test
            directory.mkdir(parents=True)
            (directory / "probe_test.dart").write_text("// 审计回归夹具\n")
        (self.root / "packages/opencc_native").mkdir()
        for guard in ("tool/check_core_boundary.sh", "tests/audit/engineering_guard_audit.sh"):
            file = self.root / guard
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("exit 0\n")
        binary = self.root / "bin"
        binary.mkdir()
        for name in ("flutter", "dart", "git"):
            command = binary / name
            command.write_text(COMMAND)
            command.chmod(0o755)
        self.log = self.root / "commands.jsonl"
        self.env = os.environ | {
            "PATH": f"{binary}:{os.environ['PATH']}",
            "SPECTACULAR_AUDIT_LOG": str(self.log),
        }

    def test_covers_packages_without_implicit_dependency_resolution(self):
        result = subprocess.run(["bash", "tool/run_audit.sh"], cwd=self.root,
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = [json.loads(line) for line in self.log.read_text().splitlines()]
        for index, package in enumerate(PACKAGES):
            analyze, test = commands[index * 2:index * 2 + 2]
            self.assertEqual(analyze, [Path(package).name, "analyze", "--no-pub"])
            self.assertEqual(test[:4], [Path(package).name, "test", "--no-pub", "--reporter"])
            self.assertTrue(test[-1].endswith("probe_test.dart"))
        self.assertEqual(commands[8], ["opencc_native", "analyze"])
        self.assertFalse(any("pub" in command for command in commands))

    def test_failure_stops_following_packages(self):
        result = subprocess.run(["bash", "tool/run_audit.sh"], cwd=self.root,
                                env=self.env | {"SPECTACULAR_AUDIT_FAIL": "1"},
                                capture_output=True)
        self.assertEqual(result.returncode, 23)
        self.assertEqual(len(self.log.read_text().splitlines()), 2)


if __name__ == "__main__":
    unittest.main()
