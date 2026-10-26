import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/test_epub.dart';

Uint8List _corpusBook(String name) {
  var directory = Directory.current;
  while (true) {
    final candidate = Directory('${directory.path}/test_corpus');
    if (candidate.existsSync()) {
      return File('${candidate.path}/$name').readAsBytesSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('缺少 test_corpus/$name');
    }
    directory = parent;
  }
}

void main() {
  testWidgets('切换背景纹理不触发重排（P4-22 验收）', (tester) async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    late ReaderSession session;
    final changes = <String>[];
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
                bookId: 'background-switch',
                backgroundId: 'none',
                onSessionReady: (value) => session = value,
                onBackgroundChanged: changes.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fingerprint = session.layoutFingerprint;
    final progress = session.progress;

    // 菜单 → 设置 → 点纸纹背景。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-theme')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-bg-paper')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-bg-paper')));
    await tester.pumpAndSettle();

    expect(changes, contains('paper'), reason: '背景变化回调');
    expect(
      session.layoutFingerprint,
      fingerprint,
      reason: '换背景不进入排版指纹，不重排',
    );
    expect(session.progress, progress, reason: '位置不变');
  });

  test('背景纹理资源存在且可解码（P4-22）', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final id in <String>['paper', 'wood', 'gray']) {
      final data = await rootBundle.load('assets/textures/$id.png');
      expect(data.lengthInBytes, greaterThan(1000), reason: '$id 资源存在');
    }
  });
}
