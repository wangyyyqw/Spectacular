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
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
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
}
