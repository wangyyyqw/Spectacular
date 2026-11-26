import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/footnote_dialog.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';
import 'package:reader_core/source/chapter_source.dart';

class _Source implements ReaderChapterSource {
  _Source() {
    pages = <PageContent>[
      _page('第一页', pageIndex: 0),
      _page(
        '1正文中的注号',
        pageIndex: 1,
        footnote: const PageFootnote(
          start: 0,
          end: 1,
          label: '1',
          kind: NoteKind.footnote,
          text: '第一段注释\n第二段注释',
        ),
      ),
    ];
  }

  late final List<PageContent> pages;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => pages;
}

PageContent _page(
  String text, {
  required int pageIndex,
  PageFootnote? footnote,
}) {
  final style = ComputedStyle(const <String, String>{
    'font-size': '16px',
    'line-height': '1.5',
    'font-family': 'Ahem',
  });
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: 240,
  );
  final block = PageBlock(
    layout: layout,
    style: style,
    startCfi: 'epubcfi(/6/4!/4/2/1)',
    footnotes: footnote == null
        ? const <PageFootnote>[]
        : <PageFootnote>[footnote],
  );
  final slice = PageBlockSlice(
    block: block,
    startLine: 0,
    endLine: layout.lineCount,
    height: layout.height,
  );
  return PageContent(
    spineIndex: 0,
    pageIndex: pageIndex,
    slices: <PageBlockSlice>[slice],
    usedHeight: layout.height,
    pageHeight: 400,
    topPadding: 8,
  );
}

void main() {
  testWidgets('点击注号弹出注释正文且不翻页', (tester) async {
    final source = _Source();
    final store = MemoryReaderProgressStore();
    await store.save(
      'footnote',
      const ReaderProgress(spineIndex: 0, pageIndex: 1),
    );
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: store,
            bookId: 'footnote',
            theme: ReaderTheme.black,
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            onSessionReady: (value) => session = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(session.progress?.pageIndex, 1);

    final line = TextHitTester.lineBoxes(source.pages[1]).first;
    await tester.tapAt(
      tester.getTopLeft(find.byType(ReaderView)) +
          Offset(line.rect.left + 2, line.rect.center.dy),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderFootnoteDialog), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('第一段注释')).dy -
          tester.getTopLeft(find.byType(ReaderFootnoteDialog)).dy,
      lessThan(25),
      reason: '注释弹窗不再重复绘制手柄，内容直接开始',
    );
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey<String>('reader-footnote-dialog')),
          )
          .color,
      Colors.transparent,
      reason: '脚注内容透出共用磨砂底板',
    );
    final frosted = find.ancestor(
      of: find.byType(ReaderFootnoteDialog),
      matching: find.byType(ReaderFrostedSurface),
    );
    expect(frosted, findsOneWidget);
    expect(
      Theme.of(tester.element(frosted)).colorScheme.surface.computeLuminance(),
      greaterThan(ReaderTheme.black.background.computeLuminance()),
      reason: '深色阅读主题下脚注底板应比正文背景更浅',
    );
    expect(
      tester.getSize(find.byType(ReaderFootnoteDialog)).height,
      lessThan(400),
      reason: '短注释应贴合内容高度，不能被最大高度撑开',
    );
    expect(find.text('脚注'), findsNothing);
    expect(find.text('1'), findsNothing);
    expect(find.text('第一段注释'), findsOneWidget);
    expect(find.text('第二段注释'), findsOneWidget);
    expect(find.textContaining('正文注释引用'), findsNothing);
    expect(session.progress?.pageIndex, 1);

    Navigator.of(tester.element(find.byType(ReaderFootnoteDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderFootnoteDialog), findsNothing);
    expect(session.progress?.pageIndex, 1);
  });

  testWidgets('气泡长注释滚动后文字仍与边缘保持距离', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ReaderFootnoteDialog(
                style: ReaderFootnoteStyle.bubble,
                anchor: const Offset(180, 300),
                contentWidth: 360,
                footnote: PageFootnote(
                  start: 0,
                  end: 1,
                  label: '1',
                  kind: NoteKind.footnote,
                  text: List.generate(
                    30,
                    (index) => '第 ${index + 1} 段气泡长注释内容。',
                  ).join('\n'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final callout = find.byKey(
      const ValueKey<String>('reader-footnote-callout-bubble'),
    );
    final scroll = find
        .descendant(of: callout, matching: find.byType(SingleChildScrollView))
        .first;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: callout, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(scroll, const Offset(0, -200));
    await tester.pumpAndSettle();

    final rect = tester.getRect(callout);
    final scrollRect = tester.getRect(scroll);
    expect(scrollRect.top - rect.top, greaterThanOrEqualTo(16));
    expect(rect.bottom - scrollRect.bottom, greaterThanOrEqualTo(16));
  });

  testWidgets('注释正文两端对齐', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const ReaderFootnoteDialog(
                footnote: PageFootnote(
                  start: 0,
                  end: 1,
                  label: '1',
                  kind: NoteKind.footnote,
                  text: '第一段注释\n第二段注释',
                ),
              ),
              ReaderFootnoteDialog(
                style: ReaderFootnoteStyle.bubble,
                anchor: const Offset(100, 100),
                contentWidth: 300,
                footnote: const PageFootnote(
                  start: 0,
                  end: 1,
                  label: '2',
                  kind: NoteKind.footnote,
                  text: '气泡注释正文。',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('第一段注释')).textAlign,
      TextAlign.justify,
    );
    expect(
      tester.widget<Text>(find.text('气泡注释正文。')).textAlign,
      TextAlign.justify,
    );
  });

  testWidgets('纸条长注释高度上限为屏幕 15% 且可滚动', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ReaderFootnoteDialog(
                style: ReaderFootnoteStyle.paper,
                anchor: const Offset(180, 560),
                contentWidth: 360,
                footnote: PageFootnote(
                  start: 0,
                  end: 1,
                  label: '1',
                  kind: NoteKind.footnote,
                  text: List.generate(
                    40,
                    (index) => '第 ${index + 1} 段纸条长注释内容。',
                  ).join('\n'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final callout = find.byKey(
      const ValueKey<String>('reader-footnote-callout-paper'),
    );
    final rect = tester.getRect(callout);
    expect(rect.width, closeTo(800 * .85, .01));
    expect(rect.height, closeTo(600 * .15, .01));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: callout, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('空注释显示空态卡片', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReaderFootnoteDialog(
              footnote: PageFootnote(
                start: 0,
                end: 1,
                label: '参见',
                kind: NoteKind.link,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('注释'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('reader-footnote-label')),
      findsNothing,
    );
    expect(find.text('参见'), findsNothing);
    expect(find.text('这条注释暂无内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏长注释限制高度且正文可滚动', (tester) async {
    tester.view.physicalSize = const Size(320, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReaderFootnoteDialog(
              footnote: PageFootnote(
                start: 0,
                end: 1,
                label: '12',
                kind: NoteKind.endnote,
                text: List.generate(
                  24,
                  (index) => '第 ${index + 1} 段长注释内容。',
                ).join('\n'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('尾注'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('reader-footnote-scrollbar')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(ReaderFootnoteDialog)).height,
      lessThanOrEqualTo(360 * 0.40 + 0.01),
      reason: '弹窗最高为屏幕高度的 40%',
    );

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reader-footnote-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const ValueKey<String>('reader-footnote-scroll')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('reader-footnote-scrollbar')),
      findsOneWidget,
    );
  });

  testWidgets('横屏长注释限制高度且正文可滚动', (tester) async {
    tester.view.physicalSize = const Size(640, 284);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReaderFootnoteDialog(
              footnote: PageFootnote(
                start: 0,
                end: 1,
                label: '3',
                kind: NoteKind.footnote,
                text: List.generate(
                  18,
                  (index) => '横屏第 ${index + 1} 段注释内容。',
                ).join('\n'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(ReaderFootnoteDialog)).height,
      lessThanOrEqualTo(284 * 0.40 + 0.01),
      reason: '横屏同样只占屏幕高度的 40%',
    );

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reader-footnote-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('大字体下注释弹窗不溢出且限制高度', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReaderFootnoteDialog(
              footnote: PageFootnote(
                start: 0,
                end: 1,
                label: '125',
                kind: NoteKind.link,
                text: List.generate(
                  12,
                  (index) => '大字体第 ${index + 1} 段注释内容。',
                ).join('\n'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(ReaderFootnoteDialog)).height,
      lessThanOrEqualTo(480 * 0.40 + 0.01),
      reason: '大字体下仍不超过屏幕高度的 40%',
    );
  });
}
