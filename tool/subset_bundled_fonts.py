#!/usr/bin/env python3
"""从官方思源宋体 2.003R 生成中文阅读字库，需要 fonttools==4.68.0。"""

import argparse
import hashlib
import json
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont


UPSTREAM = {
    "Regular": "78aa7a328fd974df2d688c8a9fd74a33d8334dfa84ab24d9d11efb2ffc464117",
    "Bold": "706b8c0de2deff6cbc0c87e2cdedfd33a78b7ffd76cebb4549012f197ba611fe",
}
HANGUL_RANGES = (
    (0x1100, 0x11FF), (0x3130, 0x318F), (0xA960, 0xA97F),
    (0xAC00, 0xD7FF), (0xFFA0, 0xFFDC),
)
HAN_RANGES = (
    (0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF),
    (0x20000, 0x2FA1F), (0x30000, 0x323AF),
)


def in_ranges(code, ranges):
    return any(start <= code <= end for start, end in ranges)


def rename_font(font, family, weight):
    """保留原始版权及许可；修改派生字体的名称，避免使用保留字体名 Source。"""
    compact = family.replace(" ", "")
    names = {
        1: family, 2: weight, 3: f"2.003;Moyu;{compact}-{weight}",
        4: f"{family} {weight}", 6: f"{compact}-{weight}",
        16: family, 17: weight,
    }
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    cff = font["CFF "].cff
    cff.fontNames = [names[6]]
    for top in cff.topDictIndex:
        top.FamilyName = family
        top.FullName = names[4]
        for dictionary in getattr(top, "FDArray", []):
            if hasattr(dictionary, "FontName"):
                dictionary.FontName = dictionary.FontName.replace(
                    "SourceHanSerifSC", compact
                ).replace("SourceHanSansSC", compact)


def build_font(source, output, weight):
    expected = UPSTREAM[weight]
    if hashlib.sha256(source.read_bytes()).hexdigest() != expected:
        raise ValueError(f"{source} 不是指定的官方 2.003R 原始字体")
    font = TTFont(source, recalcTimestamp=False)
    original = set(font.getBestCmap())
    keep = {code for code in original if not in_ranges(code, HANGUL_RANGES)}
    selectors = {
        selector
        for table in font["cmap"].tables if table.format == 14
        for selector in table.uvsDict
    }
    options = subset.Options()
    features = {
        entry.FeatureTag
        for tag in ("GSUB", "GPOS")
        for entry in font[tag].table.FeatureList.FeatureRecord
    }
    options.layout_features = sorted(features - {"aalt", "ljmo", "tjmo", "vjmo"})
    options.layout_scripts = ["DFLT"] + [
        f"{script}.{language}"
        for script in ("hani", "latn", "grek", "cyrl", "kana")
        for language in ("dflt", "ZHS", "ZHT", "ZHH")
    ]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    options.notdef_outline = True
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=keep | selectors)
    worker.subset(font)
    rename_font(font, "Moyu Serif", weight)
    output.parent.mkdir(parents=True, exist_ok=True)
    font.save(output)
    font.close()
    return verify_font(source, output, original, keep)


def verify_font(source, output, original, keep):
    """检查全部保留码点及其默认字形，避免只用常用字样例掩盖缺字。"""
    with TTFont(source) as before, TTFont(output) as after:
        old_map, new_map = before.getBestCmap(), after.getBestCmap()
        if set(new_map) != keep:
            raise ValueError(f"{output} 的字符覆盖与保留清单不一致")
        variants = lambda font: {
            (selector, code)
            for table in font["cmap"].tables if table.format == 14
            for selector, entries in table.uvsDict.items()
            for code, _ in entries if code in keep
        }
        if variants(before) != variants(after):
            raise ValueError(f"{output} 的异体字序列发生丢失")
        old_chars = before["CFF "].cff.topDictIndex[0].CharStrings
        new_chars = after["CFF "].cff.topDictIndex[0].CharStrings
        old_set, new_set = before.getGlyphSet(), after.getGlyphSet()
        for code in sorted(keep):
            old_name, new_name = old_map[code], new_map[code]
            old_glyph, new_glyph = old_chars[old_name], new_chars[new_name]
            if old_glyph.calcBounds(old_set) != new_glyph.calcBounds(new_set):
                raise ValueError(f"U+{code:04X} 的字形边界发生变化")
            if before["hmtx"][old_name] != after["hmtx"][new_name]:
                raise ValueError(f"U+{code:04X} 的水平度量发生变化")
            if before["vmtx"][old_name] != after["vmtx"][new_name]:
                raise ValueError(f"U+{code:04X} 的竖排度量发生变化")
        result = {
            "file": output.name,
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
            "bytes": output.stat().st_size,
            "glyphs": len(after.getGlyphOrder()),
            "characters": len(keep),
            "han_characters": sum(in_ranges(code, HAN_RANGES) for code in keep),
            "removed_characters": len(original - keep),
            "variation_sequences": len(variants(after)),
            "weight": after["OS/2"].usWeightClass,
        }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    for weight in UPSTREAM:
        result = build_font(
            args.source_dir / f"SourceHanSerifSC-{weight}.otf",
            args.output_dir / f"MoyuSerif-{weight}.otf",
            weight,
        )
        print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
