import 'package:flutter_test/flutter_test.dart';

import 'support/css_chapter_book.dart';

/// 盒模型可用宽（P9-28）：块排版宽 = 内容盒宽，声明 `width` 按
/// `box-sizing` 折算——`border-box` 的声明值已含 padding/border。
///
/// 用例取自 tool/css_parity/cases/09-box-model.json（浏览器对照）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, double>> textWidths(String css) async {
    final source = await openCssChapter(
      body:
          '<p class="auto">自动宽的段落，文字足够长以便折行测量宽度。</p>'
          '<p class="cb">content-box 宽 200px 的段落文字。</p>'
          '<p class="bb">border-box 宽 200px 含 padding 与 border。</p>'
          '<p class="mx">max-width 150px 的段落文字。</p>'
          '<p class="pc">百分比宽 50% 的段落文字。</p>',
      css: css,
      contentWidth: 300,
      contentHeight: 500,
    );
    final pages = await source.loadChapter(0);
    final widths = <String, double>{};
    for (final slice in pages.expand((page) => page.slices)) {
      final text = slice.block.layout.text;
      if (text.startsWith('自动宽')) {
        widths['auto'] = slice.block.layout.maxWidth;
      } else if (text.startsWith('content-box')) {
        widths['cb'] = slice.block.layout.maxWidth;
      } else if (text.startsWith('border-box')) {
        widths['bb'] = slice.block.layout.maxWidth;
      } else if (text.startsWith('max-width')) {
        widths['mx'] = slice.block.layout.maxWidth;
      } else if (text.startsWith('百分比')) {
        widths['pc'] = slice.block.layout.maxWidth;
      }
    }
    return widths;
  }

  test('width: auto 用正文区宽扣水平内缩', () async {
    final widths = await textWidths('');
    expect(widths['auto'], closeTo(300, 0.01));
  });

  test('content-box：声明宽即内容宽，padding/border 另计', () async {
    final widths = await textWidths(
      '.cb { width: 200px; padding: 10px; border: 3px solid #333; }',
    );
    expect(widths['cb'], closeTo(200, 0.01));
  });

  test('border-box：声明宽含 padding+border，内容宽被压缩', () async {
    final widths = await textWidths(
      '.bb { box-sizing: border-box; width: 200px; '
      'padding: 10px; border: 3px solid #c36; }',
    );
    // 200 - (10+3)*2 = 174；修复前按 200 排版（行宽溢出正文区）。
    expect(widths['bb'], closeTo(174, 0.01));
  });

  test('max-width 与百分比宽同样按 box-sizing 解算', () async {
    final widths = await textWidths(
      '.mx { max-width: 150px; } .pc { width: 50%; }',
    );
    expect(widths['mx'], closeTo(150, 0.01));
    expect(widths['pc'], closeTo(150, 0.01));
  });
}
