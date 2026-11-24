import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

/// 偏好读取可控延迟，用来验证书架不会先按默认排序显示再改一次。
class _GatedSettingsLibrary extends LibraryStore {
  _GatedSettingsLibrary() : super.memory();

  final Completer<void> preferences = Completer<void>();
  bool gateSettings = false;

  @override
  Future<String?> getSetting(String key) async {
    if (gateSettings) await preferences.future;
    return super.getSetting(key);
  }
}

void main() {
  testWidgets('书架首帧前先读取已保存的排序与置顶', (tester) async {
    final library = _GatedSettingsLibrary();
    await tester.runAsync(() async {
      await library.importBytes(buildTestEpub(title: '甲书'));
      await library.importBytes(buildTestEpub(title: '乙书'));
    });
    library.gateSettings = true;
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.byKey(const ValueKey('book-card-cover')),
      findsNothing,
      reason: '偏好未读完时不应先按默认排序显示书架',
    );

    library.preferences.complete();
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('book-card-cover')), findsNWidgets(2));
  });
}
