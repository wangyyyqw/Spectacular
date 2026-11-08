import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/image_gallery.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_ui/gallery/reader_gallery_controls.dart';
import 'package:reader_ui/image_preview_page.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

PageBlock _imageBlock(int index, String cfi) => PageBlock.styled(
  layout: TextLayoutResult(
    text: '',
    lines: const [
      LineBox(start: 0, end: 0, top: 0, height: 80, baseline: 80, width: 240),
    ],
    width: 240,
    height: 80,
    maxWidth: 240,
  ),
  style: ComputedStyle({
    'width': '240px',
    'margin-left': '20px',
    'background-image': 'url(image://$index)',
  }),
  containingWidth: 300,
  startCfi: cfi,
);

PageBlock _textBlock(
  String text,
  ComputedStyle style,
  String cfi, {
  double width = 300,
}) => PageBlock.styled(
  layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: width),
  style: style,
  containingWidth: 300,
  startCfi: cfi,
);

PageGalleryFrame _frame(int index) {
  final root = 'epubcfi(/6/2!/4/2/${index * 2 + 2})';
  final image = _imageBlock(index, root.replaceFirst(')', '/2)'));
  final caption = _textBlock(
    '主标题 ${index + 1}',
    ComputedStyle({'width': '240px', 'margin-left': '20px'}),
    root.replaceFirst(')', '/4/1:0)'),
    width: 240,
  );
  return PageGalleryFrame(
    cfi: root,
    imageUrl: 'image://$index',
    content: Paginator(pageHeight: 200)
        .measureChapter(blocks: [image, caption])
        .pages
        .single,
  );
}

PageBlock _galleryBlock(PageGallery gallery) => PageBlock.styled(
  layout: TextLayoutResult(
    text: '',
    lines: [
      LineBox(
        start: 0,
        end: 0,
        top: 0,
        height: gallery.height,
        baseline: gallery.height,
        width: 240,
      ),
    ],
    width: 240,
    height: gallery.height,
    maxWidth: 240,
  ),
  style: ComputedStyle({'width': '240px', 'margin-left': '20px'}),
  containingWidth: 300,
  spaceBefore: 40,
  startCfi: 'epubcfi(/6/2!/4/2)',
  gallery: gallery,
);

PageContent _galleryPage() {
  final frames = List.generate(3, _frame);
  final gallery = PageGallery(
    cfi: 'epubcfi(/6/2!/4/2)',
    frames: frames,
    left: 20,
    width: 240,
    height: frames.first.content.usedHeight + PageGallery.indicatorHeight,
    indicatorExtent: PageGallery.indicatorHeight,
  );
  return Paginator(pageHeight: 500)
      .measureChapter(blocks: [_galleryBlock(gallery)])
      .pages
      .single;
}

PageContent _nextPage() {
  final style = ComputedStyle({'font-size': '16px'});
  final page = Paginator(pageHeight: 500)
      .measureChapter(
        blocks: [_textBlock('下一页正文', style, 'epubcfi(/6/2!/4/4/1:0)')],
      )
      .pages
      .single;
  return PageContent(
    spineIndex: 0,
    pageIndex: 1,
    slices: page.slices,
    usedHeight: page.usedHeight,
    pageHeight: page.pageHeight,
    topPadding: 0,
  );
}

class _Source implements ReaderChapterSource {
  final pages = [_galleryPage(), _nextPage()];
  int loads = 0;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads++;
    return pages;
  }
}

Future<ReaderSession> _show(
  WidgetTester tester,
  _Source source, {
  PageTurnMode mode = PageTurnMode.none,
  DecodedImageCache? cache,
}) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderPage(
        source: source,
        store: MemoryReaderProgressStore(),
        bookId: '画廊测试',
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
        showPageFooter: false,
        pageTurnMode: mode,
        imageCache: cache,
        onSessionReady: (value) => session = value,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> _swipe(WidgetTester tester, double dx) async {
  await tester.fling(
    find.byType(ReaderGalleryControls).first,
    Offset(dx, 0),
    1200,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('画廊内左右滑动与边界手势只切帧，不翻正文页或重新加载章节', (tester) async {
    final source = _Source();
    final session = await _show(tester, source);
    final loads = source.loads;
    final cfi = session.currentCfi;
    expect(find.text('1 / 3'), findsOneWidget);
    await _swipe(tester, -200);
    expect(find.text('2 / 3'), findsOneWidget);
    await _swipe(tester, -200);
    await _swipe(tester, -200);
    expect(find.text('3 / 3'), findsOneWidget);
    await _swipe(tester, 200);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(session.page!.pageIndex, 0);
    expect(session.currentCfi, cfi);
    expect(source.loads, loads);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开启翻页动画时图内手势仍切帧，图外手势继续翻正文页', (tester) async {
    final session = await _show(tester, _Source(), mode: PageTurnMode.cover);
    await _swipe(tester, -200);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(session.page!.pageIndex, 0);
    final origin = tester.getTopLeft(find.byType(ReaderView));
    await tester.flingFrom(
      origin + const Offset(650, 400),
      const Offset(-350, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(session.page!.pageIndex, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('连续滚动模式可在图内横滑切帧，正文视口位置保持不变', (tester) async {
    final session = await _show(tester, _Source(), mode: PageTurnMode.scroll);
    final page = session.page!.pageIndex;
    await _swipe(tester, -200);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(session.page!.pageIndex, page);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('跳到未显示帧的题注 CFI 时仍定位到画廊页并显示对应分帧', (tester) async {
    final session = await _show(tester, _Source());
    const target = 'epubcfi(/6/2!/4/2/6/4/1:0)';
    final revision = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .revision;
    expect(await session.jumpToCfi(target), isTrue);
    await tester.pumpAndSettle();
    expect(session.page!.pageIndex, 0);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(session.readingCfi, target);
    expect(
      tester.widget<PageTurnView>(find.byType(PageTurnView)).revision,
      isNot(revision),
      reason: '同页跳转也使纸面及翻页快照失效',
    );
    await _swipe(tester, 200);
    expect(find.text('2 / 3'), findsOneWidget);
    await session.jumpToCfi(target);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('键盘可切帧，语义题注随当前画面更新', (tester) async {
    final session = await _show(tester, _Source());
    final semantics = tester.ensureSemantics();
    Focus.of(tester.element(find.text('1 / 3'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.bySemanticsLabel('图片画廊\n主标题 2'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('图片画廊\n主标题 2'));
    expect(node.value, '第 2 幅，共 3 幅');
    expect(node.increasedValue, '第 3 幅，共 3 幅');
    expect(node.decreasedValue, '第 1 幅，共 3 幅');
    expect(session.page!.pageIndex, 0);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('预取仅覆盖当前与相邻帧，边缘点按预览当前主图且不触发正文翻页', (tester) async {
    final requested = <String>[];
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        requested.add(url);
        return null;
      },
    );
    addTearDown(cache.clear);
    final session = await _show(tester, _Source(), cache: cache);
    expect(requested, containsAll(['image://0', 'image://1']));
    expect(requested, isNot(contains('image://2')));
    await _swipe(tester, -200);
    expect(requested, contains('image://2'));
    final origin = tester.getTopLeft(find.byType(ReaderGalleryControls));
    await tester.tapAt(origin + const Offset(10, 30));
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewPage), findsOneWidget);
    expect(requested.last, 'image://1');
    expect(find.text('图片无法加载'), findsOneWidget);
    expect(session.page!.pageIndex, 0);
    await tester.tap(find.byKey(const ValueKey('preview-close')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('空画廊载荷不创建无效序号或可调节语义', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderGalleryControls(
          gallery: PageGallery(
            cfi: 'epubcfi(/6/2!/4/2)',
            frames: const [],
            left: 0,
            width: 240,
            height: 100,
          ),
          index: 0,
          foreground: Colors.black,
          onChanged: (_) => fail('空画廊不应切帧'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('图片画廊'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
