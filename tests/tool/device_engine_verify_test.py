"""从正式验收入口验证隔离包检查，不运行构建或连接设备。"""

import importlib.util
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "device_engine_verify", ROOT / "tool/device_engine_verify.py"
)
verifier = importlib.util.module_from_spec(SPEC)
sys.path.insert(0, str(ROOT / "tool"))
try:
    SPEC.loader.exec_module(verifier)
finally:
    sys.path.pop(0)


class InstallReached(Exception):
    """在真正安装前停止验收流程。"""


class IsolatedApkTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="spectacular-apk-test-")
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        self.apk = root / "reader.apk"
        self.args = SimpleNamespace(
            device="测试设备", output=root / "output", apk=self.apk, timeout=1
        )
        self.application_id = verifier.TEST_ID
        self.events = []
        self.replace("pick_device", return_value=self.args.device)
        self.replace("ensure_fixtures")
        self.replace("device_info", return_value={"model": "模拟设备", "android": "模拟"})
        self.replace("start_reverse_server", return_value=(Mock(), 60001))
        self.replace("prepare_workspace")
        self.replace("build_apk", return_value=self.apk)
        self.replace("run", side_effect=self.run_command)
        self.install = self.replace("install_apk", side_effect=self.stop_before_install)
        for target in ("subprocess.run", "threading.Thread"):
            self.replace(target)

    def replace(self, name, **kwargs):
        target, _, attribute = name.rpartition(".")
        owner = getattr(verifier, target) if target else verifier
        patcher = patch.object(owner, attribute, **kwargs)
        self.addCleanup(patcher.stop)
        return patcher.start()

    def run_command(self, command, **kwargs):
        self.events.append(command)
        if command[0] == "apkanalyzer":
            return self.application_id + "\n"
        if "path" in command:
            return "/data/app/正式应用/base.apk\n"
        return ""

    def stop_before_install(self, device, apk):
        self.events.append(["安装", str(apk)])
        raise InstallReached()

    def test_rejects_other_packages_before_install(self):
        for reuse in (True, False):
            for package in (verifier.APP_ID, verifier.TEST_ID + ".other"):
                with self.subTest(reuse=reuse, package=package):
                    self.args.apk = self.apk if reuse else None
                    self.application_id = package
                    with self.assertRaisesRegex(RuntimeError, "拒绝安装非隔离包"):
                        verifier.verify(self.args)
                    self.install.assert_not_called()

    def test_isolated_package_is_checked_before_install(self):
        for reuse in (True, False):
            with self.subTest(reuse=reuse):
                self.events.clear()
                self.install.reset_mock()
                self.args.apk = self.apk if reuse else None
                with self.assertRaises(InstallReached):
                    verifier.verify(self.args)
                self.install.assert_called_once_with(self.args.device, self.apk)
                checks = [event for event in self.events if event[0] == "apkanalyzer"]
                self.assertEqual(checks, [[
                    "apkanalyzer", "manifest", "application-id", str(self.apk)
                ]])
                self.assertLess(
                    self.events.index(checks[0]),
                    self.events.index(["安装", str(self.apk)]),
                )


if __name__ == "__main__":
    unittest.main()
