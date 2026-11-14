import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/page_furniture/battery_icon.dart';
import 'package:reader_ui/page_furniture/corner_info.dart';
import 'package:reader_ui/page_furniture/corner_row.dart';
import 'package:reader_ui/panels/corner_info_editor.dart';

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

  testWidgets('点击四角选择信息后更新预览，其他位置保持原值', (tester) async {
    var info = ReaderCornerInfo.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, update) => CornerInfoEditor(
              info: info,
              onChanged: (value) => update(() => info = value),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('settings-corner-top-left')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('corner-choice-bookTitle')));
    await tester.pumpAndSettle();
    expect(info.topLeft, ReaderCornerContent.bookTitle);
    expect(info.bottomLeft, ReaderCornerContent.clockAndBattery);
    expect(find.text('书名'), findsOneWidget);
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
