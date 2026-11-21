import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show BookMeta;
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/book_source/online_epub_builder.dart';

void main() {
  test('章节编号与标题另起一行，特殊标题和无编号标题保留文本', () async {
    final source = await _openChapter(
      const OnlineEpubChapter(title: '第1章 穿越？（魔法，异能等）', html: '<p>正文</p>'),
    );
    final chapter = await source.loadAnchorChapter(0);
    expect(
      chapter.blocks.first.text.replaceAll(RegExp(r'\s+'), ''),
      '第1章穿越？（魔法，异能等）',
    );
    final builder = const OnlineEpubBuilder();
    expect(
      builder.buildChapterDocument(
        const OnlineEpubChapter(title: '第1章 穿越？（魔法，异能等）', html: '正文'),
      ),
      contains('第1章<br/>穿越？（魔法，异能等）'),
    );
    expect(
      builder.buildChapterDocument(
        const OnlineEpubChapter(title: '番外：尾声', html: '正文'),
      ),
      contains('番外<br/>尾声'),
    );
    expect(
      builder.buildChapterDocument(
        const OnlineEpubChapter(title: '新书感言', html: '正文'),
      ),
      contains('class="chapter-title">新书感言</h1>'),
    );
  });

  test('纯文本附行内段评保持独立段落，仅删除开头重复标题', () async {
    final source = await _openChapter(
      const OnlineEpubChapter(
        title: '第1章 测试',
        html: '第1章 测试\n第一段<a href="reader-review:test" data-reader-action="true">〔12〕</a>\n第二段\n第1章 测试',
      ),
    );
    final chapter = await source.loadAnchorChapter(0);
    expect(chapter.blocks.map((block) => block.text).toList(), [
      '第1章\n测试',
      '第一段〔12〕',
      '第二段',
      '第1章 测试',
    ]);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test('生成 EPUB 3 目录、章节、封面与图片', () {
    final bytes = const OnlineEpubBuilder().build(
      OnlineEpubInput(
        title: '测试 & 书名',
        author: '作者',
        intro: '<p>简介</p>',
        sourceName: '示例源',
        bookUrl: 'https://example.com/book/1',
        cover: OnlineEpubImage(
          path: 'images/cover.png',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          mediaType: 'image/png',
        ),
        images: <OnlineEpubImage>[
          OnlineEpubImage(
            path: 'images/a.png',
            bytes: Uint8List.fromList(<int>[4, 5, 6]),
            mediaType: 'image/png',
          ),
        ],
        chapters: const <OnlineEpubChapter>[
          OnlineEpubChapter(title: '第一章', html: '<p>正文一</p>'),
          OnlineEpubChapter(title: '第二章', html: '<p>正文二</p>'),
        ],
      ),
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    String text(String name) => utf8.decode(archive.findFile(name)!.content);

    expect(text('mimetype'), 'application/epub+zip');
    expect(text('META-INF/container.xml'), contains('OEBPS/content.opf'));

    final opf = text('OEBPS/content.opf');
    expect(opf, contains('测试 &amp; 书名'));
    expect(opf, contains('chapter_0001.xhtml'));
    expect(opf, contains('chapter_0002.xhtml'));
    expect(opf, contains('properties="cover-image"'));
    expect(opf, contains('images/a.png'));

    final nav = text('OEBPS/nav.xhtml');
    expect(nav, contains('第一章'));
    expect(nav, contains('第二章'));
    expect(nav, contains('text/chapter_0002.xhtml'));

    expect(text('OEBPS/text/chapter_0001.xhtml'), contains('正文一'));
    expect(text('OEBPS/text/chapter_0002.xhtml'), contains('正文二'));
    expect(archive.findFile('OEBPS/images/a.png'), isNotNull);
    expect(archive.findFile('OEBPS/cover.xhtml'), isNotNull);
  });

  test('清理脚本、事件属性与无效图片', () {
    final bytes = const OnlineEpubBuilder().build(
      OnlineEpubInput(
        title: '清理',
        author: '',
        chapters: const <OnlineEpubChapter>[
          OnlineEpubChapter(
            title: '第一章',
            html:
                '<p onclick="bad()">正文</p>'
                '<script>alert(1)</script>'
                '<img src="data:image/png;base64,AAAA"/>'
                '<img src="../images/keep.png"/>',
          ),
        ],
      ),
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final chapter = utf8.decode(
      archive.findFile('OEBPS/text/chapter_0001.xhtml')!.content,
    );
    expect(chapter, isNot(contains('<script')));
    expect(chapter, isNot(contains('onclick')));
    expect(chapter, isNot(contains('data:image')));
    expect(chapter, contains('../images/keep.png'));
  });

  test('纯文本正文在正式引擎中保留独立段落、特殊字符与 CSS 缩进', () async {
    final source = await _openChapter(
      const OnlineEpubChapter(
        title: '第一章',
        html:
            '　　首段：A & B，3 < 5。\r\n'
            '\r\n'
            '  第二段 &amp; 末尾。  \r'
            '第三段。\n'
            '　　',
      ),
    );
    final page = (await source.loadChapter(0)).single;
    final paragraphs = page.slices.skip(1).map((slice) => slice.block).toList();
    const expectedText = ['首段：A & B，3 < 5。', '第二段 & 末尾。', '第三段。'];

    expect(page.slices.first.block.layout.text, '第一章');
    expect(paragraphs.map((block) => block.layout.text), expectedText);
    for (final block in paragraphs) {
      final style = block.style!;
      expect(style.textIndent, closeTo(style.fontSize * 2, 0.001));
      expect(block.layout.lines.first.indent, closeTo(style.textIndent, 0.001));
      expect(block.layout.text, isNot(contains('　')));
    }
    final anchor = await source.loadAnchorChapter(0);
    expect(anchor.blocks.skip(1).map((block) => block.text), expectedText);
  });

  test('已有 HTML 在正式引擎中保留标题、行内样式、换行与图片', () async {
    final source = await _openChapter(
      const OnlineEpubChapter(
        title: '第一章',
        html:
            '<h1>第一章</h1>'
            '导语 &amp; 3 &lt; 5。'
            '<!--内部注释-->'
            '<p style="text-indent:1em">保留<strong>强调</strong><br>'
            '原有换行<img src="../images/inline.png" '
            'style="width:14px;height:14px"></p>'
            '<p>后续段。</p>',
      ),
      resources: {
        'images/inline.png': base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a8ioAAAAASUVORK5CYII=',
        ),
      },
    );
    final page = (await source.loadChapter(0)).single;
    final text = page.slices.map((slice) => slice.block.layout.text).join();
    expect('第一章'.allMatches(text), hasLength(1));
    expect(text, contains('导语 & 3 < 5。'));
    expect(text, isNot(contains('内部注释')));
    expect(text, contains('后续段。'));

    final paragraph = page.slices
        .map((slice) => slice.block)
        .firstWhere((block) => block.layout.text.startsWith('保留强调'));
    expect(paragraph.layout.lines, hasLength(2));
    expect(
      paragraph.style!.textIndent,
      closeTo(paragraph.style!.fontSize, 0.001),
    );
    expect(
      paragraph.layout.runs.any((run) => run.style.fontWeight == 700),
      isTrue,
    );
    expect(paragraph.inlineImages.single.url, 'images/inline.png');
    final anchor = await source.loadAnchorChapter(0);
    expect(anchor.text, contains('导语 & 3 < 5。'));
    expect(anchor.text, isNot(contains('内部注释')));
  });
}

Future<EpubChapterSource> _openChapter(
  OnlineEpubChapter chapter, {
  Map<String, Uint8List> resources = const {},
}) async {
  final source = EpubChapterSource.fromChapterLoader(
    meta: const BookMeta(
      title: '在线正文回归',
      author: '',
      language: 'zh-CN',
      identifier: 'online-builder-regression',
    ),
    chapterTitles: [chapter.title],
    resources: {
      'style.css': utf8.encode(OnlineEpubBuilder.chapterStylesheet),
      ...resources,
    },
    loadChapterXhtml: (_) async =>
        const OnlineEpubBuilder().buildChapterDocument(chapter),
  );
  addTearDown(() async {
    source.close();
    await source.preparationsStopped;
  });
  await source.applyContentSize(width: 325, height: 580);
  return source;
}
