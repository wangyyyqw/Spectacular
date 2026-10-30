import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/panels/tap_zone_editor.dart';
import 'package:reader_ui/tap_zones.dart';

void main() {
  testWidgets('九宫格编辑页循环动作、保留与取消', (tester) async {
    ReaderTapZones? applied;
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: TapZoneEditor(
          zones: ReaderTapZones.defaults,
          foreground: Colors.black,
          background: Colors.white,
          onApply: (zones) => applied = zones,
          onCancel: () => cancelled = true,
        ),
      ),
    );

    for (final zone in ReaderTapZone.values) {
      expect(
        find.byKey(ValueKey<String>('tap-zone-${zone.name}')),
        findsOneWidget,
      );
    }
    expect(find.text('菜单'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('tap-zone-center')));
    await tester.pump();
    expect(find.text('无动作'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('tap-zone-apply')));
    expect(applied?.actionAt(ReaderTapZone.center), ReaderTapAction.none);

    await tester.tap(find.byKey(const ValueKey<String>('tap-zone-cancel')));
    expect(cancelled, isTrue);
  });
}
