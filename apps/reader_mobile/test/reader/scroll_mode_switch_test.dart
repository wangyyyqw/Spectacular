import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/paging/continuous_scroll_view.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/theme/reader_margins.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  for (final targetPage in [0, 4]) {
    testWidgets('EPUB 章首和章中切换滚动模式保留原位置：第 $targetPage 页', (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 853));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // 可选原书仅用于本地复现；默认样本经正式 EPUB 入口生成不同高度的切片。
      final path = Platform.environment['SCROLL_SWITCH_EPUB'];
      final bytes = path == null
          ? buildMultiChapterEpub(
              rawBody: true,
              chapters: [
                for (var chapter = 0; chapter < 6; chapter++)
                  [
                    for (var block = 0; block < 35; block++)
                      '<p style="margin-bottom:${8 + block % 5 * 11}px">'
                          '${'第 $chapter 章第 $block 段，切换模式应保留本段位置。' * (8 + block % 12)}</p>',
                  ].join(),
              ],
            )
          : File(path).readAsBytesSync();
      final targetSpine = int.parse(
        Platform.environment['SCROLL_SWITCH_SPINE'] ?? '4',
      );
      final source = await openTestChapterSource(bytes);
      final store = MemoryReaderProgressStore();
      late ReaderSession session;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderPage(
              source: source,
              store: store,
              bookId: 'scroll-mode-$targetPage',
              pageTurnMode: PageTurnMode.cover,
              overrides: const ReaderOverrides(
                fontSize: 18,
                lineHeight: 1.6,
                paragraphSpacing: 10,
              ),
              margins: const ReaderMargins(
                left: 9,
                right: 9,
                topOuter: 36,
                topInner: 0,
                bottomInner: 0,
                bottomOuter: 10,
              ),
              onSessionReady: (value) => session = value,
            ),
          ),
        ),
      );
      await pumpReaderUntilComplete(
        tester,
        () => !session.loading && session.hasContent,
      );
      await pumpReaderTask(tester, session.jumpToChapter(targetSpine));
      for (var i = 0; i < targetPage; i++) {
        await pumpReaderTask(tester, session.next());
      }
      final anchor = session.currentCfi;
      final originalPage = session.progress!.pageIndex;
      expect(session.progress!.spineIndex, targetSpine);
      expect(anchor, isNotNull);
      await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-entry-settings')));
      await tester.pumpAndSettle();
      final scrollOption = find.byKey(
        const ValueKey('settings-page-turn-scroll'),
      );
      await tester.ensureVisible(scrollOption);
      await tester.tap(scrollOption);
      await pumpReaderUntil(
        tester,
        find.byKey(const ValueKey('continuous-scroll')),
      );
      // 邻章预取与逐帧偏移校正完成后，同时检查真实视口和会话锚点。
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      final scroll = tester.state<ContinuousScrollViewState>(
        find.byType(ContinuousScrollView),
      );
      final visible = scroll.pageAt(const Offset(100, 1));
      expect(visible?.page.spineIndex, targetSpine);
      expect(visible?.page.pageIndex, originalPage);
      expect(session.currentCfi, anchor);
      final coverOption = find.byKey(
        const ValueKey('settings-page-turn-cover'),
      );
      await tester.ensureVisible(coverOption);
      await tester.tap(coverOption);
      await tester.pumpAndSettle();
      expect(session.progress?.spineIndex, targetSpine);
      expect(session.progress?.pageIndex, originalPage);
      expect(session.currentCfi, anchor);
      await tester.pumpWidget(const SizedBox.shrink());
      source.close();
    });
  }
}
