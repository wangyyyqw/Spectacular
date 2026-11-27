import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show BookMeta;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_mobile/book_source/online_epub_builder.dart';

void main() {
  test('在线单图章不插标题，竖图与横图均完整居中并取消阅读边距', () async {
    for (final size in [const Size(375, 816), const Size(640, 320)]) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFFEC985C), BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      final source = await _openChapter(
        const OnlineEpubChapter(
          title: '第一卷 卷标',
          html:
              '<div><img id="volume-art" src="../images/volume.png" '
              'width="120" height="200" style="width:120px"/></div>',
        ),
        resources: {'images/volume.png': bytes},
      );
      await source.applyOverrides(
        const ReaderOverrides(
          fontSize: 22,
          lineHeight: 1.4,
          paragraphSpacing: 8,
        ),
      );
      await source.applyContentSize(width: 351.4, height: 681.2);
      final page = (await source.loadChapter(0)).single;
      final block = page.slices.single.block;
      expect(block.layout.text, '');
      expect(block.bleedLeft && block.bleedRight, isTrue);
      expect(block.bleedTop && block.bleedBottom, isTrue);
      expect(block.style!.backgroundSize.mode, CssBackgroundSizeMode.contain);
      expect(block.style!.backgroundImage, contains('images/volume.png'));
      expect(block.startCfi, isNotNull);
      final mixed = await _openChapter(
        const OnlineEpubChapter(
          title: '第1章 空屋',
          volume: '第一卷',
          html:
              '<img src="../images/volume.png" img-width="390px" img-height="844px"/>\n'
              '第一章 空屋\n\n后续正文必须完整保留。',
        ),
        resources: {'images/volume.png': bytes},
      );
      await mixed.applyOverrides(
        const ReaderOverrides(
          fontSize: 22,
          lineHeight: 1.4,
          paragraphSpacing: 8,
        ),
      );
      await mixed.applyContentSize(
        width: 351.4,
        height: 681.2,
        topInset: 54,
        sideInsets: (left: 12, right: 12),
      );
      final handle = mixed.scheduleProgressiveChapter(0);
      final firstPages = await handle.firstPages;
      expect(firstPages.first.slices.single.block.bleedLeft, isTrue);
      expect(firstPages.first.slices.single.block.bleedTop, isTrue);
      final mixedPages = await handle.result;
      final artBlock = mixedPages.first.slices.single.block;
      expect(artBlock.bleedLeft && artBlock.bleedRight, isTrue);
      expect(artBlock.bleedTop && artBlock.bleedBottom, isTrue);
      expect(artBlock.style!.backgroundSize.mode, CssBackgroundSizeMode.cover);
      expect(
        mixedPages
            .skip(1)
            .expand((page) => page.slices)
            .map((slice) => slice.block.layout.text)
            .join(),
        contains('后续正文必须完整保留。'),
      );
    }
    const builder = OnlineEpubBuilder();
    expect(
      builder.buildChapterDocument(
        const OnlineEpubChapter(
          title: '第一卷',
          html: '<h1>第一卷</h1><img src="a.png"/>',
        ),
      ),
      isNot(contains('<h1')),
    );
    for (final html in [
      '<p>说明</p><img src="a.png"/>',
      '<img src="a.png"/><img src="b.png"/>',
    ]) {
      expect(
        builder.buildChapterDocument(
          OnlineEpubChapter(title: '第一卷', html: html),
        ),
        contains('<h1'),
      );
    }
    expect(
      builder.buildChapterDocument(
        const OnlineEpubChapter(
          title: '第一章',
          volume: '第一卷',
          html: '<img src="a.png" img-width="640px" img-height="320px"/><p>正文</p>',
        ),
      ),
      contains('background-size:contain'),
    );
  });

  test('接口开头的同名标题应用编号换行和缩小字号，正文标题样式保留', () async {
    final source = await _openChapter(
      const OnlineEpubChapter(
        title: '第1章 天天告白',
        html:
            '<h1 class="source-heading" id="heading_id_2" idx="10000">'
            '第1章 天天告白</h1><p>黄昏时刻。</p>'
            '<h2 style="font-size:18px">正文小标题</h2><p>后续正文。</p>',
      ),
    );
    // 反馈手机 1220px / 3.25，左右各 12dp，正文字号 22。
    await source.applyOverrides(
      const ReaderOverrides(fontSize: 22, lineHeight: 1.4),
    );
    await source.applyContentSize(width: 351.4, height: 681.2);
    final page = (await source.loadChapter(0)).first;
    final heading = page.slices.first.block;
    expect(heading.layout.text, '第1章\n天天告白');
    expect(heading.layout.lines, hasLength(2));
    final numberRun = heading.layout.runs.firstWhere(
      (run) => run.start == 0 && run.style.fontSize < heading.style!.fontSize,
    );
    expect(numberRun.style.fontSize, closeTo(heading.style!.fontSize - 2, .01));
    final body = page.slices[1].block;
    expect(
      heading.style!.fontSize,
      closeTo(body.style!.fontSize * (20 / 16), .01),
    );
    final subtitle = page.slices
        .map((slice) => slice.block)
        .firstWhere((block) => block.layout.text == '正文小标题');
    expect(subtitle.style!.fontSize, 18);
    final xhtml = const OnlineEpubBuilder().buildChapterDocument(
      const OnlineEpubChapter(
        title: '第1章 天天告白',
        html: '<h1 class="source-heading" id="heading_id_2">第1章 天天告白</h1>',
      ),
    );
    expect(xhtml, contains('id="heading_id_2"'));
    expect(xhtml, contains('source-heading chapter-title'));
    expect('天天告白'.allMatches(xhtml), hasLength(2)); // 文档标题与正文标题各一处。
  });

  test('正文只有目录标题时保留章首标题，不生成空章节', () async {
    const builder = OnlineEpubBuilder();
    for (final html in ['第一卷', '<p>第一卷</p>', '<h1>第一卷</h1>']) {
      final xhtml = builder.buildChapterDocument(
        OnlineEpubChapter(title: '第一卷', html: html),
      );
      expect(xhtml, contains('<h1 class="chapter-title">第一卷</h1>'));
      final source = await _openChapter(
        OnlineEpubChapter(title: '第一卷', html: html),
      );
      final chapter = await source.loadAnchorChapter(0);
      expect(chapter.text.trim(), '第一卷');
    }
  });

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
      contains('第1章</span><br/>穿越？（魔法，异能等）'),
    );
    expect(
      builder.buildChapterDocument(
        const OnlineEpubChapter(title: '番外：尾声', html: '正文'),
      ),
      contains('番外</span><br/>尾声'),
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

  test('卷首图后汉字编号与段评不阻断标题去重，正文引用保留', () async {
    final source = await _openChapter(
      const OnlineEpubChapter(
        title: '第1章 空屋',
        volume: '第一卷',
        html:
            '<img src="../images/volume.png"/>\n'
            '第一章\u200B空屋<a href="reader-review:test" data-reader-action="true">〔31〕</a>\n'
            '正文不能删除。\n第一章空屋',
      ),
    );
    final chapter = await source.loadAnchorChapter(0);
    expect(chapter.text, isNot(contains('〔31〕')));
    expect(chapter.text, contains('正文不能删除。'));
    expect('空屋'.allMatches(chapter.text), hasLength(2));
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test('生成 EPUB 3 目录、章节、封面与图片', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
    final bytes = const OnlineEpubBuilder().build(
      OnlineEpubInput(
        title: '测试 & 书名',
        author: '作者',
        intro: '<p>简介</p>',
        sourceName: '示例源',
        bookUrl: 'https://example.com/book/1',
        cover: OnlineEpubImage.fromBytes(png, 'cover'),
        images: [OnlineEpubImage.fromBytes(png, 'a')!],
        chapters: const <OnlineEpubChapter>[
          OnlineEpubChapter(
            title: '第一章',
            html: '<p>正文一</p><img src="../Images/a.png"/>',
          ),
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
    expect(opf, contains('Images/a.png'));
    expect(opf, contains('href="Styles/style.css"'));
    expect(text('OEBPS/Styles/style.css'), OnlineEpubBuilder.chapterStylesheet);
    expect(
      text('OEBPS/text/chapter_0001.xhtml'),
      contains('../Styles/style.css'),
    );
    expect(text('OEBPS/text/chapter_0001.xhtml'), contains('../Images/a.png'));
    expect(text('OEBPS/cover.xhtml'), contains('src="Images/cover.png"'));
    expect(text('OEBPS/cover.xhtml'), contains('href="Styles/style.css"'));
    final document = (await openEpub(bytes)).document!;
    addTearDown(document.archive.close);
    expect(document.readCoverBytes(), png);

    final nav = text('OEBPS/nav.xhtml');
    expect(nav, contains('第一章'));
    expect(nav, contains('第二章'));
    expect(nav, contains('text/chapter_0002.xhtml'));

    expect(text('OEBPS/text/chapter_0001.xhtml'), contains('正文一'));
    expect(text('OEBPS/text/chapter_0002.xhtml'), contains('正文二'));
    expect(archive.findFile('OEBPS/Images/a.png')!.content, png);
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
      OnlineEpubBuilder.stylesheetPath: utf8.encode(
        OnlineEpubBuilder.chapterStylesheet,
      ),
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
