import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

/// 记录 applyContentSize 的假源（P2-36：全面屏手势区兜底）。
class _SizingSource implements RestylableChapterSource, ResizableChapterSource {
  Size? appliedSize;
  double? appliedTopInset;

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
    double topInset = 0,
    ContentSideInsets? sideInsets,
  }) async {
    appliedSize = Size(width, height);
    appliedTopInset = topInset;
    return false;
  }
}

void main() {
  testWidgets('状态栏与手势条安全区都计入正文区高度', (tester) async {
    final source = _SizingSource();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          viewPadding: EdgeInsets.only(top: 44, bottom: 20),
        ),
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
    // 页边距 16×2 + 安全区（状态栏 44 + 手势条 20）+ 页眉页脚槽 70。
    expect(
      size!.height,
      closeTo(200 - 16 * 2 - 44 - 20 - PageFurniture.reservedHeight, 0.5),
    );
    expect(
      source.appliedTopInset,
      16 + 44 + PageFurniture.headerHeight + PageFurniture.headerGap,
    );
  });
}
