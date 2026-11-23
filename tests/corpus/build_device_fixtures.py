#!/usr/bin/env python3
"""构建真机验收用的 EPUB fixtures（不入库，生成到 test_corpus/generated/）。

设计口径（任务要求：真实 EPUB 不满足测试条件时，用真实 EPUB 的图片/文字
等资源自建）：

- 图片与文字优先抽取 test_corpus/real/ 下的真实书；真实书不在时回退到
  仓库内 CC0 资源（tests/corpus/assets/）与自写原创文本，保证任何机器可重建。
- 字体复用 test_fonts/ 的思源宋体（OFL）。
- 输出三本书：
  verify-mixed.epub      多章节 + 长章节 + 嵌套目录 + 复杂 CSS/字体/图片/
                         表格/SVG/错误路径/缺资源/异常样式。
  verify-tolerance.epub  EPUB2 + NCX：缺章、缺 CSS、错误 media-type、
                         重复 id、超长不可断 token、只给宽度的图片等。
  verify-small.epub      四章短书：字号/主题/翻页场景的快速样本。
  verify-broken-spine.epub
                         spine 全部指向不存在的 manifest id：验证按 manifest
                         恢复阅读顺序的 L3 降级（对照 Ferrous fallback）。

用法：
    python3 tests/corpus/build_device_fixtures.py [--out-dir test_corpus/generated]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
import zipfile
import zlib
from pathlib import Path
from xml.etree import ElementTree

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_epubs as corpus  # noqa: E402  （复用 zip/xhtml/mimetype 工具）

REAL_DIR = REPO_ROOT / "test_corpus" / "real"
FONT_DIR = REPO_ROOT / "test_fonts"
ASSET_DIR = Path(__file__).resolve().parent / "assets"

DEFAULT_OUT = REPO_ROOT / "test_corpus" / "generated"

# 抽查用真实书：优先图片丰富的样本，缺失时整本回退。
REAL_IMAGE_BOOKS = ["monk-and-robot.epub", "mj-003.epub", "ludingji-1.epub"]
REAL_TEXT_BOOKS = ["monk-and-robot.epub", "mj-003.epub", "agatha-linear-no.epub"]

FALLBACK_IMAGES = ["fullscreen-cover.jpg", "fullscreen-illustration.jpg", "fullscreen-cover-slim.jpg"]

FALLBACK_PARAGRAPH = (
    "远山在薄雾里显出轮廓，溪水从石缝间穿过，声音清脆而连续。"
    "行人沿着旧驿道慢慢走，脚下是经年被踩实的泥土，两侧是没有人打理的野草。"
    "天色将晚，村口的灯一盏一盏亮起来，像有人在纸上点了一排小点。"
    "他把手里的书合上，抬头看了看天，随后继续向前走去。"
)


# ---------------------------------------------------------------- 资源抽取

def real_book_path(name: str) -> Path | None:
    path = REAL_DIR / name
    return path if path.is_file() else None


def extract_images(limit: int = 4) -> list[tuple[str, bytes]]:
    """从真实书抽取 JPEG/PNG 图片；全部缺失时回退仓库 CC0 资源。"""
    picked: list[tuple[str, bytes]] = []
    for name in REAL_IMAGE_BOOKS:
        book = real_book_path(name)
        if book is None:
            continue
        try:
            with zipfile.ZipFile(book) as archive:
                for info in archive.infolist():
                    if info.file_size < 8 * 1024 or info.file_size > 900 * 1024:
                        continue
                    lower = info.filename.lower()
                    if not lower.endswith((".jpg", ".jpeg", ".png")):
                        continue
                    if "cover" in lower or "~slim" in lower:
                        continue
                    packed = archive.read(info)
                    if lower.endswith(".png") and packed[:8] != b"\x89PNG\r\n\x1a\n":
                        continue
                    if lower.endswith((".jpg", ".jpeg")) and packed[:2] != b"\xff\xd8":
                        continue
                    picked.append((info.filename, packed))
                    break
        except zipfile.BadZipFile:
            continue
        if len(picked) >= limit:
            break
    if picked:
        return picked
    for name in FALLBACK_IMAGES:
        path = ASSET_DIR / name
        if path.is_file():
            picked.append((name, path.read_bytes()))
    return picked


def extract_paragraphs(limit: int = 400) -> list[str]:
    """从真实书抽取正文段落文本；没有真实书时重复使用原创段落。"""
    paragraphs: list[str] = []
    for name in REAL_TEXT_BOOKS:
        book = real_book_path(name)
        if book is None:
            continue
        try:
            with zipfile.ZipFile(book) as archive:
                xhtmls = sorted(
                    info.filename
                    for info in archive.infolist()
                    if info.filename.lower().endswith(".xhtml")
                    and info.file_size < 400 * 1024
                )
                for target in xhtmls[:12]:
                    text = archive.read(target).decode("utf-8", "ignore")
                    body = text.split("<body", 1)[-1]
                    for chunk in re.findall(r"<p[^>]*>(.*?)</p>", body, re.S):
                        plain = re.sub(r"<[^>]+>", "", chunk)
                        plain = re.sub(r"\s+", "", plain)
                        if len(plain) < 60:
                            continue
                        paragraphs.append(plain)
                        if len(paragraphs) >= limit:
                            return paragraphs
        except (zipfile.BadZipFile, UnicodeDecodeError):
            continue
    if not paragraphs:
        seed = FALLBACK_PARAGRAPH
        paragraphs = [f"{seed}（第 {index + 1} 段）" for index in range(limit)]
    return paragraphs


def load_fonts() -> dict[str, bytes]:
    fonts: dict[str, bytes] = {}
    for stem in ["SourceHanSerifSC-Regular.otf", "SourceHanSerifSC-Bold.otf"]:
        path = FONT_DIR / stem
        if not path.is_file():
            raise SystemExit(f"缺少测试字体：{path}")
        fonts[stem] = path.read_bytes()
    return fonts


# ---------------------------------------------------------------- 图形生成

def svg_mark(width: int, height: int, label: str) -> bytes:
    """生成带独立宽高的矢量图（供 SVG 容错/尺寸场景）。"""
    return (
        f'<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}"'
        f' viewBox="0 0 {width} {height}">\n'
        f'  <rect x="2" y="2" width="{width - 4}" height="{height - 4}"'
        f' fill="#f3efe6" stroke="#8a7f6a" stroke-width="3"/>\n'
        f'  <circle cx="{width // 3}" cy="{height // 2}" r="{min(width, height) // 6}"'
        f' fill="#b4532a" opacity="0.85"/>\n'
        f'  <text x="{width // 2}" y="{height - 14}" font-size="20" text-anchor="middle"'
        f' fill="#3c3630">{label}</text>\n'
        f'</svg>\n'
    ).encode("utf-8")


def svg_without_size() -> bytes:
    """只有 viewBox、没有像素宽高的 SVG（尺寸回退场景）。"""
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300">\n'
        '  <rect width="400" height="300" fill="#e7dfd0"/>\n'
        '  <path d="M20 280 L180 60 L360 280 Z" fill="#5c6f82" opacity="0.8"/>\n'
        '</svg>\n'
    ).encode("utf-8")


# ---------------------------------------------------------------- 章节模板

def wrap(title: str, body: str, css: list[str], *, epub2: bool = False) -> str:
    link = "".join(
        f'<link rel="stylesheet" type="text/css" href="{href}"/>' for href in css
    )
    if epub2:
        head = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"'
            ' "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">\n'
            f'<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN">\n'
            f'<head><title>{corpus.esc(title)}</title>{link}</head>\n'
        )
    else:
        head = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<!DOCTYPE html>\n'
            '<html xmlns="http://www.w3.org/1999/xhtml"'
            ' xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-CN" lang="zh-CN">\n'
            f'<head><meta charset="utf-8"/><title>{corpus.esc(title)}</title>{link}</head>\n'
        )
    return f"{head}<body>\n{body}\n</body>\n</html>\n"


def paragraphs_html(items: list[str], *, indent: str = "  ") -> str:
    return "\n".join(f"{indent}<p>{corpus.esc(text)}</p>" for text in items)


# ---------------------------------------------------------------- 混合样本

COMPLEX_CSS = """\
@charset "utf-8";
@font-face {
  font-family: "验收宋体";
  src: url("../fonts/SourceHanSerifSC-Regular.otf");
  font-weight: 400;
}
@font-face {
  font-family: "验收宋体";
  src: url("../fonts/SourceHanSerifSC-Bold.otf");
  font-weight: 700;
}
html, body { margin: 0; padding: 0; }
body {
  font-family: "验收宋体", serif;
  font-size: 18px;
  line-height: 1.75;
  color: #2b2b2b;
  text-align: justify;
}
h1 { font-size: 1.6em; line-height: 1.3; margin: 0.8em 0 0.6em; text-align: center; }
h2 { font-size: 1.25em; line-height: 1.4; margin: 1.1em 0 0.5em; color: #6b3b1e; }
h2::before { content: "§ "; color: #b4532a; }
p { margin: 0 0 0.9em; text-indent: 2em; }
p.no-indent { text-indent: 0; margin-top: 0.4em; }
p.tight { line-height: 1.35; letter-spacing: 0.05em; }
p.wide { line-height: 2.2; margin-bottom: 1.8em; }
blockquote {
  margin: 1em 1.6em; padding: 0.6em 0.9em;
  border-left: 3px solid #b4532a; background-color: #f6f1e7;
  font-size: 0.95em; color: #4a423a;
}
ul, ol { margin: 0.4em 0 1em 2.4em; padding: 0; }
li { margin: 0.25em 0; line-height: 1.6; }
figure { margin: 1.2em 0; text-align: center; }
figure img { max-width: 100%; height: auto; }
figcaption { font-size: 0.85em; color: #6d6459; margin-top: 0.4em; }
img.float-right { float: right; width: 38%; margin: 0.2em 0 0.6em 0.9em; }
img.float-left { float: left; width: 34%; margin: 0.2em 0.9em 0.6em 0; }
p.clear { clear: both; }
table { border-collapse: collapse; width: 92%; margin: 1em auto; font-size: 0.92em; }
caption { caption-side: top; font-weight: 700; margin-bottom: 0.4em; }
th, td { border: 1px solid #b9ad99; padding: 0.4em 0.6em; line-height: 1.5; }
th { background-color: #efe7d8; text-align: center; }
td.num { text-align: right; font-variant-numeric: tabular-nums; }
.shadow-box {
  margin: 1.2em -0.6em; padding: 0.8em 1em;
  background-color: #f7f3ea; border: 1px solid #ded3bd; border-radius: 4px;
}
.banner {
  margin: 1em 0; padding: 0.8em; text-align: center; font-weight: 700;
  border-top: 3px double #b4532a; border-bottom: 3px double #b4532a;
}
span.kai { font-style: italic; }
span.small-caps { font-size: 0.8em; letter-spacing: 0.12em; }
code { font-family: monospace; background-color: #f1ece2; padding: 0 0.2em; }
svg.inline-mark { vertical-align: middle; }
"""

AUTHOR_CSS = """\
/* 第二份样式表：验证层叠顺序与后写覆盖 */
h2 { color: #234a63; }
p { text-align: justify; }
p.author-em { font-weight: 700; color: #7a2f1d; }
"""

BROKEN_CSS = """\
/* 异常样式表：未闭合花括号、非法值与未知属性混排，验证解析容错 */
p { color: #333; margin-bottom: 1em;
h2 { font-size: giant; color: ;; }
@media screen and (min-width: {
.missing { background-image: url("../images/not-exist.png"); }
@unknown-at-rule { whatever: 1; }
p { line-height: 1.9; /* 后写覆盖，仍应生效 */
"""


def make_mixed(
    images: list[tuple[str, bytes]], paragraphs: list[str], fonts: dict[str, bytes]
) -> tuple[dict, dict[str, bytes]]:
    book = {
        "id": "verify-mixed",
        "file": "verify-mixed.epub",
        "title": "真机验收·混合样本",
        "language": "zh-CN",
        "author": "Spectacular 验收组",
        "license": "仅本地测试使用；图片摘自本地真实 EPUB，不入库",
        "description": "多章节/长章节/嵌套目录/复杂 CSS/字体/图片/表格/SVG/容错综合样本",
        "uuid": corpus.book_uuid("verify-mixed"),
    }
    files: dict[str, bytes] = {}
    files["META-INF/container.xml"] = corpus.container_xml()
    files["OEBPS/styles/complex.css"] = COMPLEX_CSS.encode("utf-8")
    files["OEBPS/styles/author.css"] = AUTHOR_CSS.encode("utf-8")
    files["OEBPS/styles/broken.css"] = BROKEN_CSS.encode("utf-8")
    for stem, payload in fonts.items():
        files[f"OEBPS/fonts/{stem}"] = payload

    image_names: list[str] = []
    for index, (original, payload) in enumerate(images[:3]):
        ext = "png" if payload[:8] == b"\x89PNG\r\n\x1a\n" else "jpg"
        name = f"photo-{index + 1}.{ext}"
        files[f"OEBPS/images/{name}"] = payload
        image_names.append(name)
    while len(image_names) < 3:
        name = f"photo-{len(image_names) + 1}.png"
        files[f"OEBPS/images/{name}"] = corpus.png_rgb(
            320, 240, (150, 120, 90)
        )
        image_names.append(name)
    files["OEBPS/images/diagram.png"] = corpus.png_rgb(640, 200, (210, 200, 180))
    files["OEBPS/images/mark.svg"] = svg_mark(480, 320, "矢量标记")
    files["OEBPS/images/viewbox-only.svg"] = svg_without_size()

    pool = paragraphs if paragraphs else [FALLBACK_PARAGRAPH]

    def take(start: int, count: int) -> list[str]:
        return [pool[(start + i) % len(pool)] for i in range(count)]

    # ---- 封面与正文各章
    files["OEBPS/cover.xhtml"] = wrap(
        "封面",
        f'  <div class="cover"><img src="images/{image_names[0]}" alt="封面"/></div>',
        [],
    )
    files["OEBPS/part1.xhtml"] = wrap(
        "第一部 起卷",
        '  <h1>第一部 起卷</h1>\n  <div class="banner">部首页：目录层级验证用独立文件。</div>',
        ["styles/complex.css", "styles/author.css"],
    )
    files["OEBPS/part2.xhtml"] = wrap(
        "第二部 图文",
        '  <h1>第二部 图文</h1>\n  <div class="banner">图文部的部首页。</div>',
        ["styles/complex.css", "styles/author.css"],
    )
    files["OEBPS/part3.xhtml"] = wrap(
        "第三部 压力",
        '  <h1>第三部 压力</h1>\n  <div class="banner">压力部的部首页。</div>',
        ["styles/complex.css", "styles/author.css"],
    )
    files["OEBPS/ch01.xhtml"] = wrap(
        "第一章 卷首",
        "  <h1>第一章 卷首</h1>\n"
        + paragraphs_html(take(0, 6)),
        ["styles/complex.css", "styles/author.css"],
    )
    files["OEBPS/ch02.xhtml"] = wrap(
        "第二章 样式",
        "  <h1>第二章 样式</h1>\n  <h2>行距与段距</h2>\n"
        + paragraphs_html(take(6, 5))
        + '\n  <p class="tight">这一行使用紧缩行距与轻微字距，用于验证 line-height 与 letter-spacing 的差异。</p>\n'
        + '  <p class="wide">这一行使用宽松行距与更大段距，用于验证段距与行距分别生效。</p>\n'
        + '  <p class="no-indent">这一行取消首行缩进，用于验证 text-indent 覆盖。</p>\n'
        + '  <p class="author-em">这一行来自作者样式表的加强规则，应当以加粗深色呈现。</p>\n'
        + '  <p>段落中包含 <b>加粗</b>、<i>斜体</i>、<code>等宽</code>、'
        '<span class="small-caps">小号字距</span> 与 <span class="kai">伪斜体</span>，用于验证行内标记。</p>\n'
        + '  <div class="shadow-box">带负外边距与背景色的盒子，用于验证盒模型与负 margin 钳制。</div>',
        ["styles/complex.css", "styles/author.css"],
    )
    files["OEBPS/ch03.xhtml"] = wrap(
        "第二章·其一 行内标记",
        '  <h2 id="refs">行内标记与引用</h2>\n'
        + paragraphs_html(take(11, 2))
        + "\n  <blockquote>引文段落：文字应当保持斜体语义与缩进边界，"
        "行内 <b>强调</b> 不应破坏行距。</blockquote>\n"
        + "  <ul>\n    <li>无序列表第一项，较长文本用于观察换行与悬挂缩进。</li>\n"
        "    <li>无序列表第二项</li>\n  </ul>\n"
        + "  <ol>\n    <li>有序列表第一项</li>\n    <li>有序列表第二项</li>\n  </ol>\n"
        + paragraphs_html(take(13, 2)),
        ["styles/complex.css", "styles/author.css"],
    )
    files["OEBPS/ch04.xhtml"] = wrap(
        "第二章·其二 表格",
        '  <h2 id="tables">表格与题注</h2>\n'
        "  <table>\n    <caption>表一：验收数据</caption>\n"
        "    <thead><tr><th>项目</th><th>数值</th><th>说明</th></tr></thead>\n"
        "    <tbody>\n"
        "      <tr><td>章节数</td><td class=\"num\">12</td><td>含长章节与容错章</td></tr>\n"
        "      <tr><td colspan=\"2\">跨两列单元格</td><td>colspan 验证</td></tr>\n"
        "      <tr><td>图片</td><td class=\"num\">5</td><td>含缺失与错误路径</td></tr>\n"
        "    </tbody>\n  </table>\n"
        + paragraphs_html(take(15, 3)),
        ["styles/complex.css", "styles/author.css"],
    )
    files["OEBPS/ch05.xhtml"] = wrap(
        "第三章 图片",
        "  <h1>第三章 图片</h1>\n"
        f'  <figure><img src="images/{image_names[0]}" width="360" alt="横向图片"/>'
        "<figcaption>图一：横向图片，带 figcaption。</figcaption></figure>\n"
        f'  <p><img class="float-right" src="images/{image_names[1]}" alt="右浮动图片"/>'
        "这一段文字应当环绕在右浮动图片的左侧，用于验证浮动绕排与段落间距。"
        + corpus.esc(pool[0][:120])
        + "</p>\n"
        f'  <p class="clear"><img class="float-left" src="images/{image_names[2]}" alt="左浮动图片"/>'
        "这一段文字环绕在左浮动图片的右侧，随后清除浮动。</p>\n"
        + "  <figure>\n"
        f'    <img src="images/missing-photo.jpg" width="300" alt="缺失图片"/>'
        "<figcaption>图四：引用了不存在的图片文件，应当占位且不影响后续排版。</figcaption>\n"
        "  </figure>\n"
        + "  <figure>\n"
        + '    <img src="images/../images/photo-1.'
        + ("png" if image_names[0].endswith("png") else "jpg")
        + '" width="300" alt="回绕路径图片"/>'
        "<figcaption>图五：使用 <code>../</code> 回绕路径，应当正常解析到同一张图。</figcaption>\n"
        "  </figure>\n"
        + paragraphs_html(take(18, 3)),
        ["styles/complex.css", "styles/author.css"],
    )
    files["OEBPS/ch06.xhtml"] = wrap(
        "第四章 矢量与标点",
        "  <h1>第四章 矢量与标点</h1>\n"
        '  <p class="no-indent">以下为 SVG 位图引用，用于验证矢量资源在缺少解码器时的降级表现：</p>\n'
        '  <figure><img src="images/mark.svg" width="320" alt="SVG 图片"/>'
        "<figcaption>图六：SVG 图片（image/svg+xml）。</figcaption></figure>\n"
        '  <figure><img src="images/viewbox-only.svg" alt="只有 viewBox 的 SVG"/>'
        "<figcaption>图七：只有 viewBox 的 SVG，未声明像素宽高。</figcaption></figure>\n"
        "  <p>行内矢量对象：<svg class=\"inline-mark\" xmlns=\"http://www.w3.org/2000/svg\""
        " width=\"48\" height=\"28\"><rect width=\"48\" height=\"28\" fill=\"#d7c6a8\"/>"
        "<circle cx=\"14\" cy=\"14\" r=\"8\" fill=\"#b4532a\"/></svg>，其后继续正文。</p>\n"
        "  <p>标点挤压与避头尾：他说：“这里的引号、括号（含全角）与行末标点，"
        "都应当按照中文禁则处理；行首不应出现”——这类符号。</p>\n"
        + paragraphs_html(take(21, 4)),
        ["styles/complex.css", "styles/author.css"],
    )
    long_body = ["  <h1>长章节</h1>"]
    long_body.append("  <p>本章用于长章节性能与内存验证，内容由真实书段落循环拼装。</p>")
    for index in range(240):
        long_body.append(paragraphs_html(take(25 + index * 3, 1)))
        if index in (39, 79, 159):
            long_body.append("  <h2>分节标题</h2>")
        if index in (59, 139):
            long_body.append(
                "  <table><caption>长章表</caption><tbody><tr><th>序号</th><th>内容</th></tr>"
                f"<tr><td class=\"num\">{index}</td><td>表格单元格文本，用于跨页切分验证。</td></tr>"
                "<tr><td class=\"num\">2</td><td>第二行单元格。</td></tr></tbody></table>"
            )
        if index in (99, 199):
            long_body.append(
                f'  <figure><img src="images/{image_names[index % 3]}" width="300" alt="长章插图"/>'
                "<figcaption>长章插图</figcaption></figure>"
            )
    files["OEBPS/long.xhtml"] = wrap(
        "长章节",
        "\n".join(long_body),
        ["styles/complex.css", "styles/author.css"],
    )
    files["OEBPS/tolerance.xhtml"] = wrap(
        "容错章",
        "  <h1>容错章</h1>\n"
        "  <p>本章引用缺失样式表与异常样式：</p>\n"
        '  <div class="missing-css">异常样式表链接（styles/does-not-exist.css）不应阻断本章渲染。</div>\n'
        "  <p>以下内联样式包含非法值：<span style=\"font-size: giant; color: ;\">"
        "非法字号与空颜色声明应被忽略。</span></p>\n"
        '  <p style="margin: 0 0 1em; text-indent: 2em">合法的内联样式仍然生效。</p>\n'
        + "  <div>" * 40
        + "深层嵌套容器（40 层）内的文字仍应正常排版。"
        + "</div>" * 40
        + "\n  <p>超长不可断 token："
        + "A" * 300
        + "</p>\n"
        '  <p id="dup">重复 id 段落一。</p>\n'
        '  <p id="dup">重复 id 段落二。</p>\n'
        + paragraphs_html(take(30, 2)),
        ["styles/complex.css", "styles/author.css", "styles/does-not-exist.css"],
    )

    manifest = [
        {"id": "nav", "href": "nav.xhtml", "media_type": "application/xhtml+xml",
         "properties": "nav"},
        {"id": "css-complex", "href": "styles/complex.css", "media_type": "text/css"},
        {"id": "css-author", "href": "styles/author.css", "media_type": "text/css"},
        {"id": "css-broken", "href": "styles/broken.css", "media_type": "text/css"},
        {"id": "cover", "href": "cover.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "part1", "href": "part1.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "ch01", "href": "ch01.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "ch02", "href": "ch02.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "ch03", "href": "ch03.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "ch04", "href": "ch04.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "part2", "href": "part2.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "ch05", "href": "ch05.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "ch06", "href": "ch06.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "part3", "href": "part3.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "long", "href": "long.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "tolerance", "href": "tolerance.xhtml", "media_type": "application/xhtml+xml"},
    ]
    for index, name in enumerate(image_names + ["diagram.png"], start=1):
        media = "image/png" if name.endswith(".png") else "image/jpeg"
        manifest.append({"id": f"img{index}", "href": f"images/{name}", "media_type": media})
    manifest.append({"id": "img-svg", "href": "images/mark.svg", "media_type": "image/svg+xml"})
    manifest.append(
        {"id": "img-svg2", "href": "images/viewbox-only.svg", "media_type": "image/svg+xml"}
    )
    for index, (stem, payload) in enumerate(fonts.items(), start=1):
        manifest.append(
            {"id": f"font{index}", "href": f"fonts/{stem}", "media_type": "font/otf"}
        )
    spine = [
        "cover", "part1", "ch01", "ch02", "ch03", "ch04",
        "part2", "ch05", "ch06", "part3", "long", "tolerance",
    ]

    files["OEBPS/content.opf"] = corpus.opf3(book, manifest, spine)
    files["OEBPS/nav.xhtml"] = nav_nested(book["title"])
    return book, files


def nav_nested(title: str) -> str:
    """三层嵌套目录：部（独立文件）→ 章 → 章内小节（锚点）。

    每层目标互不相同（含 fragment），避免被目录清洗按重复目标合并。
    """
    def li(label: str, href: str, indent: int, children: list[str] | None = None) -> str:
        pad = "  " * indent
        if children:
            return (
                f'{pad}<li><a href="{href}">{corpus.esc(label)}</a>\n'
                f"{pad}  <ol>\n"
                + "\n".join(children)
                + f"\n{pad}  </ol>\n{pad}</li>"
            )
        return f'{pad}<li><a href="{href}">{corpus.esc(label)}</a></li>'

    part1 = [
        li("第一章 卷首", "ch01.xhtml", 6),
        li("第二章 样式", "ch02.xhtml", 6),
        li(
            "第二章·其一 行内标记",
            "ch03.xhtml",
            6,
            children=[
                li("引用与列表", "ch03.xhtml#refs", 8),
                li("表格与题注", "ch04.xhtml#tables", 8),
            ],
        ),
    ]
    part2 = [
        li("第三章 图片", "ch05.xhtml", 6),
        li("第四章 矢量与标点", "ch06.xhtml", 6),
    ]
    part3 = [
        li("长章节", "long.xhtml", 6),
        li("容错章", "tolerance.xhtml", 6),
    ]
    body = "\n".join(
        [
            '  <nav epub:type="toc" id="toc">',
            "    <h1>目录</h1>",
            "    <ol>",
            li("第一部 起卷", "part1.xhtml", 3, part1),
            li("第二部 图文", "part2.xhtml", 3, part2),
            li("第三部 压力", "part3.xhtml", 3, part3),
            "    </ol>",
            "  </nav>",
        ]
    )
    return wrap(title + "·目录", body, [])


def make_tolerance(paragraphs: list[str]) -> tuple[dict, dict[str, bytes]]:
    book = {
        "id": "verify-tolerance",
        "file": "verify-tolerance.epub",
        "title": "真机验收·容错样本",
        "language": "zh-CN",
        "author": "Spectacular 验收组",
        "license": "仅本地测试使用，不入库",
        "description": "EPUB2/NCX 容错样本：缺章、缺 CSS、错误 media-type、重复 id、超长 token",
        "uuid": corpus.book_uuid("verify-tolerance"),
    }
    files: dict[str, bytes] = {}
    files["META-INF/container.xml"] = corpus.container_xml()
    files["OEBPS/styles/base.css"] = (
        "body { font-family: serif; line-height: 1.7; }\n"
        "p { margin: 0 0 0.8em; text-indent: 2em; }\n"
        "h1 { text-align: center; }\n"
        ".chapter-mark { border-top: 1px solid #999; margin-top: 1.5em; }\n"
    ).encode("utf-8")
    files["OEBPS/ch01.xhtml"] = wrap(
        "第一章 正常章",
        "  <h1>第一章 正常章</h1>\n" + paragraphs_html(paragraphs[:4]),
        ["styles/base.css"],
        epub2=True,
    )
    files["OEBPS/ch02.xhtml"] = wrap(
        "第二章 缺图与重复 id",
        "  <h1>第二章 缺图与重复 id</h1>\n"
        '  <p><img src="images/does-not-exist.jpg" alt="缺失图片"/></p>\n'
        '  <p><img src="IMAGES/not-here.png" width="120" alt="大小写错误路径"/></p>\n'
        '  <p id="same">重复标识段落一。</p>\n'
        '  <p id="same">重复标识段落二。</p>\n'
        "  <p>" + "B" * 240 + "</p>\n"
        + paragraphs_html(paragraphs[4:8]),
        ["styles/base.css", "styles/missing.css"],
        epub2=True,
    )
    files["OEBPS/ch03.xhtml"] = wrap(
        "第三章 结构松散",
        "  <h1>第三章 结构松散</h1>\n"
        "  <p>缺少 tbody 的表格：</p>\n"
        "  <table border=\"1\"><tr><td>甲</td><td>乙</td></tr>"
        "<tr><td>丙</td><td>丁</td></tr></table>\n"
        "  <p>只给宽度的图片：<img src=\"images/only-width.png\" width=\"180\"/></p>\n"
        "  <p>空段落与连续空元素：</p>\n  <p></p>\n  <div/>\n  <span/>\n"
        "  <p>内联 svg 引用：<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"60\" height=\"20\">"
        "<image href=\"images/mark.png\" width=\"60\" height=\"20\"/></svg></p>\n"
        + paragraphs_html(paragraphs[8:12]),
        ["styles/base.css"],
        epub2=True,
    )
    files["OEBPS/images/mark.png"] = corpus.png_rgb(120, 80, (120, 140, 160))
    files["OEBPS/images/only-width.png"] = corpus.png_rgb(240, 160, (170, 150, 130))
    nav2 = [
        ("nav1", "第一章 正常章", "ch01.xhtml"),
        ("nav2", "第二章 缺图与重复 id", "ch02.xhtml"),
        ("nav3", "第三章 结构松散", "ch03.xhtml"),
    ]
    files["OEBPS/toc.ncx"] = corpus.ncx(book, nav2)
    manifest = [
        {"id": "ncx", "href": "toc.ncx", "media_type": "application/x-dtbncx+xml"},
        {"id": "css", "href": "styles/base.css", "media_type": "text/plain"},
        {"id": "css-missing", "href": "styles/missing.css", "media_type": "text/css"},
        {"id": "ch01", "href": "ch01.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "ch02", "href": "ch02.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "ch03", "href": "ch03.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "missing", "href": "missing-chapter.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "img1", "href": "images/mark.png", "media_type": "image/png"},
        {"id": "img2", "href": "images/only-width.png", "media_type": "image/png"},
    ]
    spine = ["ch01", "ch02", "missing", "ch03"]
    guide = (
        '    <reference type="text" title="正文" href="ch01.xhtml"/>\n'
        '    <reference type="missing" title="失效指引" href="gone.xhtml"/>'
    )
    files["OEBPS/content.opf"] = corpus.opf2(book, manifest, spine, guide)
    return book, files


def make_broken_spine(paragraphs: list[str]) -> tuple[dict, dict[str, bytes]]:
    """spine 全部指向不存在的 id：验证按 manifest 恢复阅读顺序的 L3 降级。"""
    book = {
        "id": "verify-broken-spine",
        "file": "verify-broken-spine.epub",
        "title": "真机验收·断链 spine 样本",
        "language": "zh-CN",
        "author": "Spectacular 验收组",
        "license": "仅本地测试使用，不入库",
        "description": "spine 的 itemref 全部指向不存在的 manifest id；"
        "manifest 中三章正文应仍可读，目录由 nav 提供",
        "uuid": corpus.book_uuid("verify-broken-spine"),
    }
    files: dict[str, bytes] = {}
    files["META-INF/container.xml"] = corpus.container_xml()
    files["OEBPS/styles/spine.css"] = (
        "body { font-family: serif; line-height: 1.7; }\n"
        "p { margin: 0 0 0.9em; text-indent: 2em; }\n"
        "h1 { text-align: center; }\n"
    ).encode("utf-8")
    titles = ["第一章 恢复顺序甲", "第二章 恢复顺序乙", "第三章 恢复顺序丙"]
    for index, title in enumerate(titles):
        files[f"OEBPS/ch0{index + 1}.xhtml"] = wrap(
            title,
            f"  <h1>{title}</h1>\n"
            + paragraphs_html(paragraphs[index * 3 : index * 3 + 3]),
            ["styles/spine.css"],
        )
    files["OEBPS/nav.xhtml"] = corpus.nav_xhtml(
        book["title"],
        [(title, f"ch0{index + 1}.xhtml") for index, title in enumerate(titles)],
    )
    manifest = [
        {"id": "nav", "href": "nav.xhtml", "media_type": "application/xhtml+xml",
         "properties": "nav"},
        {"id": "css", "href": "styles/spine.css", "media_type": "text/css"},
        {"id": "ch01", "href": "ch01.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "ch02", "href": "ch02.xhtml", "media_type": "application/xhtml+xml"},
        {"id": "ch03", "href": "ch03.xhtml", "media_type": "application/xhtml+xml"},
    ]
    opf = corpus.opf3(book, manifest, [])
    files["OEBPS/content.opf"] = opf.replace(
        "  <spine>\n",
        '  <spine>\n    <itemref idref="ghost-1"/>\n    <itemref idref="ghost-2"/>\n',
    )
    return book, files


def make_small(paragraphs: list[str]) -> tuple[dict, dict[str, bytes]]:
    book = {
        "id": "verify-small",
        "file": "verify-small.epub",
        "title": "真机验收·小样本",
        "language": "zh-CN",
        "author": "Spectacular 验收组",
        "license": "仅本地测试使用，不入库",
        "description": "四章短书：字号/主题/翻页/目录快速场景",
        "uuid": corpus.book_uuid("verify-small"),
    }
    files: dict[str, bytes] = {}
    files["META-INF/container.xml"] = corpus.container_xml()
    files["OEBPS/styles/small.css"] = (
        "body { font-family: serif; line-height: 1.8; }\n"
        "p { margin: 0 0 1em; text-indent: 2em; }\n"
        "h1 { text-align: center; margin: 0.6em 0 1em; }\n"
    ).encode("utf-8")
    for index in range(1, 5):
        files[f"OEBPS/s{index}.xhtml"] = wrap(
            f"小样本 第 {index} 章",
            f"  <h1>小样本 第 {index} 章</h1>\n"
            + paragraphs_html([p for p in paragraphs[index - 1 :: 4][:6]]),
            ["styles/small.css"],
        )
    manifest = [{"id": "css", "href": "styles/small.css", "media_type": "text/css"}]
    manifest += [
        {"id": f"s{i}", "href": f"s{i}.xhtml", "media_type": "application/xhtml+xml"}
        for i in range(1, 5)
    ]
    spine = [f"s{i}" for i in range(1, 5)]
    files["OEBPS/content.opf"] = corpus.opf3(book, manifest, spine)
    files["OEBPS/nav.xhtml"] = corpus.nav_xhtml(
        book["title"], [(f"小样本 第 {i} 章", f"s{i}.xhtml") for i in range(1, 5)]
    )
    return book, files


# ---------------------------------------------------------------- 入口

def build_all(out_dir: Path) -> list[dict]:
    images = extract_images()
    paragraphs = extract_paragraphs()
    fonts = load_fonts()
    builders = [
        lambda: make_mixed(images, paragraphs, fonts),
        lambda: make_tolerance(paragraphs),
        lambda: make_small(paragraphs),
        lambda: make_broken_spine(paragraphs),
    ]
    out_dir.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []
    for builder in builders:
        book, files = builder()
        files = {
            rel: (payload.encode("utf-8") if isinstance(payload, str) else payload)
            for rel, payload in files.items()
        }
        corpus.validate_files(book["id"], files)
        path = out_dir / book["file"]
        corpus.zip_epub(book["id"], files, path)
        payload = path.read_bytes()
        records.append(
            {
                **book,
                "sha256": hashlib.sha256(payload).hexdigest(),
                "size_bytes": len(payload),
            }
        )
        print(f"生成 {path}  {len(payload)} 字节  {records[-1]['sha256'][:12]}…")
    manifest = {
        "version": 1,
        "description": "真机验收 fixtures；由 tests/corpus/build_device_fixtures.py 生成，不入库。",
        "samples": records,
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return records


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    records = build_all(args.out_dir)
    source = "真实书资源" if real_book_path(REAL_IMAGE_BOOKS[0]) else "仓库 CC0 资源"
    print(f"完成：{len(records)} 本；图片/文字来源：{source}")


if __name__ == "__main__":
    main()
