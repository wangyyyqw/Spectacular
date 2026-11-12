#!/usr/bin/env python3
"""构造可重复的大型 EPUB：短封面及单 XHTML 长章，无外部依赖。"""

import argparse
import hashlib
from pathlib import Path
import random
import struct
import zlib
import zipfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "apps/reader_mobile/dist/performance-stress.epub"
TITLE = "长章与复杂样式性能样本"
CSS = """
html, body { margin: 0; padding: 0; }
body { font-family: serif; font-size: 18px; line-height: 1.45; color: #253035; }
h1 { font-size: 1.4em; margin: 0 0 12px; }
h2 { font-size: 1.1em; margin: 0 0 6px; color: #285a60; }
p { margin: 4px 0; text-indent: 2em; }
.page h2 { page-break-before: always; break-before: page; }
.outer { border: 1px solid #719096; padding: 6px; margin: 0 0 5px; }
.inner { border-left: 3px solid #285a60; padding: 3px 6px; background: #f1f5f3; }
.emphasis { color: #7c3f2d; font-weight: bold; }
.figure { margin: 5px 0; text-align: center; }
.figure img { width: 112px; height: 70px; border: 1px solid #719096; }
.caption { margin: 2px 0; text-indent: 0; font-size: 0.75em; }
.float { float: right; width: 82px; margin: 0 0 4px 6px; }
.float img { width: 76px; height: 52px; }
.clear { clear: both; }
table { width: 100%; border-collapse: collapse; margin: 4px 0; font-size: 0.8em; }
th, td { border: 1px solid #719096; padding: 2px 4px; text-align: left; }
.note { font-size: 0.8em; color: #526066; text-indent: 0; }
"""


def png_chunk(kind, payload):
    checksum = zlib.crc32(kind + payload) & 0xffffffff
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)


def make_png(size, seed):
    """有效 RGB PNG；确定性纹理提供真实解码负担，文件没有虚假填充。"""
    random_source = random.Random(seed)
    rows = []
    for y in range(size):
        row = bytearray(random_source.randbytes(size * 3))
        # 左侧色带使缩略图可辨认；其余像素保留纹理，不易被 ZIP 压缩。
        stripe = bytes((40 + seed % 150, 70 + y * 100 // size, 100))
        row[:max(1, size // 8) * 3] = stripe * max(1, size // 8)
        rows.append(b"\x00" + row)
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(b"".join(rows), level=0))
            + png_chunk(b"IEND", b""))


def xhtml(title, body):
    return f'''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN">
<head><title>{title}</title><link rel="stylesheet" href="styles.css"/></head>
<body>{body}</body></html>'''


def section(index, image_count):
    image = index % image_count
    place = ("河岸", "山谷", "树林", "溪畔", "田野", "湖边", "村口")[index % 7]
    view = ("树影", "云霞", "炊烟", "山峰", "飞鸟")[index % 5]
    subject = ("花草", "石桥", "路标", "河流", "屋舍", "古树")[index % 6]
    figure = f'''<div class="figure{' float' if index % 11 == 0 else ''}">
<img src="images/texture-{image:03d}.png" alt="确定性色带纹理 {image + 1}"/>
<p class="caption">图 {image + 1}：纹理与色带</p></div>'''
    table = '''<table><tr><th>项目</th><th>观察内容</th></tr>
<tr><td>边框</td><td>连续且无遮挡</td></tr>
<tr><td>文字</td><td>正常换行与对齐</td></tr></table>''' if index % 10 == 0 else ""
    return f'''<section class="page" id="section-{index + 1}">
<h2>第 {index + 1:03d} 节：山间阅读札记</h2>
<div class="outer"><div class="inner">
{figure}<p>第 {index + 1:03d} 次行程沿着{place}向前延伸，远处的{view}映入眼帘。
旅人停在桥边翻开手中的书，<span class="emphasis">不同的段落与图像</span>
在纸页间交替出现，记录下{subject}的模样。</p>
<p>第 {index + 1:03d} 节正文用于观察连续排版、中文换行和嵌套边距。
翻页与跳转后应保持相同内容，边框、图片说明及表格不应遮住文字。</p>
<div class="clear"></div>{table}</div></div>
<p class="note">本节结束，下一节从新页开始。</p></section>'''


def package_document(sections, image_count, image_size, seed):
    identity = hashlib.sha256(
        f"{sections}:{image_count}:{image_size}:{seed}".encode()
    ).hexdigest()
    images = "".join(
        f'<item id="image-{i}" href="images/texture-{i:03d}.png" media-type="image/png"/>'
        for i in range(image_count)
    )
    return f'''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="book-id">urn:sha256:{identity}</dc:identifier>
<dc:title>{TITLE}</dc:title><dc:language>zh-CN</dc:language>
<dc:creator>性能测试夹具</dc:creator>
<meta property="dcterms:modified">2026-11-12T00:00:00Z</meta></metadata>
<manifest><item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
<item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
<item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>
<item id="style" href="styles.css" media-type="text/css"/>{images}</manifest>
<spine><itemref idref="cover"/><itemref idref="chapter"/></spine></package>'''


def write_entry(archive, name, content, *, stored=False):
    entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    entry.compress_type = zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED
    entry.external_attr = 0o100644 << 16
    archive.writestr(entry, content)


# 默认 271 节在正式引擎 360×600、18px 下实测为 200 页。
def build_epub(output, sections=271, image_count=48, image_size=1024, seed=20261112):
    if sections < 1 or image_count < 1 or image_size < 1:
        raise ValueError("节数、图片数和图片边长必须为正整数")
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    container = '''<?xml version="1.0" encoding="utf-8"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="OEBPS/package.opf"
media-type="application/oebps-package+xml"/></rootfiles></container>'''
    navigation = '''<nav xmlns:epub="http://www.idpf.org/2007/ops" epub:type="toc">
<h1>目录</h1><ol><li><a href="cover.xhtml">封面</a></li>
<li><a href="chapter.xhtml">单文件长章</a></li></ol></nav>'''
    with zipfile.ZipFile(output, "w") as archive:
        write_entry(archive, "mimetype", "application/epub+zip", stored=True)
        write_entry(archive, "META-INF/container.xml", container)
        write_entry(archive, "OEBPS/package.opf",
                    package_document(sections, image_count, image_size, seed))
        write_entry(archive, "OEBPS/styles.css", CSS)
        write_entry(archive, "OEBPS/cover.xhtml", xhtml(
            TITLE, f"<h1>{TITLE}</h1><p>单一正文文件，包含 {sections} 个分页段。</p>"))
        write_entry(archive, "OEBPS/nav.xhtml", xhtml("目录", navigation))
        write_entry(archive, "OEBPS/chapter.xhtml", xhtml(
            "单文件长章", "".join(section(i, image_count) for i in range(sections))))
        for index in range(image_count):
            write_entry(archive, f"OEBPS/images/texture-{index:03d}.png",
                        make_png(image_size, seed + index), stored=True)
    return output.stat().st_size


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--sections", type=int, default=271)
    parser.add_argument("--image-count", type=int, default=48)
    parser.add_argument("--image-size", type=int, default=1024)
    parser.add_argument("--seed", type=int, default=20261112)
    args = parser.parse_args()
    try:
        size = build_epub(args.output, args.sections, args.image_count, args.image_size, args.seed)
    except ValueError as error:
        parser.error(str(error))
    print(f"已生成：{args.output.resolve()}")
    print(f"大小：{size / (1 << 20):.2f} MiB；图像：{args.image_count} 张 {args.image_size}² RGB PNG")
    print(f"spine 0：短封面；spine 1：单 XHTML，{args.sections} 个内容段；seed={args.seed}")


if __name__ == "__main__":
    main()
