#!/usr/bin/env python3
"""生成 CSS 属性覆盖矩阵（属性 × 用例）。

数据源：
1. docs/css-property-audit.md：116 条属性审计（A 组=解析且消费 69 条、
   C 组=占位式 7 条、D 组=完全未处理 40 条）；
2. packages/reader_core/lib/css/computed_style.dart：当前取值点
   （explicitValue/fontValue/backgroundValue/dimension），用于标注审计外新增；
3. tool/css_parity/cases/*.json：扫描 css 与 html（含内联 style）里的声明，
   声明出现即算覆盖。

输出：tool/css_parity/coverage.md（幂等，可重复运行）。

用法：/usr/bin/python3 tool/css_parity/coverage.py
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
AUDIT = ROOT / 'docs/css-property-audit.md'
COMPUTED = ROOT / 'packages/reader_core/lib/css/computed_style.dart'
CASES = pathlib.Path(__file__).resolve().parent / 'cases'
OUT = pathlib.Path(__file__).resolve().parent / 'coverage.md'

GROUP_TITLES = {
    'consume': '解析且消费（审计 A 组）',
    'placeholder': '占位式（审计 C 组：有字段、零消费）',
    'unhandled': '完全未处理（审计 D 组：无字段）',
}
FOUR_CORNERS = (
    'border-top-left-radius', 'border-top-right-radius',
    'border-bottom-right-radius', 'border-bottom-left-radius',
)
LOGICAL_PROPS = (
    'margin-inline-start', 'margin-inline-end',
    'padding-inline-start', 'padding-inline-end',
    'border-inline-start', 'border-inline-end',
)
LONG_TAIL_FROM = 46  # 长尾用例起始编号


# ---------------------------------------------------------------- 审计文档
def audit_rows(text, start_marker, end_marker):
    """取某节 `| # | 属性 | ...` 表格行：(审计编号, 属性单元格)。"""
    start = text.index(start_marker)
    end = text.index(end_marker, start) if end_marker else len(text)
    rows = []
    for line in text[start:end].splitlines():
        if not line.startswith('|'):
            continue
        cells = [cell.strip() for cell in line.strip('|').split('|')]
        if len(cells) < 2 or not cells[0].isdigit():
            continue
        rows.append((int(cells[0]), cells[1]))
    return rows


def expand_names(cell):
    """把属性单元格展开成单个属性名（`a/-b/-c`、`x` / `-y`、四角、逻辑属性）。"""
    if '逻辑属性' in cell:
        return list(LOGICAL_PROPS)
    if '等四角' in cell:
        return list(FOUR_CORNERS)
    tokens = re.findall(r'`([^`]+)`', cell) or [cell]
    names = []
    for token in tokens:
        token = re.sub(r'\s*[:：].*$', '', token).strip()
        if not token:
            continue
        # `text-decoration` / `-line`：后半截是后缀，base 与 base-line 都算
        if token.startswith('-') and token.count('-') == 1 and names:
            names.append(f'{names[-1]}{token}')
            continue
        if '/' in token:
            base, *rest = token.split('/')
            base = base.strip()
            if rest and all(part.startswith('-') for part in rest):
                prefix = base.rsplit('-', 1)[0]
                names.append(base)
                names.extend(f'{prefix}{part}' for part in rest)
                continue
            names.extend(part.strip() for part in token.split('/') if part.strip())
            continue
        names.append(token)
    out = []
    for name in names:
        if re.fullmatch(r'-{0,2}[a-z][a-z0-9-]*', name) and name not in out:
            out.append(name)
    return out


def load_audit(path):
    """返回审计条目列表：审计编号、属性名、分组、所在单元格原文。"""
    text = path.read_text(encoding='utf-8')
    sections = {
        'consume': ('### 3.1 A 组', '### 3.2 B 组'),
        'placeholder': ('### 3.3 C 组', '### 3.4 D 组'),
        'unhandled': ('### 3.4 D 组', '\n## 4. '),
    }
    entries = []
    for group, (start, end) in sections.items():
        for audit_id, cell in audit_rows(text, start, end):
            for name in expand_names(cell):
                entries.append({
                    'audit_id': audit_id,
                    'name': name,
                    'group': group,
                    'raw': re.sub(r'\s+', ' ', cell.replace('`', '')).strip(),
                })
    return entries


# ---------------------------------------------------------------- 解析点与用例
def load_parse_points(path):
    text = path.read_text(encoding='utf-8')
    pattern = re.compile(
        r"(?:explicitValue|fontValue|backgroundValue|dimension)\(\s*'(-{0,2}[a-z][a-z0-9-]*)'"
    )
    return sorted(set(pattern.findall(text)))


def load_cases(directory):
    cases = []
    for path in sorted(directory.glob('*.json')):
        data = json.loads(path.read_text(encoding='utf-8'))
        cases.append({
            'id': path.stem.split('-')[0],
            'name': str(data.get('name', path.stem)),
            'text': f"{data.get('css', '')}\n{data.get('html', '')}",
        })
    return cases


def declaration_pattern(name):
    """声明匹配：允许厂商前缀别名（-duokan-bleed 与 duokan-bleed 互认）。"""
    bare = re.escape(name.lstrip('-'))
    return re.compile(rf'(?<![\w-])-{{0,2}}{bare}\s*:', re.IGNORECASE)


def find_coverage(entries, cases):
    covered = {}
    seen = set()
    for entry in entries:
        name = entry['name']
        if name in seen:
            continue
        seen.add(name)
        pattern = declaration_pattern(name)
        hits = [case['id'] for case in cases if pattern.search(case['text'])]
        if hits:
            covered[name] = hits
    return covered


def suggest_case_numbers(uncovered, first_free, per_case=2):
    """未覆盖属性按 1-2 个一组分配建议用例编号。"""
    suggestions = {}
    for index in range(0, len(uncovered), per_case):
        number = first_free + index // per_case
        for entry in uncovered[index:index + per_case]:
            suggestions.setdefault(entry['name'], number)
    return suggestions


# ---------------------------------------------------------------- 输出
def covered_table(entries, covered, group):
    rows = ['| 属性 | 审计编号 | 覆盖用例 |', '| --- | --- | --- |']
    for entry in entries:
        if entry['group'] != group or entry['name'] not in covered:
            continue
        rows.append(
            f"| `{entry['name']}` | #{entry['audit_id']} | "
            f"{'、'.join(covered[entry['name']])} |"
        )
    if len(rows) == 2:
        rows.append('| - | - | - |')
    return rows


def uncovered_table(entries, covered, group, suggestions):
    rows = ['| 属性 | 审计编号 | 审计原文 | 建议用例 |', '| --- | --- | --- | --- |']
    for entry in entries:
        if entry['group'] != group or entry['name'] in covered:
            continue
        number = suggestions.get(entry['name'])
        rows.append(
            f"| `{entry['name']}` | #{entry['audit_id']} | {entry['raw']} | "
            f"{number if number else '-'} |"
        )
    if len(rows) == 2:
        rows.append('| - | - | - | - |')
    return rows


def new_case_section(cases, covered):
    """编号 ≥ LONG_TAIL_FROM 的用例「首次覆盖」了哪些属性。

    只看每个属性的首个覆盖用例，避免通用属性（font-size 等）在每个
    长尾用例里重复列一遍。
    """
    by_case = {}
    for name, ids in covered.items():
        first = min(ids, key=int)
        if int(first) >= LONG_TAIL_FROM:
            by_case.setdefault(first, []).append(name)
    rows = ['| 用例 | 覆盖属性 |', '| --- | --- |']
    for case_id in sorted(by_case, key=int):
        names = '、'.join(f'`{name}`' for name in sorted(by_case[case_id]))
        rows.append(f'| {case_id} | {names} |')
    if len(rows) == 2:
        rows.append('| - | - |')
    return rows


def build_report(entries, covered, cases, parse_points):
    names = list(dict.fromkeys(entry['name'] for entry in entries))
    group_of = {}
    for entry in entries:
        group_of.setdefault(entry['name'], entry['group'])
    dedicated = []
    seen = set()
    for entry in entries:
        if entry['name'] in covered or entry['name'] in seen:
            continue
        seen.add(entry['name'])
        dedicated.append(entry)
    first_free = max(int(case['id']) for case in cases) + 1
    suggestions = suggest_case_numbers(
        [entry for entry in dedicated if entry['group'] == 'consume'], first_free
    )
    rest = [entry for entry in dedicated if entry['group'] != 'consume']
    if rest:
        rest_start = first_free + len(
            [entry for entry in dedicated if entry['group'] == 'consume']
        ) // 2
        suggestions.update(suggest_case_numbers(rest, rest_start))
    covered_total = len([name for name in names if name in covered])
    total = len(names)
    audit_names = set(names)
    audit_extra = [name for name in parse_points if name not in audit_names]

    lines = [
        '# CSS 属性覆盖矩阵',
        '',
        '> 由 `tool/css_parity/coverage.py` 生成（幂等，可重复运行）。',
        '> 属性清单 = `docs/css-property-audit.md` 的 116 条审计（A/C/D 组）展开；',
        '> 覆盖判定 = `tool/css_parity/cases/*.json` 的 `css` 与 `html`（含内联',
        '> style）中出现该属性声明（含厂商前缀别名）即算覆盖。',
        '',
        f'- 审计条目 **116** 条，展开后属性名 **{total}** 个（同一条目里的多属性按名拆分）',
        f'- 已覆盖 **{covered_total}** 个（{covered_total / total * 100:.1f}%），'
        f'未覆盖 **{total - covered_total}** 个',
        f'- 用例 **{len(cases)}** 个（编号 {cases[0]["id"]}–{cases[-1]["id"]}）',
        f'- 下一个可用用例编号：**{first_free}**（未覆盖表的「建议用例」按 1-2 属性/例分配）',
        '',
        '## 1. 分组覆盖概览',
        '',
        '| 分组 | 属性数 | 已覆盖 | 覆盖率 |',
        '| --- | --- | --- | --- |',
    ]
    for group, title in GROUP_TITLES.items():
        group_names = [name for name in names if group_of[name] == group]
        done = [name for name in group_names if name in covered]
        rate = len(done) / len(group_names) * 100 if group_names else 0.0
        lines.append(f'| {title} | {len(group_names)} | {len(done)} | {rate:.1f}% |')
    lines.extend([
        '',
        '## 2. 未覆盖清单（按分组，附建议用例编号）',
        '',
    ])
    for group, title in GROUP_TITLES.items():
        lines.append(f'### {title}')
        lines.append('')
        lines.extend(uncovered_table(dedicated, covered, group, suggestions))
        lines.append('')
    lines.extend([
        '## 3. 已覆盖清单',
        '',
    ])
    for group, title in GROUP_TITLES.items():
        lines.append(f'### {title}')
        lines.append('')
        lines.extend(covered_table(entries, covered, group))
        lines.append('')
    lines.extend([
        '## 4. 编号 ≥46 的长尾用例',
        '',
        '每个用例聚焦 1-2 个此前零覆盖、且引擎有解析/有消费的属性；',
        '下表只列该用例「首次覆盖」的属性（通用属性如 font-size 不重复列）。',
        '',
        *new_case_section(cases, covered),
        '',
        '## 5. 审计外的新增解析点',
        '',
        '`computed_style.dart` 里有取值点、但审计 116 条未列出的属性',
        '（审计基线之后新增，需 T7 复核是否真的消费）：',
        '',
    ])
    if audit_extra:
        lines.append('、'.join(f'`{name}`' for name in audit_extra))
    else:
        lines.append('- 无')
    lines.extend([
        '',
        '## 6. 口径说明',
        '',
        '- 「声明出现即算覆盖」是保守判据：只有写法与属性名完全一致才算；',
        '  简写（`margin`、`border`、`background`）不自动覆盖其长属性，',
        '  因此 `margin-top` 等长属性仍会出现在未覆盖表里，需要单独声明。',
        '- 审计分组沿用 `docs/css-property-audit.md`：A 组解析且消费、C 组占位式、',
        '  D 组完全未处理；引擎后续改动可能让分组过期，第 5 节列出审计外变化。',
        '- 未覆盖表的建议编号只是排期建议，新增用例后重跑本脚本会自动前移。',
        '',
    ])
    return '\n'.join(lines)


def main():
    entries = load_audit(AUDIT)
    parse_points = load_parse_points(COMPUTED)
    cases = load_cases(CASES)
    covered = find_coverage(entries, cases)
    report = build_report(entries, covered, cases, parse_points)
    OUT.write_text(report, encoding='utf-8')
    names = list(dict.fromkeys(entry['name'] for entry in entries))
    covered_total = len([name for name in names if name in covered])
    print(
        f'写出 {OUT}：属性 {len(names)} 个，已覆盖 {covered_total} 个'
        f'（{covered_total / len(names) * 100:.1f}%），用例 {len(cases)} 个'
    )


if __name__ == '__main__':
    main()
