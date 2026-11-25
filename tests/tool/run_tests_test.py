"""验证职责分类、真实 Git 改动选择与执行失败传播，不运行业务全量。"""

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("run_tests", ROOT / "tool/run_tests.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def write(root, name, content="// 测试夹具\n"):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


def minimal_catalog(root):
    catalog = {
        "groups": {"ui": "界面", "css": "CSS 引擎"},
        "test_rules": [
            {"group": "ui", "paths": ["packages/reader_ui/test/*_test.dart"]},
            {"group": "css", "paths": ["packages/reader_core/test/css/*_test.dart"]},
        ],
        "source_rules": [],
    }
    write(root, "tool/test_groups.json", json.dumps(catalog, ensure_ascii=False))
    write(root, "packages/reader_ui/test/menu_test.dart")
    write(root, "packages/reader_core/test/css/cascade_test.dart")
    return catalog


class SelectionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog, cls.tests = runner.load_catalog(ROOT)

    def select(self, paths):
        with redirect_stdout(io.StringIO()):
            return runner.select_changed(paths, self.catalog, self.tests)

    def selected_groups(self, paths):
        return {runner.test_group(path, self.catalog) for path in self.select(paths)}

    def test_ui_change_selects_ui_without_engine_or_storage(self):
        paths = ["apps/reader_mobile/lib/home/bookshelf_page.dart"]
        selected = self.select(paths)
        self.assertEqual(self.selected_groups(paths), {"ui"})
        self.assertIn("apps/reader_mobile/test/home/bookshelf_view_test.dart", selected)
        self.assertNotIn("apps/reader_mobile/test/reader/css_gaps_test.dart", selected)
        self.assertNotIn("apps/reader_mobile/test/storage/db_test.dart", selected)

    def test_css_change_includes_chapter_regressions_without_ui(self):
        paths = ["packages/reader_core/lib/css/cascade.dart"]
        selected = self.select(paths)
        self.assertEqual(self.selected_groups(paths), {"css"})
        self.assertIn("packages/reader_core/test/css/cascade_test.dart", selected)
        self.assertIn("apps/reader_mobile/test/reader/css_gaps_test.dart", selected)
        self.assertNotIn("packages/reader_ui/test/settings_panel_test.dart", selected)

    def test_chapter_styles_use_core_scope(self):
        paths = ["packages/reader_core/lib/epub/chapter/chapter_styles.dart"]
        self.assertEqual(self.selected_groups(paths), {"css"})

    def test_layout_and_paint_changes_select_their_consumers(self):
        layout = ["packages/reader_core/lib/layout/paginator.dart"]
        paint = ["packages/reader_core/lib/paint/page_renderer.dart"]
        self.assertEqual(self.selected_groups(layout), {"layout"})
        self.assertEqual(self.selected_groups(paint), {"paint"})
        self.assertIn("apps/reader_mobile/test/reader/float_flat_test.dart", self.select(layout))
        self.assertIn("apps/reader_mobile/test/reader/zhushen_job_decoration_test.dart", self.select(paint))

    def test_storage_and_font_loading_have_distinct_scopes(self):
        storage = ["apps/reader_mobile/lib/storage/db.dart"]
        fonts = ["packages/reader_core/lib/css/book_font_loader.dart"]
        self.assertEqual(self.selected_groups(storage), {"storage"})
        self.assertEqual(self.selected_groups(fonts), {"css", "resources"})

    def test_modified_test_runs_only_that_file(self):
        path = "apps/reader_mobile/test/home/stats_page_test.dart"
        self.assertEqual(self.select([path, path]), [path])

    def test_recent_tests_are_selected_by_their_behavior(self):
        cases = {
            "apps/reader_mobile/test/editing/epub_file_editor_page_test.dart": "ui",
            "apps/reader_mobile/test/library/book_list_store_test.dart": "storage",
            "apps/reader_mobile/test/page_turn_perf_app_test.dart": "perf",
            "apps/reader_mobile/test/reader/scroll_mode_switch_test.dart": "position",
        }
        for path, group in cases.items():
            with self.subTest(path=path):
                self.assertEqual(runner.test_group(path, self.catalog), group)
                self.assertEqual(self.select([path]), [path])

    def test_epub_toolkit_changes_select_local_tool_regressions(self):
        path = "packages/epub_toolkit/lib/src/features/img_to_webp/img_to_webp.dart"
        selected = self.select([path])
        self.assertEqual(self.selected_groups([path]), {"resources"})
        self.assertIn("packages/epub_toolkit/test/media_tools_test.dart", selected)
        self.assertIn("packages/epub_toolkit/test/structure_tools_test.dart", selected)

    def test_deleted_test_selects_remaining_tests_in_its_group(self):
        path = "apps/reader_mobile/test/home/removed_test.dart"
        self.assertEqual(self.selected_groups([path]), {"ui"})
        self.assertNotIn(path, self.select([path]))

    def test_mixed_changes_combine_groups_without_duplicate_files(self):
        paths = ["packages/reader_core/lib/css/cascade.dart",
                 "apps/reader_mobile/lib/home/bookshelf_page.dart",
                 "apps/reader_mobile/test/reader/css_gaps_test.dart"]
        selected = self.select(paths)
        self.assertEqual(self.selected_groups(paths), {"ui", "css"})
        self.assertEqual(selected.count("apps/reader_mobile/test/reader/css_gaps_test.dart"), 1)

    def test_unknown_source_and_dependency_config_require_explicit_scope(self):
        for path in ("packages/reader_core/lib/new_module/example.dart",
                     "apps/reader_mobile/pubspec.yaml", "analysis_options.yaml",
                     "apps/reader_mobile/integration_test/m0_test.dart"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "无法自动确定"):
                self.select([path])

    def test_documents_and_existing_book_do_not_trigger_tests(self):
        self.assertEqual(self.select(["README.md", "docs/开发约定.md", "格列佛游记.epub"]), [])


class CatalogTest(unittest.TestCase):
    def test_new_unclassified_test_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            minimal_catalog(root)
            write(root, "apps/reader_mobile/test/reader/new_behavior_test.dart")
            with self.assertRaisesRegex(ValueError, "未分类.*new_behavior_test"):
                runner.load_catalog(root)

    def test_removed_or_renamed_exact_rule_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog = minimal_catalog(root)
            catalog["test_rules"][0]["paths"] = ["packages/reader_ui/test/old_menu_test.dart"]
            write(root, "tool/test_groups.json", json.dumps(catalog))
            with self.assertRaisesRegex(ValueError, "失效规则.*old_menu_test"):
                runner.load_catalog(root)

    def test_unknown_group_in_source_rule_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog = minimal_catalog(root)
            catalog["source_rules"] = [{"groups": ["missing"], "paths": ["src/*"]}]
            write(root, "tool/test_groups.json", json.dumps(catalog))
            with self.assertRaisesRegex(ValueError, "源码规则引用了未知分类"):
                runner.load_catalog(root)

    def test_unclassified_epub_toolkit_test_is_not_silently_omitted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            minimal_catalog(root)
            write(root, "packages/epub_toolkit/test/new_tool_test.dart")
            with self.assertRaisesRegex(ValueError, "未分类.*new_tool_test"):
                runner.load_catalog(root)


class GitChangesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git("init", "-q")
        for name in ("暂存.dart", "工作区.dart", "旧 名称.dart"):
            write(self.root, name, "原始\n")
        self.git("add", "暂存.dart", "工作区.dart", "旧 名称.dart")
        self.commit("test：准备改动选择夹具")

    def git(self, *args):
        result = subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def commit(self, message):
        self.git("-c", "user.name=分类测试", "-c", "user.email=tests@example.invalid",
                 "commit", "-qm", message)

    def test_collects_staged_worktree_untracked_and_both_rename_paths(self):
        write(self.root, "暂存.dart", "暂存版本\n")
        self.git("add", "暂存.dart")
        write(self.root, "暂存.dart", "原始\n")
        write(self.root, "工作区.dart", "修改\n")
        self.git("mv", "旧 名称.dart", "新 名称.dart")
        write(self.root, "未跟踪\n文件.dart")
        self.assertEqual(set(runner.changed_paths(self.root)), {
            "暂存.dart", "工作区.dart", "旧 名称.dart", "新 名称.dart", "未跟踪\n文件.dart",
        })

    def test_base_includes_committed_changes_and_current_worktree(self):
        base = self.git("rev-parse", "HEAD")
        write(self.root, "已提交.dart")
        self.git("add", "已提交.dart")
        self.commit("test：准备已提交改动")
        write(self.root, "工作区.dart", "修改\n")
        self.assertEqual(set(runner.changed_paths(self.root, base)), {"已提交.dart", "工作区.dart"})
        self.assertEqual(set(runner.changed_paths(self.root)), {"工作区.dart"})

    def test_invalid_base_is_reported(self):
        with self.assertRaisesRegex(ValueError, "无法读取 Git 改动"):
            runner.changed_paths(self.root, "missing-base")

    def test_local_python_cache_is_excluded_from_changed_paths(self):
        write(self.root, ".gitignore", (ROOT / ".gitignore").read_text(encoding="utf-8"))
        cache = "tool/__pycache__/run_tests.cpython-313.pyc"
        write(self.root, cache)
        write(self.root, "tool/changed.py")
        paths = runner.changed_paths(self.root)
        self.assertNotIn(cache, paths)
        self.assertIn("tool/changed.py", paths)


class ExecutionTest(unittest.TestCase):
    def test_commands_use_only_selected_packages_and_never_fetch_dependencies(self):
        files = ["packages/reader_ui/test/settings_panel_test.dart",
                 "apps/reader_mobile/test/home/stats_page_test.dart"]
        commands = runner.build_commands(files, analyze=True)
        self.assertEqual([package for package, _ in commands], [
            "packages/reader_ui", "packages/reader_ui", "apps/reader_mobile", "apps/reader_mobile",
        ])
        for _, command in commands:
            self.assertIn("--no-pub", command)
            self.assertNotIn("get", command)
        tests = [command for _, command in commands if command[1] == "test"]
        self.assertEqual([command[-1] for command in tests], [
            "test/settings_panel_test.dart", "test/home/stats_page_test.dart",
        ])

    def test_tooling_executes_without_flutter_and_stops_on_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "failed_test.py", "import sys\nsys.exit(7)\n")
            write(root, "later_test.py", "from pathlib import Path\nPath('unexpected').touch()\n")
            commands = [(".", [sys.executable, "failed_test.py"]),
                        (".", [sys.executable, "later_test.py"])]
            with patch.object(runner.shutil, "which") as which, redirect_stdout(io.StringIO()):
                self.assertEqual(runner.execute_commands(commands, root), 7)
            which.assert_not_called()
            self.assertFalse((root / "unexpected").exists())

    def test_missing_cache_fails_before_any_command(self):
        with tempfile.TemporaryDirectory() as directory:
            commands = runner.build_commands(["packages/reader_ui/test/settings_panel_test.dart"])
            with patch.object(runner.shutil, "which", return_value="/local/flutter"), \
                    patch.object(runner.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "flutter pub get --offline"):
                    runner.execute_commands(commands, Path(directory))
                run.assert_not_called()

    def test_dry_run_does_not_launch_tools(self):
        with patch.object(runner, "execute_commands") as execute, \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(runner.main(["css", "--dry-run"]), 0)
        execute.assert_not_called()
        self.assertIn("选择分类：css", output.getvalue())
        self.assertNotIn("执行目录：packages/reader_ui", output.getvalue())

    def test_all_dry_run_includes_epub_toolkit_without_device_tests(self):
        with patch.object(runner, "execute_commands") as execute, \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(runner.main(["--all", "--dry-run"]), 0)
        execute.assert_not_called()
        preview = output.getvalue()
        self.assertIn("执行目录：packages/epub_toolkit", preview)
        self.assertIn("test/media_tools_test.dart", preview)
        self.assertIn("test/local_dispatch_test.dart", preview)
        self.assertNotIn("integration_test/", preview)
        self.assertNotIn("third_party/", preview)

    def test_unknown_category_fails_without_execution(self):
        with patch.object(runner, "execute_commands") as execute, redirect_stderr(io.StringIO()):
            self.assertEqual(runner.main(["unknown"]), 2)
        execute.assert_not_called()

    def test_path_cannot_escape_repository(self):
        with self.assertRaisesRegex(ValueError, "路径不能越出"):
            runner.normalize_path("../outside.dart", ROOT)
        path = ROOT / "packages/reader_core/lib/css/cascade.dart"
        self.assertEqual(runner.normalize_path(str(path), ROOT), "packages/reader_core/lib/css/cascade.dart")

    def test_conflicting_cli_scopes_are_rejected(self):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            runner.parse_args(["ui", "--all"])
        self.assertEqual(error.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
