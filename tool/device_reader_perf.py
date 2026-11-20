#!/usr/bin/env python3
"""在隔离 release 包中测量真实书架打开、目录跳转及正文图片首帧。"""

import argparse
import base64
from functools import partial
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
import time

from device_css_test import (
    APP_ID, ROOT, TEST_ID, drop_plugin_dependency, prepare_workspace, run)


SOURCE_ROOTS = ("apps/reader_mobile/lib", "packages")
BUSINESS_PATHS = ("apps/reader_mobile/lib", ":(glob)packages/*/lib/**")
HARNESS_PATHS = ("tool/device_reader_perf.py", "tool/device_css_test.py",
                 "apps/reader_mobile/integration_test/reader_perf_app.dart",
                 "apps/reader_mobile/integration_test/page_turn_perf_app.dart",
                 "apps/reader_mobile/integration_test/reader_perf_probe.dart")


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def business_snapshot(workspace):
    """散列实际复制的业务代码，测试入口与测试文件不计入业务脏状态。"""
    roots = [workspace / SOURCE_ROOTS[0], *workspace.glob("packages/*/lib")]
    entries = sorted(
        (path.relative_to(workspace).as_posix(), file_sha256(path))
        for root in roots for path in root.rglob("*") if path.is_file()
    )
    encoded = json.dumps(entries, ensure_ascii=False, separators=(",", ":"))
    return {"file_count": len(entries),
            "sha256": hashlib.sha256(encoded.encode("utf-8")).hexdigest()}


def revision_metadata(revision):
    def git(*arguments):
        return run(["git", *arguments], cwd=ROOT, capture=True).strip()

    def changes(*paths):
        return run(["git", "status", "--porcelain=v1", "--untracked-files=all",
                    "--", *paths], cwd=ROOT, capture=True).splitlines()

    business = changes(*BUSINESS_PATHS)
    harness = changes(*HARNESS_PATHS)
    working_tree = changes()
    head = git("rev-parse", "--verify", "HEAD^{commit}")
    commit = git("rev-parse", "--verify", f"{revision}^{{commit}}") if revision else head
    return {
        "source": {"revision": commit,
                   "kind": "git_archive" if revision else "working_tree",
                   "business_dirty": bool(business) if not revision else False},
        "harness": {"revision": head, "dirty": bool(harness), "changes": harness},
        "working_tree": {"revision": head, "dirty": bool(working_tree),
                         "changes": working_tree,
                         "business_dirty": bool(business), "business_changes": business},
    }


def device_metadata(adb):
    """仅在正式运行时读取设备环境；失败保留原因，不把缺失值当一致。"""
    commands = {
        "manufacturer": ["getprop", "ro.product.manufacturer"],
        "model": ["getprop", "ro.product.model"],
        "device": ["getprop", "ro.product.device"],
        "android_release": ["getprop", "ro.build.version.release"],
        "sdk": ["getprop", "ro.build.version.sdk"],
        "build_fingerprint": ["getprop", "ro.build.fingerprint"],
        "abi": ["getprop", "ro.product.cpu.abi"],
        "wm_size": ["wm", "size"],
        "wm_density": ["wm", "density"],
        "font_scale": ["settings", "get", "system", "font_scale"],
    }
    values = {"serial": adb[-1]}
    errors = {}
    for key, command in commands.items():
        try:
            result = subprocess.run(adb + ["shell", *command], capture_output=True,
                                    text=True, timeout=10, check=False)
            if result.returncode:
                errors[key] = {"exit_code": result.returncode, "stderr": result.stderr.strip()}
            else:
                values[key] = result.stdout.strip()
        except (OSError, subprocess.TimeoutExpired) as error:
            errors[key] = str(error)
    return {**values, "errors": errors}


def report_provenance(args, workspace, revisions, device):
    harness_files = {
        name: file_sha256((workspace if name.startswith("apps/") else ROOT) / name)
        for name in HARNESS_PATHS
    }
    return {
        "source": {**revisions["source"], "snapshot": business_snapshot(workspace)},
        "harness": {**revisions["harness"], "sha256_by_path": harness_files},
        "working_tree": revisions["working_tree"],
        "book": {"path": str(args.book.resolve()), "sha256": file_sha256(args.book),
                 "size_bytes": args.book.stat().st_size},
        "command": {"argv": list(sys.argv), "cwd": str(Path.cwd()),
                    "parameters": {key: str(value) if isinstance(value, Path) else value
                                   for key, value in vars(args).items()}},
        "device": device,
    }


class ReportHandler(SimpleHTTPRequestHandler):
    """流式保存样本，完成后唤醒宿主；不接受任何设备命令。"""

    def __init__(self, *args, output, done, provenance, **kwargs):
        self.output = output
        self.done = done
        self.provenance = provenance
        super().__init__(*args, **kwargs)

    def do_POST(self):
        if self.path not in ("/sample", "/done"):
            self.send_error(404)
            return
        size = int(self.headers.get("Content-Length", 0))
        if not 0 < size < 1024 * 1024:
            self.send_error(400)
            return
        data = json.loads(self.rfile.read(size))
        data["provenance"] = self.provenance
        self.output.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        print(json.dumps(data, ensure_ascii=False), flush=True)
        self.send_response(204)
        self.end_headers()
        if self.path == "/done":
            self.done.set()


def sample_meminfo(adb, package, stop, samples, interval):
    """轮询 Android 总 PSS；包含 EGL/图形共享页，作为系统设置口径。"""
    started = time.monotonic()
    while not stop.is_set():
        try:
            result = subprocess.run(
                adb + ["shell", "dumpsys", "meminfo", package],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            pss = re.search(r"^\s*TOTAL PSS:\s*([\d,]+)", result.stdout, re.MULTILINE)
            rss = re.search(r"^\s*TOTAL RSS:\s*([\d,]+)", result.stdout, re.MULTILINE)
            if pss:
                breakdown = {}
                for line in result.stdout.splitlines():
                    match = re.match(
                        r"^\s*(.+?)\s+([\d,]+)(?:\s+[\d,]+){4,7}\s*$",
                        line,
                    )
                    if match is None:
                        continue
                    name = match.group(1).strip()
                    if name in ("App Summary", "Dalvik"):
                        break
                    breakdown[name] = int(match.group(2).replace(",", "")) * 1024
                samples.append({
                    "t_ms": int((time.monotonic() - started) * 1000),
                    "total_pss_bytes": int(pss.group(1).replace(",", "")) * 1024,
                    "total_rss_bytes": (
                        int(rss.group(1).replace(",", "")) * 1024 if rss else None
                    ),
                    "breakdown": breakdown,
                })
        except (OSError, subprocess.TimeoutExpired):
            pass
        stop.wait(interval)


def summarize_meminfo(samples):
    if not samples:
        return {"samples": [], "peak_total_pss_bytes": None,
                "peak_total_rss_bytes": None}
    return {
        "samples": samples,
        "peak_total_pss_bytes": max(item["total_pss_bytes"] for item in samples),
        "peak_total_rss_bytes": max(
            item["total_rss_bytes"] or 0 for item in samples
        ),
        "peak_sample": max(samples, key=lambda item: item["total_pss_bytes"]),
    }


def prepare(workspace, revision):
    prepare_workspace(workspace)
    # 仅复制已经下载的原生依赖；sqlite3 hook 会按当前包内哈希重新校验。
    cache = Path("apps/reader_mobile/.dart_tool/hooks_runner/shared/sqlite3/build")
    for source in (ROOT / cache).glob("download-*"):
        shutil.copytree(source, workspace / cache / source.name, dirs_exist_ok=True)
    if revision:
        # 只替换业务源与包；测试入口始终用当前版本以保持测量口径一致。
        archive = subprocess.check_output([
            "git", "archive", revision, *SOURCE_ROOTS], cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
            for member in bundle.getmembers():
                path = Path(member.name)
                if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                    raise RuntimeError(f"不支持的源码归档条目：{member.name}")
            # 当前版本新增的文件不在旧归档中；先清临时业务目录，避免混入基线。
            for name in SOURCE_ROOTS:
                target = workspace / name
                if target.exists():
                    shutil.rmtree(target)
            bundle.extractall(workspace)
    manifest = workspace / "apps/reader_mobile/android/app/src/main/AndroidManifest.xml"
    source = manifest.read_text()
    if 'android:name="android.permission.INTERNET"' not in source:
        source = source.replace(
            "    <application",
            '    <uses-permission android:name="android.permission.INTERNET"/>\n'
            '    <application',
        )
    if 'android:usesCleartextTraffic=' not in source:
        source = source.replace(
            'android:label="CSS 真机测试"',
            'android:usesCleartextTraffic="true" android:label="阅读性能测试"')
    else:
        source = source.replace(
            'android:label="CSS 真机测试"',
            'android:label="阅读性能测试"')
    manifest.write_text(source)
    drop_plugin_dependency(workspace / "apps/reader_mobile/pubspec.yaml")


def build(workspace, url, args):
    app = workspace / "apps/reader_mobile"
    target = "integration_test/" + ("page_turn_perf_app.dart" if args.page_turn else "reader_perf_app.dart")
    defines = {
        "PERF_SERVER": url, "PERF_ROUNDS": str(args.rounds),
        "PERF_SPINE": str(args.target_spine), "PERF_FONT_SIZE": str(args.font_size),
        "PERF_TITLE": args.title,
        **{name: "true" if value else "false" for name, value in {
            "PERF_RESIZE": args.resize, "PERF_IMPORT": args.measure_import,
            "PERF_LONG_SCAN": args.long_scan, "PERF_FAR_JUMP": args.far_jump,
        }.items()},
    }
    run(["flutter", "pub", "get", "--offline"], cwd=app)
    run([
        "flutter", "build", "apk", "--release", "--no-pub", "--config-only",
        "--target=" + target,
        "--target-platform=android-arm64",
        *[f"--dart-define={key}={value}" for key, value in defines.items()]], cwd=app)
    encoded = ",".join(base64.b64encode(f"{key}={value}".encode()).decode()
                       for key, value in defines.items())
    # target/defines 是 Gradle 项目参数；config-only 不持久化这两项。
    run(["./gradlew", "--offline", "--console=plain", ":app:assembleRelease",
         "-Ptarget-platform=android-arm64", "-Ptarget=" + target,
         "-Pdart-defines=" + encoded], cwd=app / "android", env=dict(os.environ))
    apk = app / "build/app/outputs/flutter-apk/app-release.apk"
    actual = run(["apkanalyzer", "manifest", "application-id", str(apk)], capture=True).strip()
    if actual != TEST_ID:
        raise RuntimeError(f"拒绝安装非隔离包：{actual}")
    shutil.copy2(apk, args.output / "app-release.apk")
    return apk


def benchmark(args):
    adb = ["adb", "-s", args.device]
    before = run(adb + ["shell", "pm", "path", APP_ID], capture=True)
    args.output.mkdir(parents=True, exist_ok=True)
    done = threading.Event()
    revisions = revision_metadata(args.revision)
    with tempfile.TemporaryDirectory(prefix="spectacular-perf-") as directory:
        workspace = Path(directory)
        prepare(workspace, revisions["source"]["revision"] if args.revision else None)
        provenance = report_provenance(args, workspace, revisions, device_metadata(adb))
        inputs = workspace / "inputs"
        inputs.mkdir()
        (inputs / "book.epub").symlink_to(args.book.resolve())
        server = ThreadingHTTPServer(("127.0.0.1", 0), partial(ReportHandler,
            directory=str(inputs), output=args.output / "report.json", done=done,
            provenance=provenance))
        port = str(server.server_port)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            apk = build(workspace, f"http://127.0.0.1:{port}", args)
            run(adb + ["reverse", f"tcp:{port}", f"tcp:{port}"])
            run(adb + ["shell", "am", "force-stop", TEST_ID])
            run(adb + ["install", "--no-streaming", "-r", str(apk)])
            stop_meminfo = threading.Event()
            meminfo_samples = []
            meminfo_thread = None
            if args.meminfo_interval > 0:
                meminfo_thread = threading.Thread(
                    target=sample_meminfo,
                    args=(adb, TEST_ID, stop_meminfo, meminfo_samples,
                          args.meminfo_interval),
                    daemon=True,
                )
            run(adb + ["shell", "am", "start", "-n", TEST_ID + "/" + TEST_ID + ".MainActivity"])
            if meminfo_thread is not None:
                meminfo_thread.start()
            if not done.wait(900):
                raise TimeoutError("性能测试超时，已有样本保留在 report.json")
            if meminfo_thread is not None:
                stop_meminfo.set()
                meminfo_thread.join(timeout=12)
            report = json.loads((args.output / "report.json").read_text())
            report["host_meminfo"] = summarize_meminfo(meminfo_samples)
            (args.output / "report.json").write_text(
                json.dumps(report, ensure_ascii=False, indent=2)
            )
            if "error" in report:
                raise RuntimeError(report["error"])
        finally:
            if "stop_meminfo" in locals():
                stop_meminfo.set()
            server.shutdown()
            server.server_close()
            subprocess.run(adb + ["shell", "am", "force-stop", TEST_ID], check=False)
            subprocess.run(adb + ["reverse", "--remove", f"tcp:{port}"], check=False)
            if run(adb + ["shell", "pm", "path", APP_ID], capture=True) != before:
                raise RuntimeError("正式应用安装路径发生变化")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--book", type=Path, default=ROOT / "test_corpus/real/zhushen-yuxi.epub")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", help="可选基线 Git revision；当前测试入口保持不变")
    parser.add_argument("--rounds", type=int, default=5, help="每种开书及字号变化的样本轮数")
    parser.add_argument("--page-turn", action="store_true", help="测量3D翻页准备、连续翻页及跨章；格列佛游记使用 --target-spine 10")
    parser.add_argument("--target-spine", type=int, default=29, help="开书恢复的 spine 序号")
    parser.add_argument("--font-size", type=float, default=21, help="基准字号；字号测试往返基准和基准加一")
    parser.add_argument("--title", default="诸神愚戏", help="隔离书架测试书名")
    parser.add_argument("--resize", action="store_true", help="每轮测量真实阅读页字号更新及缓存恢复")
    parser.add_argument("--long-scan", action="store_true",
                        help="连续加载全书抽样章节并记录 RSS 与缓存状态")
    parser.add_argument("--far-jump", action=argparse.BooleanOptionalAction, default=True,
                        help="测试远跳；前后版本必须使用相同开关，旧版本不支持时传 --no-far-jump")
    parser.add_argument("--measure-import", action="store_true",
                        help="在隔离包临时书库测量完整导入，含读盘、校验、落盘、字符统计与入库")
    parser.add_argument("--meminfo-interval", type=float, default=1.0,
                        help="dumpsys meminfo 采样间隔秒；0 关闭")
    args = parser.parse_args()
    if not args.book.is_file():
        parser.error("找不到原书")
    benchmark(args)


if __name__ == "__main__":
    main()
