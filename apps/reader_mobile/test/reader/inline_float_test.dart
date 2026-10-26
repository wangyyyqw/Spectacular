import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

/// 行内元素浮动（W17）：`span.talent-tag{float:right}`、`span.job-tag`、
/// `img.avatar` 这类挂在**行内元素**上的 float，在 flat 管线里原本只是
/// 行内 run，浮动完全不生效。章节源把它们从段落文本流里摘出来生成独立
/// 浮动块，段落行按剩余宽度绕排（沿用块级浮动的行 offsetX 机制）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<PageBlockSlice>> slicesOf(
    String body,
    String css, {
    double contentWidth = 320,
    Map<String, List<int>> binaryFiles = const <String, List<int>>{},
  }) async {
    final source = await openCssChapter(
      body: body,
      css: css,
      binaryFiles: binaryFiles,
      contentWidth: contentWidth,
      contentHeight: 700,
    );
    final pages = await source.loadChapter(0);
    return [for (final page in pages) ...page.slices];
  }

  test('段首 span 右浮动标签：生成靠右浮动块，段落首行收窄', () async {
    final slices = await slicesOf(
      '<p class="talent-item"><span class="talent-tag">欺诈信仰天赋 · 主动</span>'
          '<span class="talent-name">谎如昨日（SS）这是一段足够长的正文，'
          '用来验证右侧浮动标签旁边的首行会收窄到剩余宽度，后续行再恢复整行宽度。</span></p>',
      'p { margin: 6px 0; line-height: 1.6; } '
          '.talent-tag { float: right; color: #d2b87a; font-size: 0.75em; }',
    );
    final floated = slices.where((slice) => slice.block.floatSide != null);
    expect(floated, hasLength(1), reason: '行内浮动标签摘出为独立浮动块');
    final tag = floated.single;
    expect(tag.block.floatSide, FloatSide.right);
    expect(tag.block.layout.text, '欺诈信仰天赋 · 主动');
    // 右浮动贴右缘：x ≈ 版心宽 − 标签宽。
    expect(
      tag.leftInset + tag.block.layout.width,
      closeTo(320, 2),
      reason: '右浮动标签贴右缘',
    );
    // 段落不再包含标签文字，且首行按剩余宽度排版。
    final paragraph = slices.firstWhere(
      (slice) => slice.block.layout.text.startsWith('谎如昨日'),
    );
    expect(
      paragraph.block.layout.text,
      isNot(contains('欺诈信仰天赋')),
      reason: '标签文字从段落流里摘出',
    );
    final firstLine = paragraph.block.layout.lines.first;
    expect(
      firstLine.width,
      lessThan(320 - tag.block.layout.width + 1),
      reason: '首行宽度 ≤ 版心 − 标签宽',
    );
  });

  test('段中 span 浮动同样摘出，前后文字拼成同一段', () async {
    final slices = await slicesOf(
      '<p>这段文字前面有内容<span class="chip">居中标签</span>后面还有更多文字内容。</p>',
      'p { margin: 0; line-height: 1.6; } .chip { float: left; }',
    );
    final floated = slices.where((slice) => slice.block.floatSide != null);
    expect(floated, hasLength(1));
    expect(floated.single.block.layout.text, '居中标签');
    expect(floated.single.block.floatSide, FloatSide.left);
    final paragraph = slices.firstWhere(
      (slice) => slice.block.layout.text.startsWith('这段文字'),
    );
    expect(paragraph.block.layout.text, isNot(contains('居中标签')));
    expect(paragraph.block.layout.text, contains('后面还有更多文字'));
  });

  test('两个标签浮动都摘出（job-tag + talent-tag 并存）', () async {
    final slices = await slicesOf(
      '<p class="meta"><span class="job-tag">职业：牧师</span>'
          '<span class="talent-tag">天赋</span>正文内容继续。</p>',
      'p { margin: 0; line-height: 1.6; } '
          '.job-tag { float: right; } .talent-tag { float: right; }',
    );
    final floated = slices.where((slice) => slice.block.floatSide != null);
    expect(floated, hasLength(2));
    expect(
      floated.every((slice) => slice.block.floatSide == FloatSide.right),
      isTrue,
    );
    // 两个浮块横向错开（贴在右缘但互不重叠）。
    final xs = floated.map((slice) => slice.leftInset).toList()..sort();
    expect(xs.last - xs.first, greaterThan(1), reason: '两个右浮标签并排');
  });

  test('img.avatar 行内图片浮动：图片行内 run 变成浮动块', () async {
    final slices = await slicesOf(
      '<p><img class="avatar" src="../Images/a.png"/>头像后面的文字，'
          '用来观察行内图片浮动的绕排效果以及首行收窄。</p>',
      'p { margin: 0; line-height: 1.6; } '
          '.avatar { float: left; width: 42px; height: 42px; margin: 0 8px 0 0; }',
      binaryFiles: <String, List<int>>{'OEBPS/Images/a.png': _tinyPng()},
    );
    final floated = slices.where((slice) => slice.block.floatSide != null);
    expect(floated, hasLength(1), reason: 'img.avatar 的 float 生效');
    expect(floated.single.block.floatSide, FloatSide.left);
    expect(floated.single.block.layout.width, closeTo(42, 0.5));
    expect(floated.single.block.layout.height, closeTo(42, 0.5));
    expect(floated.single.block.style!.backgroundImage, 'OEBPS/Images/a.png');
  });

  test('真书取证：zhushen-yuxi 天赋/职业章（spine 27/28）出现浮动块', () async {
    final file = File('../../test_corpus/real/zhushen-yuxi.epub');
    if (!file.existsSync()) {
      return;
    }
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      verifyCrc: false,
    );
    // 0 基: 27 = 天赋/职业页，28 = 角色卡页。
    for (final spine in <int>[27, 28]) {
      final pages = await source.loadChapter(spine);
      final floats = pages
          .expand((page) => page.slices)
          .where((slice) => slice.block.floatSide != null)
          .toList();
      expect(floats, isNotEmpty, reason: 'spine $spine 应有行内浮动标签块');
      expect(
        floats.every((slice) => slice.block.floatSide == FloatSide.right),
        isTrue,
        reason: '书里标签都是 float: right',
      );
    }
  });
}

/// 1×1 透明 PNG（图片块只需要能被 decode 出尺寸）。
List<int> _tinyPng() => <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];
