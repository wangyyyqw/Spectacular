"""从指定 ReaMicro Git 版本同步正式矢量路径，不修改参考仓库。"""

import argparse
import re
import subprocess
from pathlib import Path


def svg_path(text):
    tokens = re.findall(r"[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?", text)
    index, command, x, y, start_x, start_y = 0, "", 0, 0, 0, 0
    control, previous = None, ""
    result = ["Path()..fillType = PathFillType.evenOdd"]
    lengths = dict(M=2, L=2, H=1, V=1, C=6, S=4, Q=4, T=2, A=7)

    def number(value):
        return f"{value:.6f}".rstrip("0").rstrip(".") if value else "0"

    def call(method, *values):
        result.append(f"..{method}({', '.join(number(v) for v in values)})")

    while index < len(tokens):
        if tokens[index].isalpha():
            command = tokens[index]
            index += 1
        kind, relative = command.upper(), command.islower()
        if kind == "Z":
            result.append("..close()")
            x, y, control, previous, command = start_x, start_y, None, "Z", ""
            continue
        count = lengths[kind]
        args = list(map(float, tokens[index:index + count]))
        index += count
        old_x, old_y = x, y

        def point(offset):
            return args[offset] + (old_x if relative else 0), args[offset + 1] + (old_y if relative else 0)

        next_control = None
        if kind in ("M", "L"):
            x, y = point(0)
            call("moveTo" if kind == "M" else "lineTo", x, y)
            if kind == "M":
                start_x, start_y = x, y
                command = "l" if relative else "L"
        elif kind == "H":
            x = args[0] + (x if relative else 0)
            call("lineTo", x, y)
        elif kind == "V":
            y = args[0] + (y if relative else 0)
            call("lineTo", x, y)
        elif kind in ("C", "S"):
            first = point(0) if kind == "C" else (
                (2 * x - control[0], 2 * y - control[1])
                if control and previous in ("C", "S") else (x, y)
            )
            second = point(2 if kind == "C" else 0)
            x, y = point(4 if kind == "C" else 2)
            call("cubicTo", *first, *second, x, y)
            next_control = second
        elif kind in ("Q", "T"):
            first = point(0) if kind == "Q" else (
                (2 * x - control[0], 2 * y - control[1])
                if control and previous in ("Q", "T") else (x, y)
            )
            x, y = point(2 if kind == "Q" else 0)
            call("quadraticBezierTo", *first, x, y)
            next_control = first
        elif kind == "A":
            x, y = point(5)
            result.append(
                f"..arcToPoint(Offset({number(x)}, {number(y)}), "
                f"radius: Radius.elliptical({number(args[0])}, {number(args[1])}), "
                f"rotation: {number(args[2])}, "
                f"largeArc: {str(bool(args[3])).lower()}, clockwise: {str(bool(args[4])).lower()})"
            )
        control, previous = next_control, kind
    return "\n    ".join(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    parser.add_argument("--ref", default="origin/main")
    args = parser.parse_args()

    def read(name):
        return subprocess.check_output(
            ["git", "-C", str(args.checkout), "show", f"{args.ref}:{name}"]
        ).decode("utf-8")

    revision = subprocess.check_output(
        ["git", "-C", str(args.checkout), "rev-parse", args.ref], text=True
    ).strip()
    prefix = "app/src/main/java/com/reamicro/fix/"
    embedded = read(prefix + "hook/HostEmbeddedIcons.kt")
    names = {
        "Back": "arrowBack", "Import": "add", "Expanded": "chevronDown",
        "Collapsed": "chevronRight", "Close": "close", 
        "Link": "link",  "SearchResults": "listBulleted",
        "Edit2": "edit", "ImageOutline": "image", "DeleteOutline": "delete",
        "DeleteForever": "deleteSweep", "Copy": "copy", "NavigateNext": "arrowForward",
        "AutoAwesome": "autoFix",  "Check": "check",
    }
    paths = {}
    for name, body in re.findall(r'val (\w+) = icon\("\w[^"]*",\s*(.*?)\)\s*\n', embedded, re.S):
        if name in names:
            paths[names[name]] = svg_path("".join(re.findall(r'"([^"]*)"', body)))
    layout = read(prefix + "hook/discover/DiscoverLayoutArtwork.kt")
    for name, glyph in [("list", "listView"), ("grid", "gridView")]:
        text = re.search(rf'val {name} = listOf\([^"]*"([^"]+)"', layout).group(1)
        paths[glyph] = svg_path(text)

    # Miuix Regular 的原生路径，坐标和翻转直接转换为 Flutter Path。
    for name, glyph in [
        ("Play", "play"), ("Settings", "settings"), ("Info", "info"),
        ("Delete", "delete"), ("Sort", "sort"), ("SelectAll", "multiSelect"),
        ("Close", "close"), ("Contacts", "profile"),
    ]:
        text = read("third_party/miuix/upstream/miuix-icons/src/commonMain/kotlin/"
                    f"top/yukonga/miuix/kmp/icon/extended/{name}.kt")
        viewport = float(re.search(r"viewportWidth = ([\d.]+)f", text).group(1))
        flip = "scaleY = -1.0f" in text
        commands = []
        for method, raw in re.findall(r"PathNode\.(\w+)(?:\(([^)]*)\))?", text):
            if method == "Close":
                commands.append("Z")
                continue
            values = [float(v.strip().removesuffix("f")) for v in raw.split(",")]
            letter = {"MoveTo": "M", "LineTo": "L", "QuadTo": "Q",
                      "CurveTo": "C", "HorizontalTo": "H", "VerticalTo": "V"}[method]
            for i, value in enumerate(values):
                is_y = method == "VerticalTo" or (method != "HorizontalTo" and i % 2 == 1)
                values[i] = (viewport - value if flip and is_y else value) * 24 / viewport
            commands.append(letter + " ".join(map(str, values)))
        paths[glyph] = svg_path(" ".join(commands))

    output = [
        "part of 'app_glyph.dart';", "",
        f"// 来源：YGHFv/ReaMicro-Extend，版本 {revision}。",
        "// 由 tool/sync_reamicro_icons.py 同步，路径保留矢量精度。",
        "// Miuix Regular 路径采用 Apache-2.0，版权归 compose-miuix-ui contributors。",
        "final _reaMicroPaths = <AppGlyph, Path>{",
    ]
    for glyph, path in paths.items():
        output.append(f"  AppGlyph.{glyph}: {path},")
    output += [
        "};", "",
        "// 发现继续使用本项目的指南针图标及选中态。",
        "bool _drawReaMicroGlyph(AppGlyph glyph, AppIconCanvas canvas) {",
        "  final path = _reaMicroPaths[glyph];",
        "  if (path == null) return false;",
        "  canvas._canvas.drawPath(path, _fillPaint(canvas.color));",
        "  return true;",
        "}", "",
    ]
    target = Path(__file__).resolve().parents[1] / "packages/reader_ui/lib/icons/rea_micro_glyph.dart"
    target.write_text("\n".join(output), encoding="utf-8")
    print(f"已同步 {len(paths)} 个矢量图标，来源版本 {revision}")


if __name__ == "__main__":
    main()
