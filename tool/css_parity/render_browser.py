#!/usr/bin/env python3
"""把 cases/*.json 渲染成浏览器截图（Chrome headless，350x800，dpr=1）。

用法：/usr/bin/python3 tool/css_parity/render_browser.py
输出：/tmp/css_parity/browser_<name>.png 与 <name>.html
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CASES = ROOT / 'tool' / 'css_parity' / 'cases'
OUT = pathlib.Path('/tmp/css_parity')
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
FONT_REG = ROOT / 'apps/reader_mobile/assets/fonts/SourceHanSerifCN-Regular.otf'
FONT_BOLD = ROOT / 'apps/reader_mobile/assets/fonts/SourceHanSerifCN-Bold.otf'

WIDTH, HEIGHT = 350, 800

TEMPLATE = """<!DOCTYPE html>
<html><head><meta charset="utf-8"/>
<style>
@font-face {{ font-family: "builtin_song"; src: url("file://{font_regular}"); font-weight: 400; }}
@font-face {{ font-family: "builtin_song"; src: url("file://{font_bold}"); font-weight: 700; }}
html, body {{ background: #ffffff; }}
{css}
</style></head>
<body>{html}</body></html>
"""


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for path in sorted(CASES.glob('*.json')):
        case = json.loads(path.read_text(encoding='utf-8'))
        name = case['name']
        html = TEMPLATE.format(
            font_regular=FONT_REG,
            font_bold=FONT_BOLD,
            css=case['css'],
            html=case['html'],
        )
        html_path = OUT / f'{name}.html'
        html_path.write_text(html, encoding='utf-8')
        png_path = OUT / f'browser_{name}.png'
        result = subprocess.run(
            [
                CHROME,
                '--headless=new',
                '--disable-gpu',
                '--hide-scrollbars',
                '--no-first-run',
                '--force-device-scale-factor=1',
                f'--window-size={WIDTH},{HEIGHT}',
                f'--screenshot={png_path}',
                html_path.as_uri(),
            ],
            capture_output=True,
            text=True,
            timeout=90,
        )
        if result.returncode != 0 or not png_path.exists():
            print(f'FAIL {name}: {result.returncode} {result.stderr[-300:]}')
            return 1
        subprocess.run(
            [
                '/usr/bin/python3',
                '-c',
                'from PIL import Image; import sys; '
                'im = Image.open(sys.argv[1]); '
                'im.resize((350, 800)).save(sys.argv[1])',
                str(png_path),
            ],
            check=False,
        )
        print(f'ok {name}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
