import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/footnote_dialog.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import 'support/css_chapter_book.dart';
import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  for (final style in ReaderFootnoteStyle.values) {
    testWidgets('${style.label}注释开关与前台恢复保持系统栏隐藏且不改变阅读位置', (tester) async {
      final bars = <Object?>[];
      const channel = MethodChannel('com.spectacular.reader_mobile/reader');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'setSystemBars') bars.add(call.arguments);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      tester.view.physicalSize = const Size(384, 854);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const padding = EdgeInsets.fromLTRB(10, 40, 10, 34);
      final source = await openCssChapter(
        body:
            '<p>${List.filled(26, '正文').join('<br/>')}'
            '<a href="#fn1" role="doc-noteref">注</a></p>'
            '<aside id="fn1" role="doc-footnote">治安：谓政治清明，社会安定。</aside>',
        css: 'body,p {margin:0;font:18px/1.5 Ahem;text-indent:0;}',
        contentWidth: 364,
        contentHeight: 780,
      );
      addTearDown(source.close);
      late ReaderSession session;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderPage(
              source: source,
              store: MemoryReaderProgressStore(),
              bookId: 'bottom-footnote',
              padding: padding,
              overrides: const ReaderOverrides(),
              showPageFooter: false,
              footnoteStyle: style,
              onSessionReady: (value) => session = value,
            ),
          ),
        ),
      );
      await pumpReaderUntilComplete(
        tester,
        () => !session.loading && session.hasContent,
        description: '底部注释首屏正文',
      );
      await tester.pumpAndSettle();
      expect(bars.last, {'statusBar': false, 'navigationBar': false});
      final page = session.page!;
      final line = TextHitTester.lineBoxes(page).last;
      final pagePosition = Offset(line.rect.right - 2, line.rect.center.dy);
      expect(
        TextHitTester.footnoteAt(page, pagePosition)?.text,
        '治安：谓政治清明，社会安定。',
      );
      final tap =
          tester.getTopLeft(find.byType(ReaderView)) +
          Offset(padding.left, padding.top) +
          pagePosition;
      expect(tap.dy, greaterThan(700));
      await tester.tapAt(tap);
      await tester.pumpAndSettle();
      final popup = find.byType(ReaderFootnoteDialog);
      expect(popup, findsOneWidget);
      expect(
        tester
            .widgetList<ModalBarrier>(find.byType(ModalBarrier))
            .any((barrier) => (barrier.color?.a ?? 0) > 0),
        isTrue,
        reason: '${style.label}注释打开时压暗阅读页',
      );
      expect(bars, everyElement({'statusBar': false, 'navigationBar': false}));
      if (style != ReaderFootnoteStyle.dialog) {
        final callout = find.byKey(
          ValueKey('reader-footnote-callout-${style.name}'),
        );
        final gap = style == ReaderFootnoteStyle.bubble ? 18.0 : 10.0;
        final rect = tester.getRect(callout);
        final scrollRect = tester.getRect(
          find
              .descendant(
                of: callout,
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        );
        expect(
          scrollRect.top - rect.top,
          greaterThanOrEqualTo(16),
          reason: '滚动视口与上边缘保持内边距，滚动时文字也不贴边',
        );
        expect(
          rect.bottom - scrollRect.bottom,
          greaterThanOrEqualTo(16),
          reason: '滚动视口与下边缘保持内边距，滚动时文字也不贴边',
        );
        final textRect = tester.getRect(find.text('治安：谓政治清明，社会安定。'));
        expect(
          textRect.top - rect.top,
          greaterThanOrEqualTo(16),
          reason: '文字与上边缘留出内边距',
        );
        expect(
          rect.bottom - textRect.bottom,
          greaterThanOrEqualTo(16),
          reason: '文字与下边缘留出内边距',
        );
        expect(rect.bottom, closeTo(tap.dy - gap, .01));
        if (style == ReaderFootnoteStyle.bubble) {
          expect(rect.width, closeTo(384 - padding.horizontal, .01));
          expect(rect.left, closeTo(384 - rect.right, .01));
        } else {
          expect(rect.width, closeTo(384 * .85, .01));
        }
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(bars.last, {'statusBar': false, 'navigationBar': false});
      expect(session.page, same(page));
      await tester.tapAt(const Offset(190, 300));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      expect(bars, everyElement({'statusBar': false, 'navigationBar': false}));
      expect(session.page, same(page));
      // 注释关闭后，普通弹层仍恢复自己的系统栏状态。
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(ReaderPage)),
          builder: (_) => const AlertDialog(content: Text('普通弹层')),
        ),
      );
      await tester.pumpAndSettle();
      expect(bars.last, {'statusBar': true, 'navigationBar': true});
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(bars.last, {'statusBar': false, 'navigationBar': false});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('浮动绕排及跨页重建保留标题和正文图片注释的实际点击区', () async {
    const tail = '正文续行。';
    final source = await openCssChapter(
      body:
          '<div class="float">浮动</div>'
          '<h1>标题<sup><a class="duokan-footnote" href="#fn1">'
          '<img src="../Images/note.png"/></a></sup></h1>'
          '<p>开头<sup><a class="duokan-footnote" href="#fn2">'
          '<img src="../Images/note.png"/></a></sup>${tail * 50}'
          '<sup><a class="duokan-footnote" href="#fn3">'
          '<img src="../Images/note.png"/></a></sup>结尾</p>'
          '<aside role="doc-footnote"><ol>'
          '<li id="fn1">标题注释</li><li id="fn2">开头注释</li>'
          '<li id="fn3">结尾注释</li></ol></aside>',
      css:
          'body,h1,p {margin:0;font:16px/1.3 Ahem;text-indent:0;} '
          '.float {float:right;width:50px;height:60px;} '
          'sup img {width:12px;height:12px;}',
      contentWidth: 240,
      contentHeight: 120,
    );
    addTearDown(source.close);
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    final hitNotes = <String?>{};
    for (final page in pages) {
      for (final box in TextHitTester.lineBoxes(page)) {
        final line = box.slice.block.layout.lines[box.lineIndex];
        for (final image in line.inlineBoxes) {
          final note = box.slice.block.footnotes
              .where((note) => note.contains(image.offset))
              .single;
          final center = Offset(
            box.rect.left + image.left + image.width / 2,
            (box.textTop ?? box.rect.top) +
                image.topIn(line.baseline - line.top) +
                image.height / 2,
          );
          expect(TextHitTester.footnoteAt(page, center), same(note));
          hitNotes.add(note.text);
        }
      }
    }
    expect(hitNotes, {'标题注释', '开头注释', '结尾注释'});
  });

  test('浮动章节中声明高度的文字盒重建后仍能点击图片注释', () async {
    final source = await openCssChapter(
      body:
          '<div class="float">浮动</div>'
          '<p>正文<a class="duokan-footnote" href="#fn1">'
          '<img src="../Images/note.png" width="12" height="12"/></a></p>'
          '<aside id="fn1" role="doc-footnote">声明高度盒的注释</aside>',
      css:
          'body,p {margin:0;font:16px/1.3 Ahem;text-indent:0;} '
          '.float {float:right;width:50px;height:30px;} '
          'p {height:70px;}',
      contentWidth: 240,
      contentHeight: 120,
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final box = TextHitTester.lineBoxes(page)
        .singleWhere((box) => box.slice.block.layout.text.startsWith('正文'));
    final note = box.slice.block.footnotes.single;
    final line = box.slice.block.layout.lines[box.lineIndex];
    final image = line.inlineBoxes.single;
    final center = Offset(
      box.rect.left + image.left + image.width / 2,
      (box.textTop ?? box.rect.top) +
          image.topIn(line.baseline - line.top) +
          image.height / 2,
    );
    expect(note.text, '声明高度盒的注释');
    expect(TextHitTester.footnoteAt(page, center), same(note));
  });

  test('注释定义不进入正文页面，注号映射为可点击数据', () async {
    final source = await openCssChapter(
      body: '''
<p>正文一<sup><a href="#fn1" role="doc-noteref">[1]</a></sup></p>
<p>正文二<a href="#en1" role="doc-noteref">[2]</a></p>
<aside id="fn1" role="doc-footnote">
  <p>脚注正文第一段</p><p>脚注正文第二段</p>
</aside>
<section role="doc-endnotes">
  <h2>尾注标题</h2>
  <ol><li id="en1" role="doc-endnote">尾注正文</li></ol>
</section>
''',
      contentHeight: 600,
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList(growable: false);
    final pageText = blocks.map((block) => block.layout.text).join('\n');
    final footnotes = blocks
        .expand((block) => block.footnotes)
        .toList(growable: false);

    expect(pageText, contains('正文一'));
    expect(pageText, contains('正文二'));
    expect(pageText, isNot(contains('脚注正文')));
    expect(pageText, isNot(contains('尾注正文')));
    expect(pageText, isNot(contains('尾注标题')));
    expect(footnotes, hasLength(2));
    expect(footnotes[0].kind, NoteKind.footnote);
    expect(footnotes[0].text, '脚注正文第一段\n脚注正文第二段');
    expect(footnotes[1].kind, NoteKind.endnote);
    expect(footnotes[1].text, '尾注正文');
  });

  test('300 章书集中末尾定义时，淘汰后回到引用章仍能弹出正确注释', () async {
    const referenceCount = 300;
    final chapters = <String>[
      for (var i = 0; i < referenceCount; i++)
        '<p>正文 $i<a href="c${referenceCount + 1}.xhtml#note$i" '
            'role="doc-noteref">[$i]</a></p>',
      '<section role="doc-endnotes">'
          '${[for (var i = 0; i < referenceCount; i++) '<aside id="note$i" role="doc-endnote">末尾注释 $i</aside>'].join()}'
          '</section>',
    ];
    final source = await openTestChapterSource(
      buildMultiChapterEpub(chapters: chapters, rawBody: true),
    );
    addTearDown(source.close);

    Future<String?> noteTextAt(int spine) async {
      final pages = await source.loadChapter(spine);
      return pages
          .expand((page) => page.slices)
          .expand((slice) => slice.block.footnotes)
          .single
          .text;
    }

    expect(await noteTextAt(0), '末尾注释 0');
    for (var spine = referenceCount - 5; spine < chapters.length; spine++) {
      await source.loadChapter(spine);
    }
    expect(
      source.cacheReport,
      contains(
        '脚注索引 ${EpubChapterSource.chapterIndexCacheLimit}/'
        '${EpubChapterSource.chapterIndexCacheLimit}',
      ),
    );

    expect(await noteTextAt(0), '末尾注释 0');
  });

  test('普通数字内链不生成注释点击区', () async {
    final source = await openCssChapter(
      body: '''
<p><a href="#chapter-1">1</a></p>
<section id="chapter-1"><p>第一章正文</p></section>
''',
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList(growable: false);
    final footnotes = blocks.expand((block) => block.footnotes);
    expect(footnotes, isEmpty);
    expect(blocks.map((block) => block.layout.text), contains('第一章正文'));
  });

  test('多看无标记返回链接保留含图片注号的整段正文与点击数据', () async {
    const noteText = '“叠”是日本面积单位，一叠约等于1.62平方米。';
    final source = await openCssChapter(
      body:
          '<p>居住在六叠<sup><a class="duokan-footnote" href="#note_3" '
          'id="noteBack_3"><img src="../Images/note.png"/></a></sup>'
          '大小的出租屋里。</p><p>下一段正文。</p>'
          '<ol class="duokan-footnote-content"><li class="duokan-footnote-item" '
          'id="note_3"><a href="#noteBack_3">$noteText</a></li></ol>',
      css:
          'p {margin:0; font:16px Ahem; text-indent:0;} '
          '.duokan-footnote img {width:1.3em; vertical-align:middle;}',
      binaryFiles: {
        'OEBPS/Images/note.png': base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
          'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
        ),
      },
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final blocks = page.slices.map((slice) => slice.block);
    expect(
      blocks.map((block) => block.layout.text).join('\n'),
      '居住在六叠\uFFFC大小的出租屋里。\n下一段正文。',
    );
    final note = blocks.expand((block) => block.footnotes).single;
    expect(note.text, noteText);
    final lineBox = TextHitTester.lineBoxes(page)
        .firstWhere((box) => box.slice.block.footnotes.contains(note));
    final line = lineBox.slice.block.layout.lines[lineBox.lineIndex];
    final image = line.inlineBoxes.single;
    final center = Offset(
      lineBox.rect.left + image.left + image.width / 2,
      (lineBox.textTop ?? lineBox.rect.top) +
          image.topIn(line.baseline - line.top) +
          image.height / 2,
    );
    expect(TextHitTester.footnoteAt(page, center), same(note));
  });

  test('目标 id 位于无 id 列表项时隐藏整条注释定义', () async {
    final source = await openCssChapter(
      body: '''
<p>正文<a epub:type="noteref" href="#fn-inner">[1]</a></p>
<ol><li><a id="fn-inner"></a>无 id 容器注释</li></ol>
''',
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList(growable: false);
    expect(
      blocks.map((block) => block.layout.text),
      isNot(contains('无 id 容器注释')),
    );
    expect(blocks.expand((block) => block.footnotes).single.text, '无 id 容器注释');
  });

  test('独立图片注号仍生成可点击注释区域', () async {
    final source = await openCssChapter(
      body: '''
<p class="icon"><img class="duokan-footnote" alt="图片注释"
  src="../Images/note.png" width="12" height="12"/></p>
''',
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final footnotes = pages
        .expand((page) => page.slices)
        .expand((slice) => slice.block.footnotes)
        .toList(growable: false);
    expect(footnotes, hasLength(1));
    expect(footnotes.single.text, '图片注释');
  });

  test('空 span 背景图注号可被精确像素命中', () async {
    final source = await openCssChapter(
      body: '''
<p>首先，如何巩固西汉王朝的统治，需要总结历史的经验，做出学术的综合。早在高帝之初，即让陆贾总结“秦所以失天下，吾所以得之者何，及古成败之国”<span class="reader js_readerFooterNote"
  data-wr-footernote="［西汉］司马迁：《史记》卷九十七《郦生陆贾列传》。"></span>的历史经验。</p>
''',
      css: '''
p { margin: 0; font-size: 24px; line-height: 2; text-indent: 2em; }
span.reader {
  position: relative;
  display: inline-block;
  width: 12px;
  height: 12px;
  vertical-align: sub;
  margin: 0 3px;
  background-image: url("../Images/note.png");
  background-size: 100%;
  background-repeat: no-repeat;
}
''',
      contentWidth: 350,
      contentHeight: 900,
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final page = pages.first;
    final block = page.slices.first.block;
    expect(block.footnotes, hasLength(1));
    expect(block.footnotes.single.text, '［西汉］司马迁：《史记》卷九十七《郦生陆贾列传》。');

    var found = false;
    for (final candidatePage in pages) {
      for (final lineBox in TextHitTester.lineBoxes(candidatePage)) {
        final line = lineBox.slice.block.layout.lines[lineBox.lineIndex];
        for (final box in line.inlineBoxes) {
          if (box.offset != block.footnotes.single.start) {
            continue;
          }
          found = true;
          final center = Offset(
            lineBox.rect.left + box.left + box.width / 2,
            lineBox.rect.top +
                box.topIn(line.baseline - line.top) +
                box.height / 2,
          );
          expect(
            TextHitTester.footnoteAt(candidatePage, center),
            same(block.footnotes.single),
          );
        }
      }
    }
    expect(found, isTrue);
  });

  test('QQ/微信读书图片注号从 alt 生成弹窗数据', () async {
    final source = await openCssChapter(
      body: '''
<p class="icon"><img class="qqreader-footnote" alt="QQ 阅读图片注正文"
  src="../Images/note.png" width="12" height="12"/></p>
''',
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final footnotes = pages
        .expand((page) => page.slices)
        .expand((slice) => slice.block.footnotes)
        .toList(growable: false);
    expect(footnotes, hasLength(1));
    expect(footnotes.single.text, 'QQ 阅读图片注正文');
  });

  test('综合注释测试书隐藏定义并生成各渠道弹窗数据', () async {
    final file = File('../../test_corpus/footnote-formats.epub');
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      contentWidth: 300,
      contentHeight: 900,
      verifyCrc: false,
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        // 同一段跨页时多个切片共用内容块，注释按原始引用计数。
        .toSet()
        .toList(growable: false);
    final pageText = blocks.map((block) => block.layout.text).join('\n');
    final footnotes = blocks
        .expand((block) => block.footnotes)
        .toList(growable: false);
    expect(pageText, contains('01 EPUB3 noteref 脚注'));
    expect(pageText, isNot(contains('EPUB3 标准脚注第一段')));
    expect(pageText, isNot(contains('多看文字注第一段')));
    expect(pageText, isNot(contains('Reeden 与多看双类名组合注文')));
    expect(footnotes, hasLength(22));
    expect(
      footnotes.map((note) => note.text).whereType<String>(),
      containsAll(<String>[
        'EPUB2 上标数字链接命中的普通段落注释。',
        'DPUB-ARIA 脚注正文。',
        '这是写在 title 属性里的旧式弹注正文。',
        '这是多看图片注，注文放在 alt 属性中。',
        '这是 QQ 阅读或微信读书图片注，注文放在 alt 属性中。',
        '这是掌阅通用弹注法，正文来自 zy-footnote 属性。',
        'WR 直接文本兼容结构。',
        '这是 js_readerFooterNote 直接文本兼容写法。',
        '这是 data-reeden-footnote-body 直接注文。',
      ]),
    );
    expect(
      footnotes
          .expand((note) => note.imageUrls)
          .where((url) => url.endsWith('note-card.png')),
      isNotEmpty,
    );
  });

  test('跨文档注释定义页只显示说明，不显示任何注文定义', () async {
    final file = File('../../test_corpus/footnote-formats.epub');
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      contentWidth: 300,
      contentHeight: 900,
      verifyCrc: false,
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(1);
    final pageText = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block.layout.text)
        .join('\n');
    expect(pageText, contains('正常阅读只应看到本说明'));
    expect(pageText, isNot(contains('跨 XHTML 标准尾注正文')));
    expect(pageText, isNot(contains('EPUB3 rearnote 尾注正文')));
    expect(pageText, isNot(contains('掌阅 zy-footnote 的真实定义目标')));
    expect(pageText, isNot(contains('21 回链兜底注文')));
  });
}
