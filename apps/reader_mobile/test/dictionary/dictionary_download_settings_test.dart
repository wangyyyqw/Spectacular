import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/dictionary/builtin_dictionaries.dart';
import 'package:reader_mobile/dictionary/dictionary_settings_page.dart';
import 'package:reader_mobile/dictionary/dictionary_store.dart';
import 'package:reader_mobile/dictionary/local_dictionary_download.dart';
import 'package:reader_mobile/dictionary/local_dictionary_store.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/theme/reader_switch.dart';

class _LocalStore extends LocalDictionaryStore {
  _LocalStore(super.library);
  final entries = <LocalDictionaryEntry>[];
  @override
  bool get canImport => true;
  @override
  Future<List<LocalDictionaryEntry>> load() async => List.of(entries);
}

class _Download extends LocalDictionaryDownload {
  final result = Completer<LocalDictionaryEntry>();
  late BuiltInDictionary source;
  late void Function(int) progress;
  late void Function() importing;
  bool cancelled = false;

  @override
  Future<LocalDictionaryEntry> install(
    BuiltInDictionary source,
    LocalDictionaryStore store, {
    required void Function(int received) onProgress,
    required void Function() onImport,
  }) {
    this.source = source;
    progress = onProgress;
    importing = onImport;
    return result.future;
  }

  @override
  void cancel() {
    cancelled = true;
    super.cancel();
    if (!result.isCompleted) {
      result.completeError(const LocalDictionaryDownloadCancelled());
    }
  }
}

Future<void> _open(
  WidgetTester tester,
  _LocalStore locals,
  _Download download,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: DictionarySettingsPage(
          store: DictionaryStore(locals.library, localDictionaries: locals),
          downloadFactory: () => download,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('dictionary-settings-local')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '下载词典').first);
  await tester.pump();
}

void main() {
  testWidgets('下载显示进度与导入状态，成功后显示已启用词典且不再重复下载', (tester) async {
    final locals = _LocalStore(LibraryStore.memory());
    final download = _Download();
    addTearDown(download.cancel);
    await _open(tester, locals, download);
    expect(download.source, builtInDictionaries.first);
    download.progress(download.source.size ~/ 2);
    await tester.pump();
    expect(find.text('正在下载 50%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dictionary-settings-ai')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dictionary-settings-local')));
    await tester.pump();
    expect(find.text('正在下载 50%'), findsOneWidget);
    download.importing();
    await tester.pump();
    expect(find.text('正在导入…'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
          .onPressed,
      isNull,
    );
    final entry = LocalDictionaryEntry(
      id: 'local-downloaded',
      name: '新世纪汉英大词典（单文件版）',
      digest: download.source.digest,
      wordCount: 239685,
    );
    locals.entries.add(entry);
    download.result.complete(entry);
    await tester.pumpAndSettle();
    expect(find.text('新世纪汉英大词典'), findsOneWidget);
    expect(find.textContaining('单文件版'), findsNothing);
    expect(
      find.byKey(const ValueKey('dictionary-download-new-century')),
      findsNothing,
    );
    expect(find.text('下载词典'), findsOneWidget);
    expect(tester.widget<ReaderSwitch>(find.byType(ReaderSwitch)).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('下载失败保留重试入口，取消和关闭页面释放下载', (tester) async {
    final locals = _LocalStore(LibraryStore.memory());
    for (final scenario in ['失败', '取消', '关闭']) {
      final download = _Download();
      await _open(tester, locals, download);
      if (scenario == '失败') {
        download.result.completeError(
          const LocalDictionaryException('下载连接中断，请重试'),
        );
        await tester.pumpAndSettle();
        expect(find.text('下载连接中断，请重试'), findsOneWidget);
        expect(find.text('下载词典'), findsNWidgets(2));
      } else if (scenario == '取消') {
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(download.cancelled, isTrue);
        expect(find.text('下载词典'), findsNWidgets(2));
        expect(find.text('已取消下载'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      if (scenario == '关闭') expect(download.cancelled, isTrue);
      download.cancel();
      expect(locals.entries, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });
}
