#!/usr/bin/env python3
"""对比浏览器与引擎的渲染几何，输出差异报告与并排对照图。

用法：/usr/bin/python3 tool/css_parity/compare.py [case...]
输入：/tmp/css_parity/browser_*.json|png 与 engine_*.json|png
输出：/tmp/css_parity/report.md 与 /tmp/css_parity/side_<case>.png
"""
import json
import pathlib
import sys

from PIL import Image

OUT = pathlib.Path('/tmp/css_parity')
TOL = 1.0  # 块几何允许误差（逻辑像素）
WIDTH_TOL = 4.0  # 行宽允许误差（断行取整）
STYLE_EPS = 0.01


def load(name):
    browser = json.loads((OUT / f'browser_{name}.json').read_text(encoding='utf-8'))
    engine = json.loads((OUT / f'engine_{name}.json').read_text(encoding='utf-8'))
    return browser, engine


def text_key(text: str) -> str:
    return ''.join(text.split())[:16]


def match_blocks(browser, engine):
    """按文本前缀把浏览器元素与引擎块配对（保持文档顺序）。"""
    elements = [el for el in browser['elements'] if el['text'].strip()]
    pairs = []
    used = set()
    for block in engine['blocks']:
        key = text_key(block['text'])
        if not key:
            continue
        for index, el in enumerate(elements):
            if index in used:
                continue
            if text_key(el['text']).startswith(key[:8]) or key.startswith(
                text_key(el['text'])[:8]
            ):
                pairs.append((el, block))
                used.add(index)
                break
    return pairs


def norm_style(raw, key):
    """把浏览器计算样式归一成数值（px / 无单位倍数）。"""
    if raw is None:
        return None
    text = str(raw).strip()
    if text in ('normal', 'auto', 'none'):
        return 0.0
    if text.endswith('px'):
        text = text[:-2]
    try:
        return float(text)
    except ValueError:
        return None


def style_equal(browser_raw, engine_value, key: str) -> bool:
    if engine_value is None:
        return True
    if key in ('textAlign', 'whiteSpace', 'textTransform', 'fontWeight'):
        return str(browser_raw).lower().replace('-', '') == str(engine_value).lower().replace('-', '') or str(engine_value).lower() in str(browser_raw).lower()
    left = norm_style(browser_raw, key)
    right = norm_style(engine_value, key)
    if left is None or right is None:
        return str(browser_raw) == str(engine_value)
    return abs(left - right) <= STYLE_EPS


def fmt(value):
    if isinstance(value, float):
        return f'{value:.1f}'
    return str(value)


def diff_case(name):
    browser, engine = load(name)
    lines = [f'## {name}']
    pairs = match_blocks(browser, engine)
    lines.append(f'- 配对 {len(pairs)} 个元素（浏览器 {len(browser["elements"])}，'
                 f'引擎 {len(engine["blocks"])}）')
    for el, block in pairs:
        brows_lines = el['lines']
        eng_lines = block['lines']
        problems = []
        el_rect, bl_rect = el['rect'], block['rect']
        for key in ('y', 'h'):
            if abs(el_rect[key] - bl_rect[key]) > TOL:
                problems.append(
                    f'{key}: 浏览器 {fmt(el_rect[key])} / 引擎 {fmt(bl_rect[key])}'
                )
        if abs(len(brows_lines) - len(eng_lines)) > 0:
            problems.append(f'行数: 浏览器 {len(brows_lines)} / 引擎 {len(eng_lines)}')
        style = block['style']
        font_size = style.get('fontSize') or 0.0
        line_height = style.get('lineHeight') or font_size
        line_tol = max(TOL, (float(line_height) - float(font_size)) / 2 + 0.5)
        for index, (b_line, e_line) in enumerate(zip(brows_lines, eng_lines)):
            if abs(b_line['y'] - e_line['y']) > line_tol:
                problems.append(
                    f'第{index + 1}行 y: 浏览器 {fmt(b_line["y"])} / 引擎 {fmt(e_line["y"])}'
                )
            if abs(b_line['x'] - e_line['x']) > TOL:
                problems.append(
                    f'第{index + 1}行 x: 浏览器 {fmt(b_line["x"])} / 引擎 {fmt(e_line["x"])}'
                )
            if abs(b_line['w'] - e_line['w']) > WIDTH_TOL:
                problems.append(
                    f'第{index + 1}行 宽: 浏览器 {fmt(b_line["w"])} / 引擎 {fmt(e_line["w"])}'
                )
        style_pairs = [
            ('fontSize', 'fontSize'),
            ('lineHeight', 'lineHeight'),
            ('letterSpacing', 'letterSpacing'),
            ('wordSpacing', 'wordSpacing'),
            ('textAlign', 'textAlign'),
            ('whiteSpace', 'whiteSpace'),
            ('textTransform', 'textTransform'),
            ('fontWeight', 'fontWeight'),
        ]
        style_line = ' '.join(
            f'{b_key}={el["style"][b_key]}/{fmt(block["style"].get(e_key))}'
            for b_key, e_key in style_pairs
            if not style_equal(el['style'][b_key], block['style'].get(e_key), b_key)
        )
        label = (el['text'].strip().replace('\n', ' ')[:24] or el['tag'])
        if problems or style_line:
            lines.append(f'- 「{label}」')
            for problem in problems:
                lines.append(f'  - {problem}')
            if style_line:
                lines.append(f'  - 样式 浏览器/引擎: {style_line}')
    return lines


def montage(name):
    browser = Image.open(OUT / f'browser_{name}.png').convert('RGB')
    engine = Image.open(OUT / f'engine_{name}.png').convert('RGB')
    width = browser.width + engine.width + 12
    height = max(browser.height, engine.height)
    canvas = Image.new('RGB', (width, height), (255, 0, 255))
    canvas.paste(browser, (0, 0))
    canvas.paste(engine, (browser.width + 12, 0))
    canvas.save(OUT / f'side_{name}.png')


def main() -> int:
    names = sys.argv[1:] or sorted(
        path.stem.removeprefix('browser_')
        for path in OUT.glob('browser_*.json')
    )
    report = ['# CSS 属性对照报告', '']
    flagged = 0
    for name in names:
        try:
            lines = diff_case(name)
            report.extend(lines)
            montage(name)
            if any(line.startswith('  - ') for line in lines):
                flagged += 1
        except FileNotFoundError as err:
            report.append(f'## {name}\n- 缺少数据：{err}')
        report.append('')
    report.insert(2, f'- 用例 {len(names)} 个，有差异 {flagged} 个\n')
    (OUT / 'report.md').write_text('\n'.join(report), encoding='utf-8')
    print('\n'.join(report))
    return 0


if __name__ == '__main__':
    sys.exit(main())
