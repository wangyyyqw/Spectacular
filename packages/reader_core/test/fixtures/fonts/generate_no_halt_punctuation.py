"""生成无 halt 标点留白回归字库；测试不执行此脚本。

再生：在安装 fontTools 的 Python 环境运行本文件。所有轮廓从矩形构造，
不含书籍或其他字体的数据。逗号和引号保留可回收的侧边留白，叹号满格，
用于验证字体度量回退不能挤压墨迹。字库不包含 GSUB/GPOS 表。
"""

from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

characters = '甲乙丙丁戊己，。！“”'
glyph_order = ['.notdef'] + [f'uni{ord(char):04X}' for char in characters]
font = FontBuilder(1000, isTTF=True)
font.setupGlyphOrder(glyph_order)
rectangles = {
    '，': (200, -100, 350, 100),
    '。': (200, 0, 350, 150),
    '“': (650, 600, 800, 800),
    '”': (200, 600, 350, 800),
    '！': (0, 0, 1000, 800),
}
glyphs = {}
metrics = {}
for name, char in zip(glyph_order, [''] + list(characters)):
    left, bottom, right, top = rectangles.get(char, (100, 0, 900, 800))
    pen = TTGlyphPen(None)
    pen.moveTo((left, bottom))
    pen.lineTo((right, bottom))
    pen.lineTo((right, top))
    pen.lineTo((left, top))
    pen.closePath()
    glyphs[name] = pen.glyph()
    metrics[name] = (1000, left)
font.setupGlyf(glyphs)
font.setupHorizontalMetrics(metrics)
font.setupHorizontalHeader(ascent=800, descent=-200)
font.setupCharacterMap({ord(char): f'uni{ord(char):04X}' for char in characters})
font.setupNameTable({
    'familyName': 'NoHaltPunctuation',
    'styleName': 'Light',
    'uniqueFontIdentifier': 'Spectacular-NoHaltPunctuation-1',
    'fullName': 'NoHaltPunctuation Light',
    'psName': 'NoHaltPunctuation-Light',
    'version': 'Version 1.0',
})
font.setupOS2(
    sTypoAscender=800,
    sTypoDescender=-200,
    usWinAscent=800,
    usWinDescent=200,
    usWeightClass=300,
    fsType=0,
)
font.setupPost()
font.setupMaxp()
font.font['head'].created = 2082844800
font.font['head'].modified = 2082844800
font.font.recalcTimestamp = False
font.save(Path(__file__).with_name('NoHaltPunctuation.ttf'))
