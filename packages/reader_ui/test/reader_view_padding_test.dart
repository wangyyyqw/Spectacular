import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

/// 记录 applyContentSize 的假源（P2-36：全面屏手势区兜底）。
class _SizingSource implements RestylableChapterSource, ResizableChapterSource {
  Size? appliedSize;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    PageContent(
      spineIndex: 0,
      pageIndex: 0,
      slices: <PageBlockSlice>[],
      usedHeight: 0,
      pageHeight: 200,
      topPadding: 0,
    ),
  ];

  @override
  Future<void> applyOverrides(_) async {}

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
  }) async {
    appliedSize = Size(width, height);
    return false;
  }
}

void main() {
  testWidgets('viewPadding.bottom 计入正文区高度，避免压到手势条', (tester) async {
    final source = _SizingSource();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 20)),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: ReaderPage(
                source: source,
                store: MemoryReaderProgressStore(),
                bookId: 'view-padding',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = source.appliedSize;
    expect(size, isNotNull);
    // 页边距 16×2 + 手势条 20 + 页眉页脚槽（设计稿 20+16+14+20=70）。
    expect(
      size!.height,
      closeTo(200 - 16 * 2 - 20 - PageFurniture.reservedHeight, 0.5),
    );
  });
}
