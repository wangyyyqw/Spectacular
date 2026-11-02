import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/footnote_dialog.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

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
      tester.getSize(find.byType(ReaderFootnoteDialog)).height,
      lessThan(400),
      reason: '短注释应贴合内容高度，不能被最大高度撑开',
    );
    expect(find.text('脚注'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('第一段注释'), findsOneWidget);
    expect(find.text('第二段注释'), findsOneWidget);
    expect(find.textContaining('正文注释引用 · 10 字'), findsOneWidget);
    expect(session.progress?.pageIndex, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('reader-footnote-close')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReaderFootnoteDialog), findsNothing);
    expect(session.progress?.pageIndex, 1);
  });

  testWidgets('空注释使用链接类型标题与空态卡片', (tester) async {
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

    expect(find.text('注释'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reader-footnote-label')),
      findsOneWidget,
    );
    expect(find.text('参见'), findsOneWidget);
    expect(find.text('这条注释暂无内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('可复制整条多段注释并显示复制反馈', (tester) async {
    MethodCall? clipboardCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardCall = call;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReaderFootnoteDialog(
              footnote: PageFootnote(
                start: 0,
                end: 1,
                label: '1',
                kind: NoteKind.footnote,
                text: '第一段注释\n第二段注释',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('reader-footnote-copy')),
    );
    await tester.pump();

    expect(clipboardCall?.method, 'Clipboard.setData');
    expect(clipboardCall?.arguments, const <String, Object?>{
      'text': '第一段注释\n第二段注释',
    });
    expect(find.text('已复制'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('复制注释'), findsOneWidget);
  });
}
