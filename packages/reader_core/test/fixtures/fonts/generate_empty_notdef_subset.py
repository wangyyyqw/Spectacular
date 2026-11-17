"""生成空缺字轮廓的子集回归字库；测试不执行此脚本。

再生：在已有 fontTools 的 Python 环境运行本文件。字形全部由矩形构造，
不包含原书或第三方字体数据；.notdef 和全角空格为空轮廓，并故意缺少
U+2060、U+FFFC，以复现跨字体行内占位测量的原生崩溃。
"""

from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

characters = '　题记扰尘埃'
order = ['.notdef'] + [f'uni{ord(char):04X}' for char in characters]
font = FontBuilder(1000, isTTF=True)
font.setupGlyphOrder(order)
glyphs = {}
for name, char in zip(order, ' ' + characters):
    pen = TTGlyphPen(None)
    if char not in '　 ':
        pen.moveTo((100, 0))
        pen.lineTo((900, 0))
        pen.lineTo((900, 800))
        pen.lineTo((100, 800))
        pen.closePath()
    glyphs[name] = pen.glyph()
font.setupGlyf(glyphs)
font.setupHorizontalMetrics({name: (1000, 0) for name in order})
font.setupHorizontalHeader(ascent=800, descent=-200)
font.setupCharacterMap({ord(char): name for char, name in zip(characters, order[1:])})
font.setupNameTable({
    'familyName': 'EmptyNotdefSubset',
    'styleName': 'Regular',
    'uniqueFontIdentifier': 'Spectacular-EmptyNotdefSubset-1',
    'fullName': 'EmptyNotdefSubset Regular',
    'psName': 'EmptyNotdefSubset-Regular',
    'version': 'Version 1.0',
})
font.setupOS2(sTypoAscender=800, sTypoDescender=-200,
             usWinAscent=800, usWinDescent=200, fsType=0)
font.setupPost()
font.setupMaxp()
font.font['head'].created = 2082844800
font.font['head'].modified = 2082844800
font.font.recalcTimestamp = False
font.save(Path(__file__).with_name('EmptyNotdefSubset.ttf'))
