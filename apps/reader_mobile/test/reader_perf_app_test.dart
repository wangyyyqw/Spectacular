import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_ui/a11y/semantics_layer.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../integration_test/reader_perf_app.dart' as perf;

PageContent _page(double size, {int spine = 3, String text = '正文'}) =>
    PageContent(
      spineIndex: spine,
      pageIndex: 0,
      slices: [
        PageBlockSlice(
          block: PageBlock(
            layout: TextLayoutResult(
              text: text,
              lines: const [],
              width: 100,
              height: 30,
              maxWidth: 100,
            ),
            style: ComputedStyle({'font-size': '${size}px'}),
          ),
          startLine: 0,
          endLine: 0,
          height: 30,
        ),
      ],
      usedHeight: 30,
      pageHeight: 600,
      topPadding: 0,
    );

void main() {
  testWidgets('阅读页挂载后立即继续，不等待250ms点击重试', (tester) async {
    var mounted = false;
    var taps = 0;
    var finished = false;
    final task = perf
        .openPerfReader(
          isMounted: () => mounted,
          tap: () {
            taps++;
            Timer(const Duration(milliseconds: 16), () => mounted = true);
          },
        )
        .then((_) => finished = true);
    await tester.pump(const Duration(milliseconds: 24));
    expect(finished, isTrue);
    expect(taps, 1);
    await task;
  });

  testWidgets('防重入点击被忽略时仍按原间隔重试', (tester) async {
    var mounted = false;
    var taps = 0;
    final task = perf.openPerfReader(
      isMounted: () => mounted,
      tap: () {
        if (++taps == 2) mounted = true;
      },
    );
    await tester.pump(const Duration(milliseconds: 240));
    expect(taps, 1);
    await tester.pump(const Duration(milliseconds: 24));
    expect(taps, 2);
    await task;
  });

  testWidgets('宿主路由已挂载后，慢章节准备不会被五秒路由期限误判', (tester) async {
    final source = Completer<EpubChapterSource>();
    final closed = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          sourceFuture: source.future,
          contentRevision: '慢准备验收',
          bookId: '慢准备验收',
          store: MemoryReaderProgressStore(),
          onClosed: closed.complete,
        ),
      ),
    );
    var taps = 0;
    var finished = false;
    Object? failure;
    final task = perf
        .openPerfReader(isMounted: perf.isPerfReaderMounted, tap: () => taps++)
        .then<void>(
          (_) => finished = true,
          onError: (Object error) => failure = error,
        );
    await tester.pump(const Duration(seconds: 6));
    expect(find.byType(ReaderPage), findsNothing, reason: '正文仍在准备，应由原正文等待接管');
    source.completeError(StateError('结束测试准备'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await task;
    await closed.future;
    expect(failure, isNull);
    expect(finished, isTrue);
    expect(taps, 0);
  });

  test('字号确认拒绝空页、旧页、错误章节与仅更新配置', () {
    final previous = _page(21);
    bool ready(PageContent? current, {double applied = 22}) =>
        perf.isRequestedFontPage(
          current: current,
          previous: previous,
          requestedSize: 22,
          appliedSize: applied,
        );
    expect(ready(null), isFalse);
    expect(ready(previous), isFalse);
    expect(ready(_page(21)), isFalse);
    expect(ready(_page(22), applied: 21), isFalse);
    expect(ready(_page(22, spine: 4)), isFalse);
    expect(ready(_page(22, text: '')), isFalse);
    expect(ready(_page(22)), isTrue);
  });

  testWidgets('封面遮挡或正文淡入未完成时，不记录完整显示', (tester) async {
    Widget reader({required bool covered, required double opacity}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: ExcludeSemantics(
            excluding: covered,
            child: FadeTransition(
              opacity: AlwaysStoppedAnimation(opacity),
              child: ReaderSemanticsLayer(page: _page(21), pageWidth: 100),
            ),
          ),
        );
    await tester.pumpWidget(reader(covered: true, opacity: 1));
    expect(perf.isPerfPageFullyVisible(3), isFalse);
    await tester.pumpWidget(reader(covered: false, opacity: 0.5));
    expect(perf.isPerfPageFullyVisible(3), isFalse);
    await tester.pumpWidget(reader(covered: false, opacity: 1));
    expect(perf.isPerfPageFullyVisible(3), isTrue);
    expect(perf.isPerfPageFullyVisible(4), isFalse);
  });
}
