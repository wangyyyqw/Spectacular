import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/text/reader_text_overlay.dart';
import 'package:reader_core/util/bounded_cache.dart';
import 'package:reader_core/epub/chapter/book_fonts.dart';
import 'package:reader_core/epub/chapter/book_resources.dart';
import 'package:reader_core/epub/chapter/chapter_layout_job.dart';
import 'package:reader_core/epub/chapter/chapter_text_measurer.dart';

import '../support/css_chapter_book.dart';
import 'package:reader_core/source/chapter_source.dart';

class _ObservedWidthCache extends BoundedCache<String, double> {
  _ObservedWidthCache() : super(128);

  int probes = 0;
  int reads = 0;
  int misses = 0;
  int writes = 0;

  void resetObservations() => probes = reads = misses = writes = 0;

  @override
  bool containsKey(String key) {
    probes += 1;
    final found = super.containsKey(key);
    if (!found) misses += 1;
    return found;
  }

  @override
  double? operator [](String key) {
    reads += 1;
    return super[key];
  }

  @override
  void operator []=(String key, double value) {
    writes += 1;
    super[key] = value;
  }
}

class _CancelWhenBudget extends LayoutBudget {
  _CancelWhenBudget(this.shouldCancel)
    : super(priority: ChapterLayoutPriority.reading, isCurrent: () => true);

  final bool Function() shouldCancel;
  int checkpoints = 0;

  @override
  Future<void> checkpoint({bool force = false}) async {
    checkpoints += 1;
    if (shouldCancel()) cancel();
    await super.checkpoint(force: force);
  }
}

Future<BookFontView> _fontView() async {
  final document = (await openEpub(
    buildCssChapterBook(body: '<p>预算测试</p>'),
    verifyCrc: false,
  )).document!;
  final resources = BookResources(document);
  final fonts = BookFonts(resources, onFontsChanged: (_) {});
  final view = fonts.freeze();
  fonts.close();
  resources.close();
  return view;
}

LayoutSnapshot _snapshot(BookFontView fonts) => LayoutSnapshot(
  spineIndex: 0,
  key: '最小内容宽度预算',
  contentVersion: '1',
  generation: 0,
  width: 300,
  height: 500,
  pageHeight: 500,
  topInset: 0,
  baseStyle: ComputedStyle({'font-size': '16px', 'font-family': 'serif'}),
  overrides: const ReaderOverrides(),
  textOverlays: ReaderTextOverlayResolver(const []),
  fontDependency: fonts.dependency(const {}),
  fonts: fonts,
  fontFamilies: const {},
  trimTextEdges: true,
);

ChapterTextMeasurer _measurer(
  LayoutSnapshot snapshot,
  LayoutBudget budget,
  BoundedCache<String, double> cache,
) => ChapterTextMeasurer(snapshot, budget, TextLayoutCache(), cache);

Future<_ObservedWidthCache> _warmCache(
  LayoutSnapshot snapshot,
  String text,
) async {
  final cache = _ObservedWidthCache();
  await _measurer(
    snapshot,
    LayoutBudget(
      priority: ChapterLayoutPriority.reading,
      isCurrent: () => true,
    ),
    cache,
  ).minContentTextWidth(
    text: text,
    breakEverywhere: true,
    style: snapshot.baseStyle,
  );
  cache.resetObservations();
  return cache;
}

void _expectStoppedInStage(
  String stage,
  _ObservedWidthCache cache,
  int segmentCount,
) {
  expect(cache.misses, 0, reason: '长文本仅重复已经预热的分段');
  expect(cache.writes, 0, reason: '全命中路径没有新的原生测量结果');
  if (stage == '分段') {
    expect(cache.probes, 0);
  } else if (stage == '缓存查找') {
    expect(cache.probes, inExclusiveRange(0, segmentCount));
    expect(cache.reads, 0);
  } else {
    expect(cache.probes, segmentCount);
    expect(cache.reads, inExclusiveRange(0, segmentCount));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutSnapshot snapshot;
  setUpAll(() async => snapshot = _snapshot(await _fontView()));

  for (final stage in ['分段', '缓存查找', '宽度汇总']) {
    test('缓存全命中的长文本在$stage途中响应取消', () async {
      const seed = '甲乙𠀀abc';
      const repetitions = 5000;
      final cache = await _warmCache(snapshot, seed);
      late final _CancelWhenBudget budget;
      budget = _CancelWhenBudget(
        () => switch (stage) {
          '分段' => budget.checkpoints >= 64,
          '缓存查找' => cache.probes >= 64,
          _ => cache.reads >= 64,
        },
      );
      await expectLater(
        _measurer(snapshot, budget, cache).minContentTextWidth(
          text: seed * repetitions,
          breakEverywhere: true,
          style: snapshot.baseStyle,
        ),
        throwsA(isA<ChapterLoadCancelled>()),
      );
      _expectStoppedInStage(stage, cache, seed.runes.length * repetitions);
    });
  }

  for (final breakEverywhere in [false, true]) {
    test('预算检查保留混排分段的精确宽度（逐字断行：$breakEverywhere）', () async {
      const cjk = '甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉';
      const text = '$cjk \talpha汉\nbeta😃\r𠀀';
      final segments = [
        ...cjk.split(''),
        for (final part in ['alpha', '汉', 'beta', '😃', '𠀀'])
          if (breakEverywhere)
            for (final rune in part.runes) String.fromCharCode(rune)
          else
            part,
      ];
      final reference = TextLayoutEngine.measureTextWidths(
        texts: segments,
        style: snapshot.baseStyle,
        hasGlyph: snapshot.fonts.hasGlyph,
      ).values.fold<double>(0, (width, next) => math.max(width, next));
      final measure = _measurer(
        snapshot,
        LayoutBudget(
          priority: ChapterLayoutPriority.reading,
          isCurrent: () => true,
        ),
        BoundedCache<String, double>(128),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        expect(
          await measure.minContentTextWidth(
            text: text,
            breakEverywhere: breakEverywhere,
            style: snapshot.baseStyle,
          ),
          reference,
        );
      }
    });
  }
}
