import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/dictionary/dictionary_rule.dart';
import 'package:reader_mobile/dictionary/dictionary_rule_client.dart';
import 'package:reader_mobile/dictionary/dictionary_settings_page.dart';
import 'package:reader_mobile/dictionary/dictionary_sheet.dart';
import 'package:reader_mobile/dictionary/dictionary_store.dart';
import 'package:reader_mobile/dictionary/local_dictionary_store.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

const _first = LocalDictionaryEntry(
  id: 'local-first',
  name: '新世纪汉英大词典（单文件版）',
  digest: 'first',
  wordCount: 10,
);
const _second = LocalDictionaryEntry(
  id: 'local-second',
  name: '大辞海（单文件版）',
  digest: 'second',
  wordCount: 20,
);

class _LocalStore extends LocalDictionaryStore {
  _LocalStore(super.library);
  @override
  Future<LocalDictionarySession> open(LocalDictionaryEntry entry) async =>
      _Session(entry);
}

class _Session extends LocalDictionarySession {
  _Session(LocalDictionaryEntry entry) : super(entry, Directory('unused'));
  @override
  Future<String?> lookup(String text) async => null;
  @override
  List<String> suggest(String text) => [];
  @override
  Future<void> close() async {}
}

Future<void> _openSettings(WidgetTester tester, DictionaryStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => DictionarySettingsPage(store: store),
            )),
            child: const Text('打开词典设置'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开词典设置'));
  await tester.pumpAndSettle();
}

Future<void> _dragFirstBelowSecond(
  WidgetTester tester,
  String first,
  String second,
) async {
  final handle = find.byKey(ValueKey('dictionary-drag-$first'));
  final secondHandle = find.byKey(ValueKey('dictionary-drag-$second'));
  final start = tester.getCenter(handle);
  final end = tester.getCenter(secondHandle) + const Offset(0, 15);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 100));
  for (var step = 1; step <= 5; step++) {
    await gesture.moveTo(Offset.lerp(start, end, step / 5)!);
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 350));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final local in [true, false]) {
    testWidgets('${local ? '本地' : '在线'}拖动排序取消不保存，保存后列表与查词来源顺序一致', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final library = LibraryStore.memory();
      await library.setSetting(
        LocalDictionaryStore.settingKey,
        jsonEncode([_first.toJson(), _second.toJson()]),
      );
      final store = DictionaryStore(
        library,
        localDictionaries: _LocalStore(library),
      );
      final firstId = local ? _first.id : dictionaryBuiltInRules[0].id;
      final secondId = local ? _second.id : dictionaryBuiltInRules[1].id;
      await _openSettings(tester, store);
      await tester.tap(
        find.byKey(
          ValueKey('dictionary-settings-${local ? 'local' : 'online'}'),
        ),
      );
      await tester.pumpAndSettle();
      if (local) expect(find.textContaining('单文件版'), findsNothing);
      final sort = find.byKey(
        ValueKey('dictionary-${local ? 'local' : 'online'}-sort'),
      );
      await tester.tap(sort);
      await tester.pumpAndSettle();
      await _dragFirstBelowSecond(tester, firstId, secondId);
      expect(
        tester
            .getTopLeft(find.byKey(ValueKey('dictionary-order-$secondId')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(ValueKey('dictionary-order-$firstId')))
              .dy,
        ),
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        local
            ? (await store.locals.load()).first.id
            : (await store.load()).rules.first.id,
        firstId,
      );
      await tester.tap(sort);
      await tester.pumpAndSettle();
      await _dragFirstBelowSecond(tester, firstId, secondId);
      await tester.tap(find.byKey(const ValueKey('dictionary-order-save')));
      await tester.pumpAndSettle();
      expect(
        local
            ? (await store.locals.load()).first.id
            : (await store.load()).rules.first.id,
        secondId,
      );
      await tester.tap(sort);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<ListTile>(
              find.descendant(
                of: find.byType(ReorderableListView),
                matching: find.byType(ListTile),
              ),
            )
            .first
            .key,
        ValueKey('dictionary-order-$secondId'),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DictionarySheet(
              store: store,
              text: '测试',
              ruleClientFactory: () => DictionaryRuleClient(
                client: MockClient((_) async => http.Response('暂时不可用', 503)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (!local) {
        await tester.tap(find.byKey(const ValueKey('dictionary-web')));
        await tester.pumpAndSettle();
      }
      final labels = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((chip) => (chip.label as Text).data);
      expect(labels.take(2), local ? ['大辞海', '新世纪汉英大词典'] : ['汉典', '海词中文']);
      expect(find.textContaining('单文件版'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
