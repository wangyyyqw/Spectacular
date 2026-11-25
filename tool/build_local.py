"""本地打包 Android 和 Windows，同轮共用一个自动递增的内部版本号。"""

import argparse
import datetime
import os
import shutil
import subprocess
import zipfile
from pathlib import Path

from release_metadata import ROOT, artifact_name, reserve


def _flutter_candidates():
    """按优先级返回可能的 Flutter SDK 根目录。"""
    roots = []
    configured = os.environ.get("FLUTTER_ROOT")
    if configured:
        roots.append(Path(configured).expanduser())

    # 允许从仓库所在目录向外推导本地 SDK，例如 E:\\MTool\\SDK\\flutter。
    for parent in (ROOT, *ROOT.parents):
        roots.extend((parent / "SDK" / "flutter", parent / "flutter"))

    seen = set()
    for root in roots:
        resolved = root.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        yield resolved


def _find_flutter():
    """返回 Flutter 可执行文件路径和 SDK 根目录；找不到时返回 ``(None, None)``。"""
    for command in ("flutter", "flutter.bat"):
        executable = shutil.which(command)
        if executable:
            path = Path(executable).resolve()
            return str(path), path.parent.parent

    for root in _flutter_candidates():
        executable = root / "bin" / ("flutter.bat" if os.name == "nt" else "flutter")
        if executable.is_file():
            return str(executable), root
    return None, None


def _with_flutter_path(environment, sdk_root):
    """把 Flutter 和其 Dart SDK 加入子进程 PATH，避免依赖调用方的全局 PATH。"""
    if sdk_root is None:
        return environment
    bin_dir = sdk_root / "bin"
    dart_bin = bin_dir / "cache" / "dart-sdk" / "bin"
    current = environment.get("PATH", "").split(os.pathsep)
    additions = [str(bin_dir), str(dart_bin)]
    environment["PATH"] = os.pathsep.join(
        [*additions, *(entry for entry in current if entry and entry not in additions)]
    )
    return environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["all", "arm64", "winx64"],
                        default="all")
    parser.add_argument("--allow-downloads", action="store_true")
    args = parser.parse_args()
    if args.platform in ("all", "winx64") and os.name != "nt":
        parser.error("Windows 构建需要在 Windows 上执行")
    flutter, flutter_sdk = _find_flutter()
    bash = shutil.which("bash")
    if os.name == "nt":
        git_bash = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/bin/bash.exe"
        if git_bash.exists():
            bash = str(git_bash)
    if not flutter or (args.platform != "winx64" and not bash):
        parser.error("请将 Flutter、Python 和 Git Bash 加入 PATH")

    version, number = reserve()
    env = dict(os.environ, READER_RELEASE_VERSION=version,
               READER_RELEASE_NUMBER=str(number), PYTHONIOENCODING="utf-8")
    _with_flutter_path(env, flutter_sdk)
    app = ROOT / "apps/reader_mobile"
    dist = app / "dist"
    dist.mkdir(parents=True, exist_ok=True)
    print(f"本轮构建版本：{version}（{number}）", flush=True)
    if args.platform in ("all", "arm64"):
        command = [bash, "tool/build_apk.sh"]
        if args.allow_downloads:
            command.append("--allow-downloads")
        subprocess.run(command, cwd=ROOT, env=env, check=True)
    if args.platform in ("all", "winx64"):
        if args.allow_downloads:
            subprocess.run([flutter, "pub", "get"], cwd=app, env=env, check=True)
        build_time = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
        subprocess.run([
            flutter, "build", "windows", "--release", "--no-pub",
            f"--build-name={version}", f"--build-number={number}",
            f"--dart-define=APP_BUILD_TIME={build_time}",
        ], cwd=app, env=env, check=True)
        release = app / "build/windows/x64/runner/Release"
        if not (release / "reader_mobile.exe").is_file():
            raise RuntimeError("Windows 可执行文件缺失")
        output = dist / artifact_name("winx64", version, number)
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(release.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(release))
        print(f"已打包：{output}", flush=True)


if __name__ == "__main__":
    main()
