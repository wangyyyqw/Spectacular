#!/usr/bin/env python3
"""重建 test_corpus 下的最小 EPUB 样本与 manifest.json。

文本均为自写原创内容，放弃著作权（CC0-1.0）；broken-resource 为故意破损的自建测试样本。
不依赖第三方 Python 库：ZIP 由 zip 命令完成（-X0 存 mimetype，-Xr9 压缩其余），
PNG 由标准库生成；多看全屏样本复用 assets/ 下的原创 JPEG。

用法：python3 tests/corpus/build_epubs.py
"""

from __future__ import annotations

import hashlib
import json
import shutil
import struct
import subprocess
import tempfile
import uuid
import zlib
from pathlib import Path
from xml.etree import ElementTree

REPO_ROOT = Path(__file__).resolve().parents[2]
CORPUS_DIR = REPO_ROOT / "test_corpus"
ASSET_DIR = Path(__file__).resolve().parent / "assets"
MIMETYPE = b"application/epub+zip"


# ---------------------------------------------------------------- 通用工具

def esc(text: str) -> str:
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def book_uuid(book_id: str) -> str:
    return f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, 'spectacular-test-corpus/' + book_id)}"


def xhtml3(title: str, body: str, css_href: str | None = None) -> str:
    link = f'<link rel="stylesheet" type="text/css" href="{css_href}"/>' if css_href else ""
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN" lang="zh-CN">
<head>
<meta charset="utf-8"/>
<title>{esc(title)}</title>
{link}
</head>
<body>
{body}
</body>
</html>
"""


def xhtml2(title: str, body: str, css_href: str | None = None) -> str:
    link = f'<link rel="stylesheet" type="text/css" href="{css_href}"/>' if css_href else ""
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN">
<head>
<title>{esc(title)}</title>
{link}
</head>
<body>
{body}
</body>
</html>
"""


def container_xml() -> str:
    return """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""


def nav_xhtml(title: str, entries: list[tuple[str, str]]) -> str:
    items = "\n".join(
        f'      <li><a href="{href}">{esc(text)}</a></li>' for text, href in entries
    )
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN" lang="zh-CN">
<head>
<meta charset="utf-8"/>
<title>{esc(title)}</title>
</head>
<body>
  <nav epub:type="toc" id="toc">
    <h1>目录</h1>
    <ol>
{items}
    </ol>
  </nav>
  <nav epub:type="landmarks" hidden="hidden">
    <ol>
      <li><a epub:type="bodymatter" href="{entries[0][1]}">正文</a></li>
    </ol>
  </nav>
</body>
</html>
"""


def opf3(
    book: dict,
    manifest: list[dict],
    spine: list[str],
    extra_meta: str = "",
    spine_properties: dict[str, str] | None = None,
) -> str:
    items = "\n".join(
        f'    <item id="{m["id"]}" href="{m["href"]}" media-type="{m["media_type"]}"'
        + (f' properties="{m["properties"]}"' if m.get("properties") else "")
        + "/>"
        for m in manifest
    )
    spine_items = "\n".join(
        f'    <itemref idref="{sid}"'
        + (
            f' properties="{spine_properties[sid]}"'
            if spine_properties and sid in spine_properties
            else ""
        )
        + "/>"
        for sid in spine
    )
    return f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="zh-CN">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">{book["uuid"]}</dc:identifier>
    <dc:title>{esc(book["title"])}</dc:title>
    <dc:language>zh-CN</dc:language>
    <dc:creator>{esc(book["author"])}</dc:creator>
    <dc:rights>{esc(book["license"])}</dc:rights>
    <dc:description>{esc(book["description"])}</dc:description>
    <meta property="dcterms:modified">2026-10-22T00:00:00Z</meta>
{extra_meta}  </metadata>
  <manifest>
{items}
  </manifest>
  <spine>
{spine_items}
  </spine>
</package>
"""


def opf2(book: dict, manifest: list[dict], spine: list[str], guide: str) -> str:
    items = "\n".join(
        f'    <item id="{m["id"]}" href="{m["href"]}" media-type="{m["media_type"]}"/>'
        for m in manifest
    )
    spine_items = "\n".join(f'    <itemref idref="{sid}"/>' for sid in spine)
    return f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="BookId">{book["uuid"]}</dc:identifier>
    <dc:title>{esc(book["title"])}</dc:title>
    <dc:language>zh-CN</dc:language>
    <dc:creator opf:role="aut">{esc(book["author"])}</dc:creator>
    <dc:rights>{esc(book["license"])}</dc:rights>
  </metadata>
  <manifest>
{items}
  </manifest>
  <spine toc="ncx">
{spine_items}
  </spine>
  <guide>
{guide}
  </guide>
</package>
"""


def ncx(book: dict, entries: list[tuple[str, str, str]]) -> str:
    points = "\n".join(
        f"""    <navPoint id="{pid}" playOrder="{i}">
      <navLabel><text>{esc(text)}</text></navLabel>
      <content src="{src}"/>
    </navPoint>"""
        for i, (pid, text, src) in enumerate(entries, start=1)
    )
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="zh-CN">
  <head>
    <meta name="dtb:uid" content="{book["uuid"]}"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>{esc(book["title"])}</text></docTitle>
  <navMap>
{points}
  </navMap>
</ncx>
"""


def png_rgb(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def xhtml_single_image(title: str, image_href: str) -> str:
    """全屏页正文只保留一个图片元素，不产生可见空白文本节点。"""
    return (
        '<?xml version="1.0" encoding="utf-8"?>'
        '<!DOCTYPE html>'
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN" lang="zh-CN">'
        f"<head><meta charset=\"utf-8\"/><title>{esc(title)}</title></head>"
        f'<body><img src="{image_href}" alt=""/></body></html>'
    )


# ---------------------------------------------------------------- 样本定义

BASIC_CSS = """body { margin: 1em 1.2em; line-height: 1.7; }
h1 { text-align: center; margin: 1.2em 0 1em; font-size: 1.4em; }
p { text-indent: 2em; margin: 0.5em 0; }
"""

BASIC_CHAPTERS = [
    (
        "chapter1",
        "第一章 山径",
        [
            "清晨的雾还没有散，石阶从村口一直铺到半山，像一条被谁轻轻放下的灰带子。",
            "阿禾背着竹篓，沿石阶往上走。篓里装着两只粗陶罐，罐口用麻布扎紧，走一步便轻轻碰响一声。",
            "路边的野草挂着水珠，裤脚很快就湿了。她并不在意，只把步子放慢，免得陶罐磕在石头上。",
            "半山有一处废弃的亭子，柱子歪着，顶上的瓦缺了大半。阿禾在那里歇了一会儿，听见远处溪水的声音。",
            "雾散的时候，山下的屋顶一间间露出来，青灰的瓦在日光里发亮。她数了数，还是那二十七间。",
            "再往上走一炷香的工夫，就到了外婆住的地方。院门虚掩着，门后传来柴火噼啪的响声。",
        ],
    ),
    (
        "chapter2",
        "第二章 溪桥",
        [
            "溪水从两块大石之间穿过，声音很急，落到下面的深潭里，便只剩下闷闷的一响。",
            "桥是木头的，只有三步宽，两侧没有栏杆。阿禾第一次独自过桥时，蹲在桥头看了很久。",
            "外婆说，这座桥比村里最老的老人还要老。桥板换过许多回，桥墩却一直没有动。",
            "春天涨水的时候，溪水会漫到桥面。村里人便把桥板抽掉两块，等水退了再铺回去。",
            "阿禾把陶罐放在桥中央，自己坐在桥边，把脚垂下去。水汽从下面升上来，凉丝丝的。",
            "她想起小时候在这里丢过一只布鞋。鞋子顺水漂走，转眼就看不见了，像从来没有存在过。",
        ],
    ),
    (
        "chapter3",
        "第三章 归灯",
        [
            "下山的时候，日头已经偏西。阿禾的竹篓空了，走起来轻快许多。",
            "村口的灯一盏一盏亮起来。最早亮的是杂货铺，其次是祠堂，最后才是各家各户的窗子。",
            "她走到自家门前，看见母亲站在灯下纳鞋底。灯芯有些短了，火苗一跳一跳的。",
            "母亲问她，外婆的身子可好。她说好，还能自己劈柴，只是膝盖遇到阴天会疼。",
            "饭是南瓜粥，配一碟腌萝卜。阿禾吃了两碗，把白天在山上的事一件件说给母亲听。",
            "夜里起风，窗纸轻轻响。她躺在床上，觉得自己还走在那条石阶上，一步一步，数着二十七间屋顶。",
        ],
    ),
]

STYLES_CSS = """body {
  margin: 2em 2.5em 2em 2.5em;
  line-height: 1.8;
  font-family: serif;
}
h1 {
  color: #1a4d7a;
  text-align: center;
  margin: 2em 0 1em 0;
  font-size: 1.6em;
}
h2 {
  color: #33691e;
  text-align: left;
  margin: 1.6em 0 0.6em 0;
}
p {
  text-indent: 2em;
  text-align: justify;
  margin: 0.4em 0;
}
p.center { text-align: center; text-indent: 0; }
p.right { text-align: right; text-indent: 0; }
p.tight { line-height: 1.2; }
p.roomy { line-height: 2.4; margin: 1.5em 0; }
span.color { color: #b03030; }
span.bold { font-weight: bold; }
span.italic { font-style: italic; }
span.both { font-weight: bold; font-style: italic; color: #2e7d32; }
blockquote { margin: 1em 3em; text-indent: 0; color: #555555; }
"""

STYLES_BODY = """<h1>样式练习册</h1>
<p>这一段用来验证首行缩进与两端对齐。文字需要足够长，才能看出每一行末尾是否被拉齐，以及行与行之间的距离是否按样式表生效。缩进应当只出现在每一段的第一行。</p>
<h2>一、行内样式</h2>
<p>这里有<span class="bold">加粗的文字</span>，有<span class="italic">倾斜的文字</span>，也有<span class="both">同时加粗并倾斜而且带颜色的文字</span>，还有<span class="color">单独使用颜色的文字</span>。它们都应当出现在同一行内，不改变段落结构。</p>
<h2>二、对齐与行高</h2>
<p class="center">这一行居中，并且取消首行缩进。</p>
<p class="right">这一行靠右，用来检查 text-align 的取值。</p>
<p class="tight">这一行行高较紧，行距是正常值的六成左右。若行高被忽略，这一段会与上下两段显得一样松。</p>
<p class="roomy">这一行行高较松，上下外边距也更大。段落之间的距离应当明显拉开。</p>
<h2>三、外边距与引用</h2>
<blockquote>引用的文字整体向内缩进，左右各留出空白，首行不再缩进。这一段用来检查 margin 的四方向取值。</blockquote>
<p>最后一段回到普通样式，用来观察前面的外边距是否把段落推得过远。</p>
"""

TABLE_CSS = """body { margin: 1.2em; line-height: 1.7; }
h1 { text-align: center; font-size: 1.4em; }
table { border-collapse: collapse; width: 100%; margin: 1em 0; }
th, td { border: 1px solid #666666; padding: 0.4em 0.6em; text-align: left; }
th { background-color: #e8eef3; }
caption { caption-side: top; margin-bottom: 0.5em; }
figure { margin: 1.2em 0; text-align: center; }
figcaption { font-size: 0.9em; color: #555555; }
"""

TABLE_BODY = """<h1>表格与插图样例</h1>
<p>下面这张表使用 colspan 合并表头，并保留一行普通数据行，用来检查列宽分配与单元格边框。</p>
<table>
  <caption>山间物产登记表</caption>
  <thead>
    <tr>
      <th colspan="2">名称与产地</th>
      <th>数量</th>
      <th>备注</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>粗陶罐</td>
      <td>后山窑口</td>
      <td>12</td>
      <td>罐口有麻布</td>
    </tr>
    <tr>
      <td>干笋</td>
      <td>溪桥村</td>
      <td>8</td>
      <td>晾晒三日</td>
    </tr>
    <tr>
      <td>野蜂蜜</td>
      <td>北坡岩下</td>
      <td>3</td>
      <td>陶罐装</td>
    </tr>
  </tbody>
</table>
<figure>
  <img src="images/teal.png" alt="一块深青色的方形色块" width="64" height="64"/>
  <figcaption>图一：8×8 像素的 PNG 测试图片放大显示。</figcaption>
</figure>
<p>图片位于 images/teal.png，仅用于验证 manifest 中的图片资源能否被正确解析与绘制。</p>
"""

NCX_CSS = """body { margin: 1.5em; line-height: 1.7; }
h1 { text-align: center; font-size: 1.4em; }
p { text-indent: 2em; margin: 0.5em 0; }
"""

NCX_CHAPTERS = [
    (
        "chapter1",
        "第一章 旧纸",
        [
            "书架的第三层放着一叠旧纸，边角发黄，用棉线草草缝在一起。",
            "纸上的字是竖着写的，从右往左读。墨色已经淡了，个别笔画要凑近才看得清。",
            "第一页只有一行字：某年某月，雨下了七日。后面便再也没有提到那场雨。",
            "翻过去是几张家用的账目，记着米、盐、灯油，还有一笔给木匠的工钱。",
        ],
    ),
    (
        "chapter2",
        "第二章 旧信",
        [
            "账目中间夹着一封信，没有信封，折成四折。收信人的名字被水浸过，模糊成一片。",
            "信里说，山上的路已经修好，来年开春可以通车。写信的人似乎很高兴，用了三个感叹号。",
            "信的末尾又补了一句：不必回信，我这里一切都好。字迹比正文潦草一些。",
            "这封信没有落款，也没有日期。它夹在账目里，像一个没有讲完的句子。",
        ],
    ),
    (
        "chapter3",
        "第三章 旧灯",
        [
            "旧纸的最下面是一张灯会的图样，画着六角宫灯，骨架与糊纸的次序都标得清楚。",
            "图样背面写着尺寸，字很小，却一笔不苟。可以想见画图的人坐在灯下，量了又量。",
            "后来灯会不再办了。这张图样被收进书架，和账目、旧信放在一起。",
            "再后来，连书架也搬走了。只剩这叠纸，被人用棉线重新缝过一回。",
        ],
    ),
]

BROKEN_CSS = """body { margin: 1.2em; line-height: 1.7; }
h1 { text-align: center; font-size: 1.4em; }
p { text-indent: 2em; margin: 0.5em 0; }
"""

VERTICAL_CSS = """html, body {
  writing-mode: vertical-rl;
  -webkit-writing-mode: vertical-rl;
  text-orientation: upright;
  line-height: 1.9;
  margin: 1em 1.5em;
  font-family: serif;
}
h1 {
  font-size: 1.5em;
  margin: 0 0 1em 0;
  text-align: start;
}
p {
  margin: 0 0.6em;
  text-indent: 2em;
}
ruby { ruby-position: over; }
rt { font-size: 0.55em; }
.punct { font-feature-settings: "vert" 1; }
"""

VERTICAL_BODY = """<h1>竖排与注音</h1>
<p>这一段用于检查竖排方向。文字应当从上往下排列，行与行之间由右向左推进。标点符号需要随文字旋转或保持直立，不能压在字上。</p>
<p>这里有注音：<ruby>山<rt>shān</rt></ruby><ruby>川<rt>chuān</rt></ruby><ruby>异<rt>yì</rt></ruby><ruby>域<rt>yù</rt></ruby>，四个字各带一段拼音。注音应当出现在字的右侧上方，不挤占正文的行距。</p>
<p class="punct">标点测试：「引号」、顿号、逗号，句号。分号；冒号：问号？叹号！破折号——省略号……以及括号（如此）。</p>
<p>竖排时，英文与数字通常需要横排或整体旋转。这里放一组数字：一二三四五，六七八九十。再放一组阿拉伯数字：2026 年 10 月。</p>
"""


def base_book(**kwargs) -> dict:
    book = {
        "id": "",
        "file": "",
        "title": "",
        "language": "zh-CN",
        "source": "自建原创文本（无版权，按 CC0-1.0 放弃著作权）",
        "license": "CC0-1.0",
        "features": [],
        "author": "Spectacular 测试样本库",
        "description": "",
    }
    book.update(kwargs)
    book["uuid"] = book_uuid(book["id"])
    return book


def build_epub3_simple(book: dict, css: str, chapters: list[tuple[str, str, list[str]]]) -> dict[str, bytes]:
    files: dict[str, bytes] = {"META-INF/container.xml": container_xml().encode()}
    files["OEBPS/styles/main.css"] = css.encode()
    manifest = [
        {"id": "css", "href": "styles/main.css", "media_type": "text/css"},
        {"id": "nav", "href": "nav.xhtml", "media_type": "application/xhtml+xml", "properties": "nav"},
    ]
    entries = []
    for cid, title, paras in chapters:
        href = f"text/{cid}.xhtml"
        body = f"<h1>{esc(title)}</h1>\n" + "\n".join(f"<p>{esc(p)}</p>" for p in paras)
        files[f"OEBPS/{href}"] = xhtml3(title, body, "../styles/main.css").encode()
        manifest.append({"id": cid, "href": href, "media_type": "application/xhtml+xml"})
        entries.append((title, href))
    files["OEBPS/nav.xhtml"] = nav_xhtml(book["title"], entries).encode()
    files["OEBPS/content.opf"] = opf3(book, manifest, [c[0] for c in chapters]).encode()
    return files


def make_basic() -> tuple[dict, dict[str, bytes]]:
    book = base_book(
        id="basic",
        file="basic.epub",
        title="山海小记",
        description="三章纯文本短篇，覆盖 OPF、spine 与 EPUB3 nav。",
        features=["EPUB3", "OPF", "spine", "nav", "三章", "纯文本", "中文"],
    )
    return book, build_epub3_simple(book, BASIC_CSS, BASIC_CHAPTERS)


def make_styles() -> tuple[dict, dict[str, bytes]]:
    book = base_book(
        id="styles",
        file="styles.epub",
        title="样式练习册",
        description="覆盖标题、粗斜体、颜色、行高、缩进、对齐与外边距的排版样式样本。",
        features=[
            "EPUB3", "CSS", "标题", "粗体", "斜体", "颜色", "行高",
            "text-indent", "text-align", "margin", "blockquote",
        ],
    )
    files = build_epub3_simple(book, STYLES_CSS, [("chapter1", "样式练习册", [])])
    # 用自定义正文覆盖上面生成的章节页
    files["OEBPS/text/chapter1.xhtml"] = xhtml3("样式练习册", STYLES_BODY, "../styles/main.css").encode()
    files["OEBPS/nav.xhtml"] = nav_xhtml(book["title"], [("样式练习册", "text/chapter1.xhtml")]).encode()
    return book, files


def make_table() -> tuple[dict, dict[str, bytes]]:
    book = base_book(
        id="table",
        file="table.epub",
        title="表格与插图样例",
        description="覆盖带 colspan 的表格、caption 与小尺寸 PNG 图片。",
        features=["EPUB3", "table", "colspan", "caption", "PNG 图片", "图文混排"],
    )
    files: dict[str, bytes] = {
        "META-INF/container.xml": container_xml().encode(),
        "OEBPS/styles/main.css": TABLE_CSS.encode(),
        "OEBPS/text/chapter1.xhtml": xhtml3("表格与插图样例", TABLE_BODY, "../styles/main.css").encode(),
        "OEBPS/images/teal.png": png_rgb(8, 8, (31, 111, 139)),
    }
    manifest = [
        {"id": "css", "href": "styles/main.css", "media_type": "text/css"},
        {"id": "nav", "href": "nav.xhtml", "media_type": "application/xhtml+xml", "properties": "nav"},
        {"id": "chapter1", "href": "text/chapter1.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "teal", "href": "images/teal.png", "media_type": "image/png"},
    ]
    files["OEBPS/nav.xhtml"] = nav_xhtml(book["title"], [("表格与插图样例", "text/chapter1.xhtml")]).encode()
    files["OEBPS/content.opf"] = opf3(book, manifest, ["chapter1"]).encode()
    return book, files


def make_toc_ncx() -> tuple[dict, dict[str, bytes]]:
    book = base_book(
        id="toc-ncx",
        file="toc-ncx.epub",
        title="旧式目录",
        description="EPUB2 样本：OPF 2.0、toc.ncx 与 guide，无 nav。",
        features=["EPUB2", "OPF 2.0", "toc.ncx", "NCX", "guide", "无 nav", "三章"],
    )
    files: dict[str, bytes] = {
        "META-INF/container.xml": container_xml().encode(),
        "OEBPS/styles/main.css": NCX_CSS.encode(),
    }
    entries = []
    for cid, title, paras in NCX_CHAPTERS:
        href = f"text/{cid}.xhtml"
        body = f"<h1>{esc(title)}</h1>\n" + "\n".join(f"<p>{esc(p)}</p>" for p in paras)
        files[f"OEBPS/{href}"] = xhtml2(title, body, "../styles/main.css").encode()
        entries.append((cid, title, href))
    manifest = [
        {"id": "ncx", "href": "toc.ncx", "media_type": "application/x-dtbncx+xml"},
        {"id": "css", "href": "styles/main.css", "media_type": "text/css"},
    ]
    manifest += [
        {"id": cid, "href": href, "media_type": "application/xhtml+xml"} for cid, _, href in entries
    ]
    files["OEBPS/toc.ncx"] = ncx(book, entries).encode()
    guide = '    <reference type="toc" title="目录" href="text/chapter1.xhtml"/>'
    files["OEBPS/content.opf"] = opf2(book, manifest, [c[0] for c in entries], guide).encode()
    return book, files


def make_broken() -> tuple[dict, dict[str, bytes]]:
    book = base_book(
        id="broken-resource",
        file="broken-resource.epub",
        title="破损之书",
        description="容量容错样本：manifest 引用不存在的图片，NCX 含指向不存在章节的坏链接。",
        source="自建测试样本（故意破损，无版权）",
        license="自建测试样本",
        features=["EPUB3", "容错", "manifest 引用缺失图片", "NCX 坏链接", "缺失资源", "坏目录项"],
    )
    chapter1 = (
        "<h1>第一章 尚存的一页</h1>\n"
        "<p>这一页是完整的。它用来确认：即使书里存在损坏的资源，正常的章节仍然应当可以打开与阅读。</p>\n"
        "<p>下面这张图片在 manifest 中有记录，但压缩包里没有对应的文件。阅读器应当跳过它，或显示占位图，而不是让整章失败。</p>\n"
        '<p><img src="images/missing.png" alt="一张并不存在的图片"/></p>\n'
        "<p>目录里还有一项指向不存在的第三章。点击它时应当停留在原处，或给出提示，不应崩溃。</p>"
    )
    files: dict[str, bytes] = {
        "META-INF/container.xml": container_xml().encode(),
        "OEBPS/styles/main.css": BROKEN_CSS.encode(),
        "OEBPS/text/chapter1.xhtml": xhtml3("第一章 尚存的一页", chapter1, "../styles/main.css").encode(),
    }
    manifest = [
        {"id": "css", "href": "styles/main.css", "media_type": "text/css"},
        {"id": "nav", "href": "nav.xhtml", "media_type": "application/xhtml+xml", "properties": "nav"},
        {"id": "ncx", "href": "toc.ncx", "media_type": "application/x-dtbncx+xml"},
        {"id": "chapter1", "href": "text/chapter1.xhtml", "media_type": "application/xhtml+xml"},
        # 故意声明一张不存在的图片，且不写入 ZIP
        {"id": "missing-image", "href": "images/missing.png", "media_type": "image/png"},
    ]
    # nav 本身保持正常；坏链接只放在 NCX 里，便于单独验证 NCX 的容错路径
    files["OEBPS/nav.xhtml"] = nav_xhtml(
        book["title"], [("第一章 尚存的一页", "text/chapter1.xhtml")]
    ).encode()
    files["OEBPS/toc.ncx"] = ncx(
        book,
        [
            ("nav1", "第一章 尚存的一页", "text/chapter1.xhtml"),
            ("nav2", "第三章 散佚", "text/chapter3.xhtml"),
        ],
    ).encode()
    files["OEBPS/content.opf"] = opf3(book, manifest, ["chapter1"]).encode()
    return book, files


def make_cjk_vertical() -> tuple[dict, dict[str, bytes]]:
    book = base_book(
        id="cjk-vertical",
        file="cjk-vertical.epub",
        title="竖排与注音",
        description="覆盖 ruby 注音、writing-mode: vertical-rl 竖排与中文标点。",
        features=["EPUB3", "ruby", "ruby-position", "竖排", "writing-mode: vertical-rl", "中文标点"],
    )
    files = build_epub3_simple(book, VERTICAL_CSS, [("chapter1", "竖排与注音", [])])
    files["OEBPS/text/chapter1.xhtml"] = xhtml3("竖排与注音", VERTICAL_BODY, "../styles/main.css").encode()
    files["OEBPS/nav.xhtml"] = nav_xhtml(book["title"], [("竖排与注音", "text/chapter1.xhtml")]).encode()
    return book, files


FOOTNOTE_CSS = """body { margin: 1em 1.2em; line-height: 1.6; }
h1 { text-align: center; font-size: 1.35em; margin: 0.6em 0 1em; }
h2 { font-size: 1.08em; margin: 1.2em 0 0.45em; color: #28536b; }
p { margin: 0.45em 0; text-indent: 0; }
a { color: #8b3f27; text-decoration: underline; }
img.duokan-footnote,
img.qqreader-footnote,
img.zhangyue-footnote,
img.epub-footnote {
  width: 18px;
  height: 18px;
  margin: 0 0.2em;
  vertical-align: middle;
}
span.reader {
  display: inline-block;
  width: 19px;
  height: 19px;
  margin: 0 0.25em;
  vertical-align: middle;
  background-image: url("../images/note-icon.png");
  background-size: 100% 100%;
}
"""

FOOTNOTE_DEMO_BODY = """<h1>注释结构总测</h1>
<p>本页每一行对应一种注释入口。正常阅读时，下方注文和跨文档定义页的注文都不得进入正文；点击注号、链接或图标后应弹出“脚注/尾注”窗口。</p>
<p><a href="notes.xhtml">普通链接：打开跨文档注释定义页</a>　<a href="normal-links.xhtml">普通链接：无注释章节</a></p>

<h2>标准 EPUB 与通用结构</h2>
<p>01 EPUB3 noteref 脚注<a id="ref-epub3" epub:type="noteref" href="#fn-epub3">〔01〕</a></p>
<p>02 DPUB-ARIA 脚注<a id="ref-dpub" role="doc-noteref" href="#fn-dpub">〔02〕</a></p>
<p>03 EPUB2 上标数字链接<sup><a id="ref-epub2" href="#fn2">[03]</a></sup></p>
<p>04 跨 XHTML 标准尾注<a id="ref-cross" epub:type="noteref" href="notes.xhtml#fn-cross">〔04〕</a></p>
<p>05 EPUB3 rearnote 尾注<a id="ref-rear" epub:type="noteref" href="notes.xhtml#fn-rear">〔05〕</a></p>
<p>06 通用 epub-footnote 类名<a id="ref-generic" class="epub-footnote" href="notes.xhtml#fn-generic">〔06〕</a></p>
<p>07 dl/dt/dd 注释列表<a id="ref-dl" epub:type="noteref" href="notes.xhtml#fn-dl">〔07〕</a></p>
<p>08 title 属性兼容注<a title="这是写在 title 属性里的旧式弹注正文。">〔08〕</a></p>

<h2>多看、QQ/微信读书、掌阅</h2>
<p>09 多看文字注<a id="ref-duokan" class="duokan-footnote" href="#fn-duokan">〔09〕</a></p>
<p>10 多看图片注 <img class="duokan-footnote" alt="这是多看图片注，注文放在 alt 属性中。" src="../images/note-icon.png"/> 点图标</p>
<p>11 QQ/微信读书图片注 <img class="qqreader-footnote" alt="这是 QQ 阅读或微信读书图片注，注文放在 alt 属性中。" src="../images/note-icon.png"/> 点图标</p>
<p>12 掌阅通用弹注法<sup><a id="ref-zy" class="duokan-footnote" epub:type="noteref" href="notes.xhtml#fn-zy"><img alt="note" class="zhangyue-footnote" src="../images/note-icon.png" zy-footnote="这是掌阅通用弹注法，正文来自 zy-footnote 属性。"/></a></sup></p>
<p>13 掌阅/多看双类名图片注 <img alt="这是双类名图片注兼容变体。" class="duokan-footnote zhangyue-footnote" src="../images/note-icon.png"/> 点图标</p>

<h2>WR/Reader 与 Reeden</h2>
<p>14 WR/Reader 空元素图标 <span class="reader" data-wr-footernote="这是 WR/Reader 的真实空元素结构，正文位于 data-wr-footernote 属性。"></span> 点图标</p>
<p>15 WR 直接文本<span class="js_readerFooterNote" data-wr-footernote="WR 直接文本兼容结构。">〔15〕</span></p>
<p>16 Reader 图片注<span reader_footer_note="file:../images/note-card.png">〔16〕</span></p>
<p>17 js_readerFooterNote 文本<span js_readerFooterNote="这是 js_readerFooterNote 直接文本兼容写法。">〔17〕</span></p>
<p>18 Reeden 组合结构<a id="ref-reeden" class="reeden-footnote duokan-footnote" href="#fn-reeden">〔18〕</a></p>
<p>19 Reeden 直接注文<span class="reeden-footnote" data-reeden-footnote-body="这是 data-reeden-footnote-body 直接注文。">〔19〕</span></p>

<h2>兜底与误判边界</h2>
<p>20 缺少目标 id，按序号文字兜底<a id="ref-text-fallback" epub:type="noteref" href="notes.xhtml#missing-target">[20]</a></p>
<p>21 缺少目标 id，按返回链接兜底<a id="ref-backlink" href="notes.xhtml#gone">[21]</a></p>
<p>22 得到兼容路径（仅标准 EPUB3）<a id="ref-dedao" epub:type="noteref" href="#fn-dedao">〔22〕</a></p>
<p>23 普通数字站内链接不应弹注<a href="#section-target">〔23〕</a></p>
<p id="section-target">这是普通内链目标，【23】不是注释。</p>

<aside id="fn-epub3" epub:type="footnote">
  <p>EPUB3 标准脚注第一段。</p>
  <p>第二段与下方图片都应出现在同一个弹窗中。</p>
  <img src="../images/note-card.png" alt="书内注释插图"/>
  <a href="#ref-epub3" epub:type="backlink">返回</a>
</aside>
<aside id="fn-dpub" role="doc-footnote">
  <p>DPUB-ARIA 脚注正文。</p>
  <a href="#ref-dpub" role="doc-backlink">返回</a>
</aside>
<p id="fn2">EPUB2 上标数字链接命中的普通段落注释。</p>
<p id="fn-dedao" epub:type="footnote">得到未检索到专用类名；此处验证其可用的标准 EPUB3 语义路径。</p>

<ol class="duokan-footnote-content">
  <li class="duokan-footnote-item" id="fn-duokan">
    <p>多看文字注第一段，定义来自 duokan-footnote-item。</p>
    <p>第二段保留完整文本。</p>
    <a class="duokan-footnote-back" href="#ref-duokan">返回</a>
  </li>
</ol>
<ol class="reeden-footnote-content duokan-footnote-content">
  <li class="reeden-footnote-item duokan-footnote-item" id="fn-reeden">
    Reeden 与多看双类名组合注文。
    <a class="duokan-footnote-back" href="#ref-reeden">返回</a>
  </li>
</ol>
"""

FOOTNOTE_NOTES_BODY = """<h1>跨文档注释定义页</h1>
<p>正常阅读只应看到本说明；以下所有注文定义都必须隐藏。</p>
<aside id="fn-cross" role="doc-endnote">
  <p>跨 XHTML 标准尾注正文。</p>
  <a href="../text/footnote-demo.xhtml#ref-cross" role="doc-backlink">返回</a>
</aside>
<section epub:type="endnotes">
  <h2>章末尾注集合</h2>
  <ol><li id="fn-rear" epub:type="rearnote">EPUB3 rearnote 尾注正文。</li></ol>
</section>
<p id="fn-zy" class="epub-footnote">掌阅 zy-footnote 的真实定义目标。</p>
<dl class="footnotes">
  <dt>通用类名注释定义</dt>
  <dd id="fn-generic" class="epub-footnote">epub-footnote 通用类名注文。</dd>
  <dt>列表注释定义</dt>
  <dd id="fn-dl">dl/dt/dd 列表中的注释正文。</dd>
</dl>
<ol class="footnotes">
  <li epub:type="endnote">20 序号兜底注文：目标 id 缺失时由注号文字定位。</li>
</ol>
<aside id="fn-back">
  <p>21 回链兜底注文：目标 id 缺失时由返回链接定位。</p>
  <a href="../text/footnote-demo.xhtml#ref-backlink" epub:type="backlink">返回</a>
</aside>
"""

FOOTNOTE_NORMAL_BODY = """<h1>普通链接对照页</h1>
<p>本页没有注释定义。回到总测页，普通章节链接和普通数字内链都不应被误判为脚注。</p>
<p><a href="footnote-demo.xhtml">返回注释结构总测</a></p>
<p><a href="#ordinary-target">普通数字链接 23</a></p>
<p id="ordinary-target">这是普通站内链接目标段落。</p>
"""


def make_footnote_formats() -> tuple[dict, dict[str, bytes]]:
    book = base_book(
        id="footnote-formats",
        file="footnote-formats.epub",
        title="注释结构总测",
        description=(
            "覆盖 EPUB3、DPUB-ARIA、多看、QQ/微信读书、掌阅、通用类名、"
            "WR/Reader、Reeden 与标准兜底路径；含跨文档、图片和多段注释。"
        ),
        source=(
            "自建原创测试正文；结构依据 710-epub-footnote-formats.md、"
            "QQ/微信读书与掌阅公开结构样本、WR/Reader 真实书样本"
        ),
        features=[
            "注释", "EPUB3 noteref", "DPUB-ARIA", "footnote", "endnote",
            "rearnote", "多看 duokan-footnote", "QQ/微信读书 qqreader-footnote",
            "掌阅 zhangyue-footnote", "通用 epub-footnote", "WR/Reader",
            "Reeden", "跨 XHTML", "图片注释", "多段注释", "返回链接", "dl/dt/dd",
            "序号兜底", "回链兜底", "普通链接误判边界",
        ],
    )
    nav_entries = [
        ("注释结构总测", "text/footnote-demo.xhtml"),
        ("跨文档注释定义页", "text/notes.xhtml"),
        ("普通链接对照页", "text/normal-links.xhtml"),
    ]
    files: dict[str, bytes] = {
        "META-INF/container.xml": container_xml().encode(),
        "OEBPS/styles/main.css": FOOTNOTE_CSS.encode(),
        "OEBPS/text/footnote-demo.xhtml": xhtml3(
            "注释结构总测", FOOTNOTE_DEMO_BODY, "../styles/main.css"
        ).encode(),
        "OEBPS/text/notes.xhtml": xhtml3(
            "跨文档注释定义页", FOOTNOTE_NOTES_BODY, "../styles/main.css"
        ).encode(),
        "OEBPS/text/normal-links.xhtml": xhtml3(
            "普通链接对照页", FOOTNOTE_NORMAL_BODY, "../styles/main.css"
        ).encode(),
        "OEBPS/images/note-icon.png": png_rgb(18, 18, (148, 62, 38)),
        "OEBPS/images/note-card.png": png_rgb(96, 48, (37, 93, 116)),
    }
    manifest = [
        {"id": "css", "href": "styles/main.css", "media_type": "text/css"},
        {"id": "nav", "href": "nav.xhtml", "media_type": "application/xhtml+xml", "properties": "nav"},
        {"id": "footnote-demo", "href": "text/footnote-demo.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "notes", "href": "text/notes.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "normal-links", "href": "text/normal-links.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "note-icon", "href": "images/note-icon.png", "media_type": "image/png"},
        {"id": "note-card", "href": "images/note-card.png", "media_type": "image/png"},
    ]
    files["OEBPS/nav.xhtml"] = nav_xhtml(book["title"], nav_entries).encode()
    files["OEBPS/content.opf"] = opf3(
        book,
        manifest,
        ["footnote-demo", "notes", "normal-links"],
    ).encode()
    return book, files


def make_duokan_fullscreen() -> tuple[dict, dict[str, bytes]]:
    book = base_book(
        id="duokan-fullscreen",
        file="duokan-fullscreen.epub",
        title="多看全屏封面测试",
        description=(
            "封面页和插图页在 OPF 的 itemref 上声明 "
            "duokan-page-fullscreen；封面页正文只有一个图片元素。"
        ),
        source="自建抽象封面测试样本",
        features=[
            "EPUB3", "OPF", "duokan-page-fullscreen", "全屏封面",
            "全屏插图", "高清 JPEG", "4:3", "16:9", "a~slim 适配图",
        ],
    )
    files: dict[str, bytes] = {
        "META-INF/container.xml": container_xml().encode(),
        "OEBPS/text/cover.xhtml": xhtml_single_image(
            "封面", "../images/a.jpg"
        ).encode(),
        "OEBPS/text/illustration.xhtml": xhtml_single_image(
            "全屏插图", "../images/illustration.jpg"
        ).encode(),
        "OEBPS/text/chapter1.xhtml": xhtml3(
            "正文",
            "<h1>正文</h1><p>前面的封面和插图应整页显示；本页应按普通章节分页。</p>",
        ).encode(),
        "OEBPS/images/a.jpg": (ASSET_DIR / "fullscreen-cover.jpg").read_bytes(),
        "OEBPS/images/a~slim.jpg": (
            ASSET_DIR / "fullscreen-cover-slim.jpg"
        ).read_bytes(),
        "OEBPS/images/illustration.jpg": (
            ASSET_DIR / "fullscreen-illustration.jpg"
        ).read_bytes(),
    }
    manifest = [
        {
            "id": "cover-image",
            "href": "images/a.jpg",
            "media_type": "image/jpeg",
            "properties": "cover-image",
        },
        {"id": "slim-image", "href": "images/a~slim.jpg", "media_type": "image/jpeg"},
        {
            "id": "illustration-image",
            "href": "images/illustration.jpg",
            "media_type": "image/jpeg",
        },
        {"id": "cover", "href": "text/cover.xhtml", "media_type": "application/xhtml+xml"},
        {
            "id": "illustration",
            "href": "text/illustration.xhtml",
            "media_type": "application/xhtml+xml",
        },
        {"id": "chapter1", "href": "text/chapter1.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "nav", "href": "nav.xhtml", "media_type": "application/xhtml+xml", "properties": "nav"},
    ]
    files["OEBPS/nav.xhtml"] = nav_xhtml(
        book["title"],
        [
            ("封面", "text/cover.xhtml"),
            ("全屏插图", "text/illustration.xhtml"),
            ("正文", "text/chapter1.xhtml"),
        ],
    ).encode()
    files["OEBPS/content.opf"] = opf3(
        book,
        manifest,
        ["cover", "illustration", "chapter1"],
        extra_meta='    <meta name="cover" content="cover-image"/>\n',
        spine_properties={
            "cover": "duokan-page-fullscreen",
            "illustration": "duokan-page-fullscreen",
        },
    ).encode()
    return book, files


BUILDERS = [
    make_basic,
    make_styles,
    make_table,
    make_toc_ncx,
    make_broken,
    make_cjk_vertical,
    make_footnote_formats,
    make_duokan_fullscreen,
]


# ---------------------------------------------------------------- 打包与校验

def zip_epub(book_id: str, files: dict[str, bytes], out_path: Path) -> None:
    if out_path.exists():
        out_path.unlink()
    with tempfile.TemporaryDirectory(prefix=f"epub-{book_id}-") as tmp:
        staging = Path(tmp)
        (staging / "mimetype").write_bytes(MIMETYPE)
        for rel, data in files.items():
            target = staging / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        # OCF：mimetype 必须第一个写入且不压缩
        subprocess.run(
            ["zip", "-X0", str(out_path), "mimetype"],
            cwd=staging, check=True, stdout=subprocess.DEVNULL,
        )
        subprocess.run(
            ["zip", "-Xr9", str(out_path), "META-INF", "OEBPS"],
            cwd=staging, check=True, stdout=subprocess.DEVNULL,
        )


def validate_files(book_id: str, files: dict[str, bytes]) -> None:
    for rel, data in files.items():
        if rel.endswith((".xml", ".opf", ".ncx", ".xhtml")):
            try:
                ElementTree.fromstring(data)
            except ElementTree.ParseError as exc:
                raise SystemExit(f"[{book_id}] {rel} 不是合法 XML：{exc}") from exc


def main() -> None:
    if shutil.which("zip") is None:
        raise SystemExit("缺少 zip 命令")
    CORPUS_DIR.mkdir(parents=True, exist_ok=True)
    records = []
    for builder in BUILDERS:
        book, files = builder()
        validate_files(book["id"], files)
        out_path = CORPUS_DIR / book["file"]
        zip_epub(book["id"], files, out_path)
        data = out_path.read_bytes()
        if len(data) >= 200 * 1024:
            raise SystemExit(f"[{book['id']}] 超过 200KB：{len(data)} 字节")
        records.append(
            {
                "id": book["id"],
                "file": book["file"],
                "title": book["title"],
                "language": book["language"],
                "source": book["source"],
                "license": book["license"],
                "features": book["features"],
                "sha256": hashlib.sha256(data).hexdigest(),
                "size_bytes": len(data),
            }
        )
        print(f"生成 {book['file']}  {len(data)} 字节  {records[-1]['sha256'][:12]}…")

    manifest = {
        "version": 1,
        "description": "Spectacular 测试样本库清单；file 相对 test_corpus/ 目录。",
        "samples": records,
    }
    manifest_path = CORPUS_DIR / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"写入 {manifest_path.relative_to(REPO_ROOT)}，共 {len(records)} 条记录")


if __name__ == "__main__":
    main()
