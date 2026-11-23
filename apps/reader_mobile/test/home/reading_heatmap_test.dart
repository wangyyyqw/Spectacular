import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reading_heatmap.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';

ReaMicroChartPoint point(
  String day,
  int seconds, {
  int reading = 0,
  int listening = 0,
}) => ReaMicroChartPoint(
  day: day,
  durationSeconds: seconds,
  readingDurationSeconds: reading,
  listeningDurationSeconds: listening,
);

class _Account extends ReaMicroController {
  _Account()
    : super(library: LibraryStore.memory(), enableLanLoginServer: false);
  bool active = true;
  @override
  bool get signedIn => active;
  @override
  ReaMicroUser? get user =>
      active ? const ReaMicroUser(id: 1, nickName: '读者', avatar: '') : null;
  @override
  List<ReaMicroChartPoint> get heatmapChart => [point('2026-11-24', 3660)];
  void clearAccount() {
    active = false;
    notifyListeners();
  }
}

void main() {
  test('跨年和闰日按周一对齐，补零、合并当天、忽略区间外数据', () {
    final data = ReadingHeatmapData([
      point('2024-02-29', 900),
      point('2024-02-29', 0, reading: 300, listening: 600),
      point('2024-03-01', -10),
      point('2023-01-01', 3600),
      point('2024-03-03', 3600),
      point('无效日期', 3600),
    ], DateTime(2024, 3, 2));
    expect(data.gridStart.weekday, DateTime.monday);
    expect(data.seconds[DateTime(2024, 2, 29)], 1800);
    expect(data.intensity(DateTime(2024, 2, 29)), 3);
    expect(data.intensity(DateTime(2024, 3, 2)), 0);
    expect(data.readingDays, 1);
    expect(data.contains(DateTime(2024, 3, 3)), isFalse);
    expect(data.contains(DateTime(2023, 1, 1)), isFalse);
    expect(data.end.difference(data.start).inDays, 364);
  });

  testWidgets('手机窄屏大字号显示热力图，最新日期可点击，退出账号后隐藏', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = _Account();
    addTearDown(account.dispose);
    final today = DateTime(2026, 11, 24);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: ListView(
              children: [ReadingHeatmap(controller: account, today: today)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('近一年阅读 1 天'), findsOneWidget);
    expect(find.text('2026年11月24日 · 1 小时 1 分'), findsOneWidget);
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('heatmap-months')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, position.maxScrollExtent);
    final paint = find.byType(CustomPaint).last;
    final data = ReadingHeatmapData(account.heatmapChart, today);
    final local = Offset((data.weeks - 1) * 12 + 4, 20 + 4);
    await tester.tapAt(tester.getTopLeft(paint) + local);
    await tester.pumpAndSettle();
    expect(find.text('2026年11月23日 · 0 分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
    account.clearAccount();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-reading-heatmap')), findsNothing);
  });
}
