import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/text/reader_text_overlay.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/relocator.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/decorations/decoration_rule_defaults.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/decorations/decoration_editor_sheet.dart';
import 'package:reader_ui/selection/selection_layer.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

const _text = 'abcdefghijklmnopqrstuvwx';
String _cfi(int spine, [int offset = 0]) =>
    'epubcfi(/6/${(spine + 1) * 2}!/4/2/1:$offset)';

String _anchorData(
  int spine, {
  String text = _text,
  int from = 3,
  int to = 8,
}) => AnchorRecord(
  original: AnchorBook(
    revision: 'r1',
    chapters: [
      AnchorChapter(
        spineIndex: spine,
        href: '$spine.xhtml',
        blocks: [AnchorBlock(cfi: _cfi(spine), text: text)],
      ),
    ],
  ).capture(_cfi(spine, from), endCfi: _cfi(spine, to))!,
).encode();

ReaderDecoration _decoration(String id, int spine, {bool typography = true}) =>
    ReaderDecoration(
      id: id,
      startCfi: _cfi(spine, 3),
      endCfi: _cfi(spine, 8),
      quote: 'defgh',
      anchorData: _anchorData(spine),
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
  anchorData: item.anchorData,
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
      anchorData: _anchorData(
        spineIndexOfCfi(EpubCfi.parse(startCfi)!)!,
        from: cfiCharOffset(startCfi) ?? 0,
        to: cfiCharOffset(endCfi) ?? 0,
      ),
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
  ReaderDecorationRuleStore? rules,
}) => MaterialApp(
  home: Scaffold(
    body: ReaderPage(
      source: source,
      store: store,
      bookId: 'prepared',
      contentRevision: 'r1',
      decorations: decorations,
      decorationRules: rules,
      onLoadFont: loadFont,
      onSessionReady: ready,
      pageTurnMode: mode,
      overrides: const ReaderOverrides(fontSize: 23),
    ),
  ),
);

Future<void> _expectFirstPaint(
  WidgetTester tester,
  _PreparedSource source,
) async {
  // 不推进空闲定时器，单独核验首屏就绪不依赖邻章准备。
  await tester.pump();
  await tester.pump();
  expect(source.loads.map((item) => item.spine), [740]);
  expect(find.byType(ReaderPageFooter), findsOneWidget);
  expect(find.byType(ReaderPageHeader), findsNothing, reason: '章首页隐藏页眉');
}

void _expectIdlePreparations(_PreparedSource source) {
  expect(source.loads.where((item) => item.spine == 740), hasLength(1));
  expect(source.loads.map((item) => item.spine).toSet(), {
    738,
    739,
    740,
    741,
    742,
  }, reason: '前后两页预热与邻章预排共用加载；不读取更远章节');
}

Future<bool> _hasColor(WidgetTester tester, GlobalKey key, int color) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = boundary.toImageSync();
  final pixels = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  image.dispose();
  for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
    if (pixels.getUint8(offset) == ((color >> 16) & 255) &&
        pixels.getUint8(offset + 1) == ((color >> 8) & 255) &&
        pixels.getUint8(offset + 2) == (color & 255) &&
        pixels.getUint8(offset + 3) == 255) {
      return true;
    }
  }
  return false;
}

void main() {
  testWidgets('同页装饰几何复用后，改色与移除立即更新像素且保留原文位置', (tester) async {
    final source = _PreparedSource();
    final progress = await _saved();
    final key = GlobalKey();
    late ReaderSession session;
    Widget reader(int? color) => RepaintBoundary(
      key: key,
      child: _reader(
        source,
        progress,
        _Store([
          if (color != null)
            _copy(
              _decoration('cached', 740, typography: false),
              style: ReaderDecorationStyle(
                backgroundColor: color,
                paddingTop: 6,
              ),
            ),
        ]),
        ready: (value) => session = value,
      ),
    );
    await tester.pumpWidget(reader(0xFFFF0000));
    await _expectFirstPaint(tester, source);
    await tester.pumpAndSettle();
    final page = session.page;
    final cfi = session.currentCfi;
    expect(await _hasColor(tester, key, 0xFFFF0000), isTrue);
    await tester.pumpWidget(reader(0xFF0000FF));
    await tester.pumpAndSettle();
    expect(await _hasColor(tester, key, 0xFF0000FF), isTrue);
    expect(await _hasColor(tester, key, 0xFFFF0000), isFalse);
    await tester.pumpWidget(reader(null));
    await tester.pumpAndSettle();
    expect(await _hasColor(tester, key, 0xFF0000FF), isFalse);
    expect(session.page, same(page));
    expect(session.currentCfi, cfi);
    expect(session.pageTurns, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('默认图片高亮的绘制留白不传入排版行盒', (tester) async {
    final source = _PreparedSource();
    await tester.pumpWidget(
      _reader(source, await _saved(), _Store([]), rules: _DefaultRuleStore()),
    );
    for (var frame = 0; frame < 60 && source.loads.isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    final overlay = source.loads.first.overlays.single;
    expect(overlay.fontSizeScale, 0.9);
    expect(overlay.paddingByTextHeight, EdgeInsets.zero);
    final style = readerDecorationBuiltInStyles.first.style.decorationStyle;
    expect(style.paddingTop, 9);
    expect(style.paddingBottom, 9);
    expect(style.backgroundImagePath, isNotNull);
  });

  testWidgets('连续滚动选字保存装饰后立即可点击编辑，位置不跳动', (tester) async {
    final source = _PreparedSource();
    final decorations = _Store([]);
    late ReaderSession session;
    await tester.pumpWidget(
      _reader(
        source,
        await _saved(),
        decorations,
        mode: PageTurnMode.scroll,
        ready: (value) => session = value,
      ),
    );
    await tester.pumpAndSettle();
    final paper = find.byKey(const ValueKey('scroll-page-740-0'));
    final line = TextHitTester.lineBoxes(session.page!).first;
    final point =
        tester.getTopLeft(paper) +
        Offset(line.rect.left + 10, line.rect.center.dy);
    final progress = session.progress;
    await tester.longPressAt(point);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('selection-action-decoration')));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderDecorationEditorSheet), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('decoration-save')));
    await tester.pumpAndSettle();
    expect(decorations.items, hasLength(1));
    expect(decorations.items.single.quote, line.text);
    expect(session.progress, progress);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ReaderDecorationEditorSheet>(
            find.byType(ReaderDecorationEditorSheet),
          )
          .quote,
      line.text,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
    await _expectFirstPaint(tester, source);
    await tester.pumpAndSettle();
    _expectIdlePreparations(source);
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
    await _expectFirstPaint(tester, source);
    await tester.pumpAndSettle();
    expect(source.requestedFamilies, {'AuditFont'});
    expect(source.availability, {'AuditFont': false});
    expect(loads, ['AuditFont']);
    expect(source.anchors, [740]);
    _expectIdlePreparations(source);
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
    await _expectFirstPaint(tester, source);
    await tester.pumpAndSettle();
    _expectIdlePreparations(source);
    final current = source.loads.firstWhere((item) => item.spine == 740);
    expect(current.font, 23);
    expect(current.overlays, hasLength(1));
    expect(current.overlays.single.fontSizeScale, 0.85);
    expect(current.overlays.single.fontWeight, 600);
    expect(session.chapterPageCount, 1);
    expect(find.byType(ReaderPageHeader), findsNothing, reason: '章首页不显示页码');
    expect(find.byType(ReaderPageFooter), findsOneWidget);
    expect(session.progress?.cfi, _cfi(740, 3));
    expect(session.pageTurns, 0, reason: '空闲预取不提交阅读位置');
    expect((await store.load('prepared'))?.cfi, _cfi(740, 3));
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
    late ReaderSession session;
    await tester.pumpWidget(
      _reader(
        source,
        store,
        _Store([_decoration('a', 740, typography: false)]),
        ready: (value) => session = value,
      ),
    );
    await _expectFirstPaint(tester, source);
    await tester.pumpAndSettle();
    _expectIdlePreparations(source);
    final page = session.page;
    final progress = session.progress;
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
    _expectIdlePreparations(source);
    expect(source.overlays, hasLength(2));
    expect(session.page, same(page), reason: '纯绘制装饰复用当前页的几何结果');
    expect(session.progress, progress);
    expect(session.pageTurns, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('高亮染色更新复用章节几何，颜色透明度和阅读位置保持正确', (tester) async {
    final source = _PreparedSource();
    final progressStore = await _saved();
    late ReaderSession session;
    ReaderDecoration decoration(int color) => _copy(
      _decoration('tint', 740, typography: false),
      style: ReaderDecorationStyle(
        highlight: ReaderDecorationHighlight(
          style: ReaderAnnotationStyle.tint,
          color: color,
          opacity: 0.5,
        ),
      ),
    );
    await tester.pumpWidget(
      _reader(
        source,
        progressStore,
        _Store([decoration(0xFFFF0000)]),
        ready: (value) => session = value,
      ),
    );
    await _expectFirstPaint(tester, source);
    await tester.pumpAndSettle();
    final page = session.page;
    final cfi = session.currentCfi;
    final loads = source.loads.where((item) => item.spine == 740).length;
    expect(source.overlays.single.color, 0xFFFF0000);
    expect(source.overlays.single.paintColor!.a, closeTo(0.5, 0.01));
    await tester.pumpWidget(
      _reader(source, progressStore, _Store([decoration(0xFF0000FF)])),
    );
    await tester.pumpAndSettle();
    expect(source.overlays.single.color, 0xFF0000FF);
    expect(source.overlays.single.colorOpacity, 0.5);
    expect(source.loads.where((item) => item.spine == 740), hasLength(loads));
    expect(session.page, same(page));
    expect(session.currentCfi, cfi);
    expect(session.pageTurns, 0);
    await tester.pumpWidget(const SizedBox());
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
      anchorData: _anchorData(0, text: quote, from: 0, to: quote.length),
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

class _DefaultRuleStore implements ReaderDecorationRuleStore {
  @override
  Future<List<ReaderDecorationRuleGroup>> listGroups() async => [
    const ReaderDecorationRuleGroup(id: 'default', name: '默认'),
  ];
  @override
  Future<List<ReaderDecorationRule>> listRules() async => [
    ReaderDecorationRule(
      id: 'highlight',
      groupId: 'default',
      pattern: 'defgh',
      style: readerDecorationBuiltInStyles.first.style,
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
