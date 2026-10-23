import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_mobile/reader/demo_source.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import 'm0_snapshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('M0 打开/翻页/切章/返回', (tester) async {
    ReaderSession? session;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 480,
              child: ReaderPage(
                source: DemoChapterSource(),
                store: MemoryReaderProgressStore(),
                bookId: 'm0-smoke',
                onSessionReady: (value) => session = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(session, isNotNull);
    expect(
      session!.progress,
      const ReaderProgress(spineIndex: 0, pageIndex: 0),
    );
    expect(find.byType(CustomPaint), findsWidgets);

    // 点击右区翻页。
    final origin = tester.getTopLeft(find.byType(ReaderPage));
    await tester.tapAt(origin + const Offset(280, 240));
    await tester.pumpAndSettle();
    expect(
      session!.progress,
      const ReaderProgress(spineIndex: 0, pageIndex: 1),
    );

    // 切到下一章（绕过手势直接驱动会话，覆盖章节切换）。
    while (session!.progress!.spineIndex == 0) {
      expect(await session!.next(), isTrue);
    }
    await tester.pump();
    expect(session!.progress!.spineIndex, 1);
    expect(session!.page, isNotNull);

    // 返回第一章第一页。
    while (await session!.previous()) {}
    await tester.pump();
    expect(
      session!.progress,
      const ReaderProgress(spineIndex: 0, pageIndex: 0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('首版页序列快照 hash 与基线一致', (tester) async {
    final snapshot = await buildM0Snapshot();
    final baselineText = await rootBundle.loadString(
      'integration_test/m0_page_sequence.json',
    );
    final baseline = jsonDecode(baselineText) as Map<String, dynamic>;
    expect(snapshot.pages, hasLength(baseline['pageCount'] as int));
    expect(snapshot.hash, baseline['hash']);
  });
}
