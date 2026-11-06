#!/usr/bin/env python3
"""在隔离 release 包中测量真实书架打开、目录跳转及正文图片首帧。"""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import threading

from device_css_test import (
    APP_ID, ROOT, TEST_ID, drop_plugin_dependency, prepare_workspace, run)


class ReportHandler(SimpleHTTPRequestHandler):
    """流式保存样本，完成后唤醒宿主；不接受任何设备命令。"""

    def __init__(self, *args, output, done, **kwargs):
        self.output = output
        self.done = done
        super().__init__(*args, **kwargs)

    def do_POST(self):
        if self.path not in ("/sample", "/done"):
            self.send_error(404)
            return
        size = int(self.headers.get("Content-Length", 0))
        if not 0 < size < 65536:
            self.send_error(400)
            return
        data = json.loads(self.rfile.read(size))
        self.output.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        print(json.dumps(data, ensure_ascii=False), flush=True)
        self.send_response(204)
        self.end_headers()
        if self.path == "/done":
            self.done.set()


def prepare(workspace, revision):
    prepare_workspace(workspace)
    if revision:
        # 只替换业务源与包；测试入口始终用当前版本以保持测量口径一致。
        archive = subprocess.check_output([
            "git", "archive", revision, "apps/reader_mobile/lib", "packages"], cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
            for member in bundle.getmembers():
                path = Path(member.name)
                if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                    raise RuntimeError(f"不支持的源码归档条目：{member.name}")
            bundle.extractall(workspace)
    manifest = workspace / "apps/reader_mobile/android/app/src/main/AndroidManifest.xml"
    source = manifest.read_text().replace(
        "    <application", '    <uses-permission android:name="android.permission.INTERNET"/>\n    <application')
    manifest.write_text(source.replace(
        'android:label="CSS 真机测试"',
        'android:usesCleartextTraffic="true" android:label="阅读性能测试"'))
    drop_plugin_dependency(workspace / "apps/reader_mobile/pubspec.yaml")


def build(workspace, url, args):
    app = workspace / "apps/reader_mobile"
    run(["flutter", "pub", "get", "--offline"], cwd=app)
    run([
        # 不能加 --no-pub：release 需要 flutter 重新注入插件列表，
        # 否则会沿用 pub get 生成（含已移除开发依赖）的注册文件。
        "flutter", "build", "apk", "--release",
        "--target=integration_test/reader_perf_app.dart", "--target-platform=android-arm64",
        "--dart-define=PERF_SERVER=" + url,
        "--dart-define=PERF_IMPORT=" + ("true" if args.measure_import else "false"),
        "--dart-define=PERF_LONG_SCAN=" + ("true" if args.long_scan else "false"),
        "--dart-define=PERF_FAR_JUMP=" + ("true" if args.far_jump else "false")], cwd=app)
    apk = app / "build/app/outputs/flutter-apk/app-release.apk"
    actual = run(["apkanalyzer", "manifest", "application-id", str(apk)], capture=True).strip()
    if actual != TEST_ID:
        raise RuntimeError(f"拒绝安装非隔离包：{actual}")
    return apk


def benchmark(args):
    adb = ["adb", "-s", args.device]
    before = run(adb + ["shell", "pm", "path", APP_ID], capture=True)
    args.output.mkdir(parents=True, exist_ok=True)
    done = threading.Event()
    with tempfile.TemporaryDirectory(prefix="spectacular-perf-") as directory:
        workspace = Path(directory)
        prepare(workspace, args.revision)
        inputs = workspace / "inputs"
        inputs.mkdir()
        (inputs / "book.epub").symlink_to(args.book.resolve())
        server = ThreadingHTTPServer(("127.0.0.1", 0), partial(ReportHandler,
            directory=str(inputs), output=args.output / "report.json", done=done))
        port = str(server.server_port)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            apk = build(workspace, f"http://127.0.0.1:{port}", args)
            run(adb + ["reverse", f"tcp:{port}", f"tcp:{port}"])
            run(adb + ["shell", "am", "force-stop", TEST_ID])
            run(adb + ["install", "-r", str(apk)])
            run(adb + ["shell", "am", "start", "-n", TEST_ID + "/" + TEST_ID + ".MainActivity"])
            if not done.wait(900):
                raise TimeoutError("性能测试超时，已有样本保留在 report.json")
            report = json.loads((args.output / "report.json").read_text())
            if "error" in report:
                raise RuntimeError(report["error"])
        finally:
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
    parser.add_argument("--long-scan", action="store_true",
                        help="连续加载全书抽样章节并记录 RSS 与缓存状态")
    parser.add_argument("--far-jump", action=argparse.BooleanOptionalAction, default=True,
                        help="测试远跳；前后版本必须使用相同开关，旧版本不支持时传 --no-far-jump")
    parser.add_argument("--measure-import", action="store_true",
                        help="在隔离包临时书库测量完整导入，含读盘、校验、落盘、字符统计与入库")
    args = parser.parse_args()
    if not args.book.is_file():
        parser.error("找不到原书")
    benchmark(args)


if __name__ == "__main__":
    main()
