import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/selection/selection_layer.dart';

import '../support/reader_pump.dart';
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

Future<void> _pumpReader(WidgetTester tester, EpubChapterSource source) async {
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
              bookId: 'selection-menu',
            ),
          ),
        ),
      ),
    ),
  );
  await pumpReaderUntil(tester, find.byType(ReaderView));
}

void main() {
  setUp(() {
    // 剪贴板走测试 mock，避免 platform channel 未实现。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('长按出现选区与菜单，点复制后清除（P4-16）', (tester) async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    await _pumpReader(tester, source);

    await tester.longPressAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('selection-menu')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-copy')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing, reason: '复制后清除选区');
    expect(find.text('已复制'), findsOneWidget);
  });

  testWidgets('菜单里全选覆盖整页，取消清除选区（P4-16）', (tester) async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    await _pumpReader(tester, source);

    await tester.longPressAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    final before = tester.widget<SelectionLayer>(find.byType(SelectionLayer));

    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-more')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-select-all')),
    );
    await tester.pumpAndSettle();
    final after = tester.widget<SelectionLayer>(find.byType(SelectionLayer));
    expect(after.selection.start.charOffset, 0);
    expect(
      after.selection.end.textOffset,
      greaterThanOrEqualTo(before.selection.end.textOffset),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-dismiss')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing);
  });

  testWidgets('双击选词、三击选句（P4-16）', (tester) async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    await _pumpReader(tester, source);

    final center = tester.getCenter(find.byType(ReaderView));
    // 先长按建立选区（之后才启用双击/三击识别，避免单击翻页被延迟）。
    await tester.longPressAt(center);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsOneWidget);

    // 双击 → 选词。
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsOneWidget);
    final word = tester.widget<SelectionLayer>(find.byType(SelectionLayer));

    // 三击 → 选句：范围不小于选词。
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsOneWidget);
    final sentence = tester.widget<SelectionLayer>(find.byType(SelectionLayer));
    expect(
      sentence.selection.end.textOffset - sentence.selection.start.textOffset,
      greaterThanOrEqualTo(
        word.selection.end.textOffset - word.selection.start.textOffset,
      ),
      reason: '选句范围应覆盖选词',
    );
  });
}
