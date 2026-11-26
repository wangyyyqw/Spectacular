import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/page_furniture/battery_icon.dart';
import 'package:reader_ui/page_furniture/corner_info.dart';
import 'package:reader_ui/page_furniture/corner_row.dart';
import 'package:reader_ui/panels/corner_info_editor.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

void main() {
  test('四角偏好按项读取，未知类型回到对应默认值', () {
    final info = ReaderCornerInfo.fromJson({
      'topLeft': 'bookTitle',
      'topRight': 'invalid',
      'bottomLeft': 'none',
      'bottomRight': 'battery',
    });
    expect(info.topLeft, ReaderCornerContent.bookTitle);
    expect(info.topRight, ReaderCornerContent.chapterPage);
    expect(info.bottomLeft, ReaderCornerContent.none);
    expect(info.bottomRight, ReaderCornerContent.battery);
    expect(ReaderCornerInfo.fromJson(info.toJson()), info);
    expect(
      info
          .withContent(ReaderCornerSlot.topRight, ReaderCornerContent.none)
          .hasHeader,
      isTrue,
    );
  });

  testWidgets('边角设置先预览，保存后一次提交，重新打开保留设置，返回放弃修改', (tester) async {
    var info = ReaderCornerInfo.defaults;
    final changes = <ReaderCornerInfo>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, update) => SettingsPanel(
              section: SettingsSection.settings,
              overrides: ReaderSettingsDefaults.overrides,
              themeId: 'white',
              onOverridesChanged: (_) {},
              onThemeChanged: (_) {},
              cornerInfo: info,
              onCornerInfoChanged: (value) {
                changes.add(value);
                update(() => info = value);
              },
            ),
          ),
        ),
      ),
    );
    final entry = find.byKey(const ValueKey('settings-corner-info'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('corner-choice-bookTitle')));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('corner-preview-topLeft')))
          .data,
      '书名',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('corner-preview-bottomLeft')))
          .data,
      '时间与电量',
    );
    const selections = {
      'topRight': ReaderCornerContent.none,
      'bottomLeft': ReaderCornerContent.clock,
      'bottomRight': ReaderCornerContent.battery,
    };
    for (final selection in selections.entries) {
      await tester.tap(find.byKey(ValueKey('corner-${selection.key}-tab')));
      await tester.pumpAndSettle();
      final choice = find.byKey(
        ValueKey('corner-choice-${selection.value.name}'),
      );
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }
    expect(changes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('corner-settings-save')));
    await tester.pumpAndSettle();
    expect(changes, hasLength(1));
    expect(info.topLeft, ReaderCornerContent.bookTitle);
    expect(info.topRight, ReaderCornerContent.none);
    expect(info.bottomLeft, ReaderCornerContent.clock);
    expect(info.bottomRight, ReaderCornerContent.battery);
    expect(find.byType(CornerInfoEditor), findsNothing);
    expect(find.textContaining('左上 书名 · 右上 隐藏'), findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('corner-choice-bookTitle')),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('corner-choice-none')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(changes, hasLength(1));
    expect(info.topLeft, ReaderCornerContent.bookTitle);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('corner-choice-bookTitle')),
          )
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('边角设置在 $brightness 窄屏大字号下共用分区布局，滚动不移动保存按钮', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: applyReaderUiStyle(ThemeData(brightness: brightness)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const Scaffold(
            body: CornerInfoEditor(info: ReaderCornerInfo.defaults),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tabs = find.byKey(const ValueKey('corner-settings-section-tabs'));
      final preview = find.byKey(const ValueKey('corner-settings-preview'));
      final save = find.byKey(const ValueKey('corner-settings-save'));
      final frame = find.byKey(const ValueKey('corner-settings-fixed-height'));
      expect(
        tester.getTopLeft(tabs).dy - tester.getBottomLeft(preview).dy,
        closeTo(8, .1),
      );
      final footerRect = tester.getRect(save);
      final height = tester.getSize(frame).height;
      for (final slot in ReaderCornerSlot.values) {
        await tester.tap(find.byKey(ValueKey('corner-${slot.name}-tab')));
        await tester.pumpAndSettle();
        for (final content in ReaderCornerContent.values) {
          final chip = tester.widget<ChoiceChip>(
            find.byKey(ValueKey('corner-choice-${content.name}')),
          );
          expect(
            chip.selected,
            ReaderCornerInfo.defaults.contentAt(slot) == content,
          );
        }
        final choice = find.byKey(
          const ValueKey('corner-choice-clockAndBattery'),
        );
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        expect(choice.hitTestable(), findsOneWidget);
        expect(tester.getRect(save), footerRect);
        expect(tester.getSize(frame).height, height);
        expect(save.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('未提供边角回调时不打开编辑面板', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.settings,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
          ),
        ),
      ),
    );
    final entry = find.byKey(const ValueKey('settings-corner-info'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(CornerInfoEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('阅读信息显示真实电量与本页数据，隐藏项没有占位文字', (tester) async {
    const channel = MethodChannel('com.spectacular.reader_mobile/reader');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => {'level': 73, 'charging': false},
    );
    const events = EventChannel('com.spectacular.reader_mobile/battery');
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        events,
        null,
      ),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderCornerRow(
            left: ReaderCornerContent.bookTitle,
            right: ReaderCornerContent.battery,
            now: DateTime(2026, 11, 12, 9, 8),
            data: const ReaderCornerData(
              bookTitle: '测试书',
              pageLabel: '2/10',
              progress: .125,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试书'), findsOneWidget);
    expect(find.text('73%'), findsNothing);
    expect(
      tester.widget<ReaderBatteryIcon>(find.byType(ReaderBatteryIcon)).level,
      73,
    );
    expect(
      tester.widget<ReaderBatteryIcon>(find.byType(ReaderBatteryIcon)).charging,
      isFalse,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReaderCornerRow(
            left: ReaderCornerContent.none,
            right: ReaderCornerContent.progress,
            data: ReaderCornerData(progress: .125),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('12.50%'), findsOneWidget);
    expect(find.text('测试书'), findsNothing);
  });
}
