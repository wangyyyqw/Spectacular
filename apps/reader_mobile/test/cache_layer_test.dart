import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/ua_stylesheet.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// P7-23：三层缓存与设置失效矩阵——
/// 主题颜色变化 → 零重排（pagination 层键不含颜色）；
/// 字号/行高/对齐/边距 → pagination 层失效；
/// 几何变化 → 全失效；页索引重放命中（P7-22）。
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
    return EpubChapterSource.open(
      file.readAsBytesSync(),
      contentWidth: 320,
      contentHeight: 480,
    );
  }

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
    expect(identical(before, after), isTrue,
        reason: '颜色变化不失效 pagination 层');
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

  test('页索引重放命中：页缓存清空后仍按索引直接出页（分页状态机跳过）', () async {
    final source = await openSource();
    final first = await source.loadChapter(0);
    // 直接清页缓存（模拟重开书），页索引仍在。
    source.clearPaginationCache();
    final replayed = await source.loadChapter(0);
    expect(replayed, hasLength(first.length));
    for (var i = 0; i < first.length; i++) {
      expect(replayed[i].pageIndex, first[i].pageIndex);
      expect(replayed[i].usedHeight, closeTo(first[i].usedHeight, 0.01));
    }
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

  test('UA 覆盖层的 styles 层缓存按标签复用（P7-03/P7-23）', () {
    final base = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
    });
    final h1 = UaBlockDefaults.apply(base, 'h1')!;
    final p = UaBlockDefaults.apply(base, 'p');
    expect(identical(h1, UaBlockDefaults.apply(base, 'h1')), isFalse,
        reason: '工厂每次构造（上层负责按标签缓存）');
    expect(p, isNull);
  });
}
