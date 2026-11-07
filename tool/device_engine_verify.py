#!/usr/bin/env python3
"""真机 EPUB 引擎验收：一键构建隔离 APK、运行场景、收集指标/截图/日志。

用法：
    python3 tool/device_engine_verify.py                 # 自动取唯一设备
    python3 tool/device_engine_verify.py --device <序列号>
    python3 tool/device_engine_verify.py --skip-build --apk <已构建 APK>

流程：生成 fixtures（缺失时）→ 构建 engine_test 隔离包 → adb 安装启动 →
App 内跑章节加载/目录/翻页/滚动/字体排版/图片/容错场景 → 检查点截图与
采样回传 → 汇总 report.json 与 SUMMARY.md，并保存 logcat。

只安装隔离测试包（.engine_test），不改动正式应用与手机数据。
"""

from __future__ import annotations

import argparse
import json
import os
from functools import partial
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zlib
from pathlib import Path

from device_css_test import drop_plugin_dependency

ROOT = Path(__file__).resolve().parents[1]
APP_ID = "com.spectacular.reader_mobile"
TEST_ID = APP_ID + ".engine_test"
FIXTURE_DIR = ROOT / "test_corpus" / "generated"
FIXTURE_NAMES = [
    "verify-mixed.epub",
    "verify-tolerance.epub",
    "verify-small.epub",
    "verify-broken-spine.epub",
]
REVERSE_PORT_RANGE = range(60001, 60051)


class DeviceHandler(BaseHTTPRequestHandler):
    """提供 fixtures、接收采样、按检查点截图；不执行任何设备写入命令。"""

    def __init__(self, *args, device, fixtures, output, state, **kwargs):
        self.device = device
        self.fixtures = fixtures
        self.output = output
        self.state = state
        super().__init__(*args, **kwargs)

    def log_message(self, format, *args):  # noqa: A002 （静默）
        return

    def do_GET(self):
        name = self.path.removeprefix("/fixtures/")
        if self.path == f"/fixtures/{name}" and name in FIXTURE_NAMES:
            payload = (self.fixtures / name).read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/epub+zip")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_error(404)

    def do_POST(self):
        size = int(self.headers.get("Content-Length", 0))
        if not 0 < size < 1 << 20:
            self.send_error(400)
            return
        data = json.loads(self.rfile.read(size) or b"{}")
        if self.path.startswith("/capture/"):
            name = self.path.removeprefix("/capture/")
            self.state["screenshots"].append(name)
            capture(self.device, self.output / "screenshots" / f"{name}.png")
            self.send_response(204)
            self.end_headers()
            return
        if self.path == "/sample":
            self.state["samples"] += 1
            (self.output / "report.partial.json").write_text(
                json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            print(f"  采样 #{self.state['samples']}", flush=True)
            self.send_response(204)
            self.end_headers()
            return
        if self.path == "/done":
            self.state["report"] = data
            self.state["done"].set()
            self.send_response(204)
            self.end_headers()
            return
        self.send_error(404)


def run(command, *, cwd=ROOT, capture=False, env=None, check=True):
    return subprocess.run(
        command, cwd=cwd, check=check, text=True, capture_output=capture, env=env
    ).stdout


def install_apk(device: str, apk: Path) -> None:
    """安装隔离包；Flyme 的按包名 USB 安装白名单关闭时先放行再重试。"""
    result = subprocess.run(
        ["adb", "-s", device, "install", "-r", str(apk)],
        text=True, capture_output=True,
    )
    if result.returncode == 0:
        return
    if "INSTALL_FAILED_USER_RESTRICTED" not in (result.stdout + result.stderr):
        raise RuntimeError(f"安装失败：{result.stdout}{result.stderr}")
    key = f"usb_install_item_{TEST_ID}"
    subprocess.run(
        ["adb", "-s", device, "shell", "settings", "put", "secure", key,
         "引擎真机验收:1"],
        check=True, capture_output=True, text=True,
    )
    print(f"  已放行 USB 安装权限（{key}）后重试", flush=True)
    run(["adb", "-s", device, "install", "-r", str(apk)])


def capture(device, target: Path) -> None:
    """检查点截图：读设备帧缓冲，同时保留原始 PNG。"""
    result = subprocess.run(
        ["adb", "-s", device, "exec-out", "screencap", "-p"],
        check=True,
        capture_output=True,
    )
    if not result.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("设备截图不是 PNG")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(result.stdout)
    print(f"  截图 {target.name}", flush=True)


def png_dominant_color(path: Path, *, top_rows: int = 0):
    """解出 PNG 的主色与暗像素占比；用于主题深/浅判定。"""
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError(f"{path} 不是 PNG")
    pos = 8
    width = height = None
    bit_depth = color_type = None
    idat = bytearray()
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        tag = data[pos + 4 : pos + 8]
        payload = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(
                ">IIBB", payload[:10]
            )
        elif tag == b"IDAT":
            idat.extend(payload)
        elif tag == b"IEND":
            break
    if bit_depth != 8 or color_type not in (2, 6):
        return {"unsupported": f"bit_depth={bit_depth} color_type={color_type}"}
    channels = 3 if color_type == 2 else 4
    stride = width * channels
    raw = zlib.decompress(bytes(idat))
    rows = []
    previous = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        line = bytearray(raw[offset : offset + stride])
        offset += stride
        if filter_type == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filter_type == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif filter_type == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif filter_type == 4:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                up = previous[i]
                up_left = previous[i - channels] if i >= channels else 0
                estimate = left + up - up_left
                pa, pb, pc = abs(estimate - left), abs(estimate - up), abs(
                    estimate - up_left
                )
                predictor = left if (pa <= pb and pa <= pc) else (
                    up if pb <= pc else up_left
                )
                line[i] = (line[i] + predictor) & 0xFF
        rows.append(line)
        previous = line
    start = 0
    end = height if top_rows <= 0 else min(top_rows, height)
    counts = {}
    dark = 0
    total = 0
    for row in rows[start:end]:
        for x in range(0, stride, channels):
            key = (row[x] >> 3, row[x + 1] >> 3, row[x + 2] >> 3)
            counts[key] = counts.get(key, 0) + 1
            if row[x] + row[x + 1] + row[x + 2] < 200:
                dark += 1
            total += 1
    best, count = max(counts.items(), key=lambda item: item[1])
    return {
        "dominant_rgb": [value << 3 for value in best],
        "dominant_share": round(count / max(1, total), 3),
        "dark_ratio": round(dark / max(1, total), 3),
        "size": [width, height],
    }


def prepare_workspace(destination: Path) -> None:
    """复制当前代码到临时目录，Android 标识切到隔离测试包。"""
    paths = run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z",
         "--", "apps/reader_mobile", "packages"],
        capture=True,
    )
    for name in paths.split("\0"):
        if not name or not (ROOT / name).is_file():
            continue
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    android = Path("apps/reader_mobile/android")
    for name in [
        "gradlew", "gradlew.bat", "local.properties",
        "gradle/wrapper/gradle-wrapper.jar",
    ]:
        source = ROOT / android / name
        if source.exists():
            target = destination / android / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    app = destination / android / "app"
    for name in [
        "build.gradle.kts",
        "src/main/AndroidManifest.xml",
        "src/main/kotlin/com/spectacular/reader_mobile/MainActivity.kt",
    ]:
        path = app / name
        path.write_text(path.read_text().replace(APP_ID, TEST_ID))
    manifest = app / "src/main/AndroidManifest.xml"
    manifest.write_text(
        manifest.read_text().replace(
            "    <application",
            '    <uses-permission android:name="android.permission.INTERNET"/>\n'
            "    <application",
        ).replace(
            'android:label="reader_mobile"',
            'android:usesCleartextTraffic="true" android:label="引擎真机验收"',
        )
    )
    drop_plugin_dependency(destination / "apps/reader_mobile/pubspec.yaml")


def build_apk(workspace: Path, url: str) -> Path:
    app = workspace / "apps/reader_mobile"
    run(["flutter", "pub", "get", "--offline"], cwd=app)
    run(
        [
            # 不能加 --no-pub：release 需要 flutter 重新注入插件列表，
            # 否则会沿用 pub get 生成（含 integration_test 等开发依赖）的注册文件。
            "flutter", "build", "apk", "--release",
            "--target=integration_test/engine_verify_app.dart",
            "--target-platform=android-arm64",
            "--dart-define=ENGINE_SERVER=" + url,
        ],
        cwd=app,
    )
    apk = app / "build/app/outputs/flutter-apk/app-release.apk"
    actual = run(
        ["apkanalyzer", "manifest", "application-id", str(apk)], capture=True
    ).strip()
    if actual != TEST_ID:
        raise RuntimeError(f"拒绝安装非隔离包：{actual}")
    return apk


def ensure_fixtures() -> None:
    missing = [name for name in FIXTURE_NAMES if not (FIXTURE_DIR / name).is_file()]
    if not missing:
        return
    python = "/usr/bin/python3" if Path("/usr/bin/python3").exists() else sys.executable
    run([python, str(ROOT / "tests/corpus/build_device_fixtures.py")])
    still = [name for name in FIXTURE_NAMES if not (FIXTURE_DIR / name).is_file()]
    if still:
        raise RuntimeError(f"fixtures 生成后仍缺失：{still}")


def start_reverse_server(device: str, handler_factory):
    """在设备允许的端口段启动宿主服务并建立 reverse。

    Flyme/Android 16 会拒绝部分落在临时端口区间内的监听端口（实测 50019
    返回 Operation not permitted，60001 正常）。这里逐个尝试安全端口，
    既避免随机端口偶发失败，也保留本机端口被占用时的回退。
    """
    for port in REVERSE_PORT_RANGE:
        try:
            server = ThreadingHTTPServer(("127.0.0.1", port), handler_factory)
        except OSError:
            continue
        result = subprocess.run(
            ["adb", "-s", device, "reverse", f"tcp:{port}", f"tcp:{port}"],
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode == 0:
            return server, port
        server.server_close()
    raise RuntimeError("无法建立 adb reverse：设备拒绝了 60001-60050 全部端口")


def pick_device(requested: str | None) -> str:
    if requested:
        return requested
    output = run(["adb", "devices"], capture=True)
    devices = [
        line.split("\t")[0]
        for line in output.splitlines()[1:]
        if line.strip().endswith("device")
    ]
    if len(devices) != 1:
        raise SystemExit(f"需要恰好一台设备（当前 {devices}），请用 --device 指定")
    return devices[0]


def device_info(device: str) -> dict:
    def prop(name: str) -> str:
        return run(["adb", "-s", device, "shell", "getprop", name], capture=True).strip()

    return {
        "serial": device,
        "model": prop("ro.product.model"),
        "android": prop("ro.build.version.release"),
        "sdk": prop("ro.build.version.sdk"),
    }


def summarize(report: dict, output: Path) -> None:
    """写 SUMMARY.md：场景/步骤结论 + 关键指标。"""
    lines = ["# 真机引擎验收摘要", ""]
    lines.append(f"- 设备：{report.get('device', {})}")
    lines.append(f"- fixtures：{report.get('fixtures', {})}")
    lines.append(f"- 总耗时：{report.get('total_ms')} ms")
    lines.append("")
    lines.append("| 场景 | 步骤 | 结论 | 耗时 ms | 关键指标 |")
    lines.append("| --- | --- | --- | ---: | --- |")
    for scenario in report.get("scenarios", []):
        for step in scenario.get("steps", []):
            verdict = "通过" if step.get("ok") else f"失败：{step.get('error', '')}"
            metrics = json.dumps(step.get("metrics", {}), ensure_ascii=False)
            if len(metrics) > 220:
                metrics = metrics[:217] + "…"
            lines.append(
                f"| {scenario.get('name', '')} | {step.get('name', '')} | "
                f"{verdict} | {step.get('ms', 0)} | `{metrics}` |"
            )
    screenshots = report.get("screenshots", {})
    if screenshots:
        lines.append("")
        lines.append("## 截图主色（主题/图片检查）")
        lines.append("")
        lines.append("| 截图 | 主色 | 占比 | 暗像素比例 |")
        lines.append("| --- | --- | ---: | ---: |")
        for name, info in screenshots.items():
            lines.append(
                f"| {name} | {info.get('dominant_rgb')} | "
                f"{info.get('dominant_share')} | {info.get('dark_ratio')} |"
            )
    errors = report.get("errors", [])
    if errors:
        lines.append("")
        lines.append("## 错误")
        lines.append("")
        for error in errors:
            lines.append(f"- {error.splitlines()[0]}")
    (output / "SUMMARY.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def verify(args) -> None:
    device = pick_device(args.device)
    ensure_fixtures()
    args.output.mkdir(parents=True, exist_ok=True)
    info = device_info(device)
    print(f"设备：{info['model']} / Android {info['android']}")
    before = run(["adb", "-s", device, "shell", "pm", "path", APP_ID], capture=True)
    state = {"done": threading.Event(), "report": None, "samples": 0, "screenshots": []}
    logcat = args.output / "logcat.txt"
    handler_factory = partial(
        DeviceHandler,
        device=device,
        fixtures=FIXTURE_DIR,
        output=args.output,
        state=state,
    )
    server, host_port = start_reverse_server(device, handler_factory)
    port = str(host_port)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    workspace_ctx = tempfile.TemporaryDirectory(prefix="spectacular-engine-")
    try:
        if args.apk:
            apk = args.apk
        else:
            workspace = Path(workspace_ctx.name)
            prepare_workspace(workspace)
            apk = build_apk(workspace, f"http://127.0.0.1:{port}")
        print(f"APK：{apk}")
        subprocess.run(
            ["adb", "-s", device, "logcat", "-c"], check=False,
            capture_output=True,
        )
        run(["adb", "-s", device, "shell", "am", "force-stop", TEST_ID], check=False)
        install_apk(device, Path(apk))
        activity = run(
            ["adb", "-s", device, "shell", "cmd", "package", "resolve-activity",
             "--brief", TEST_ID],
            capture=True,
        ).strip().splitlines()[-1]
        if not activity.startswith(TEST_ID):
            raise RuntimeError(f"隔离包没有可启动 Activity：{activity}")
        run(["adb", "-s", device, "shell", "am", "start", "-n", activity])
        deadline = time.time() + args.timeout
        while not state["done"].wait(5):
            if time.time() > deadline:
                raise TimeoutError("真机验收超时（可查 report.partial.json）")
            print(f"  运行中：采样 {state['samples']}，截图 {len(state['screenshots'])}")
        report = state["report"] or {}
        (args.output / "report.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        logcat.write_text(
            run(
                ["adb", "-s", device, "logcat", "-d", "-v", "time"],
                capture=True,
                check=False,
            ),
            encoding="utf-8",
        )
        analysis = {}
        for name in state["screenshots"]:
            path = args.output / "screenshots" / f"{name}.png"
            if path.is_file():
                try:
                    analysis[name] = png_dominant_color(path)
                except Exception as error:  # noqa: BLE001 （分析失败只记录）
                    analysis[name] = {"error": str(error)}
        report["device"] = info
        report["screenshots"] = analysis
        report["apk_sha256"] = run(
            ["shasum", "-a", "256", str(apk)], capture=True
        ).split()[0] if Path(apk).is_file() else None
        (args.output / "report.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        summarize(report, args.output)
        print(f"报告：{args.output / 'report.json'}，摘要：{args.output / 'SUMMARY.md'}")
    finally:
        server.shutdown()
        server.server_close()
        subprocess.run(
            ["adb", "-s", device, "shell", "am", "force-stop", TEST_ID], check=False,
            capture_output=True,
        )
        subprocess.run(
            ["adb", "-s", device, "reverse", "--remove", f"tcp:{port}"],
            check=False, capture_output=True,
        )
        workspace_ctx.cleanup()
        after = run(["adb", "-s", device, "shell", "pm", "path", APP_ID], capture=True)
        if after != before:
            raise RuntimeError("正式应用安装路径发生变化，必须检查设备数据")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="adb 序列号；缺省自动取唯一设备")
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "apps/reader_mobile/dist/engine-device-results",
    )
    parser.add_argument("--apk", type=Path, help="复用已构建的隔离 APK，跳过构建")
    parser.add_argument("--timeout", type=int, default=1200, help="整体超时秒数")
    args = parser.parse_args()
    for command in ["git", "flutter", "adb", "apkanalyzer", "shasum"]:
        if not shutil.which(command):
            parser.error(f"缺少命令：{command}")
    if args.apk and not args.apk.is_file():
        parser.error(f"APK 不存在：{args.apk}")
    verify(args)


if __name__ == "__main__":
    main()
