#!/usr/bin/env python3
"""按行为职责或 Git 改动运行测试，默认复用本地 Flutter 依赖。"""

import argparse
from fnmatch import fnmatchcase
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ("packages/reader_core", "packages/reader_ui", "apps/reader_mobile")


def matches(path, patterns):
    return any(fnmatchcase(path, pattern) for pattern in patterns)


def test_group(path, catalog):
    for rule in catalog["test_rules"]:
        if matches(path, rule["paths"]):
            return rule["group"]
    return None


def source_groups(path, catalog):
    for rule in catalog["source_rules"]:
        if matches(path, rule["paths"]):
            return set(rule["groups"])
    return set()


def discover_tests(root):
    paths = [path for package in PACKAGES
             for path in (root / package / "test").rglob("*_test.dart")]
    paths.extend((root / "tests/tool").glob("*_test.py"))
    return sorted(path.relative_to(root).as_posix() for path in paths if path.is_file())


def load_catalog(root):
    catalog = json.loads((root / "tool/test_groups.json").read_text(encoding="utf-8"))
    groups = set(catalog["groups"])
    for rule in catalog["test_rules"]:
        if rule["group"] not in groups:
            raise ValueError(f"测试规则引用了未知分类：{rule['group']}")
    for rule in catalog["source_rules"]:
        if not set(rule["groups"]) <= groups:
            raise ValueError(f"源码规则引用了未知分类：{rule['groups']}")
    tests = discover_tests(root)
    missing = [path for path in tests if test_group(path, catalog) is None]
    stale = [pattern for rule in catalog["test_rules"] for pattern in rule["paths"]
             if not any(fnmatchcase(path, pattern) for path in tests)]
    if missing or stale:
        details = [*(f"未分类：{path}" for path in missing),
                   *(f"失效规则：{pattern}" for pattern in stale)]
        raise ValueError("测试索引需要同步更新：\n" + "\n".join(details))
    return catalog, tests


def git_paths(root, arguments):
    result = subprocess.run(["git", *arguments], cwd=root, capture_output=True)
    if result.returncode:
        raise ValueError("无法读取 Git 改动：" + result.stderr.decode(errors="replace").strip())
    return result.stdout.decode("utf-8", errors="surrogateescape").split("\0")


def changed_paths(root, base=None):
    commands = [["diff", "--name-only", "--no-renames", "-z", "--"],
                ["diff", "--cached", "--name-only", "--no-renames", "-z", "--"],
                ["ls-files", "--others", "--exclude-standard", "-z"]]
    if base:
        resolved = git_paths(root, ["rev-parse", "--verify", "--end-of-options", f"{base}^{{commit}}"])[0].strip()
        commands.append(["diff", "--name-only", "--no-renames", "-z", f"{resolved}...HEAD", "--"])
    return sorted({path for command in commands for path in git_paths(root, command) if path})


def normalize_path(path, root):
    candidate = Path(path)
    if candidate.is_absolute():
        try:
            candidate = candidate.relative_to(root)
        except ValueError as error:
            raise ValueError(f"路径不在当前仓库内：{path}") from error
    if ".." in candidate.parts:
        raise ValueError(f"路径不能越出仓库：{path}")
    return candidate.as_posix()


def outside_scope(path):
    if path.endswith(".md"):
        return True
    if path in ("analysis_options.yaml", "pubspec.yaml", "pubspec.lock"):
        return False
    return not path.startswith(("packages/", "apps/", "tool/", "tests/", "test_fonts/"))


def select_changed(paths, catalog, tests):
    groups, direct, unknown = set(), set(), []
    available = set(tests)
    for path in paths:
        if path in available:
            direct.add(path)
        elif test_group(path, catalog):
            groups.add(test_group(path, catalog))
        elif outside_scope(path):
            print(f"跳过文档或范围外文件：{path}")
        elif selected := source_groups(path, catalog):
            groups.update(selected)
        else:
            unknown.append(path)
    if unknown:
        raise ValueError("无法自动确定测试范围：\n" + "\n".join(unknown)
                         + "\n请补充 source_rules，或显式指定分类；真机入口需单独运行。")
    selected = direct | {path for path in tests if test_group(path, catalog) in groups}
    return sorted(selected)


def build_commands(tests, analyze=False):
    commands = []
    for package in PACKAGES:
        files = [path[len(package) + 1:] for path in tests if path.startswith(package + "/")]
        if not files:
            continue
        if analyze:
            commands.append((package, ["flutter", "analyze", "--no-pub"]))
        commands.append((package, ["flutter", "test", "--no-pub", "--reporter", "expanded", *files]))
    commands.extend((".", [sys.executable, path]) for path in tests if path.endswith(".py"))
    return commands


def execute_commands(commands, root):
    flutter = shutil.which("flutter") if any(args[0] == "flutter" for _, args in commands) else None
    for package, args in commands:
        if args[0] != "flutter":
            continue
        if not flutter:
            raise ValueError("找不到 Flutter，请把本地 SDK 的 bin 目录加入 PATH。")
        if not (root / package / ".dart_tool/package_config.json").is_file():
            raise ValueError(f"{package} 缺少本地依赖配置，请先在该包运行 flutter pub get --offline。")
    for package, args in commands:
        print(f"执行目录：{package}\n{shlex.join(args)}", flush=True)
        command = [flutter, *args[1:]] if args[0] == "flutter" else args
        result = subprocess.run(command, cwd=root / package)
        if result.returncode:
            return result.returncode
    return 0


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("groups", nargs="*", help="分类名称，可指定多个；不指定时按 Git 改动选择")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--changed", action="store_true", help="读取暂存、未暂存和未跟踪文件")
    mode.add_argument("--all", action="store_true", help="显式运行全部本地测试，不含真机入口")
    mode.add_argument("--paths", nargs="+", help="按给定仓库相对路径选择，支持已删除的路径")
    mode.add_argument("--list", action="store_true", help="列出分类和测试文件数量")
    mode.add_argument("--check", action="store_true", help="校验未分类测试和失效规则")
    parser.add_argument("--base", help="同时包含从指定 Git 基线分叉后的已提交改动")
    parser.add_argument("--dry-run", action="store_true", help="只打印选中范围与执行命令")
    parser.add_argument("--analyze", action="store_true", help="测试前静态分析选中的 Flutter 包")
    args = parser.parse_args(argv)
    explicit_mode = args.changed or args.all or args.paths is not None or args.list or args.check
    if args.groups and (explicit_mode or args.base):
        parser.error("分类名称不能与其他选择方式同时使用")
    if args.base and (args.all or args.paths is not None or args.list or args.check):
        parser.error("--base 仅适用于按 Git 改动选择")
    return args


def select_tests(args, root, catalog, tests):
    if args.all:
        return tests
    if args.groups:
        unknown = set(args.groups) - set(catalog["groups"])
        if unknown:
            raise ValueError("未知测试分类：" + ", ".join(sorted(unknown)) + "；请用 --list 查看")
        return [path for path in tests if test_group(path, catalog) in args.groups]
    paths = args.paths if args.paths is not None else changed_paths(root, args.base)
    paths = [normalize_path(path, root) for path in paths]
    for path in paths:
        print(f"改动路径：{path}")
    return select_changed(paths, catalog, tests)


def main(argv=None):
    args = parse_args(argv)
    try:
        catalog, tests = load_catalog(ROOT)
        if args.list:
            for group, description in catalog["groups"].items():
                count = sum(test_group(path, catalog) == group for path in tests)
                print(f"{group:12} {count:3} 个文件  {description}")
            return 0
        if args.check:
            print(f"分类校验通过：{len(tests)} 个测试文件，{len(catalog['groups'])} 个分类")
            return 0
        selected = select_tests(args, ROOT, catalog, tests)
        if not selected:
            print("没有需要运行的测试。")
            return 0
        groups = sorted({test_group(path, catalog) for path in selected})
        print(f"选择分类：{', '.join(groups)}；共 {len(selected)} 个测试文件", flush=True)
        commands = build_commands(selected, args.analyze)
        if args.dry_run:
            for package, command in commands:
                print(f"执行目录：{package}\n{shlex.join(command)}")
            return 0
        code = execute_commands(commands, ROOT)
        if not code:
            print(f"通过：已完成 {len(selected)} 个测试文件的执行。")
        return code
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"失败：{error}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
