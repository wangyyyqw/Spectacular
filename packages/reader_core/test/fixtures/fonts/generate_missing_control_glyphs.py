"""生成行内占位回归字库；仅再生时需要 fontTools，测试不执行此脚本。

运行：python3 test/fixtures/fonts/generate_missing_control_glyphs.py
字形全部从矩形构造，不包含书籍或其他字体的数据。故意不提供空格、
U+2060 和 U+FFFC，使排版引擎使用真实的控制字符与占位回退路径。
"""

from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

characters = '题记扰尘埃'
glyph_order = ['.notdef'] + [f'uni{ord(char):04X}' for char in characters]
font = FontBuilder(1000, isTTF=True)
font.setupGlyphOrder(glyph_order)
glyphs = {}
for name in glyph_order:
    pen = TTGlyphPen(None)
    pen.moveTo((100, 0))
    pen.lineTo((900, 0))
    pen.lineTo((900, 800))
    pen.lineTo((100, 800))
    pen.closePath()
    glyphs[name] = pen.glyph()
font.setupGlyf(glyphs)
font.setupHorizontalMetrics({name: (1000, 0) for name in glyph_order})
font.setupHorizontalHeader(ascent=800, descent=-200)
font.setupCharacterMap({ord(char): f'uni{ord(char):04X}' for char in characters})
font.setupNameTable({
    'familyName': 'MissingControlGlyphs',
    'styleName': 'Regular',
    'uniqueFontIdentifier': 'Spectacular-MissingControlGlyphs-1',
    'fullName': 'MissingControlGlyphs Regular',
    'psName': 'MissingControlGlyphs-Regular',
    'version': 'Version 1.0',
})
font.setupOS2(
    sTypoAscender=800,
    sTypoDescender=-200,
    usWinAscent=800,
    usWinDescent=200,
    fsType=0,
)
font.setupPost()
font.setupMaxp()
font.font['head'].created = 2082844800
font.font['head'].modified = 2082844800
font.font.recalcTimestamp = False
font.save(Path(__file__).with_name('MissingControlGlyphs.ttf'))
