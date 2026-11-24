import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/txt.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/txt/txt_chapter_rule_page.dart';
import 'package:reader_mobile/txt/txt_encoding_dialog.dart';
import 'package:reader_mobile/txt/txt_rule_store.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../support/reader_pump.dart';

Future<void> _finishWork(WidgetTester tester) async {
  var idleFrames = 0;
  for (var frame = 0; frame < 60; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      if (++idleFrames >= 10) return;
    } else {
      idleFrames = 0;
    }
  }
  fail('章节页面后台任务未在限定时间内完成');
}

Future<void> _selectMode(WidgetTester tester, String mode) async {
  await tester.tap(find.byType(ReaderDropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode).last);
  await tester.pumpAndSettle();
}

void main() {
  late Directory temporary;
  late AppDatabase database;
  late LibraryStore library;
  late BookEntry entry;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('txt-rule-ui-');
    database = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(
      database: database,
      directoryProvider: () async => temporary,
    );
    final converted = File('${temporary.path}/input.epub');
    await TxtEpubConverter.convertBytes(
      Uint8List.fromList(
        utf8.encode(
          '第一章 初见\n这是第一章的正文，保留它来验证预览和合章不会改变内容。\n第二章 重逢\n这是第二章的正文，保存之后仍然可以正确阅读。',
        ),
      ),
      converted,
      title: '章节规则测试',
    );
    entry = await library.importFile(converted.path);
  });

  tearDown(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  Future<void> showPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TxtChapterRulePage(entry: entry, library: library),
      ),
    );
    await _finishWork(tester);
  }

  testWidgets('真实 EPUB 预览后才能应用，修改规则使预览失效，零匹配不改书', (tester) async {
    await showPage(tester);
    FilledButton apply() =>
        tester.widget(find.byKey(const ValueKey('txt-apply')));
    expect(apply().onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('txt-preview')));
    await _finishWork(tester);
    expect(
      find.textContaining('目录预览 · 2 项'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join('\n'),
    );
    expect(apply().onPressed, isNotNull);

    await _selectMode(tester, '自定义正则');
    expect(apply().onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('txt-chapter-pattern')),
      '^不存在的标题\$',
    );
    await tester.tap(find.byKey(const ValueKey('txt-preview')));
    await _finishWork(tester);
    expect(find.textContaining('没有匹配到章节'), findsOneWidget);
    expect(apply().onPressed, isNull);
    expect(
      (await library.bookById(entry.id))!.contentRevision,
      entry.contentRevision,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('自定义规则预览并应用到当前 EPUB，返回成功且保持书籍身份', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        TxtChapterRulePage(entry: entry, library: library),
                  ),
                );
              },
              child: const Text('打开规则'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开规则'));
    await _finishWork(tester);
    await _selectMode(tester, '自定义正则');
    await tester.enterText(
      find.byKey(const ValueKey('txt-chapter-pattern')),
      r'^第一章.*$',
    );
    await tester.tap(find.byKey(const ValueKey('txt-preview')));
    await _finishWork(tester);
    expect(find.textContaining('目录预览 · 1 项'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('txt-apply')));
    await _finishWork(tester);
    expect(result, isTrue);
    final updated = await library.bookById(entry.id);
    expect(updated!.id, entry.id);
    expect(updated.spineCount, 1);
    expect(updated.contentRevision, isNot(entry.contentRevision));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('另存个人规则默认不自动启用，也不会提交书籍', (tester) async {
    await showPage(tester);
    await _selectMode(tester, '自定义正则');
    await tester.enterText(
      find.byKey(const ValueKey('txt-chapter-pattern')),
      r'^第.+章.*$',
    );
    await tester.ensureVisible(find.text('另存为我的规则'));
    await tester.tap(find.text('另存为我的规则'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSheetForm), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '规则名称'), '我的章标题');
    await tester.tap(find.text('保存规则'));
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(ReaderSheetForm).evaluate().isEmpty,
      description: 'TXT 规则另存抽屉退场',
    );
    await _finishWork(tester);
    final rules = await TxtRuleStore(library).load();
    expect(find.byType(ReaderSheetForm), findsNothing);
    expect(find.byType(TxtChapterRulePage), findsOneWidget);
    expect(rules.single.name, '我的章标题');
    expect(rules.single.autoEnabled, isFalse);
    expect(
      (await library.bookById(entry.id))!.contentRevision,
      entry.contentRevision,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('个人规则管理抽屉保存自动识别开关，关闭后回到原章节页', (tester) async {
    final store = TxtRuleStore(library);
    await store.save(
      const ChapterRule(
        id: 'user-manager',
        name: '我的章节',
        pattern: r'^第.+章.*$',
        autoEnabled: false,
      ),
    );
    await showPage(tester);
    await tester.ensureVisible(find.text('管理我的规则'));
    await tester.tap(find.text('管理我的规则'));
    await _finishWork(tester);
    expect(find.byType(ReaderSheetForm), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('我的章节'), findsOneWidget);
    expect(
      tester
          .widget<AppIcon>(
            find.descendant(
              of: find.byTooltip('删除规则'),
              matching: find.byType(AppIcon),
            ),
          )
          .glyph,
      AppGlyph.delete,
    );
    await tester.tap(find.byType(ReaderSwitch));
    await _finishWork(tester);
    expect((await store.load()).single.autoEnabled, isTrue);
    await tester.tap(find.byTooltip('关闭'));
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(ReaderSheetForm).evaluate().isEmpty,
      description: 'TXT 规则管理抽屉退场',
    );
    await _finishWork(tester);
    expect(find.byType(ReaderSheetForm), findsNothing);
    expect(find.byType(TxtChapterRulePage), findsOneWidget);
    expect(
      (await library.bookById(entry.id))!.contentRevision,
      entry.contentRevision,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('编码选择展示实际样例并返回所选编码', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await chooseTxtEncoding(context, const [
                TxtEncodingCandidate(name: 'GBK', sample: '简体正文样例'),
                TxtEncodingCandidate(name: 'Big5', sample: '繁體正文樣例'),
              ]);
            },
            child: const Text('选择编码'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择编码'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSheetForm), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('简体正文样例'), findsOneWidget);
    await tester.tap(find.byType(ReaderDropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Big5').last);
    await tester.pumpAndSettle();
    expect(find.text('繁體正文樣例'), findsOneWidget);
    await tester.tap(find.text('继续导入'));
    await tester.pumpAndSettle();
    expect(selected, 'Big5');
    expect(find.byType(ReaderSheetForm), findsNothing);
    await tester.tap(find.text('选择编码'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.byType(ReaderSheetForm), findsNothing);
    expect(find.text('选择编码'), findsOneWidget);
  });
}
