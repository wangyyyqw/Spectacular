#!/usr/bin/env python3
"""把 hyph_en_US.dic 转成 reader_core 内嵌的 Dart 常量。"""

from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "packages/reader_core/third_party/hyph_en_US/hyph_en_US.dic"
OUTPUT = ROOT / "packages/reader_core/lib/layout/en_us_hyphenation.dart"


def main() -> None:
    patterns = []
    for line in SOURCE.read_text(encoding="utf-8").splitlines():
        value = line.strip()
        if not value or value.startswith("%"):
            continue
        # 元数据行都是大写指令，Patterns 从字母或句点开始。
        if not (value[0] == "." or value[0].isalpha() or value[0].isdigit()):
            continue
        if value.split(" ", 1)[0].isupper():
            continue
        if "'''" in value:
            raise ValueError(f"无法写入 Dart 原始字符串：{value}")
        patterns.append(value)

    body = "\n".join(patterns)
    OUTPUT.write_text(
        "// 由 tool/generate_en_us_hyphenation.py 生成，请勿手改。\n"
        "// 数据：hyph_en_US.dic，BSD-style 许可；来源与完整声明见\n"
        "// packages/reader_core/third_party/hyph_en_US/README.txt。\n\n"
        "const enUsHyphenationPatterns = r'''\n"
        f"{body}\n"
        "''';\n",
        encoding="utf-8",
    )
    print(f"写入 {len(patterns)} 条模式：{OUTPUT}")


if __name__ == "__main__":
    main()
