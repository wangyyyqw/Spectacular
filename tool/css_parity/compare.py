#!/usr/bin/env python3
"""对比浏览器与引擎的渲染几何，输出差异报告与并排对照图。

用法：/usr/bin/python3 tool/css_parity/compare.py [case...]
输入：/tmp/css_parity/browser_*.json|png 与 engine_*.json|png
输出：/tmp/css_parity/report.md 与 /tmp/css_parity/side_<case>.png

报告口径：
- 几何：块盒（y/x/宽/高）、行盒（y/x/行宽）、表格单元格盒与格内首行。
- 行宽用行实际占据宽（引擎 advanceWidth，含 justify 均分；浏览器量的是
  绘制宽），不是自然宽。
- 跨页用例（用例 JSON 标 multipage）：引擎分页、浏览器连续流，只比页内
  相对关系（行距、页内间距、宽度），页界断裂属预期差异，只记录不计数。
- 属性维度：取用例 JSON 的 tags，首个为主维度；每条失配计入主维度。
- 配对：按「文本 + 角色」。ul/ol/dl 等容器元素不参与块配对，li 只与
  引擎列表项块配对；配不上记「未配对」并单列，不计入失配。
- 门禁：`--threshold N` 或 `CSS_PARITY_THRESHOLD=N`，任一维度失配项数
  超过 N 时退出码为 2；默认 0 表示不启用（退出码 0）。
"""
import argparse
from collections import Counter
import json
import os
import pathlib
import re
import sys

from PIL import Image, ImageChops

OUT = pathlib.Path(os.environ.get('CSS_PARITY_OUT', '/tmp/css_parity'))
CASES = pathlib.Path(__file__).resolve().parent / 'cases'
TOL = 1.5  # 块/单元格几何允许误差（逻辑像素）
WIDTH_TOL = 4.0
BASELINE_TOL = 1.5  # 行宽允许误差（断行取整）
STYLE_EPS = 0.01
PIXEL_FLAG = 0.02  # 视觉差异判定阈值（差异像素占比）
TABLE_TAGS = {'td', 'th', 'tr', 'tbody', 'thead', 'tfoot', 'caption', 'col', 'colgroup'}
# 容器元素：只承载子块，自身不参与块配对（否则会抢 li 的文本）。
CONTAINER_TAGS = {
    'ul', 'ol', 'dl', 'menu', 'table', 'tbody', 'thead', 'tfoot', 'tr',
    'colgroup', 'col', 'caption',
}


# ---------------------------------------------------------------- 数据装载
def load(name):
    browser = json.loads((OUT / f'browser_{name}.json').read_text(encoding='utf-8'))
    engine = json.loads((OUT / f'engine_{name}.json').read_text(encoding='utf-8'))
    return browser, engine


def case_meta(name):
    path = CASES / f'{name}.json'
    if not path.exists():
        return {'tags': [], 'multipage': False, 'engine_only': False, 'expect': {}}
    data = json.loads(path.read_text(encoding='utf-8'))
    tags = [str(tag) for tag in data.get('tags', [])]
    return {
        'tags': tags,
        'multipage': bool(data.get('multipage')),
        # 浏览器不支持的属性（hanging-punctuation / initial-letter 等）：
        # 只记录引擎行为，不计失配、不算视觉差异。
        'engine_only': bool(data.get('engine_only')),
        # 浏览器不支持的用例可附引擎期望值（页数 / 每页列数等），
        # 报告里与实测并列展示，不计失配。
        'expect': data.get('expect') or {},
    }


def nkey(text, limit=16):
    """配对用文本键：去空白 + 转小写。

    引擎会把 text-transform 应用到排版文本（uppercase/capitalize），浏览器
    textContent 仍是原文，大小写不敏感才能配上；大小写本身的差异由
    textTransform 样式项比对。
    """
    # CSS `quotes` 生成的引号没有 DOM textContent；配对时忽略引号标点，
    # 引号字形是否一致由行几何与截图覆盖。
    return re.sub(r'[\s\'"“”‘’「」『』«»]+', '', str(text)).lower()[:limit]


def nkey_long(text, limit=400):
    """包含判断用的长文本键（去空白 + 转小写，不截断到 16）。"""
    return re.sub(r'[\s\'"“”‘’「」『』«»]+', '', str(text)).lower()[:limit]


def norm_enum(raw):
    """枚举值归一：contentBox → content-box。"""
    if raw is None:
        return ''
    text = str(raw).strip()
    return re.sub(r'([a-z0-9])([A-Z])', r'\1-\2', text).lower()


def norm_number(raw):
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if text in ('normal', 'auto', 'none'):
        return 0.0
    match = re.fullmatch(r'(-?\d+(?:\.\d+)?)(px)?', text)
    return float(match.group(1)) if match else None


def fmt(value):
    if value is None:
        return '?'
    if isinstance(value, float):
        return f'{value:.1f}'
    return str(value)


# ---------------------------------------------------------------- 配对
def browser_elements(browser):
    """可参与块配对的候选：有文字、且不是容器/表格内部元素。

    容器元素（有块级子元素、自身无直接文本，如 `<div><p/><p/></div>`）的
    textContent 只是子块拼接，配给引擎段落块会产生假差异（61 的 div.rtl），
    这里直接排除；配不上时由调用方记「未配对」。
    """
    return [
        el for el in browser['elements']
        if str(el.get('text', '')).strip()
        and not el.get('container')
        and el['tag'] not in TABLE_TAGS
        and el['tag'] not in CONTAINER_TAGS
    ]


def browser_tables(browser):
    """表格元素单独一列：容器不参与文本块配对，但表格块要配到 table。"""
    return [el for el in browser['elements'] if el['tag'] == 'table']


def block_role(block):
    """引擎块角色：table（表格）/ li（列表项）/ block（普通块）。

    dump 会直接给 role；旧数据没有时按 cells / listMarker 推断。
    """
    role = block.get('role')
    if role:
        return role
    if block.get('cells'):
        return 'table'
    return 'li' if block.get('listMarker') else 'block'


def _pick(key, elements, used, tags=None, exclude_tags=()):
    """在候选元素里按文本挑一个：完全相等优先，其次长度最接近。"""
    if not key:
        return None
    best = None
    for index, el in enumerate(elements):
        if index in used:
            continue
        if tags is not None and el['tag'] not in tags:
            continue
        if el['tag'] in exclude_tags:
            continue
        el_key = nkey(el.get('text', ''))
        if not el_key:
            continue
        if not (el_key.startswith(key[:8]) or key.startswith(el_key[:8])):
            continue
        score = (0 if el_key == key else 1, abs(len(el_key) - len(key)), index)
        if best is None or score < best[0]:
            best = (score, index, el)
    if best is None:
        return None
    used.add(best[1])
    return best[2]


def pair_table(block, tables, used_tables):
    """表格块按单元格文字配 table 元素（独立 used，避免与文本块抢）。"""
    cells_text = ''.join(str(cell.get('text', '')) for cell in block.get('cells') or [])
    return _pick(nkey(cells_text), tables, used_tables)


def pair_element(block, elements, used):
    """文本 + 角色配对；返回 None 表示未配对（由调用方单列，不算失配）。"""
    role = block_role(block)
    if role == 'table':
        return None  # 表格块走 pair_table
    key = nkey(block.get('text', ''))
    if role == 'li':
        # li 只与 li 配对；配不上就记未配对。
        return _pick(key, elements, used, tags={'li'})
    # 普通块：先排除 li（避免正文段落抢列表项），找不到再兜底允许 li
    # （引擎对 list-style:none 的列表项没有 listMarker，role 只能是 block）。
    el = _pick(key, elements, used, exclude_tags={'li'})
    return el if el is not None else _pick(key, elements, used, tags={'li'})


def pair_contained(block, elements, used):
    """多列布局下引擎把一段文字拆成多个块，块文本是浏览器元素文本的子串。

    返回 (元素, True)；只用于普通块，配不上返回 (None, False)。这种配对
    只比块顶位置，行级不可比（每块只是一个列片段）。
    """
    if block_role(block) in ('li', 'table'):
        return None, False
    key = nkey_long(block.get('text', ''))
    if len(key) < 6:
        return None, False
    best = None
    for index, el in enumerate(elements):
        if index in used:
            continue
        el_key = nkey_long(el.get('text', ''))
        if key.startswith(el_key) or key in el_key or el_key in key:
            score = abs(len(el_key) - len(key))
            if best is None or score < best[0]:
                best = (score, index)
    if best is None:
        return None, False
    used.add(best[1])
    return elements[best[1]], True


# ---------------------------------------------------------------- 逐项比较
def engine_box_rect(block):
    """把引擎块几何折算成浏览器口径的边框盒。

    引擎导出：x = 内容左缘（margin + border + padding），h = 内容高，
    rect.w = 最长行宽（不是盒宽，不能直接比）。块宽用 dump 的 `bboxW`
    （边框盒宽 = contentWidth + padding + border）；引擎未知（pre/nowrap 的
    Infinity）时为 null，按「未知」跳过比较，不算失配。
    """
    bbox = block.get('bboxRect')
    if block.get('transformed') and isinstance(bbox, dict):
        # 有 transform 时浏览器量的是变换后 bbox；dump 已按 transform +
        # transform-origin 算好轴对齐 bbox，直接同口径比较。
        return dict(bbox)
    rect = dict(block.get('rect') or {})
    style = block.get('style') or {}
    padding = style.get('padding') or [0.0, 0.0, 0.0, 0.0]
    border = style.get('border') or [0.0, 0.0, 0.0, 0.0]
    try:
        rect['x'] = (rect.get('x') or 0.0) - padding[3] - border[3]
        rect['y'] = (rect.get('y') or 0.0) - padding[0] - border[0]
        bbox_w = block.get('bboxW')
        if bbox_w is None:
            content = block.get('contentWidth')
            bbox_w = (None if content is None else
                      content + padding[1] + padding[3] + border[1] + border[3])
        rect['w'] = bbox_w
        rect['h'] = (rect.get('h') or 0.0) + padding[0] + padding[2] + border[0] + border[2]
    except TypeError:
        pass
    return rect


def compare_rect(browser_rect, engine_rect, keys=('y', 'x', 'w', 'h'), tol=TOL):
    problems = []
    for key in keys:
        left = browser_rect.get(key)
        right = engine_rect.get(key)
        if right is None:
            # 引擎侧未知（如 pre/nowrap 的无限可用宽）不判失配。
            continue
        if left is None:
            problems.append(f'{key}: 浏览器 {fmt(left)} / 引擎 {fmt(right)}（浏览器缺失）')
            continue
        if abs(left - right) > tol:
            problems.append(f'{key}: 浏览器 {fmt(left)} / 引擎 {fmt(right)}')
    return problems


def line_tolerance(engine_style):
    font_size = engine_style.get('fontSize') or 0.0
    line_height = engine_style.get('lineHeight') or font_size
    return max(TOL, (float(line_height) - float(font_size)) / 2 + 0.5)


def compare_lines(browser_lines, engine_lines, tol, width_cap=None,
                  use_baseline=False):
    """逐行比 y/x/宽。

    [width_cap] 用于 `text-overflow: ellipsis|clip`：浏览器量到的是整行
    自然宽，引擎是截断后的内容宽，行宽按 `min(浏览器, width_cap)` 比较。
    """
    problems = []
    if len(browser_lines) != len(engine_lines):
        problems.append(f'行数: 浏览器 {len(browser_lines)} / 引擎 {len(engine_lines)}')
    for index, (left, right) in enumerate(zip(browser_lines, engine_lines)):
        pos = f'第{index + 1}行'
        for key, limit in (('y', tol), ('x', TOL), ('w', WIDTH_TOL)):
            a, b = left.get(key), right.get(key)
            if (key == 'y' and use_baseline
                    and left.get('baseline') is not None
                    and right.get('baselineAbs') is not None):
                # 行级 y：浏览器 rect 顶受字形盒模型影响（=基线−墨迹 ascent），
                # 直接比基线更稳；浏览器 baseline 由 rect.y+墨迹 ascent 反推，
                # 引擎导出页内绝对基线。
                a, b = left['baseline'], right['baselineAbs']
                limit = BASELINE_TOL
            if a is None or b is None:
                problems.append(f'{pos} {key}: 浏览器 {fmt(a)} / 引擎 {fmt(b)}（缺失）')
                continue
            if key == 'w' and width_cap is not None:
                # 对称截断：截断式布局下两侧都按内容宽封顶，避免
                # 「浏览器整行自然宽 vs 引擎截断宽」的假差异。
                a = min(a, width_cap)
                b = min(b, width_cap)
            if abs(a - b) > limit:
                problems.append(f'{pos} {key}: 浏览器 {fmt(a)} / 引擎 {fmt(b)}')
    return problems


def ellipsis_width_cap(browser_style, block):
    """text-overflow 截断元素的可用行宽上限；不需要时返回 None。

    浏览器文本 rect 报整行自然宽，引擎布局已按内容宽截断，所以宽度维度
    用 `min(浏览器行宽, 内容宽)` 比较（内容宽取引擎 contentWidth，缺失时
    用浏览器边框盒宽扣 padding/border 近似）。
    """
    style = browser_style or {}
    overflow_value = str(style.get('overflow', 'visible')).lower()
    if overflow_value not in ('hidden', 'clip', 'scroll', 'auto'):
        # text-overflow 只在溢出被裁剪时生效；默认 clip 是初始值，不能据此
        # 给每个元素都套宽度上限。
        return None
    text_overflow = str(style.get('textOverflow', '')).lower()
    if text_overflow not in ('ellipsis', 'clip'):
        return None
    cap = block.get('contentWidth')
    if cap is not None:
        return cap
    return None


def overflow_clips(style):
    """浏览器计算样式是否在两轴中的任一轴启用裁剪。"""
    x = str(style.get('overflowX', style.get('overflow', 'visible')))
    y = str(style.get('overflowY', x))
    return any(
        value.strip().lower() not in ('', 'visible', 'none')
        for value in (x, y)
    )


def overflow_visible_lines(lines, rect, style):
    """按内容盒底过滤浏览器行盒；被裁行不参与逐行比较。

    浏览器会报告 overflow 容器内完整布局的全部行，即使内容盒以下已被裁剪。
    引擎只导出实际绘制起点在盒内的行，因此这里按相同口径过滤。
    """
    if not overflow_clips(style):
        return lines
    content_bottom = (
        (rect.get('y') or 0.0)
        + (rect.get('h') or 0.0)
        - box_side(style.get('padding'), 2)
        - box_side(style.get('border'), 2)
    )
    return [
        line for line in lines
        if (line.get('y') or 0.0) < content_bottom - 0.01
    ]


def box_side(value, index):
    """取 CSS 1–4 值盒模型的某一边；浏览器 computed 字符串/引擎数组都支持。"""
    if isinstance(value, (int, float)):
        values = [float(value)]
    elif isinstance(value, (list, tuple)):
        values = [float(item) for item in value]
    else:
        values = [
            float(token)
            for token in re.findall(r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)', str(value))
        ]
    if not values:
        return 0.0
    if len(values) == 1:
        values *= 4
    elif len(values) == 2:
        values = [values[0], values[1], values[0], values[1]]
    elif len(values) == 3:
        values = [values[0], values[1], values[2], values[1]]
    return values[index % 4]


STYLE_KEYS = (
    ('fontSize', 'fontSize', 'number'),
    ('lineHeight', 'lineHeight', 'number'),
    ('letterSpacing', 'letterSpacing', 'number'),
    ('wordSpacing', 'wordSpacing', 'number'),
    ('textIndent', 'textIndent', 'number'),
    ('fontWeight', 'fontWeight', 'number'),
    ('fontStretch', 'fontStretch', 'percent'),
    ('textAlign', 'textAlign', 'enum'),
    ('whiteSpace', 'whiteSpace', 'enum'),
    ('textTransform', 'textTransform', 'enum'),
    ('textDecorationUnderline', 'textDecorationUnderline', 'bool'),
    ('textDecorationLineThrough', 'textDecorationLineThrough', 'bool'),
    ('textDecorationOverline', 'textDecorationOverline', 'bool'),
    ('boxSizing', 'boxSizing', 'enum'),
    ('verticalAlign', 'verticalAlign', 'enum'),
    ('outlineWidth', 'outlineWidth', 'number'),
    ('outlineStyle', 'outlineStyle', 'enum'),
    ('outlineOffset', 'outlineOffset', 'number'),
    # T2 新导出的键（dump 与浏览器两侧同名）
    # 引擎只记录单轴裁剪状态；浏览器会把另一轴从 visible 提升为 auto，
    # 因此把两轴归一成「是否裁剪」再比较，避免 overflow-y-only 的假失配。
    ('overflowX', 'overflow', 'overflow'),
    ('writingMode', 'writingMode', 'enum'),
    ('textOrientation', 'textOrientation', 'enum'),
    ('direction', 'direction', 'enum'),
    ('hyphens', 'hyphens', 'enum'),
    ('wordBreak', 'wordBreak', 'enum'),
    ('overflowWrap', 'overflowWrap', 'enum'),
    ('listStylePosition', 'listStylePosition', 'enum'),
    ('columnCount', 'columnCount', 'number'),
)


def compare_style(browser_style, engine_style):
    problems = []
    for b_key, e_key, kind in STYLE_KEYS:
        left = browser_style.get(b_key)
        right = engine_style.get(e_key)
        if left is None or right is None:
            continue
        if kind == 'overflow':
            equal = overflow_clips(browser_style) == (
                str(right).strip().lower() not in ('', 'visible', 'none')
            )
        elif kind == 'bool':
            equal = bool(left) == bool(right)
        elif kind == 'number':
            if str(left).strip().endswith('%') or str(right).strip().endswith('%'):
                # 浏览器 computed 对部分属性保留百分比（如 text-indent:10%），
                # 与引擎解算后的 px 不可直接比；由几何（行 x）反映。
                continue
            if e_key == 'lineHeight' and str(left).strip().lower() == 'normal':
                # 浏览器对 line-height: normal 不做数值解析，跳过该属性比较
                # （行高差异由块高 h 与行 y 反映）。
                continue
            a, b = norm_number(left), norm_number(right)
            if a is None or b is None:
                equal = str(left) == str(right)
            else:
                equal = abs(a - b) <= STYLE_EPS
        elif kind == 'percent':
            a = norm_number(str(left).strip().removesuffix('%'))
            b = norm_number(str(right).strip().removesuffix('%'))
            equal = a is not None and b is not None and abs(a - b) <= STYLE_EPS
        else:
            equal = norm_enum(left) == norm_enum(right)
        if not equal:
            problems.append(f'{e_key}: 浏览器 {left} / 引擎 {right}')
    return problems


def compare_transform(browser_style, engine_style):
    """transform 字符串（浏览器 matrix）与引擎变换列表不可直接比，先比有无。"""
    browser_raw = str((browser_style or {}).get('transform', 'none')).strip()
    has_browser = browser_raw not in ('', 'none', 'None')
    has_engine = bool((engine_style or {}).get('transform'))
    if has_browser != has_engine:
        return [f'transform: 浏览器 {browser_raw} / 引擎 '
                f'{"有变换" if has_engine else "无变换"}']
    return []


def compare_runs(elements, block):
    """行内 run 与浏览器行内元素比字重/斜体/字号（相对字重覆盖）。

    引擎把 <b>/<strong>/<span> 的行内样式落在 run 上，块级样式看不出来；
    这里按 run 文本去浏览器元素里找同文本的内联元素再比。
    """
    problems = []
    for run in block.get('runs') or []:
        key = nkey(run.get('text', ''))
        if not key:
            continue
        match = None
        for el in elements:
            if el['tag'] in ('p', 'div', 'li', 'td', 'th', 'body', 'html'):
                continue
            if nkey(el.get('text', '')) == key:
                match = el
                break
        if match is None:
            continue
        label = f'行内「{key[:10]}」'
        browser_weight = norm_number(match['style'].get('fontWeight'))
        engine_weight = norm_number(run.get('fontWeight'))
        if (browser_weight is not None and engine_weight is not None
                and abs(browser_weight - engine_weight) > STYLE_EPS):
            problems.append(f'{label} 字重: 浏览器 {match["style"].get("fontWeight")} / 引擎 {run.get("fontWeight")}')
        browser_italic = norm_enum(match['style'].get('fontStyle')) in ('italic', 'oblique')
        engine_italic = bool(run.get('italic'))
        if browser_italic != engine_italic:
            problems.append(f'{label} 斜体: 浏览器 {match["style"].get("fontStyle")} / 引擎 {engine_italic}')
        browser_size = norm_number(match['style'].get('fontSize'))
        engine_size = norm_number(run.get('fontSize'))
        if (browser_size is not None and engine_size is not None
                and abs(browser_size - engine_size) > 0.5):
            problems.append(f'{label} 字号: 浏览器 {match["style"].get("fontSize")} / 引擎 {fmt(run.get("fontSize"))}')
    return problems


def compare_cells(browser_cells, engine_cells, tol=2.0):
    """逐格比较：配对优先级 = 同 (行,列) 且文本一致 → 文本一致 → 顺序。"""
    problems = []
    used = set()
    for cell in engine_cells:
        label = f'格[{cell["row"]},{cell["col"]}]「{nkey(cell["text"], 12)}」'
        candidates = []
        for index, el in enumerate(browser_cells):
            if index in used:
                continue
            same_pos = el.get('row') == cell['row'] and el.get('col') == cell['col']
            same_text = nkey(el.get('text', '')) == nkey(cell['text'])
            candidates.append((0 if same_pos and same_text else 1 if same_text else 2, index, el))
        candidates.sort(key=lambda item: item[0])
        if not candidates or candidates[0][0] > 1:
            problems.append(f'{label} 未配到浏览器单元格')
            continue
        _, index, el = candidates[0]
        used.add(index)
        if nkey(el.get('text', '')) != nkey(cell['text']):
            problems.append(f'{label} 文本: 浏览器「{nkey(el["text"], 12)}」/ 引擎「{nkey(cell["text"], 12)}」')
        for item in compare_rect(el['rect'], cell['rect'], tol=tol):
            problems.append(f'{label} {item}')
        browser_lines = el.get('lines') or []
        engine_lines = cell.get('lines') or []
        if browser_lines and engine_lines:
            for item in compare_lines(browser_lines, engine_lines[:len(browser_lines)], tol):
                problems.append(f'{label} {item}')
    return problems


def compare_table_cells(browser, engine_blocks):
    """按表内 (行,列) 比对；本函数只处理单页（跨页走相对关系）。"""
    problems = []
    tables = [block for block in engine_blocks if block.get('cells')]
    for table_index, block in enumerate(tables):
        browser_cells = [c for c in browser.get('cells', []) if c.get('table') == table_index]
        if not browser_cells:
            problems.append(f'表格{table_index + 1}: 浏览器没有对应单元格')
            continue
        problems.extend(compare_cells(browser_cells, block['cells']))
    return problems


# ---------------------------------------------------------------- 单页用例
def is_vertical(style):
    """书写模式是否为竖排（引擎 `verticalRl` / 浏览器 `vertical-rl` 等）。"""
    mode = str((style or {}).get('writingMode', '')).lower()
    return mode not in ('', 'horizontal-tb', 'horizontaltb', 'horizontal_tb')


def column_count_of(el):
    """浏览器元素的计算 column-count；`auto` 或无法解析按 1 处理。"""
    try:
        return int(str((el.get('style') or {}).get('columnCount', '')))
    except ValueError:
        return 1


def browser_columns(el):
    """从浏览器未合并行里按 x 聚出列带：(列左, 列宽)。"""
    columns = {}
    for line in el.get('rawLines') or []:
        start = round(line['x'], 1)
        end = line['x'] + line['w']
        columns[start] = max(columns.get(start, 0.0), end - start)
    return sorted(columns.items())


def engine_columns(members):
    """引擎每个列块的行范围：(列左, 列宽)。"""
    columns = []
    for member in members:
        lines = member.get('lines') or []
        if not lines:
            continue
        left = min(line['x'] for line in lines)
        right = max(line['x'] + line['w'] for line in lines)
        columns.append((round(left, 1), right - left))
    return columns


def compare_columns(el, members):
    """多列块合并比较：列带并集 bbox + 每列 x/宽 + 逐行（绝对 x/y/宽）。

    引擎把多列容器拆成「每列一个块」，浏览器只有一个元素；先把块按 x 排序
    合并成逻辑块，块级用列带并集 bbox，行级用各列行拼接后与浏览器未合并行
    逐行比。返回 (问题列表, 列描述)。
    """
    problems = []
    style = el.get('style') or {}
    rect_tol = 2.5 if str(style.get('lineHeight', '')).lower() == 'normal' else TOL
    left = min(member['rect']['x'] for member in members)
    top = min(member['rect']['y'] for member in members)
    right = max(member['rect']['x'] + member['rect']['w'] for member in members)
    bottom = max(member['rect']['y'] + member['rect']['h'] for member in members)
    problems.extend(compare_rect(
        el['rect'],
        {'x': left, 'y': top, 'w': right - left, 'h': bottom - top},
        tol=rect_tol,
    ))
    engine_cols = engine_columns(members)
    chrome_cols = browser_columns(el)
    if len(engine_cols) != len(chrome_cols):
        problems.append(f'列数: 浏览器 {len(chrome_cols)} / 引擎 {len(engine_cols)}')
    for index, ((left_e, width_e), (left_c, width_c)) in enumerate(
        zip(engine_cols, chrome_cols)
    ):
        if abs(left_e - left_c) > TOL:
            problems.append(f'第{index + 1}列 x: 浏览器 {fmt(left_c)} / 引擎 {fmt(left_e)}')
        if abs(width_e - width_c) > WIDTH_TOL:
            problems.append(f'第{index + 1}列 w: 浏览器 {fmt(width_c)} / 引擎 {fmt(width_e)}')
    engine_lines = [line for member in members for line in member.get('lines') or []]
    engine_lines.sort(key=lambda item: (round(item['y'], 1), item['x']))
    chrome_lines = sorted(
        el.get('rawLines') or [],
        key=lambda item: (round(item['y'], 1), item['x']),
    )
    if len(engine_lines) != len(chrome_lines):
        problems.append(
            f'多列总行数: 浏览器 {len(chrome_lines)} / 引擎各列之和 {len(engine_lines)}'
        )
    for index, (left_line, right_line) in enumerate(zip(chrome_lines, engine_lines)):
        pos = f'第{index + 1}行'
        for key, limit in (('y', line_tolerance(members[0].get('style') or {})),
                           ('x', TOL), ('w', WIDTH_TOL)):
            if abs(left_line[key] - right_line[key]) > limit:
                problems.append(
                    f'{pos} {key}: 浏览器 {fmt(left_line[key])} / 引擎 {fmt(right_line[key])}'
                )
    desc = (
        f'{len(members)} 列，列 x/宽 = '
        f'[{"、".join(f"{fmt(l)}/{fmt(w)}" for l, w in engine_cols)}]'
    )
    return problems, desc


def diff_single_page(name, browser, engine, meta):
    problems = []
    unpaired = []
    lines = []
    elements = browser_elements(browser)
    tables = browser_tables(browser)
    used = set()
    used_tables = set()
    pages = engine.get('pages') or [{'index': 0, 'blocks': engine.get('blocks', [])}]
    blocks = pages[0].get('blocks', [])
    text_blocks = [block for block in blocks if not block.get('cells')]
    table_blocks = [block for block in blocks if block.get('cells')]
    lines.append(
        f'- 引擎块 {len(text_blocks)}（文字）+ {len(table_blocks)}（表格），'
        f'浏览器可配对元素 {len(elements)}'
    )
    partial = []
    ellipsis = []
    transformed_blocks = []
    vertical_blocks = []
    # 多列容器：引擎每列一个块，浏览器一个元素。先按「块文本是元素文本片段」
    # 把同一容器的列块归组，块级用列带并集 bbox、行级用各列行拼接后比较。
    multicol_groups = {}
    multi_columns = []
    claimed = set()
    for el in elements:
        if column_count_of(el) <= 1:
            continue
        el_key = nkey_long(el['text'])
        members = [
            block for block in text_blocks
            if id(block) not in claimed
            and len(nkey_long(block['text'])) >= 1
            and (
                nkey_long(block['text']) in el_key
                or el_key in nkey_long(block['text'])
            )
        ]
        if not members:
            continue
        members.sort(key=lambda item: (item['rect']['x'], item['rect']['y']))
        multicol_groups[id(el)] = (el, members)
        claimed.update(id(member) for member in members)
    for block in text_blocks:
        if id(block) in claimed:
            continue
        el = pair_element(block, elements, used)
        if el is None:
            el, _ = pair_contained(block, elements, used)
        if el is None:
            unpaired.append(
                f'块「{nkey(block["text"], 12)}」（角色 {block_role(block)}）'
            )
            continue
        label = (str(el['text']).strip().replace('\n', ' ')[:24] or el['tag'])
        tol = line_tolerance(block.get('style') or {})
        vertical = is_vertical(block.get('style')) or is_vertical(el.get('style'))
        if vertical:
            vertical_blocks.append(label)
        found = []
        width_cap = ellipsis_width_cap(el.get('style'), block)
        if width_cap is not None:
            ellipsis.append(label)
        if nkey(el['text']) != nkey(block['text']):
            # 部分配对：浏览器元素里含子块（如 li 里嵌 ul），文本是引擎块的
            # 超集。只比块顶位置与前 min(行数) 行，块高/行数/宽度不可比。
            partial.append(f'「{label}」')
            lines_b = el.get('lines') or []
            lines_e = block.get('lines') or []
            count = min(len(lines_b), len(lines_e))
            found.extend(compare_rect(el['rect'], engine_box_rect(block), keys=('y', 'x')))
            if count and not vertical:
                found.extend(compare_lines(lines_b[:count], lines_e[:count], tol,
                                           width_cap=width_cap))
        else:
            rect_tol = TOL
            if str((el.get('style') or {}).get('lineHeight', '')).lower() == 'normal':
                # 引擎取字体度量整数和、Chrome 用小数，normal 行高存在
                # 0.5px 级差异（12-table 表高 93/91 即此），放宽到 2.5px。
                rect_tol = 2.5
            found.extend(compare_rect(el['rect'], engine_box_rect(block), tol=rect_tol))
            if vertical:
                # 竖排：浏览器 getClientRects 把整列合并成单行，逐行不可比；
                # 只比块盒（x/y/w/h），行级跳过并在报告标注。
                pass
            elif block.get('transformed'):
                # transform 块只比变换后 bbox：dump 的行坐标是变换前的，
                # 与浏览器 getClientRects（已含变换）不可直接比。
                transformed_blocks.append(label)
            else:
                browser_lines = overflow_visible_lines(
                    el.get('lines') or [],
                    el.get('rect') or {},
                    el.get('style') or {},
                )
                found.extend(compare_lines(
                    browser_lines, block.get('lines') or [], tol,
                    width_cap=width_cap,
                    use_baseline=bool(block.get('hasInlineBox')
                                      or is_vertical(block.get('style'))
                                      or is_vertical(el.get('style')))))
        found.extend(compare_style(el.get('style') or {}, block.get('style') or {}))
        found.extend(compare_transform(el.get('style'), block.get('style')))
        found.extend(compare_runs(elements, block))
        if found:
            problems.append(f'「{label}」')
            problems.extend(found)
    # 多列容器：把同一容器的列块合并成逻辑块后比较。
    for el, members in multicol_groups.values():
        label = (str(el['text']).strip().replace('\n', ' ')[:24] or el['tag'])
        found, desc = compare_columns(el, members)
        found.extend(compare_style(el.get('style') or {}, members[0].get('style') or {}))
        multi_columns.append(f'「{label}」{desc}')
        if found:
            problems.append(f'「{label}」（{desc}）')
            problems.extend(found)
    if partial:
        lines.append(
            f'- 部分配对 {len(partial)} 个（浏览器元素含子块，只比块顶与前几行）：'
            + '、'.join(partial[:4])
        )
    if ellipsis:
        lines.append(
            f'- ellipsis/clip 行宽按 min(行宽, 内容宽) 比较（{len(ellipsis)} 个元素）：'
            + '、'.join(ellipsis[:3])
        )
    if multi_columns:
        lines.append(
            f'- 多列块合并比较（列带并集 bbox + 每列 x/宽 + 逐行；{len(multi_columns)} 个）：'
            + '；'.join(multi_columns[:3])
        )
    if vertical_blocks:
        lines.append(
            f'- 竖排块（只比块盒，不比较行级；{len(vertical_blocks)} 个）：'
            + '、'.join(vertical_blocks[:3])
        )
    if transformed_blocks:
        lines.append(
            f'- transform 块只比变换后 bbox，不比较行内坐标（{len(transformed_blocks)} 个）：'
            + '、'.join(transformed_blocks[:3])
        )
    if table_blocks:
        total_cells = sum(len(block['cells']) for block in table_blocks)
        label = f'表格 ×{len(table_blocks)}（合计 {total_cells} 格）'
        found = []
        for index, block in enumerate(table_blocks):
            # 表格块自身没有文字，pair_element 会按 role=table 用单元格文字配对。
            table_element = pair_table(block, tables, used_tables)
            if table_element is None:
                unpaired.append(f'表格{index + 1}（{len(block["cells"])} 格）未配对')
                continue
            found.extend(compare_rect(table_element['rect'], engine_box_rect(block)))
        found.extend(compare_table_cells(browser, table_blocks))
        if found:
            problems.append(f'「{label}」')
            problems.extend(found)
    return problems, lines, unpaired


# ---------------------------------------------------------------- 跨页用例
def page_bottom(block):
    rect = block['rect']
    return (rect.get('y') or 0.0) + (rect.get('h') or 0.0)


def diff_multipage(name, browser, engine, meta):
    """分页 vs 连续流：只比页内相对关系。

    不比较绝对 y（引擎分页会把内容整体下移），只比较：
    行距、页内相邻块间距、宽度；页界断裂只记录。
    """
    problems = []
    unpaired = []
    notes = []
    elements = browser_elements(browser)
    tables = browser_tables(browser)
    used_tables = set()
    pages = engine.get('pages') or []
    page_h = float(engine['pageSize']['h'])
    notes.append(f'- 引擎 {engine.get("pageCount", len(pages))} 页（导出前 {len(pages)} 页），页高 {page_h:.0f}px')
    notes.append('- 比较项：行距 / 页内相邻块间距 / 宽度；不比较绝对 y（分页整体位移），页界断裂只记录不计数')
    if len(pages) < 2 and meta.get('multipage'):
        problems.append('跨页用例没有产生第 2 页（内容不足一页，几何无法对照）')
    previous = None  # (page_index, block, element, page-local top)
    for page in pages:
        page_index = page['index']
        for block in page['blocks']:
            is_table = bool(block.get('cells'))
            el = (pair_table(block, tables, used_tables) if is_table
                  else pair_element(block, elements, set()))
            if el is None:
                unpaired.append(
                    f'第{page_index + 1}页块「{nkey(block.get("text") or "", 10)}」'
                    f'（角色 {block_role(block)}）'
                )
                continue
            style = block.get('style') or {}
            tol = line_tolerance(style)
            found = []
            if is_table:
                found.extend(compare_cells_relative(browser, block, page_index))
            else:
                engine_lines = block.get('lines') or []
                browser_lines = el.get('lines') or []
                if not (is_vertical(style) or is_vertical(el.get('style'))):
                    found.extend(compare_pitch(browser_lines, engine_lines, tol))
                else:
                    notes.append(f'- 竖排块「{nkey(block["text"], 10)}」不比较行距')
                slice_info = block.get('slice') or {}
                if slice_info.get('continuesBefore'):
                    notes.append(
                        f'- 页界：块「{nkey(block["text"], 10)}」从第 '
                        f'{slice_info.get("startLine", 0) + 1} 行续排'
                    )
                for item in compare_rect(el['rect'], engine_box_rect(block), keys=('x', 'w')):
                    found.append(f'宽/位: {item}')
            if previous is not None:
                prev_page, prev_block, prev_el, _ = previous
                if prev_page == page_index and not is_table and not prev_block.get('cells'):
                    engine_gap = (block['rect'].get('y') or 0.0) - page_bottom(prev_block)
                    browser_gap = (prev_el['rect'].get('y') or 0.0) + (prev_el['rect'].get('h') or 0.0)
                    browser_gap = (el['rect'].get('y') or 0.0) - browser_gap
                    if abs(engine_gap - browser_gap) > 2.0:
                        found.append(
                            f'页内间距: 浏览器 {fmt(browser_gap)} / 引擎 {fmt(engine_gap)}'
                        )
            if found:
                problems.append(f'「{nkey(el.get("text", ""), 18)}」')
                problems.extend(found)
            previous = (page_index, block, el, block['rect'].get('y') or 0.0)
    return problems, notes, unpaired


def compare_pitch(browser_lines, engine_lines, tol):
    """跨页切片比行距（不依赖绝对 y）。"""
    problems = []
    if not engine_lines:
        return problems
    if len(engine_lines) == 1:
        return problems
    def pitches(lines):
        return [round(b['y'] - a['y'], 2) for a, b in zip(lines, lines[1:])]
    engine_p = pitches(engine_lines)
    browser_p = pitches(browser_lines)
    if not browser_p:
        return problems
    if len(engine_p) == len(browser_p):
        for index, (a, b) in enumerate(zip(browser_p, engine_p)):
            if abs(a - b) > tol:
                problems.append(f'行距{index + 1}: 浏览器 {fmt(a)} / 引擎 {fmt(b)}')
    else:
        mean_browser = sum(browser_p) / len(browser_p)
        mean_engine = sum(engine_p) / len(engine_p)
        if abs(mean_browser - mean_engine) > tol:
            problems.append(f'平均行距: 浏览器 {fmt(mean_browser)} / 引擎 {fmt(mean_engine)}')
    return problems


def compare_cells_relative(browser, block, page_index):
    """跨页表格只比格宽/格高与行列间距。"""
    problems = []
    browser_cells = [c for c in browser.get('cells', []) if c.get('table') == 0]
    if not browser_cells:
        problems.append(f'第{page_index + 1}页表格没有对应浏览器单元格')
        return problems
    engine_cells = block['cells']
    def pitches(cells, axis):
        values = []
        for a in cells:
            for b in cells:
                same_line = a['row'] == b['row'] if axis == 'x' else a['col'] == b['col']
                step = b['col'] - a['col'] if axis == 'x' else b['row'] - a['row']
                if same_line and step == 1:
                    delta = (b['rect']['x'] - a['rect']['x']) if axis == 'x' else (b['rect']['y'] - a['rect']['y'])
                    values.append(round(delta, 2))
        return values
    for axis, name in (('x', '列间距'), ('y', '行间距')):
        engine_p = pitches(engine_cells, axis)
        browser_p = pitches(browser_cells, axis)
        for index, (a, b) in enumerate(zip(browser_p, engine_p)):
            if abs(a - b) > 2.0:
                problems.append(f'{name}{index + 1}: 浏览器 {fmt(a)} / 引擎 {fmt(b)}')
    for browser_cell, engine_cell in zip(browser_cells, engine_cells):
        for item in compare_rect(browser_cell['rect'], engine_cell['rect'], keys=('w', 'h')):
            problems.append(f'格[{engine_cell["row"]},{engine_cell["col"]}] {item}')
    return problems


# ---------------------------------------------------------------- 视觉差异
def pixel_ratio(name):
    browser_path = OUT / f'browser_{name}.png'
    engine_path = OUT / f'engine_{name}.png'
    if not browser_path.exists() or not engine_path.exists():
        return None
    browser = Image.open(browser_path).convert('RGB')
    engine = Image.open(engine_path).convert('RGB')
    if browser.size != engine.size:
        return 1.0
    diff = ImageChops.difference(browser, engine).convert('L')
    histogram = diff.histogram()
    changed = sum(histogram[8:])  # 忽略 <=7 的量化噪声
    total = browser.width * browser.height
    return changed / total if total else 0.0


def montage(name):
    browser = Image.open(OUT / f'browser_{name}.png').convert('RGB')
    engine = Image.open(OUT / f'engine_{name}.png').convert('RGB')
    width = browser.width + engine.width + 12
    height = max(browser.height, engine.height)
    canvas = Image.new('RGB', (width, height), (255, 0, 255))
    canvas.paste(browser, (0, 0))
    canvas.paste(engine, (browser.width + 12, 0))
    canvas.save(OUT / f'side_{name}.png')


# ---------------------------------------------------------------- 汇总
def run_case(name):
    meta = case_meta(name)
    browser, engine = load(name)
    if meta['engine_only']:
        pages = engine.get('pages') or []
        blocks = sum(len(page.get('blocks') or []) for page in pages)
        # 导出只取前 2 页；页数口径要用引擎 pageCount，不能数导出页。
        total_pages = int(engine.get('pageCount', len(pages)))
        notes = [
            f'- 浏览器不支持该属性，只记录引擎行为（{total_pages} 页、'
            f'{blocks} 块），不计失配'
        ]
        expect = meta.get('expect') or {}
        if expect:
            first = (pages[0].get('blocks') or [{}])[0] if pages else {}
            rect = first.get('rect') or {}
            advance = expect.get('columnAdvance')
            columns = None
            if advance:
                columns = int(round((rect.get('w') or 0.0) / float(advance)))
            notes.append(
                f'- 期望：{expect.get("pages", "?")} 页（±{expect.get("pagesTolerance", 0)}）、'
                f'每页 {expect.get("columnsPerPage", expect.get("columnsUsed", "?"))} 列、每列 '
                f'{expect.get("charsPerColumn", "?")} 字、列推进 '
                f'{expect.get("columnAdvance", "?")}px、页内 '
                f'{expect.get("direction", "?")}；实测：{total_pages} 页、{blocks} 块、'
                f'首块 {fmt(rect.get("w"))}×{fmt(rect.get("h"))}'
                + (f'、列数 {columns}' if columns is not None else '')
            )
            tolerance = int(expect.get('pagesTolerance', 0))
            if abs(total_pages - int(expect.get('pages', total_pages))) > tolerance:
                notes.append(
                    f'- ⚠ 页数与期望不符（期望 {expect.get("pages")}±{tolerance} / '
                    f'实测 {total_pages}）'
                )
            expected_width = expect.get('firstBlockWidth')
            if expected_width is not None and abs(
                (rect.get('w') or 0.0) - float(expected_width)
            ) > 2.0:
                notes.append(
                    f'- ⚠ 首块宽度与期望不符（期望 {expected_width} / '
                    f'实测 {fmt(rect.get("w"))}）'
                )
            expected_columns = expect.get('columnsUsed')
            if expected_columns is not None and columns is not None \
                    and abs(columns - int(expected_columns)) > 1:
                notes.append(
                    f'- ⚠ 页内列数与期望不符（期望 {expected_columns} / 实测 {columns}）'
                )
        return {
            'name': name,
            'meta': meta,
            'dimension': (meta['tags'] or ['未标注'])[0],
            'problems': [],
            'unpaired': [],
            'notes': notes,
            'visual': None,
            'null_geometry': engine.get('nullGeometry') or [],
        }
    if meta['multipage'] or int(engine.get('pageCount', 1)) > 1:
        problems, notes, unpaired = diff_multipage(name, browser, engine, meta)
    else:
        problems, notes, unpaired = diff_single_page(name, browser, engine, meta)
    ratio = pixel_ratio(name)
    if ratio is not None:
        montage(name)
    dimension = meta['tags'][0] if meta['tags'] else '未标注'
    return {
        'name': name,
        'meta': meta,
        'dimension': dimension,
        # 去重：同一用例里完全相同的失配行只计一次。
        'problems': list(dict.fromkeys(problems)),
        'unpaired': unpaired,
        'notes': notes,
        'visual': ratio,
        'null_geometry': engine.get('nullGeometry') or [],
    }


def top_table(results):
    buckets = {}
    for result in results:
        if not result['problems']:
            continue
        bucket = buckets.setdefault(
            result['dimension'],
            {'count': 0, 'cases': [], 'sample': ''},
        )
        bucket['count'] += len(result['problems'])
        if result['name'] not in bucket['cases']:
            bucket['cases'].append(result['name'])
        if not bucket['sample']:
            bucket['sample'] = f"{result['name']}: {result['problems'][0][:60]}"
    ordered = sorted(buckets.items(), key=lambda item: (-item[1]['count'], item[0]))
    rows = ['| # | 属性维度 | 失配项 | 用例数 | 代表用例与首条失配 |', '| --- | --- | --- | --- | --- |']
    for rank, (dimension, bucket) in enumerate(ordered[:10], start=1):
        rows.append(
            f"| {rank} | {dimension} | {bucket['count']} | {len(bucket['cases'])} | "
            f"{bucket['sample'].replace('|', '/')} |"
        )
    return rows, ordered


def dimension_table(ordered):
    rows = ['| 属性维度 | 失配项 | 用例数 | 用例 |', '| --- | --- | --- | --- |']
    for dimension, bucket in ordered:
        cases = '、'.join(case for case in bucket['cases'][:6])
        if len(bucket['cases']) > 6:
            cases += f' 等 {len(bucket["cases"])} 个'
        rows.append(f'| {dimension} | {bucket["count"]} | {len(bucket["cases"])} | {cases} |')
    return rows


def visual_table(results):
    rows = ['| 用例 | 差异像素占比 | 判定 |', '| --- | --- | --- |']
    for result in sorted(results, key=lambda item: -(item['visual'] or 0.0)):
        ratio = result['visual']
        if ratio is None:
            rows.append(f"| {result['name']} | 缺图 | - |")
            continue
        flag = '显著差异' if ratio > PIXEL_FLAG else '接近'
        rows.append(f"| {result['name']} | {ratio * 100:.2f}% | {flag} |")
    return rows


def detail_case(result):
    lines = [f"## {result['name']}"]
    tags = '、'.join(result['meta']['tags']) or '未标注'
    visual = result['visual']
    visual_text = '未统计' if visual is None else f'{visual * 100:.2f}%'
    lines.append(
        f"- 维度 {tags}；几何/样式失配 {len(result['problems'])} 项；"
        f"视觉差异 {visual_text}"
    )
    if result['notes']:
        lines.extend(result['notes'])
    for item in result.get('unpaired') or []:
        lines.append(f'- 未配对（不计失配）：{item}')
    if result['null_geometry']:
        sample = '、'.join(result['null_geometry'][:3])
        lines.append(f"- 引擎非有限几何（Infinity/NaN，已按未知处理）：{sample}")
    for problem in result['problems']:
        lines.append(f'- {problem}' if problem.startswith('「') else f'  - {problem}')
    return lines


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description='CSS 属性对照：浏览器 vs 引擎几何/样式比对',
    )
    parser.add_argument('cases', nargs='*', help='只跑指定用例（默认全部）')
    parser.add_argument(
        '--threshold',
        type=int,
        default=int(os.environ.get('CSS_PARITY_THRESHOLD', '0')),
        help='失配门禁：任一属性维度的失配项数超过该值时退出码为 2；'
             '默认 0（不启用），也可用 CSS_PARITY_THRESHOLD 设置',
    )
    return parser.parse_args(argv)


def unpaired_section(results):
    rows = ['## 未配对（不计失配）', '']
    rows.append('| 用例 | 未配对块数 | 明细 |')
    rows.append('| --- | --- | --- |')
    total = 0
    for result in results:
        items = result.get('unpaired') or []
        if not items:
            continue
        total += len(items)
        sample = '；'.join(items[:4]).replace('|', '/')
        if len(items) > 4:
            sample += f' 等 {len(items)} 项'
        rows.append(f'| {result["name"]} | {len(items)} | {sample} |')
    if total == 0:
        rows.append('| - | 0 | 全部块都配到了浏览器元素 |')
    return rows


def main(argv=None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    # 用例以 cases/*.json 为准：OUT 里可能残留已删除用例的 browser_*.json，
    # 不能再按输出目录枚举，否则会多出「缺少数据」的幽灵用例。
    names = args.cases or sorted(path.stem for path in CASES.glob('*.json'))
    results, missing = [], []
    for name in names:
        try:
            results.append(run_case(name))
        except FileNotFoundError as err:
            meta = case_meta(name)
            missing.append(name)
            results.append({
                'name': name,
                'meta': meta,
                'dimension': (meta['tags'] or ['未标注'])[0],
                'problems': [f'缺少数据：{err.filename}'],
                'unpaired': [],
                'notes': [],
                'visual': None,
                'null_geometry': [],
            })
    flagged = [result for result in results if result['problems']]
    mismatches = sum(len(result['problems']) for result in results)
    unpaired_total = sum(len(result.get('unpaired') or []) for result in results)
    unpaired_cases = sum(1 for result in results if result.get('unpaired'))
    top_rows, ordered = top_table(results)
    report = [
        '# CSS 属性对照报告',
        '',
        f'- 用例 {len(results)} 个：失配 {mismatches} 项，涉及 {len(flagged)} 个用例；'
        f'未配对 {unpaired_total} 项（{unpaired_cases} 个用例，不计失配）',
        f"- 视觉差异超阈值 {PIXEL_FLAG * 100:.0f}% 的 "
        f"{sum(1 for result in results if (result['visual'] or 0.0) > PIXEL_FLAG)} 个",
        f'- 数据目录 `{OUT}`：browser_*/engine_*（几何与截图）、side_*.png（左浏览器 / 右引擎）',
        '- 口径：行宽 = 行实际占据宽（引擎 advanceWidth，含 justify 均分；浏览器量的是绘制宽）；'
        '跨页用例只比页内相对关系；ul/ol 等容器不参与块配对，li 只对列表项块。',
        '',
        '## Top 失配清单（按维度）',
        '',
        *top_rows,
        '',
        '## 按属性维度汇总',
        '',
        *dimension_table(ordered),
        '',
        *unpaired_section(results),
        '',
        '## 视觉差异（像素占比）',
        '',
        *visual_table(results),
        '',
        '## 逐用例明细',
        '',
    ]
    for result in results:
        report.extend(detail_case(result))
        report.append('')
    if missing:
        report.append(f'- 缺少引擎/浏览器数据的用例：{"、".join(missing)}')
    text = '\n'.join(report)
    (OUT / 'report.md').write_text(text, encoding='utf-8')
    print(text)
    if args.threshold > 0:
        over = [(dimension, bucket) for dimension, bucket in ordered
                if bucket['count'] > args.threshold]
        if over:
            for dimension, bucket in over:
                print(
                    f'门禁失败：维度 {dimension} 失配 {bucket["count"]} 项'
                    f' > 阈值 {args.threshold}',
                    file=sys.stderr,
                )
            return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
