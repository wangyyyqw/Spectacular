import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

import 'reader/support/css_chapter_book.dart';

import 'package:reader_core/source/chapter_source.dart';

/// P7-23：三层缓存与设置失效矩阵——
/// 主题颜色变化 → 零重排（pagination 层键不含颜色）；
/// 字号/行高/对齐/边距/几何 → 完整键隔离并保留近期结果；
/// 页、块和索引共用三项/64MiB 完成缓存，索引可以独立重放。
void main() {
  Directory? corpus;

  setUpAll(() {
    var directory = Directory.current;
    while (true) {
      final candidate = Directory('${directory.path}/test_corpus');
      if (candidate.existsSync()) {
        corpus = candidate;
        break;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        break;
      }
      directory = parent;
    }
  });

  Future<EpubChapterSource> openSource() async {
    final file = File('${corpus!.path}/basic.epub');
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      contentWidth: 320,
      contentHeight: 480,
    );
    addTearDown(source.close);
    return source;
  }

  Future<EpubChapterSource> openStyleProbe() async {
    final source = await openCssChapter(
      body: '<p>缓存样式验证</p>',
      css: 'html, body { font-size: 16px; } p { margin: 0; text-indent: 0; }',
      contentWidth: 320,
      contentHeight: 480,
      overrides: const ReaderOverrides(fontSize: 18),
    );
    addTearDown(source.close);
    return source;
  }

  test('级联基准保留作者字号，正文测量消费阅读器字号和颜色', () async {
    final source = await openStyleProbe();
    final first = source.style;
    expect(source.style, same(first));
    expect(first.fontSize, 16, reason: '作者 em 几何在阅读字号覆盖前解算');
    final before = await source.loadChapter(0);
    final initialBlock = before.single.slices.single.block;
    expect(initialBlock.style!.fontSize, 18);
    expect(initialBlock.layout.runs.single.style.fontSize, 18);

    await source.applyOverrides(
      const ReaderOverrides(fontSize: 22, textColor: Color(0xFF123456)),
    );
    final after = await source.loadChapter(0);
    final updatedBlock = after.single.slices.single.block;
    expect(after, isNot(same(before)));
    expect(source.style.fontSize, 16);
    expect(source.style.color, const Color(0xFF123456));
    expect(source.style, same(source.style));
    expect(updatedBlock.style!.fontSize, 22);
    expect(updatedBlock.layout.runs.single.style.fontSize, 22);
    expect(
      updatedBlock.layout.runs.single.style.color,
      const Color(0xFF123456),
    );
  });

  test('尺寸变化更新实际测量，重复尺寸复用已完成布局', () async {
    final source = await openStyleProbe();
    final before = await source.loadChapter(0);
    expect(before.single.slices.single.block.layout.maxWidth, 320);

    expect(await source.applyContentSize(width: 280, height: 420), isTrue);
    final resized = await source.loadChapter(0);
    expect(resized, isNot(same(before)));
    expect(resized.single.slices.single.block.layout.maxWidth, 280);
    expect(
      resized.single.slices.single.block.layout.runs.single.style.fontSize,
      18,
    );
    expect(source.style.fontSize, 16);
    expect(source.style, same(source.style));

    expect(await source.applyContentSize(width: 280, height: 420), isFalse);
    expect(await source.loadChapter(0), same(resized));
  });

  test('切主题（颜色）：页对象原样复用（零重排）', () async {
    final source = await openSource();
    final before = await source.loadChapter(0);
    await source.applyOverrides(
      const ReaderOverrides(
        textColor: Color(0xFF333333),
        backgroundColor: Color(0xFF111111),
      ),
    );
    final after = await source.loadChapter(0);
    expect(identical(before, after), isTrue, reason: '颜色变化不失效 pagination 层');
    expect(after.first.pageIndex, before.first.pageIndex);
  });

  test('字号变化：pagination 层失效并重排（结果页数可不同）', () async {
    final source = await openSource();
    final before = await source.loadChapter(0);
    await source.applyOverrides(const ReaderOverrides(fontSize: 20));
    final after = await source.loadChapter(0);
    expect(identical(before, after), isFalse, reason: '排版字段变化触发重排');
    expect(after, isNotEmpty);
  });

  test('相同设置重复应用：不失效（P2-24 行为不回退）', () async {
    final source = await openSource();
    final before = await source.loadChapter(0);
    await source.applyOverrides(const ReaderOverrides(fontSize: 18));
    final resized = await source.loadChapter(0);
    await source.applyOverrides(const ReaderOverrides(fontSize: 18));
    final again = await source.loadChapter(0);
    expect(identical(resized, again), isTrue);
    expect(before, isNot(same(resized)));
  });

  test('几何变化：全失效（矩阵「几何全变」行）', () async {
    final source = await openSource();
    final before = await source.loadChapter(0);
    final changed = await source.applyContentSize(width: 280, height: 420);
    expect(changed, isTrue);
    final after = await source.loadChapter(0);
    expect(identical(before, after), isFalse);
  });

  test('失效日志：四类诱因可区分且带 old/new（P7-27）', () async {
    final source = await openSource();
    await source.loadChapter(0);
    source.invalidationLog.clear();

    // ① configChanged（排版字段）。
    await source.applyOverrides(const ReaderOverrides(fontSize: 20));
    await source.loadChapter(0);
    // ② 颜色不产生日志（零失效）。
    await source.applyOverrides(
      const ReaderOverrides(fontSize: 20, textColor: Color(0xFF333333)),
    );
    // ③ viewportSizeChanged。
    await source.applyContentSize(width: 300, height: 440);
    await source.loadChapter(0);
    // ④ indexCorrupted（写入坏索引后触发）。
    source.clearPaginationCache();
    source.injectPageIndexForTest(0, Uint8List.fromList(<int>[1, 2, 3]));
    await source.loadChapter(0);

    final reasons = source.invalidationLog
        .map((line) => line.split('|').first.trim())
        .toList(growable: false);
    expect(reasons, contains('configChanged'));
    expect(reasons, contains('viewportSizeChanged'));
    expect(reasons, contains('indexCorrupted'));
    expect(
      reasons.where((r) => r == 'configChanged'),
      hasLength(1),
      reason: '颜色变化不产生失效日志',
    );
    // 日志带 old/new 上下文。
    final configLine = source.invalidationLog.firstWhere(
      (line) => line.startsWith('configChanged'),
    );
    expect(configLine, contains(' -> '));
  });

  test('页索引重放命中：页缓存清空后仍按索引直接出页（分页状态机跳过）', () async {
    final source = await openSource();
    final first = await source.loadChapter(0);
    expect(source.blockCacheHits, 0);
    // 直接清页缓存（模拟重开书），页索引仍在。
    source.clearPaginationCache();
    final replayed = await source.loadChapter(0);
    expect(source.blockCacheHits, 1, reason: 'styles 层块树复用，不重新级联/测量');
    expect(replayed, hasLength(first.length));
    for (var i = 0; i < first.length; i++) {
      expect(replayed[i].pageIndex, first[i].pageIndex);
      expect(replayed[i].usedHeight, closeTo(first[i].usedHeight, 0.01));
    }
  });

  test('字号变化保留旧布局，新字号重建并可切回复用', () async {
    final source = await openSource();
    final before = await source.loadChapter(0);
    expect(source.cacheReport, contains('块缓存 1/'));
    expect(source.cacheReport, contains('基础级联 1/'));
    expect(source.displayDocumentCacheHits, 0);

    await source.applyOverrides(const ReaderOverrides(fontSize: 20));
    expect(source.cacheReport, contains('块缓存 1/'));
    expect(source.cacheReport, contains('基础级联 1/'));
    expect(
      source.cacheReport,
      contains('文档缓存 1/'),
      reason: '字号不改变章节结构与 display 聚合',
    );

    await source.loadChapter(0);
    expect(source.blockCacheHits, 0, reason: '失效后重新构建，不复用旧块');
    expect(source.displayDocumentCacheHits, 1, reason: '重排复用已解析章节结构');
    await source.applyOverrides(const ReaderOverrides());
    expect(await source.loadChapter(0), same(before));
  });

  test('只换字族：切回同一字族直接命中分页缓存', () async {
    final source = await openSource();
    addTearDown(source.close);
    final builtin = await source.loadChapter(0);

    await source.applyOverrides(
      const ReaderOverrides(fontFamily: 'user_font_a'),
    );
    final custom = await source.loadChapter(0);
    expect(identical(custom, builtin), isFalse);
    expect(source.cacheReport, contains('页缓存 2/'), reason: '两套字体各留一份');

    await source.applyOverrides(const ReaderOverrides());
    expect(
      identical(await source.loadChapter(0), builtin),
      isTrue,
      reason: '切回默认字体免重排',
    );
    await source.applyOverrides(
      const ReaderOverrides(fontFamily: 'user_font_a'),
    );
    expect(
      identical(await source.loadChapter(0), custom),
      isTrue,
      reason: '切回自定义字体免重排',
    );
    expect(
      source.invalidationLog.where(
        (line) => line.startsWith('fontFamilyChanged'),
      ),
      hasLength(3),
      reason: '三次换字体都走字族专用失效，不整表清空',
    );
  });

  test('字号与字族同时变化隔离结果，三套近期布局各可复用', () async {
    final source = await openSource();
    addTearDown(source.close);
    final builtin = await source.loadChapter(0);
    await source.applyOverrides(
      const ReaderOverrides(fontFamily: 'user_font_a'),
    );
    final custom = await source.loadChapter(0);

    await source.applyOverrides(
      const ReaderOverrides(fontSize: 20, fontFamily: 'user_font_a'),
    );
    expect(source.cacheReport, contains('页缓存 2/'));
    expect(source.cacheReport, contains('块缓存 2/'));
    final resized = await source.loadChapter(0);
    expect(resized, isNot(same(custom)));
    await source.applyOverrides(const ReaderOverrides());
    expect(await source.loadChapter(0), same(builtin));
    await source.applyOverrides(
      const ReaderOverrides(fontFamily: 'user_font_a'),
    );
    expect(await source.loadChapter(0), same(custom));
  });

  test('几何变化保留旧完整布局，结构按新宽度准备，切回可命中', () async {
    final source = await openSource();
    final before = await source.loadChapter(0);
    expect(source.cacheReport, contains('基础级联 1/'));
    await source.applyContentSize(width: 280, height: 420);
    expect(source.cacheReport, contains('块缓存 1/'));
    expect(source.cacheReport, contains('文档缓存 0/'));
    expect(
      source.cacheReport,
      contains('基础级联 1/'),
      reason: '尺寸变化只影响媒体查询求值，不改变已解析选择器',
    );
    expect(await source.loadChapter(0), isNot(same(before)));
    await source.applyContentSize(width: 320, height: 480);
    expect(await source.loadChapter(0), same(before));
  });

  test('关闭章节源释放缓存并拒绝后续渲染', () async {
    final source = await openSource();
    await source.loadChapter(0);
    expect(source.cacheReport, isNot(contains('页缓存 0/')));

    source.close();

    expect(source.isClosed, isTrue);
    expect(source.cacheReport, contains('页缓存 0/'));
    expect(source.cacheReport, contains('块缓存 0/'));
    expect(source.cacheReport, contains('文档缓存 0/'));
    await expectLater(
      source.loadChapter(0),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    source.close();
  });

  test('指纹口径：颜色不参与、排版字段参与（P7-23）', () {
    final base = const ReaderOverrides().fingerprint;
    final colored = const ReaderOverrides(
      textColor: Color(0xFF000000),
      backgroundColor: Color(0xFFEEEEEE),
    ).fingerprint;
    expect(colored, base, reason: '颜色不进排版指纹');
    final sized = const ReaderOverrides(fontSize: 20).fingerprint;
    expect(sized, isNot(base));
  });
}
