import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

Uint8List _book(
  String head,
  Map<String, String> styles, {
  int chapterCount = 1,
}) {
  assert(chapterCount > 0);
  final chapterNames = [
    for (var i = 0; i < chapterCount; i++) i == 0 ? 'c.xhtml' : 'c$i.xhtml',
  ];
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
        'version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OEBPS/content.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="b"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="b">audit</dc:identifier><dc:title>审计</dc:title>'
        '<dc:language>zh</dc:language></metadata><manifest>'
        '${chapterNames.indexed.map((e) => '<item id="c${e.$1}" href="${e.$2}" media-type="application/xhtml+xml"/>').join()}'
        '${styles.keys.indexed.map((e) => '<item id="s${e.$1}" href="${e.$2}" media-type="text/css"/>').join()}'
        '</manifest><spine>'
        '${chapterNames.indexed.map((e) => '<itemref idref="c${e.$1}"/>').join()}'
        '</spine></package>',
    for (final chapterName in chapterNames)
      'OEBPS/$chapterName':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head>$head</head>'
          '<body><p>审计样式 $chapterName</p></body></html>',
    for (final e in styles.entries) 'OEBPS/${e.key}': e.value,
  };
  final archive = Archive();
  files.forEach((name, value) {
    final bytes = utf8.encode(value);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

Future<Color> _colorOf(EpubChapterSource source) async {
  final pages = await source.loadChapter(0);
  return pages
      .expand((p) => p.slices)
      .firstWhere((s) => s.block.layout.text.contains('审计样式'))
      .block
      .style!
      .color;
}

Future<Color> _actual(String head, Map<String, String> styles) async {
  final source = await EpubChapterSource.open(
    _book(head, styles),
    contentWidth: 300,
    contentHeight: 500,
  );
  await source.applyOverrides(const ReaderOverrides());
  return _colorOf(source);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('文档顺序：后面的 link 应覆盖前面的 style', () async {
    expect(
      await _actual(
        '<style>p { color: red; }</style><link rel="stylesheet" href="s.css"/>',
        {'s.css': 'p { color: blue; }'},
      ),
      const Color(0xff0000ff),
    );
  });
  test('媒体属性：print 样式不应覆盖屏幕样式', () async {
    expect(
      await _actual(
        '<link rel="stylesheet" href="a.css"/><link rel="stylesheet" media="print" href="b.css"/>',
        {'a.css': 'p { color: blue; }', 'b.css': 'p { color: red; }'},
      ),
      const Color(0xff0000ff),
    );
  });
  test('内嵌 style 中的 import 应加载', () async {
    expect(
      await _actual('<style>@import "s.css";</style>', {
        's.css': 'p { color: blue; }',
      }),
      const Color(0xff0000ff),
    );
  });
  test('重复 link 应保留最后出现位置', () async {
    expect(
      await _actual(
        '<link rel="stylesheet" href="a.css"/><link rel="stylesheet" href="b.css"/><link rel="stylesheet" href="a.css"/>',
        {'a.css': 'p { color: blue; }', 'b.css': 'p { color: red; }'},
      ),
      const Color(0xff0000ff),
    );
  });
  test('import 的 min-width 条件应参与判断', () async {
    expect(
      await _actual('<link rel="stylesheet" href="a.css"/>', {
        'a.css': '@import "b.css" screen and (min-width: 9999px); p { color: blue; }',
        'b.css': 'p { color: red !important; }',
      }),
      const Color(0xff0000ff),
    );
  });
  test('内嵌 style 的 print 条件不污染屏幕样式', () async {
    expect(
      await _actual(
        '<style>p { color: blue; }</style>'
        '<style media="print">p { color: red; }</style>',
        {},
      ),
      const Color(0xff0000ff),
    );
  });

  test('import 的媒体列表按或求值而非按 print 字符串排除', () async {
    expect(
      await _actual('<style>@import "s.css" print, screen;</style>', {
        's.css': 'p { color: blue; }',
      }),
      const Color(0xff0000ff),
    );
  });

  test('循环导入终止，后续重复导入仍保留层叠位置', () async {
    expect(
      await _actual(
        '<link rel="stylesheet" href="a.css"/>'
        '<link rel="stylesheet" href="c.css"/>',
        {
          'a.css': '@import "b.css"; p { color: blue; }',
          'b.css': '@import "a.css"; p { color: red; }',
          'c.css': '@import "b.css";',
        },
      ),
      const Color(0xffff0000),
    );
  });

  test('来源与导入条件都必须命中，窗口变化重新求值', () async {
    final source = await EpubChapterSource.open(
      _book(
        '<style>p { color: blue; }</style>'
        '<link rel="stylesheet" media="not print" href="a.css"/>',
        {
          'a.css': '@import "b.css" screen and (min-width: 400px);',
          'b.css': '@import "nested/c.css" (max-width: 600px);',
          'nested/c.css': 'p { color: red; }',
        },
      ),
      contentWidth: 300,
      contentHeight: 500,
    );
    await source.applyOverrides(const ReaderOverrides());
    expect(await _colorOf(source), const Color(0xff0000ff));
    await source.applyContentSize(width: 500, height: 500);
    expect(await _colorOf(source), const Color(0xffff0000));
    await source.applyContentSize(width: 700, height: 500);
    expect(await _colorOf(source), const Color(0xff0000ff));
  });

  test('共享作者样式跨章节复用准备结果且每章样式正确', () async {
    final source = await EpubChapterSource.open(
      _book('<link rel="stylesheet" href="s.css"/>', {
        's.css': 'p { color: red; }',
      }, chapterCount: 3),
      contentWidth: 300,
      contentHeight: 500,
    );
    await source.applyOverrides(const ReaderOverrides());

    for (var spine = 0; spine < 3; spine++) {
      final pages = await source.loadChapter(spine);
      final color = pages
          .expand((page) => page.slices)
          .firstWhere((slice) => slice.block.layout.text.contains('审计样式'))
          .block
          .style!
          .color;
      expect(color, const Color(0xffff0000));
    }
    // 三章共享同一套作者样式，首章准备后走基础级联缓存，不应逐章重算。
    expect(source.cacheReport, contains('基础级联 1/3 组'));
    expect(source.cacheReport, contains('级联准备 0/3 组'));
  });
}
