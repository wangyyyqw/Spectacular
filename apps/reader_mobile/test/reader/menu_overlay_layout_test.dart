import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/test_epub.dart';

void main() {
  testWidgets('菜单与抽屉开关是浮层：排版指纹不变（不重排）', (tester) async {
    final bytes = buildTestEpub(
      title: '浮层菜单',
      paragraphs: const <String>['第一段内容足够长以便分页显示多行。', '第二段内容。'],
    );
    final source = await openTestChapterSource(bytes);
    late ReaderSession session;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 520,
              child: ReaderPage(
                source: source,
                store: MemoryReaderProgressStore(),
                bookId: 'overlay-menu',
                onSessionReady: (value) => session = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fingerprint = session.layoutFingerprint;
    final pageBefore = session.page;

    // 打开菜单。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(session.layoutFingerprint, fingerprint, reason: '开菜单不重排');
    expect(session.page, same(pageBefore), reason: '页码与内容不变');

    // 打开主题抽屉（浮层叠加）。
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-theme')));
    await tester.pumpAndSettle();
    expect(session.layoutFingerprint, fingerprint, reason: '开抽屉不重排');

    // 关闭抽屉 → 关闭菜单。
    await tester.tap(find.byKey(const ValueKey<String>('menu-drawer-close')));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(session.layoutFingerprint, fingerprint, reason: '收菜单不重排');
  });
}
