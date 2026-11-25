import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/theme/reader_switch.dart';

void main() {
  testWidgets('胶囊开关随所在页面取色，点击行与开关各切换一次，禁用时保留状态', (tester) async {
    var value = false;
    var changes = 0;
    var enabled = true;
    var seed = Colors.purple;
    Widget app() => MaterialApp(
      theme: ThemeData(
        useMaterial3: false,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      ),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, update) => ReaderSwitchListTile(
            title: const Text('设置开关'),
            value: value,
            onChanged: enabled
                ? (next) => update(() {
                    value = next;
                    changes++;
                  })
                : null,
          ),
        ),
      ),
    );
    await tester.pumpWidget(app());
    await tester.tap(find.text('设置开关'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(changes, 1);
    final track = find.descendant(
      of: find.byType(ReaderSwitch),
      matching: find.byType(AnimatedContainer),
    );
    Color trackColor() =>
        (tester.widget<AnimatedContainer>(track).decoration! as BoxDecoration)
            .color!;
    expect(tester.getSize(track), const Size(42, 22));
    expect(trackColor(), ColorScheme.fromSeed(seedColor: seed).primary);
    seed = Colors.teal;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(trackColor(), ColorScheme.fromSeed(seedColor: seed).primary);
    await tester.tap(find.byType(ReaderSwitch));
    await tester.pumpAndSettle();
    expect(value, isFalse);
    expect(changes, 2);
    enabled = false;
    await tester.pumpWidget(app());
    await tester.tap(find.text('设置开关'));
    await tester.pumpAndSettle();
    expect(changes, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Material 3 使用原生开关，保留禁用状态与触控区域', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(body: ReaderSwitch(value: true, onChanged: null)),
      ),
    );
    final track = find.descendant(
      of: find.byType(ReaderSwitch),
      matching: find.byType(Switch),
    );
    expect(track, findsOneWidget);
    expect(tester.widget<Switch>(track).onChanged, isNull);
    expect(tester.widget<Switch>(track).value, isTrue);
    expect(tester.getSize(find.byType(ReaderSwitch)), const Size(56, 44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('MD3 设置行和开关各切换一次，禁用后不触发回调', (tester) async {
    var value = false;
    var count = 0;
    var enabled = true;
    Widget app() => MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, update) => ReaderSwitchListTile(
            title: const Text('MD3 设置'),
            value: value,
            onChanged: enabled
                ? (next) => update(() {
                    value = next;
                    count++;
                  })
                : null,
          ),
        ),
      ),
    );
    await tester.pumpWidget(app());
    await tester.tap(find.text('MD3 设置'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(count, 1);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(value, isFalse);
    expect(count, 2);
    enabled = false;
    await tester.pumpWidget(app());
    await tester.tap(find.text('MD3 设置'));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(count, 2);
    expect(tester.takeException(), isNull);
  });
}
