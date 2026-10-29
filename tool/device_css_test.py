#!/usr/bin/env python3
"""在独立 Android 包中验证原书 CSS，保留手机现有阅读器。"""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading


ROOT = Path(__file__).resolve().parents[1]
APP_ID = "com.spectacular.reader_mobile"
TEST_ID = APP_ID + ".css_test"


class DeviceHandler(SimpleHTTPRequestHandler):
    """提供原书并按测试检查点截取 Android 正常渲染表面。"""

    def __init__(self, *args, device, output, **kwargs):
        self.device = device
        self.output = output
        super().__init__(*args, **kwargs)

    def do_POST(self):
        name = self.path.removeprefix("/capture/")
        allowed = {"chapter6-page-1", "chapter6-page-2", "chapter6-page-3",
                   "chapter6-enlarged", "chapter3-page-1", "chapter3-page-2",
                   "chapter3-page-3", "chapter3-diaoming", "chapter4-fanrong"}
        if self.path != f"/capture/{name}" or name not in allowed:
            self.send_error(404)
            return
        result = subprocess.run(
            ["adb", "-s", self.device, "exec-out", "screencap", "-p"],
            check=True, capture_output=True)
        if not result.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
            self.send_error(500, "Invalid PNG")
            return
        self.output.mkdir(parents=True, exist_ok=True)
        (self.output / f"{name}.png").write_bytes(result.stdout)
        self.send_response(204)
        self.end_headers()


def run(command, *, cwd=ROOT, capture=False, env=None):
    """失败立即停止，不尝试卸载后重装。"""
    return subprocess.run(command, cwd=cwd, check=True, text=True,
                          capture_output=capture, env=env).stdout


def prepare_workspace(destination):
    """复制当前代码到临时目录，Android 标识全部切换到测试包。"""
    paths = run(["git", "ls-files", "--cached", "--others", "--exclude-standard",
                 "-z", "--", "apps/reader_mobile", "packages"], capture=True)
    for name in paths.split("\0"):
        if not name or not (ROOT / name).is_file():
            continue
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    android = Path("apps/reader_mobile/android")
    for name in ["gradlew", "gradlew.bat", "local.properties",
                 "gradle/wrapper/gradle-wrapper.jar"]:
        source = ROOT / android / name
        if source.exists():
            shutil.copy2(source, destination / android / name)
    app = destination / android / "app"
    for name in ["build.gradle.kts", "src/main/AndroidManifest.xml",
                 "src/main/kotlin/com/spectacular/reader_mobile/MainActivity.kt"]:
        path = app / name
        path.write_text(path.read_text().replace(APP_ID, TEST_ID))
    manifest = app / "src/main/AndroidManifest.xml"
    manifest.write_text(manifest.read_text().replace(
        'android:label="reader_mobile"', 'android:label="CSS 真机测试"'))


def build_verified_apk(workspace, book_url):
    """从 APK 读取实际包名；不以 Gradle namespace 推断安装目标。"""
    app = workspace / "apps/reader_mobile"
    run(["flutter", "pub", "get", "--offline"], cwd=app)
    run(["flutter", "build", "apk", "--debug", "--no-pub",
         "--target=integration_test/real_book_css_test.dart",
         "--target-platform=android-arm64",
         "--dart-define=EPUB_TEST_URL=" + book_url], cwd=app)
    apk = app / "build/app/outputs/flutter-apk/app-debug.apk"
    actual_id = run(["apkanalyzer", "manifest", "application-id", str(apk)],
                    capture=True).strip()
    if actual_id != TEST_ID:
        raise RuntimeError(f"停止安装：APK 包名 {actual_id} 不是 {TEST_ID}")
    return apk


def drive(device, workspace, apk, output):
    """使用已校验 APK，关闭 Flutter 的结束卸载流程。"""
    env = dict(os.environ, CSS_DEVICE_OUTPUT=str(output))
    run(["flutter", "drive", "--no-pub", "-d", device,
         "--target=integration_test/real_book_css_test.dart",
         "--driver=test_driver/css_screenshot_test.dart",
         "--use-application-binary=" + str(apk), "--keep-app-running",
         "--timeout=600"], cwd=workspace / "apps/reader_mobile", env=env)


def test_on_device(args):
    adb = ["adb", "-s", args.device]
    before = run(adb + ["shell", "pm", "path", APP_ID], capture=True)
    with tempfile.TemporaryDirectory(prefix="spectacular-css-") as directory:
        workspace = Path(directory)
        prepare_workspace(workspace)
        inputs = workspace / "inputs"
        inputs.mkdir()
        (inputs / "book.epub").symlink_to(args.book.resolve())
        server = ThreadingHTTPServer(("127.0.0.1", 0),
            partial(DeviceHandler, directory=str(inputs), device=args.device,
                    output=args.output.resolve()))
        port = str(server.server_port)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            apk = build_verified_apk(workspace, f"http://127.0.0.1:{port}/book.epub")
            run(adb + ["reverse", f"tcp:{port}", f"tcp:{port}"])
            drive(args.device, workspace, apk, args.output.resolve())
        finally:
            server.shutdown()
            server.server_close()
            subprocess.run(adb + ["reverse", "--remove", f"tcp:{port}"],
                           check=False, capture_output=True)
            # 仅停止本脚本的测试包，不卸载任何应用。
            subprocess.run(adb + ["shell", "am", "force-stop", TEST_ID], check=False)
            after = run(adb + ["shell", "pm", "path", APP_ID], capture=True)
            if after != before:
                raise RuntimeError("正式应用安装路径发生变化，必须检查设备数据")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="adb 的 USB 设备序列号")
    parser.add_argument("--book", type=Path,
                        default=ROOT / "test_corpus/real/zhushen-yuxi.epub")
    parser.add_argument("--output", type=Path,
                        default=ROOT / "apps/reader_mobile/dist/css-device-results")
    args = parser.parse_args()
    if not args.book.is_file():
        parser.error("原书不存在，请用 --book 指定《诸神愚戏》EPUB")
    for command in ["git", "flutter", "adb", "apkanalyzer"]:
        if not shutil.which(command):
            parser.error(f"缺少命令：{command}")
    test_on_device(args)


if __name__ == "__main__":
    main()
