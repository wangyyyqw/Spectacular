"""性能报告来源可追溯，基线工作区不混入新版源码；不调用设备或构建工具。"""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[2]
APP_HARNESS = "apps/reader_mobile/integration_test/reader_perf_app.dart"
PROBE_HARNESS = "apps/reader_mobile/integration_test/reader_perf_probe.dart"
SPEC = importlib.util.spec_from_file_location(
    "device_reader_perf", ROOT / "tool/device_reader_perf.py"
)
perf = importlib.util.module_from_spec(SPEC)
sys.path.insert(0, str(ROOT / "tool"))
try:
    SPEC.loader.exec_module(perf)
finally:
    sys.path.pop(0)


def write(root, name, content):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


def archive_files(files):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w") as archive:
        for name, content in files.items():
            data = content.encode("utf-8")
            member = tarfile.TarInfo(name)
            member.size = len(data)
            archive.addfile(member, io.BytesIO(data))
    return output.getvalue()


class BaselineWorkspaceTest(unittest.TestCase):
    def test_baseline_removes_new_files_but_keeps_current_harness(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)

            def seed(destination):
                write(destination, "apps/reader_mobile/lib/new.dart", "新版")
                write(destination, "packages/new_package/lib/new.dart", "新版")
                for name in perf.HARNESS_PATHS:
                    if name.startswith("apps/"):
                        write(destination, name, f"当前入口：{name}")
                write(destination, "apps/reader_mobile/pubspec.yaml",
                      "dev_dependencies:\n  integration_test:\n    sdk: flutter\n")
                write(destination, "apps/reader_mobile/android/app/src/main/AndroidManifest.xml",
                      '    <application android:label="CSS 真机测试"/>')

            archive = archive_files({
                "apps/reader_mobile/lib/old.dart": "旧版",
                "packages/old_package/lib/old.dart": "旧版",
            })
            with patch.object(perf, "prepare_workspace", side_effect=seed), \
                    patch.object(perf.subprocess, "check_output", return_value=archive) as command:
                perf.prepare(workspace, "baseline-commit")
            command.assert_called_once_with(
                ["git", "archive", "baseline-commit", *perf.SOURCE_ROOTS], cwd=perf.ROOT)
            self.assertFalse((workspace / "apps/reader_mobile/lib/new.dart").exists())
            self.assertFalse((workspace / "packages/new_package").exists())
            self.assertEqual((workspace / "apps/reader_mobile/lib/old.dart").read_text(), "旧版")
            for name in (APP_HARNESS, PROBE_HARNESS):
                self.assertEqual((workspace / name).read_text(), f"当前入口：{name}")

    def test_invalid_archive_is_rejected_before_clearing_workspace(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            original = write(workspace, "apps/reader_mobile/lib/main.dart", "当前源码")
            archive = archive_files({"../escaped.dart": "无效条目"})
            with patch.object(perf, "prepare_workspace"), \
                    patch.object(perf.subprocess, "check_output", return_value=archive):
                with self.assertRaisesRegex(RuntimeError, "不支持的源码归档条目"):
                    perf.prepare(workspace, "baseline-commit")
            self.assertEqual(original.read_text(), "当前源码")


class RevisionMetadataTest(unittest.TestCase):
    def metadata(self, revision, business):
        def command(arguments, **kwargs):
            if arguments[1] == "rev-parse":
                return "head-commit\n" if arguments[-1] == "HEAD^{commit}" else "baseline-commit\n"
            self.assertEqual(arguments[1], "status")
            paths = tuple(arguments[arguments.index("--") + 1:])
            if paths == perf.BUSINESS_PATHS:
                return business
            return " M apps/reader_mobile/integration_test/reader_perf_app.dart\n"

        with patch.object(perf, "run", side_effect=command):
            return perf.revision_metadata(revision)

    def test_harness_change_does_not_mark_business_dirty(self):
        data = self.metadata(None, "")
        self.assertEqual(data["source"]["revision"], "head-commit")
        self.assertFalse(data["source"]["business_dirty"])
        self.assertTrue(data["working_tree"]["dirty"])
        self.assertTrue(data["harness"]["dirty"])
        self.assertTrue(data["harness"]["changes"][0].startswith(" M "))

    def test_current_source_records_business_edits(self):
        data = self.metadata(None, "?? packages/reader_core/lib/new.dart\n")
        self.assertTrue(data["source"]["business_dirty"])
        self.assertTrue(data["working_tree"]["business_dirty"])

    def test_archived_source_stays_clean_when_current_business_is_dirty(self):
        data = self.metadata("baseline", " M apps/reader_mobile/lib/main.dart\n")
        self.assertEqual(data["source"]["revision"], "baseline-commit")
        self.assertEqual(data["source"]["kind"], "git_archive")
        self.assertFalse(data["source"]["business_dirty"])
        self.assertTrue(data["working_tree"]["business_dirty"])
        self.assertEqual(data["harness"]["revision"], "head-commit")


class ProvenanceTest(unittest.TestCase):
    def test_snapshot_changes_only_with_actual_business_files(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            write(workspace, "apps/reader_mobile/lib/main.dart", "正文")
            write(workspace, "packages/reader_core/lib/core.dart", "引擎")
            first = perf.business_snapshot(workspace)
            self.assertEqual(first["file_count"], 2)
            for name in perf.HARNESS_PATHS:
                if name.startswith("apps/"):
                    write(workspace, name, "修改测试入口")
            write(workspace, "packages/reader_core/test/core_test.dart", "测试")
            self.assertEqual(perf.business_snapshot(workspace), first)
            write(workspace, "packages/reader_core/lib/core.dart", "修改引擎")
            self.assertNotEqual(perf.business_snapshot(workspace)["sha256"], first["sha256"])

    def test_report_hashes_book_and_copied_harness_and_serializes_parameters(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / "workspace"
            book = write(root, "book.epub", "abc")
            for name in perf.HARNESS_PATHS:
                write(root, name, "宿主内容")
                if name.startswith("apps/"):
                    write(workspace, name, f"实际复制入口：{name}")
            write(workspace, "apps/reader_mobile/lib/main.dart", "业务")
            args = argparse.Namespace(book=book, output=root / "report", rounds=5, revision="old")
            revisions = {"source": {"revision": "resolved"},
                         "harness": {"revision": "current"}, "working_tree": {"dirty": True}}
            with patch.object(perf, "ROOT", root), patch.object(sys, "argv", ["perf.py", "--rounds", "5"]):
                data = perf.report_provenance(args, workspace, revisions, {"model": "设备"})
            self.assertEqual(data["book"]["sha256"], hashlib.sha256(b"abc").hexdigest())
            self.assertEqual(data["book"]["size_bytes"], 3)
            for name in (APP_HARNESS, PROBE_HARNESS):
                self.assertEqual(data["harness"]["sha256_by_path"][name],
                                 hashlib.sha256(f"实际复制入口：{name}".encode()).hexdigest())
            self.assertEqual(data["command"]["parameters"]["output"], str(root / "report"))
            self.assertEqual(data["command"]["argv"], ["perf.py", "--rounds", "5"])
            self.assertEqual(data["source"]["revision"], "resolved")
            json.dumps(data)

    def test_device_metadata_uses_only_read_commands_and_preserves_failures(self):
        def command(arguments, **kwargs):
            self.assertEqual(arguments[:4], ["adb", "-s", "serial", "shell"])
            self.assertIn(arguments[4], ("getprop", "wm", "settings"))
            if arguments[-1] == "density":
                raise subprocess.TimeoutExpired(arguments, 10)
            if arguments[-1] == "font_scale":
                return subprocess.CompletedProcess(arguments, 1, "", "不可读取")
            return subprocess.CompletedProcess(arguments, 0, "设备值\n", "")

        with patch.object(perf.subprocess, "run", side_effect=command):
            data = perf.device_metadata(["adb", "-s", "serial"])
        self.assertEqual(data["serial"], "serial")
        self.assertEqual(data["model"], "设备值")
        self.assertIn("wm_density", data["errors"])
        self.assertEqual(data["errors"]["font_scale"]["exit_code"], 1)

    def test_partial_and_final_reports_keep_host_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            for endpoint in ("/sample", "/done"):
                handler = object.__new__(perf.ReportHandler)
                handler.path = endpoint
                data = json.dumps({"open_0": {}, "provenance": "设备不能覆盖宿主来源"}).encode()
                handler.headers = {"Content-Length": str(len(data))}
                handler.rfile = io.BytesIO(data)
                handler.output = Path(directory) / "report.json"
                handler.provenance = {"source": {"revision": "resolved"}}
                handler.done = threading.Event()
                handler.send_response = Mock()
                handler.end_headers = Mock()
                with patch("builtins.print"):
                    handler.do_POST()
                saved = json.loads(handler.output.read_text())
                self.assertEqual(saved["provenance"], handler.provenance)
                self.assertEqual(handler.done.is_set(), endpoint == "/done")


if __name__ == "__main__":
    unittest.main()
