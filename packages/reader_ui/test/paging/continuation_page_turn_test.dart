import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/paging/continuation_geometry.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

const _sheet = Size(360, 520);
const _padding = EdgeInsets.fromLTRB(30, 24, 22, 28);
const _paper = Color(0xFFF1E8D5);
const _oldInk = Color(0xFF155E9B);
const _newInk = Color(0xFFBD4B21);

ComputedStyle _style({bool vertical = false, String? effect}) => ComputedStyle({
  'font-family': 'Ahem',
  'font-size': '16px',
  'line-height': '1.5',
  'white-space': 'pre-wrap',
  'margin-bottom': '14px',
  if (vertical) 'writing-mode': 'vertical-rl',
  'text-shadow': ?effect,
});

List<PageBlock> _blocks(
  int spine,
  double width, {
  int count = 4,
  PageContainer? container,
}) => [
  for (var index = 0; index < count; index++)
    PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: List.filled(
          spine == 0 ? index % 2 + 1 : (index + 1) % 2 + 1,
          'ABCDEFGHIJKLMNOP',
        ).join('\n'),
        style: ComputedStyle({
          ..._style().values,
          'color': spine == 0 ? '#155e9b' : '#bd4b21',
        }),
        maxWidth: width,
      ),
      style: ComputedStyle({
        ..._style().values,
        'color': spine == 0 ? '#155e9b' : '#bd4b21',
      }),
      containingWidth: width,
      startCfi: 'epubcfi(/6/${(spine + 1) * 2}!/4/${(index + 1) * 2}/1:0)',
    ).withSpacing(
      containers: container == null
          ? null
          : [
              PageContainerFragment(
                container: container,
                startsHere: index == 0,
                endsHere: index == count - 1,
              ),
            ],
    ),
];

class _Source implements ReaderChapterSource, ResizableChapterSource {
  _Source({this.gate});

  final Completer<void>? gate;
  double width = 308;
  double height = 400;
  double topInset = 0;

  @override
  int get chapterCount => 2;

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
    ContentSideInsets? sideInsets,
  }) async {
    final changed = this.width != width || this.height != height;
    this.width = width;
    this.height = height;
    this.topInset = topInset;
    return changed;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (spineIndex == 1) await gate?.future;
    return Paginator(pageHeight: height)
        .measureChapter(
          spineIndex: spineIndex,
          blocks: _blocks(spineIndex, width),
        )
        .pages;
  }
}

Widget _reader(
  _Source source,
  MemoryReaderProgressStore store,
  GlobalKey boundary, {
  PageTurnMode mode = PageTurnMode.continuation,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: _sheet.width,
        height: _sheet.height,
        child: RepaintBoundary(
          key: boundary,
          child: ReaderPage(
            source: source,
            store: store,
            bookId: '接续正式分页回归',
            contentRevision: '接续-r1',
            background: _paper,
            padding: _padding,
            overrides: const ReaderOverrides(),
            bookTitle: '接续正式分页',
            pageTurnMode: mode,
          ),
        ),
      ),
    ),
  ),
);

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 100 && !ready(); frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: '正式翻页入口应到达检查阶段');
}

PageTurnViewState _view(WidgetTester tester) =>
    tester.state<PageTurnViewState>(find.byType(PageTurnView));

void _configure(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _drag(PageTurnController controller, double fraction) {
  final down = Offset(controller.size.width - 10, controller.size.height / 2);
  final touch = down.translate(-controller.size.width * fraction, 0);
  controller.pointerDown(down);
  controller.beginDrag(DragStartDetails(localPosition: down));
  controller.updateDrag(
    DragUpdateDetails(localPosition: touch, globalPosition: touch),
  );
}

Future<ByteData> _bytes(WidgetTester tester, ui.Image image) async =>
    (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;

Future<ByteData> _frame(
  WidgetTester tester,
  GlobalKey key, {
  String? name,
}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = boundary.toImageSync();
  try {
    final directory = Platform.environment['CONTINUATION_FRAME_DIR'];
    if (directory != null && name != null) {
      await tester.runAsync(() async {
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png').writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
      });
    }
    return await _bytes(tester, image);
  } finally {
    image.dispose();
  }
}

List<int> _pixel(ByteData bytes, int x, int y, {int width = 360}) =>
    List.generate(
      4,
      (channel) => bytes.getUint8((y * width + x) * 4 + channel),
    );

int _solidInk(ByteData bytes, Color color) {
  final rgba = [
    (color.r * 255).round(),
    (color.g * 255).round(),
    (color.b * 255).round(),
    255,
  ];
  var count = 0;
  for (var offset = 0; offset < bytes.lengthInBytes; offset += 4) {
    if (bytes.getUint8(offset) == rgba[0] &&
        bytes.getUint8(offset + 1) == rgba[1] &&
        bytes.getUint8(offset + 2) == rgba[2] &&
        bytes.getUint8(offset + 3) == 255) {
      count++;
    }
  }
  return count;
}

void main() {
  test('接续使用稳定标识并与连续滚动分离', () {
    expect(PageTurnMode.fromId('continuation'), PageTurnMode.continuation);
    expect(PageTurnMode.continuation.label, '接续');
    expect(PageTurnMode.continuation, isNot(PageTurnMode.scroll));
  });

  test('正式分页的多段按实际行框独立接力', () {
    final page = Paginator(pageHeight: 400)
        .measureChapter(spineIndex: 0, blocks: _blocks(0, 308))
        .pages
        .single;
    const insets = EdgeInsets.fromLTRB(30, 60, 22, 62);
    final geometry = ContinuationPageGeometry.resolve(
      page,
      _sheet,
      pageInsets: insets,
    );
    expect(geometry.parts, hasLength(6));
    expect(geometry.parts.first.clip.top, 0);
    expect(geometry.parts.last.clip.bottom, _sheet.height);
    expect(geometry.body, const Rect.fromLTWH(30, 60, 308, 398));
    final first = geometry.progressFor(
      geometry.parts.first,
      0.5,
      outgoing: true,
      direction: 1,
    );
    final last = geometry.progressFor(
      geometry.parts.last,
      0.5,
      outgoing: true,
      direction: 1,
    );
    expect(first, greaterThan(last), reason: '上方行先退出，不能退化成整页平移');
    for (final part in geometry.parts) {
      final old = geometry.progressFor(part, 0.5, outgoing: true, direction: 1);
      final next = geometry.progressFor(
        part,
        0.5,
        outgoing: false,
        direction: 1,
      );
      expect(old, greaterThan(next), reason: '同一行旧内容先给新内容让位');
    }
  });

  test('普通段落自动折行与跨页续段都逐行切分', () {
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: 'ABCDEFGHIJKLMNOP ' * 15,
      style: style,
      maxWidth: 308,
    );
    final pages = Paginator(pageHeight: 108)
        .measureChapter(
          spineIndex: 0,
          blocks: [
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: 308,
            ),
          ],
        )
        .pages;
    expect(pages.length, greaterThan(1));
    expect(pages[1].slices.single.startLine, greaterThan(0));
    for (final page in pages) {
      final geometry = ContinuationPageGeometry.resolve(
        page,
        _sheet,
        pageInsets: _padding,
      );
      expect(
        geometry.parts,
        hasLength(page.slices.single.lines.length),
        reason: '只拆分本页实际可见行，段落跨页后仍逐行接续',
      );
      expect(geometry.parts.first.clip.top, 0);
      expect(geometry.parts.last.clip.bottom, _sheet.height);
    }
  });

  test('真实竖排连续列各自接力，共用背景边框则保持完整容器', () {
    final style = ComputedStyle({
      ..._style(vertical: true).values,
      'height': '180px',
    });
    final layout = TextLayoutEngine.layout(
      text: 'ABCDEFGHIJKLMNOP' * 4,
      style: style,
      maxWidth: 308,
    );
    final page = Paginator(pageHeight: 400)
        .measureChapter(
          spineIndex: 0,
          blocks: [
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: 308,
            ),
          ],
        )
        .pages
        .first;
    final columns = ContinuationPageGeometry.resolve(page, _sheet);
    expect(columns.vertical, isTrue);
    expect(columns.parts.length, greaterThan(1), reason: '相接列框不能全部合并');
    final container = PageContainer(
      style: ComputedStyle({
        'background-color': '#dddddd',
        'border': '2px solid #555555',
      }),
      left: 0,
      width: 308,
    );
    final card = Paginator(pageHeight: 400)
        .measureChapter(
          spineIndex: 0,
          blocks: _blocks(0, 308, container: container),
        )
        .pages
        .single;
    expect(
      ContinuationPageGeometry.resolve(card, _sheet).parts,
      hasLength(1),
      reason: '同一个作者卡片的背景与边框不能在段间切开',
    );
  });

  test('文字阴影与整页作者背景沿原快照完整保留', () {
    final style = _style(effect: '12px 16px 8px red');
    final layout = TextLayoutEngine.layout(
      text: 'ABCDEFGHIJKLMNOP',
      style: style,
      maxWidth: 308,
    );
    final page = Paginator(pageHeight: 400)
        .measureChapter(
          spineIndex: 0,
          blocks: [
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: 308,
            ),
            ..._blocks(0, 308),
          ],
        )
        .pages
        .single;
    expect(ContinuationPageGeometry.resolve(page, _sheet).parts, hasLength(1));
    final background = page.withBackground(
      const PageBackground(backgroundColor: Color(0xFFE8D8C8)),
    );
    expect(
      ContinuationPageGeometry.resolve(background, _sheet).parts,
      hasLength(1),
    );
  });

  testWidgets('正式阅读页逐行不透明横移，保留实际内缩、固定纸底和页脚', (tester) async {
    _configure(tester);
    final source = _Source();
    final store = MemoryReaderProgressStore();
    final boundary = GlobalKey();
    await tester.pumpWidget(_reader(source, store, boundary));
    await tester.pumpAndSettle();
    final view = _view(tester);
    final session = view.controller.session;
    expect(view.widget.pageInsets.left, _padding.left);
    expect(view.widget.pageInsets.top, source.topInset);
    final before = await _frame(tester, boundary, name: 'continuation-before');
    _drag(view.controller, 0.45);
    await _until(tester, () => view.controller.phase == PageTurnPhase.dragging);
    await tester.pump(const Duration(milliseconds: 100));
    final image = (await _bytes(tester, view.controller.originImage!));
    expect(_pixel(image, 359, 0).last, 0, reason: '快照省略主题纸底和边角信息');
    final middle = await _frame(tester, boundary, name: 'continuation-middle');
    expect(_solidInk(middle, _oldInk), greaterThan(0));
    expect(_solidInk(middle, _newInk), greaterThan(0));
    final page = session.page!;
    final multiline = page.slices[1];
    var lineTop =
        view.widget.pageInsets.top +
        page.topPadding +
        page.slices.first.height +
        multiline.leadingExtent;
    final rightEdges = <int>[];
    for (final line in multiline.lines) {
      final y = (lineTop + line.height / 2).round();
      var right = -1;
      for (var x = 0; x < _sheet.width; x++) {
        final pixel = _pixel(middle, x, y);
        if (pixel[0] == 0x15 &&
            pixel[1] == 0x5E &&
            pixel[2] == 0x9B &&
            pixel[3] == 255) {
          right = x;
        }
      }
      expect(right, greaterThanOrEqualTo(0));
      rightEdges.add(right);
      lineTop += line.height;
    }
    expect(rightEdges, hasLength(2));
    expect(
      rightEdges.first,
      lessThan(rightEdges.last),
      reason: '同段内上行比下行先移出，不能仍把整个段落一起移动',
    );
    expect(_pixel(middle, 359, 0), _pixel(before, 359, 0));
    for (var y = 480; y < 520; y++) {
      for (var x = 0; x < 360; x++) {
        expect(_pixel(middle, x, y), _pixel(before, x, y), reason: '页脚固定');
      }
    }
    expect(session.page!.spineIndex, 0, reason: '拖动未完成不能提前提交位置');
    view.controller.cancelDrag();
    await tester.pumpAndSettle();
    expect(session.pageTurns, 0);
    final cancelled = await _frame(tester, boundary);
    expect(cancelled.buffer.asUint8List(), before.buffer.asUint8List());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('跨章接续只在620毫秒时钟收尾提交一次并保存文本位置', (tester) async {
    _configure(tester);
    final source = _Source();
    final store = MemoryReaderProgressStore();
    final boundary = GlobalKey();
    await tester.pumpWidget(_reader(source, store, boundary));
    await tester.pumpAndSettle();
    final controller = _view(tester).controller;
    final session = controller.session;
    controller.request(true);
    await _until(tester, () => controller.phase == PageTurnPhase.settling);
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.page!.spineIndex, 0);
    expect(session.pageTurns, 0);
    await tester.pumpAndSettle();
    expect(session.page!.spineIndex, 1);
    expect(session.pageTurns, 1);
    await session.flushProgress();
    final progress = await store.load('接续正式分页回归');
    expect(progress!.spineIndex, 1);
    expect(progress.cfi, startsWith('epubcfi(/6/4!'));
    await _frame(tester, boundary, name: 'continuation-after');
    controller.request(false);
    await tester.pumpAndSettle();
    expect(session.page!.spineIndex, 0);
    expect(session.pageTurns, 2, reason: '反向接续沿原分页与位置提交入口');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('冷章等待不复制原文，目标就绪保持原始墨迹不透明度', (tester) async {
    _configure(tester);
    final gate = Completer<void>();
    final source = _Source(gate: gate);
    final store = MemoryReaderProgressStore();
    final boundary = GlobalKey();
    await tester.pumpWidget(_reader(source, store, boundary));
    await tester.pumpAndSettle();
    final controller = _view(tester).controller;
    final before = await _frame(tester, boundary);
    _drag(controller, 0.5);
    await _until(tester, () => controller.originImage != null);
    expect(controller.phase, PageTurnPhase.preparing);
    final waiting = await _frame(tester, boundary);
    var difference = 0;
    for (var offset = 0; offset < waiting.lengthInBytes; offset++) {
      final channel = (waiting.getUint8(offset) - before.getUint8(offset))
          .abs();
      if (channel > difference) difference = channel;
    }
    // 透明墨迹铺回纸底会有一次整数舍入；重复正文或移动至少会超过此界限。
    expect(difference, lessThanOrEqualTo(2));
    gate.complete();
    await _until(tester, () => controller.phase == PageTurnPhase.dragging);
    expect(controller.targetOpacity, 1, reason: '接续不启动冷目标淡入，不叠加两套正文');
    await tester.pump(const Duration(milliseconds: 80));
    expect(controller.targetOpacity, 1);
    controller.endDrag(DragEndDetails());
    await tester.pumpAndSettle();
    expect(controller.session.page!.spineIndex, 1);
    expect(controller.session.pageTurns, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('活动翻页切换模式取消旧轮，透明与整纸快照不混用', (tester) async {
    _configure(tester);
    final source = _Source();
    final store = MemoryReaderProgressStore();
    final boundary = GlobalKey();
    await tester.pumpWidget(_reader(source, store, boundary));
    await tester.pumpAndSettle();
    final controller = _view(tester).controller;
    _drag(controller, 0.5);
    await _until(tester, () => controller.phase == PageTurnPhase.dragging);
    await tester.pumpWidget(
      _reader(source, store, boundary, mode: PageTurnMode.cover),
    );
    await tester.pumpAndSettle();
    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.page!.spineIndex, 0);
    expect(controller.session.pageTurns, 0);
    controller.request(true);
    await _until(tester, () => controller.originImage != null);
    final opaque = await _bytes(tester, controller.originImage!);
    expect(_pixel(opaque, 359, 0).last, 255);
    await tester.pumpAndSettle();
    await tester.pumpWidget(_reader(source, store, boundary));
    await tester.pumpAndSettle();
    controller.request(false);
    await _until(tester, () => controller.originImage != null);
    final transparent = await _bytes(tester, controller.originImage!);
    expect(_pixel(transparent, 359, 0).last, 0);
    await tester.pumpAndSettle();
    expect(controller.session.page!.spineIndex, 0);
    expect(controller.session.pageTurns, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
