import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/text_layout_cache.dart';

import 'support/css_chapter_book.dart';

class _Element implements SelectorElement {
  const _Element(this.tag);
  @override
  final String tag;
  @override
  Map<String, String> get attributes => const {};
  @override
  List<SelectorElement> get childElements => const [];
}

ComputedStyle _compute(String css, {ComputedStyle? parent}) => Cascade.compute(
  element: const _Element('p'),
  ancestors: const [],
  rules: CascadeRule.fromStylesheet(
    CssParser.parse(css),
    origin: CascadeOrigin.author,
  ),
  parent: parent,
  containingWidth: 300,
  viewportWidth: 300,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同文不同颜色的行内区间不能复用旧颜色', () async {
    final source = await openCssChapter(
      body:
          '<p><span class="red">相同文字</span></p>'
          '<p><span class="blue">相同文字</span></p>',
      css: '.red { color: red; } .blue { color: blue; }',
    );
    addTearDown(source.close);
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .where((block) => block.layout.text == '相同文字')
        .toList();
    final colors = [
      for (final block in blocks) block.layout.runs.first.style.color,
    ];
    expect(colors, const [Color(0xffff0000), Color(0xff0000ff)]);
  });

  test('同文行内背景和装饰不应复用首段样式', () async {
    final source = await openCssChapter(
      body:
          '<p><span class="red">装饰同文</span></p>'
          '<p><span class="blue">装饰同文</span></p>',
      css:
          '.red { background-color: red; text-decoration: underline; }'
          '.blue { background-color: blue; text-decoration: line-through; }',
    );
    addTearDown(source.close);
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .where((block) => block.layout.text == '装饰同文')
        .toList();
    final styles = [for (final block in blocks) block.layout.runs.first.style];
    expect(styles[1].backgroundColor, const Color(0xff0000ff));
    expect(styles[1].textDecoration, CssTextDecoration.lineThrough);
  });

  test('不同字号的同文不撞缓存', () async {
    final source = await openCssChapter(
      body:
          '<p><span class="small">字号同文</span></p>'
          '<p><span class="large">字号同文</span></p>',
      css: '.small { font-size: 12px; } .large { font-size: 24px; }',
    );
    addTearDown(source.close);
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .where((block) => block.layout.text == '字号同文')
        .toList();
    expect(blocks[0].layout.runs.first.style.fontSize, 12);
    expect(blocks[1].layout.runs.first.style.fontSize, 24);
    expect(identical(blocks[0].layout, blocks[1].layout), isFalse);
  });

  test('章节源同文 clip 与 ellipsis 应分别保留行状态', () async {
    final source = await openCssChapter(
      body:
          '<p class="clip">省略号缓存键省略号缓存键省略号缓存键</p>'
          '<p class="ellipsis">省略号缓存键省略号缓存键省略号缓存键</p>',
      css:
          'p { width: 100px; white-space: nowrap; overflow: hidden; }'
          '.clip { text-overflow: clip; } .ellipsis { text-overflow: ellipsis; }',
    );
    addTearDown(source.close);
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .where((block) => block.layout.text.contains('省略号缓存键'))
        .toList();
    expect(blocks[0].layout.ellipsized, isFalse);
    expect(blocks[1].layout.ellipsized, isTrue);
  });

  test('定位子元素显式 auto 应重置父元素偏移', () async {
    final source = await openCssChapter(
      body: '<div class="parent"><p class="child">偏移同文</p></div>',
      css:
          '.parent { position: static; left: 20px; }'
          '.child { position: relative; left: auto; }',
    );
    addTearDown(source.close);
    final slice = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .firstWhere((slice) => slice.block.layout.text == '偏移同文');
    final block = slice.block;
    expect(slice.leftInset, 0);
    expect(block.style!.left, isNull);
  });

  test('背景简写按源顺序覆盖长属性', () async {
    final source = await openCssChapter(
      body: '<p>背景覆盖</p>',
      css: 'p { background-color: red; background: blue; }',
    );
    addTearDown(source.close);
    final block = (await source.loadChapter(0)).first.slices.first.block;
    expect(block.style!.backgroundColor, const Color(0xff0000ff));
  });

  test('多背景简写按层展开并保留各层省略项', () {
    final style = _compute(
      'p { background: url(a.png) no-repeat center/cover, '
      'url(b.png) repeat-x left top red; }',
    );
    final layers = style.backgroundLayers;
    expect(layers, hasLength(2));
    expect(layers[0].image, 'a.png');
    expect(layers[0].repeat, CssBackgroundRepeat.noRepeat);
    expect(layers[0].size.mode, CssBackgroundSizeMode.cover);
    expect(layers[1].image, 'b.png');
    expect(layers[1].repeat, CssBackgroundRepeat.repeatX);
    expect(style.backgroundColor, const Color(0xffff0000));
  });

  test('背景简写单个盒关键字同时设置 origin/clip，currentColor 使用当前文字色', () {
    final style = _compute(
      'p { color: red; background: currentColor content-box; }',
    );
    expect(style.backgroundColor, const Color(0xffff0000));
    expect(style.backgroundOrigin, CssBackgroundOrigin.contentBox);
    expect(style.backgroundClip, CssBackgroundClip.contentBox);
  });

  test('currentColor 背景使用正文计算颜色', () async {
    final source = await openCssChapter(
      body: '<p>背景当前色</p>',
      css: 'p { color: red; background-color: currentColor; }',
    );
    addTearDown(source.close);
    final block = (await source.loadChapter(0)).first.slices.first.block;
    expect(block.style!.backgroundColor, const Color(0xffff0000));
  });

  test('定位偏移不能默认继承父元素', () {
    final parent = _compute('p { position: relative; left: 20px; top: 10px; }');
    final child = _compute('p { position: relative; }', parent: parent);
    expect(child.left, isNull);
    expect(child.top, isNull);
  });

  test('仅显式 inherit 的定位偏移使用父值', () {
    final parent = _compute(
      'p { position: relative; left: 20px; top: 10px; right: 7px; bottom: 8px; }',
    );
    final child = _compute(
      'p { position: relative; left: inherit; top: auto; right: 5px; '
      'bottom: inherit; }',
      parent: parent,
    );
    expect(child.left!.resolve(300), 20);
    expect(child.top, isNull);
    expect(child.right!.resolve(300), 5);
    expect(child.bottom!.resolve(300), 8);

    // 直接构造样式（不经层叠预处理）也必须区分 inherit 与 auto。
    final direct = ComputedStyle(
      const {'left': 'inherit', 'top': 'auto'},
      parent: parent,
      explicitProperties: const {'left', 'top'},
    );
    expect(direct.left!.resolve(300), 20);
    expect(direct.top, isNull);
  });

  test('同章普通段落与 pre-wrap 段落分别按最终样式折叠空白', () async {
    final source = await openCssChapter(
      body:
          '<p>普通  段落\n下一行</p>'
          '<p style="white-space:pre-wrap">保留  段落\n下一行</p>'
          '<p>收尾</p>',
    );
    addTearDown(source.close);
    final texts = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block.layout.text)
        .toList();
    expect(texts, contains('普通 段落 下一行'));
    expect(texts, contains('保留  段落\n下一行'));
  });

  test('保留空白的父段落中 normal 子元素单独折叠，锚点与分页正文一致', () async {
    final source = await openCssChapter(
      body: '<p class="spaces">甲  乙\n丙 <span class="normal">丁  戊\n己</span>  庚</p>',
      css:
          '.spaces { white-space: pre-wrap; } .normal { white-space: normal; }',
    );
    addTearDown(source.close);
    final anchor = await source.loadAnchorChapter(0);
    final text = (await source.loadChapter(0))
        .first
        .slices
        .first
        .block
        .layout
        .text;
    expect(text, '甲  乙\n丙 丁 戊 己  庚');
    expect(anchor.text, text);
  });

  test('装饰简写重置先前的装饰长属性', () {
    final style = _compute(
      'p { text-decoration-line: underline; text-decoration: none; }',
    );
    expect(style.textDecoration, CssTextDecoration.none);
  });

  test('嵌套媒体查询分别按列表与合取处理', () {
    final style = _compute(
      'p { color: blue; } @media screen, print { @media (min-width: 400px) { p { color: red; } } }',
    );
    expect(style.color, const Color(0xff0000ff));
  });

  test('省略号状态应参与段落测量缓存键', () {
    final cache = TextLayoutCache();
    final plain = ComputedStyle(const {
      'font-size': '16px',
      'white-space': 'nowrap',
      'overflow': 'hidden',
      'text-overflow': 'clip',
    });
    final ellipsis = ComputedStyle(const {
      'font-size': '16px',
      'white-space': 'nowrap',
      'overflow': 'hidden',
      'text-overflow': 'ellipsis',
    });
    const text = '省略号缓存键省略号缓存键省略号缓存键';
    cache.layout(text: text, style: plain, maxWidth: 100);
    final cached = cache.layout(text: text, style: ellipsis, maxWidth: 100);
    final direct = TextLayoutEngine.layout(
      text: text,
      style: ellipsis,
      maxWidth: 100,
    );
    expect(cached.lines.first.ellipsized, direct.lines.first.ellipsized);
  });

  test('字体精确路径优先，不能被同名兜底覆盖', () async {
    final exactBytes = const <int>[0, 1, 2, 3];
    final fallbackBytes = File('assets/fonts/SourceHanSerifCN-Regular.otf')
        .readAsBytesSync();
    String digestOf(List<int> bytes) => sha256
        .convert(utf8.encode('w400i0:${sha256.convert(bytes)}'))
        .toString();
    final source = await openCssChapter(
      body: '<p>字体精确路径</p>',
      css:
          '@font-face {font-family:auditfont;src:url("Fonts/shared.otf");}'
          'p {font-family:auditfont,serif;}',
      binaryFiles: {
        // 精确来源存在但字节无效：注册必须失败，不能悄悄改用另一个目录。
        'OEBPS/Styles/Fonts/shared.otf': exactBytes,
        'OEBPS/Other/Fonts/shared.otf': fallbackBytes,
      },
    );
    addTearDown(source.close);
    final block = (await source.loadChapter(0)).first.slices.first.block;
    expect(block.style!.fontFamily, contains(digestOf(exactBytes)));
    expect(block.style!.fontFamily, isNot(contains(digestOf(fallbackBytes))));
  });
}
