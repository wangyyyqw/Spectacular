import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/text/reader_text_overlay.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/relocator.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

const _text = 'abcdefghijklmnopqrstuvwx';
String _cfi(int spine, [int offset = 0]) =>
    'epubcfi(/6/${(spine + 1) * 2}!/4/2/1:$offset)';

ReaderDecoration _decoration(String id, int spine, {bool typography = true}) =>
    ReaderDecoration(
      id: id,
      startCfi: _cfi(spine, 3),
      endCfi: _cfi(spine, 8),
      quote: 'defgh',
      style: typography
          ? const ReaderDecorationStyle(
              fontFamily: 'AuditFont',
              fontSizeScale: 0.85,
              fontWeight: 600,
            )
          : const ReaderDecorationStyle(backgroundColor: 0xFFFFCC00),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

ReaderDecoration _copy(
  ReaderDecoration item, {
  String? start,
  String? end,
  ReaderDecorationStyle? style,
}) => ReaderDecoration(
  id: item.id,
  startCfi: start ?? item.startCfi,
  endCfi: end ?? item.endCfi,
  quote: item.quote,
  style: style ?? item.style,
  createdAt: item.createdAt,
  updatedAt: item.updatedAt,
);

class _Store implements ReaderDecorationStore {
  _Store(this.items);
  final List<ReaderDecoration> items;

  @override
  Future<List<ReaderDecoration>> list() async => List.of(items);

  @override
  Future<ReaderDecoration?> add({
    required String startCfi,
    required String endCfi,
    required String quote,
    required ReaderDecorationStyle style,
    String? contextBefore,
    String? contextAfter,
  }) async {
    final item = ReaderDecoration(
      id: '${items.length}',
      startCfi: startCfi,
      endCfi: endCfi,
      quote: quote,
      style: style,
      contextBefore: contextBefore,
      contextAfter: contextAfter,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    items.add(item);
    return item;
  }

  @override
  Future<void> remove(String id) async =>
      items.removeWhere((item) => item.id == id);

  @override
  Future<void> update(String id, {required ReaderDecorationStyle style}) async {
    final index = items.indexWhere((item) => item.id == id);
    if (index >= 0) items[index] = _copy(items[index], style: style);
  }

  @override
  Future<void> relocate(
    String id, {
    required String startCfi,
    required String endCfi,
  }) async {
    final index = items.indexWhere((item) => item.id == id);
    if (index >= 0) {
      items[index] = _copy(items[index], start: startCfi, end: endCfi);
    }
  }
}

class _PreparedSource
    implements
        PreparedChapterSource,
        ReaderTextOverlaySource,
        RestylableChapterSource,
        CurrentReadingChapterSource {
  Future<void> Function(int)? preparer;
  final anchors = <int>[];
  final loads =
      <({int spine, double font, List<ReaderTextOverlay> overlays})>[];
  List<ReaderTextOverlay> overlays = const [];
  String bookTypography = '';
  double font = 16;
  final currentChapters = <int>[];

  @override
  int get chapterCount => 1000;

  @override
  void setChapterPreparer(Future<void> Function(int)? preparer) {
    this.preparer = preparer;
  }

  @override
  void setBookTypographyFingerprint(String fingerprint) =>
      bookTypography = fingerprint;

  @override
  void setCurrentReadingChapter(int spineIndex) =>
      currentChapters.add(spineIndex);

  @override
  Future<AnchorChapter> loadAnchorChapter(int spineIndex) async {
    anchors.add(spineIndex);
    return AnchorChapter(
      spineIndex: spineIndex,
      href: '$spineIndex.xhtml',
      blocks: [AnchorBlock(cfi: _cfi(spineIndex), text: _text)],
    );
  }

  @override
  Future<bool> applyTextOverlays(List<ReaderTextOverlay> next) async {
    final oldKey = ReaderTextOverlayResolver(
      overlays,
      colors: false,
    ).typographyFingerprint;
    overlays = List.unmodifiable(next);
    return oldKey !=
        ReaderTextOverlayResolver(
          overlays,
          colors: false,
        ).typographyFingerprint;
  }

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async =>
      font = overrides.fontSize ?? 16;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    await preparer?.call(spineIndex);
    loads.add((spine: spineIndex, font: font, overlays: List.of(overlays)));
    final style = ComputedStyle({
      'font-size': '${font}px',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: _text,
      style: style,
      maxWidth: 300,
    );
    return [
      PageContent(
        spineIndex: spineIndex,
        pageIndex: 0,
        slices: [
          PageBlockSlice(
            block: PageBlock(
              layout: layout,
              style: style,
              startCfi: _cfi(spineIndex),
            ),
            startLine: 0,
            endLine: layout.lineCount,
            height: layout.height,
          ),
        ],
        usedHeight: layout.height,
        pageHeight: 500,
        topPadding: 0,
      ),
    ];
  }
}

class _BookFontSource extends _PreparedSource
    implements BookTypographyFontSource {
  Set<String> requestedFamilies = const {};
  final availability = <String, bool>{};

  @override
  void setBookTypographyFamilies(Set<String> families) =>
      requestedFamilies = Set.unmodifiable(families);

  @override
  void setBookTypographyFontAvailability(String family, bool available) =>
      availability[family] = available;
}

Future<MemoryReaderProgressStore> _saved() async {
  final store = MemoryReaderProgressStore();
  await store.save(
    'prepared',
    ReaderProgress(
      spineIndex: 740,
      pageIndex: 0,
      cfi: _cfi(740, 3),
      contentRevision: 'r1',
    ),
  );
  return store;
}

Widget _reader(
  _PreparedSource source,
  ReaderProgressStore store,
  ReaderDecorationStore decorations, {
  Future<void> Function(String)? loadFont,
  ValueChanged<ReaderSession>? ready,
  PageTurnMode mode = PageTurnMode.none,
}) => MaterialApp(
  home: Scaffold(
    body: ReaderPage(
      source: source,
      store: store,
      bookId: 'prepared',
      contentRevision: 'r1',
      decorations: decorations,
      onLoadFont: loadFont,
      onSessionReady: ready,
      pageTurnMode: mode,
      overrides: const ReaderOverrides(fontSize: 23),
    ),
  ),
);

void main() {
  testWidgets('登记全书手工字体依赖，首屏只加载目标章字体', (tester) async {
    final source = _BookFontSource();
    final gate = Completer<void>();
    final loads = <String>[];
    await tester.pumpWidget(
      _reader(
        source,
        await _saved(),
        _Store([
          _decoration('current', 740),
          _copy(
            _decoration('later', 999),
            style: const ReaderDecorationStyle(fontFamily: 'MissingLaterFont'),
          ),
          _decoration('paint', 740, typography: false),
        ]),
        loadFont: (family) {
          loads.add(family);
          return gate.future;
        },
      ),
    );
    await tester.pump();
    expect(source.requestedFamilies, {'AuditFont', 'MissingLaterFont'});
    expect(source.availability, isEmpty, reason: '登记请求不代表实际加载成功');
    expect(loads, ['AuditFont']);
    expect(source.anchors, [740]);
    expect(source.loads, isEmpty);
    gate.complete();
    await tester.pumpAndSettle();
    expect(source.loads.where((item) => item.spine == 740), hasLength(1));
    expect(source.loads.map((item) => item.spine).toSet(), {739, 740, 741});
    expect(loads, ['AuditFont']);
    expect(source.availability, {'AuditFont': true});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('目标字体加载失败独立报告回退，原始请求保留且首屏只排一次', (tester) async {
    final source = _BookFontSource();
    final loads = <String>[];
    await tester.pumpWidget(
      _reader(
        source,
        await _saved(),
        _Store([_decoration('current', 740), _decoration('later', 999)]),
        loadFont: (family) async {
          loads.add(family);
          throw const FormatException('自定义字体文件已丢失');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(source.requestedFamilies, {'AuditFont'});
    expect(source.availability, {'AuditFont': false});
    expect(loads, ['AuditFont']);
    expect(source.anchors, [740]);
    expect(source.loads.where((item) => item.spine == 740), hasLength(1));
    expect(source.loads.map((item) => item.spine).toSet(), {739, 740, 741});
    final overlay = source.loads
        .firstWhere((item) => item.spine == 740)
        .overlays
        .single;
    expect(overlay.fontFamily, isNull);
    expect(overlay.fontSizeScale, 0.85, reason: '字体回退保留其余手工度量装饰');
    expect(source.bookTypography, contains('AuditFont'));
    expect(find.byType(ReaderPageFooter), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('取消后晚到的字体结果不回写源的可用性', (tester) async {
    final source = _BookFontSource();
    final gate = Completer<void>();
    await tester.pumpWidget(
      _reader(
        source,
        await _saved(),
        _Store([_decoration('current', 740)]),
        loadFont: (_) => gate.future,
      ),
    );
    await tester.pump();
    expect(source.requestedFamilies, {'AuditFont'});
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(source.availability, isEmpty);
    expect(source.loads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实字体度量装饰在目标章首排前准备，邻章预取不重复当前章', (tester) async {
    final source = _PreparedSource();
    final store = await _saved();
    final decorations = _Store([
      _decoration('current', 740),
      _decoration('later', 999),
    ]);
    final fontGate = Completer<void>();
    final fonts = <String>[];
    late ReaderSession session;
    await tester.pumpWidget(
      _reader(
        source,
        store,
        decorations,
        loadFont: (font) {
          fonts.add(font);
          return fontGate.future;
        },
        ready: (value) => session = value,
      ),
    );
    await tester.pump();
    expect(source.anchors, [740]);
    expect(source.loads, isEmpty);
    expect(fonts, ['AuditFont']);
    expect(session.page, isNull);
    expect(source.bookTypography, contains(_cfi(999, 3)));
    fontGate.complete();
    await tester.pumpAndSettle();
    expect(source.loads.where((item) => item.spine == 740), hasLength(1));
    expect(source.loads.map((item) => item.spine).toSet(), {739, 740, 741});
    final current = source.loads.firstWhere((item) => item.spine == 740);
    expect(current.font, 23);
    expect(current.overlays, hasLength(1));
    expect(current.overlays.single.fontSizeScale, 0.85);
    expect(current.overlays.single.fontWeight, 600);
    expect(find.text('1/1'), findsOneWidget);
    expect(session.progress?.cfi, _cfi(740, 3));
    expect(source.currentChapters, contains(740));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('并发章准备共享字体加载，逐章核验不改变书级指纹', (tester) async {
    final source = _PreparedSource();
    final fontGate = Completer<void>();
    final fonts = <String>[];
    await tester.pumpWidget(
      _reader(
        source,
        await _saved(),
        _Store([_decoration('current', 740), _decoration('next', 741)]),
        loadFont: (font) {
          fonts.add(font);
          return fontGate.future;
        },
      ),
    );
    await tester.pump();
    final bookTypography = source.bookTypography;
    final neighbor = source.loadChapter(741);
    final sameChapter = source.loadChapter(740);
    await tester.pump();
    expect(source.anchors, [740, 741]);
    expect(fonts, ['AuditFont']);
    fontGate.complete();
    await Future.wait([neighbor, sameChapter]);
    await tester.pumpAndSettle();
    expect(source.bookTypography, bookTypography);
    expect(source.overlays.map((overlay) => overlay.startCfi), [
      _cfi(740, 3),
      _cfi(741, 3),
    ]);
    await source.loadChapter(741);
    expect(source.anchors, [740, 741]);
    expect(fonts, ['AuditFont']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('纯绘制装饰更新不触发当前章几何重排', (tester) async {
    final source = _PreparedSource();
    final store = await _saved();
    await tester.pumpWidget(
      _reader(
        source,
        store,
        _Store([_decoration('a', 740, typography: false)]),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.loads.where((item) => item.spine == 740), hasLength(1));
    expect(source.loads.map((item) => item.spine).toSet(), {739, 740, 741});
    await tester.pumpWidget(
      _reader(
        source,
        store,
        _Store([
          _decoration('a', 740, typography: false),
          _decoration('b', 740, typography: false),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.loads.where((item) => item.spine == 740), hasLength(1));
    expect(source.loads.map((item) => item.spine).toSet(), {739, 740, 741});
    expect(source.overlays, hasLength(2));
  });

  test('原文核验允许唯一引文修正 CFI，歧义记录不参与字体装饰', () {
    final book = AnchorBook(
      revision: 'r1',
      chapters: [
        AnchorChapter(
          spineIndex: 0,
          href: '0.xhtml',
          blocks: const [
            AnchorBlock(cfi: 'epubcfi(/6/2!/4/2/9:0)', text: 'abc唯一引文xyz重复重复'),
          ],
        ),
      ],
    );
    ReaderAnnotation item(String id, String quote) => ReaderAnnotation(
      id: id,
      type: ReaderAnnotationType.mark,
      startCfi: _cfi(0),
      endCfi: _cfi(0, quote.length),
      quote: quote,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final resolved = AnnotationRelocator.relocateAnchors(
      annotations: [item('unique', '唯一引文'), item('ambiguous', '重复')],
      book: book,
    );
    expect(resolved.first.status, AnnotationRelocationStatus.relocated);
    expect(resolved.first.startCfi, 'epubcfi(/6/2!/4/2/9:3)');
    expect(resolved.first.page, isNull);
    expect(resolved.last.isResolved, isFalse);
  });
}
