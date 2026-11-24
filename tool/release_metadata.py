"""为一轮本地构建分配内部版本号，正式版本号保持不变。"""

import argparse
import os
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r"(?m)^(version:\s*)(\d+\.\d+\.\d+)\+(\d+)(\s*(?:#.*)?)$")


def reserve(pubspec=ROOT / "apps/reader_mobile/pubspec.yaml"):
    lock = pubspec.with_name(".release-version.lock")
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError as error:
        raise RuntimeError("另一轮打包正在分配版本号，请等待其完成") from error
    try:
        os.close(descriptor)
        text = pubspec.read_text(encoding="utf-8")
        match = VERSION.search(text)
        if match is None:
            raise ValueError("pubspec.yaml 需要 version: 主版本.次版本.修订版本+内部版本")
        version, number = match.group(2), int(match.group(3)) + 1
        replacement = f"{match.group(1)}{version}+{number}{match.group(4)}"
        pubspec.write_text(text[:match.start()] + replacement + text[match.end():],
                           encoding="utf-8")
        return version, number
    finally:
        lock.unlink()


def artifact_name(platform, version, number):
    if platform not in ("arm64", "winx64"):
        raise ValueError("平台必须是 arm64 或 winx64")
    suffix = "apk" if platform == "arm64" else "zip"
    return f"阅微 Extend {platform} v{version}（{number}）.{suffix}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reserve", action="store_true", required=True)
    args = parser.parse_args()
    if args.reserve:
        version, number = reserve()
        # Bash 和 PowerShell 均可读取，输出只包含 ASCII。
        print(f"{version} {number}")


if __name__ == "__main__":
    main()
