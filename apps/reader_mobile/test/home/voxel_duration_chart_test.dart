import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/voxel_duration_chart.dart';

const _boundaryKey = ValueKey('voxel-test-boundary');
const _plotHeight = 200.0;
const _barColor = Color(0xFFFF0000);

const _defaultBars = <DurationBarData>[
  (
    key: 'a',
    id: 'a',
    title: '阿西莫夫科幻短篇全集',
    shortTitle: '阿西莫夫科幻短篇全集',
    share: '100%',
    duration: Duration(hours: 10),
    color: _barColor,
  ),
];

const _mixedBars = <DurationBarData>[
  (
    key: 'a',
    id: 'a',
    title: '第一本书',
    shortTitle: '第一本书',
    share: '60%',
    duration: Duration(hours: 6),
    color: _barColor,
  ),
  (
    key: 'b',
    id: 'b',
    title: '第二本书',
    shortTitle: '第二本书',
    share: '40%',
    duration: Duration(hours: 4),
    color: Color(0xFF3366FF),
  ),
];

List<TimeOfDayBarData> _timeBuckets({bool week = false}) {
  final labels = week
      ? const ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
      : List.generate(12, (index) => '${index * 2}-${index * 2 + 2}');
  return [
    for (var index = 0; index < labels.length; index++)
      (
        key: labels[index],
        label: labels[index],
        duration: index == 0 ? const Duration(hours: 10) : Duration.zero,
        segments: index == 0
            ? [
                for (final bar in _mixedBars)
                  (
                    key: bar.key,
                    title: bar.title,
                    color: bar.color,
                    duration: bar.duration,
                  ),
              ]
            : const [],
      ),
  ];
}

Future<void> _pumpChart(
  WidgetTester tester, {
  bool rooftops = false,
  bool animations = false,
  bool settle = true,
  List<DurationBarData> bars = _defaultBars,
  List<TimeOfDayBarData> timeBars = const [],
  bool week = false,
  String? selectedBookId,
}) async {
  await tester.binding.setSurfaceSize(const Size(360, 480));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: !animations,
          size: const Size(360, 480),
        ),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: RepaintBoundary(
              key: _boundaryKey,
              child: VoxelDurationChart(
                bars: bars,
                timeBars: timeBars,
                total: bars.fold(
                  Duration.zero,
                  (sum, bar) => sum + bar.duration,
                ),
                bookCount: bars.length,
                selectedBookId: selectedBookId,
                onSelected: (_) {},
                showRooftops: rooftops,
                weekMode: week,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder _key(String suffix) =>
    find.byKey(ValueKey('stats-book-duration-$suffix'));

Finder _plotFinder() {
  final paints = find.byType(CustomPaint);
  final matches = <Finder>[];
  for (var index = 0; index < paints.evaluate().length; index++) {
    final finder = paints.at(index);
    final box = finder.evaluate().single.renderObject! as RenderBox;
    if ((box.size.height - _plotHeight).abs() < .01) matches.add(finder);
  }
  expect(matches, hasLength(1), reason: '统计图应只有一个 200 高的绘图区');
  return matches.single;
}

Future<_PixelSnapshot> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  final image = boundary.toImageSync();
  try {
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    final plot = tester
        .getRect(_plotFinder())
        .shift(-tester.getTopLeft(find.byKey(_boundaryKey)));
    return _PixelSnapshot(bytes, image.width, image.height, plot);
  } finally {
    image.dispose();
  }
}

class _PixelSnapshot {
  _PixelSnapshot(this.bytes, this.width, this.height, this.plot);

  final ByteData bytes;
  final int width;
  final int height;
  final Rect plot;

  bool isBar(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    final offset = (y * width + x) * 4;
    final r = bytes.getUint8(offset);
    final g = bytes.getUint8(offset + 1);
    final b = bytes.getUint8(offset + 2);
    return r > 150 && g < 170 && b < 170;
  }

  bool isWarm(int x, int y) {
    final offset = (y * width + x) * 4;
    final r = bytes.getUint8(offset);
    final g = bytes.getUint8(offset + 1);
    final b = bytes.getUint8(offset + 2);
    return r > 165 && g > 110 && r > g + 15 && g > b + 40;
  }

  /// 只统计暖色窗灯，不将红色柱体或蓝色堆叠色段算作灯光。
  int warmCount({double top = 0, double bottom = _plotHeight}) {
    var count = 0;
    for (
      var y = (plot.top + top).ceil();
      y < (plot.top + bottom).floor();
      y++
    ) {
      for (var x = plot.left.ceil(); x < plot.right.floor(); x++) {
        if (isWarm(x, y)) count++;
      }
    }
    return count;
  }

  /// 拆解阶段统计实际可见的连通颗粒，接触在一起的颗粒只计一次。
  int visibleFragments() {
    final pixels = <int>{};
    for (var y = plot.top.ceil(); y < plot.bottom.floor(); y++) {
      for (var x = plot.left.ceil(); x < plot.right.floor(); x++) {
        final offset = (y * width + x) * 4;
        final r = bytes.getUint8(offset);
        final g = bytes.getUint8(offset + 1);
        final b = bytes.getUint8(offset + 2);
        if (isBar(x, y) || (b > 150 && r < 180 && g < 185)) {
          pixels.add(y * width + x);
        }
      }
    }
    var fragments = 0;
    while (pixels.isNotEmpty) {
      final connected = [pixels.first];
      pixels.remove(connected.first);
      for (var index = 0; index < connected.length; index++) {
        for (var y = -1; y <= 1; y++) {
          for (var x = -1; x <= 1; x++) {
            final neighbor = connected[index] + y * width + x;
            if (pixels.remove(neighbor)) connected.add(neighbor);
          }
        }
      }
      if (connected.length >= 2) fragments++;
    }
    return fragments;
  }

  /// 等高书柱在正式绘图区的窗格中心，用像素区分亮窗和暗窗。
  List<bool> bookWindowLights(int index, int count) {
    final slot = plot.width / count;
    final halfWidth = (slot * .32).clamp(0.0, 24.0);
    final depth = halfWidth * .5;
    final centerX = plot.left + slot * (index + .5);
    final baseY = plot.bottom - depth - 6;
    final columns = halfWidth >= 16
        ? 3
        : halfWidth >= 7.5
        ? 2
        : 1;
    return [
      for (var floor = 0; floor < 11; floor++)
        for (var side = 0; side < 2; side++)
          for (var column = 0; column < columns; column++)
            isWarm(
              (centerX +
                      halfWidth *
                          ((column + .5) / columns - (side == 0 ? 1 : 0)))
                  .round(),
              (baseY -
                      (floor + .5) * 12 +
                      depth *
                          (side == 0
                              ? (column + .5) / columns
                              : 1 - (column + .5) / columns))
                  .round(),
            ),
    ];
  }

  String rooftopMask(int index, int count) {
    final slot = plot.width / count;
    final center = plot.left + slot * (index + .5);
    final halfWidth = (slot * .32).clamp(0.0, 24.0);
    final roofY = _plotHeight - halfWidth * .5 - 6 - 132;
    final mask = StringBuffer();
    for (var y = plot.top.ceil(); y < (plot.top + roofY - 8).floor(); y++) {
      for (var x = -14; x <= 14; x++) {
        mask.write(isBar((center + x).round(), y) ? '1' : '0');
      }
    }
    return mask.toString();
  }

  /// 柱体红色像素：最顶一行、最顶行宽度与整体最大宽度。
  ({int topRow, int topWidth, int maxWidth}) barProfile() {
    final left = plot.left.floor();
    final top = plot.top.floor();
    final right = plot.right.ceil();
    final bottom = plot.bottom.ceil();
    var topWidth = 0;
    final rows = <int, int>{};
    for (var y = top; y < bottom; y++) {
      var count = 0;
      for (var x = left; x < right; x++) {
        if (isBar(x, y)) count++;
      }
      if (count > 0) rows[y] = count;
    }
    if (rows.isEmpty) return (topRow: 0, topWidth: 0, maxWidth: 0);
    final topRow = rows.keys.first;
    topWidth = rows[topRow]!;
    final maxWidth = rows.values.reduce((a, b) => a > b ? a : b);
    return (topRow: topRow, topWidth: topWidth, maxWidth: maxWidth);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('柱状图顶面完整绘制为菱形，不在显示高度处被裁掉一半', (tester) async {
    await _pumpChart(tester);
    final snapshot = await _capture(tester);
    final profile = snapshot.barProfile();
    expect(profile.maxWidth, greaterThan(30), reason: '柱体应可见');
    expect(
      profile.topWidth,
      lessThan(profile.maxWidth * .4),
      reason: '最顶部应是菱形尖角，而不是被裁平的柱体全宽',
    );
  });

  testWidgets('切换周期后首帧即显示完整柱体，不重新播放长成动画', (tester) async {
    await _pumpChart(tester, animations: true);
    await _pumpChart(
      tester,
      animations: true,
      settle: false,
      bars: const [
        (
          key: 'b',
          id: 'b',
          title: '第二本书',
          shortTitle: '第二本书',
          share: '70%',
          duration: Duration(hours: 7),
          color: _barColor,
        ),
        (
          key: 'c',
          id: 'c',
          title: '第三本书',
          shortTitle: '第三本书',
          share: '30%',
          duration: Duration(hours: 3),
          color: Color(0xFF3366FF),
        ),
      ],
    );
    await tester.pump(const Duration(milliseconds: 16));
    final snapshot = await _capture(tester);
    final profile = snapshot.barProfile();
    expect(profile.maxWidth, greaterThan(30));
    expect(
      profile.topRow,
      lessThan(snapshot.plot.top + _plotHeight * .6),
      reason: '切换周期不应让柱体先缩成底部小块',
    );
  });

  testWidgets('柱顶绘制阁楼装饰，轮廓高于顶面菱形', (tester) async {
    await _pumpChart(tester);
    final plain = (await _capture(tester)).barProfile();
    await _pumpChart(tester, rooftops: true);
    final decorated = (await _capture(tester)).barProfile();
    expect(plain.maxWidth, greaterThan(30), reason: '柱体应可见');
    expect(decorated.maxWidth, greaterThan(30), reason: '柱体应可见');
    expect(
      decorated.topRow,
      lessThanOrEqualTo(plain.topRow - 4),
      reason: '阁楼应明显高出柱体顶面菱形',
    );
  });

  testWidgets('八种柱顶造型轮换且轮廓不同', (tester) async {
    await _pumpChart(
      tester,
      rooftops: true,
      bars: [
        for (var index = 0; index < 8; index++)
          (
            key: 'roof-$index',
            id: 'roof-$index',
            title: '柱顶 $index',
            shortTitle: '柱顶 $index',
            share: '12.5%',
            duration: const Duration(hours: 10),
            color: _barColor,
          ),
      ],
    );
    final snapshot = await _capture(tester);
    final shapes = {
      for (var index = 0; index < 8; index++) snapshot.rooftopMask(index, 8),
    };
    expect(shapes, hasLength(8));
  });

  for (final week in [false, true]) {
    testWidgets('${week ? '周' : '日'}时段柱顶使用紧凑装饰，不裁切最高柱', (tester) async {
      final timeBars = [
        for (final bar in _timeBuckets(week: week))
          (
            key: bar.key,
            label: bar.label,
            duration: bar.duration,
            segments: bar.duration > Duration.zero
                ? [
                    (
                      key: 'a',
                      title: '第一本书',
                      color: _barColor,
                      duration: bar.duration,
                    ),
                  ]
                : const <DurationBarSegment>[],
          ),
      ];
      await _pumpChart(tester, timeBars: timeBars, week: week);
      await tester.tap(_key('chart-mode'));
      await tester.pump();
      final plain = (await _capture(tester)).barProfile();
      await _pumpChart(tester, rooftops: true, timeBars: timeBars, week: week);
      final decorated = await _capture(tester);
      expect(
        decorated.barProfile().topRow,
        lessThanOrEqualTo(plain.topRow - 4),
      );
      expect(
        decorated.barProfile().topRow,
        greaterThan(decorated.plot.top + 1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final week in [false, true]) {
    testWidgets('${week ? '周' : '日'}柱图边重组边点灯，点灯滞后格块重组 0.2 秒并连续上行', (
      tester,
    ) async {
      await _pumpChart(
        tester,
        animations: true,
        bars: _mixedBars,
        timeBars: _timeBuckets(week: week),
        week: week,
      );
      expect((await _capture(tester)).warmCount(), greaterThan(0));
      await tester.tap(_key('chart-mode'));
      await tester.pump();
      final movingPaint = tester.widget<CustomPaint>(_key('morph'));
      await tester.pump(const Duration(milliseconds: 619));
      expect(_key('morph'), findsOneWidget);
      expect(
        identical(tester.widget<CustomPaint>(_key('morph')), movingPaint),
        isTrue,
      );
      expect(
        (await _capture(tester)).warmCount(),
        0,
        reason: '格块开始重组后 0.2 秒内仍未点灯',
      );
      await tester.pump(const Duration(milliseconds: 181));
      expect(_key('morph'), findsOneWidget, reason: '点灯时仍处于重组动画中');
      final lowerLit = await _capture(tester);
      expect(lowerLit.warmCount(top: 144), greaterThan(0));
      expect(lowerLit.warmCount(bottom: 110), 0, reason: '上层色段尚未轮到点灯');

      await tester.pump(const Duration(milliseconds: 201));
      expect(_key('morph'), findsNothing, reason: '重组动画在 1 秒结束');
      expect((await _capture(tester)).warmCount(), greaterThan(0));
      await tester.pump(const Duration(milliseconds: 200));
      final allLit = await _capture(tester);
      expect(allLit.warmCount(bottom: 110), greaterThan(0));
      expect(
        allLit.warmCount(top: 144),
        greaterThanOrEqualTo(lowerLit.warmCount(top: 144)),
      );
      await tester.tap(_key('chart-mode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(_key('bar-a'), findsOneWidget);
      expect(_key('morph'), findsOneWidget);
      final booksLit = await _capture(tester);
      expect(booksLit.warmCount(top: 144), greaterThan(0));
      expect(booksLit.warmCount(bottom: 110), 0);
      await tester.pumpAndSettle();
      expect((await _capture(tester)).warmCount(bottom: 110), greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('阁楼和塔尖的随机灯光晚于柱体楼层点亮', (tester) async {
    await _pumpChart(
      tester,
      rooftops: true,
      animations: true,
      settle: false,
      bars: [
        for (var index = 0; index < 5; index++)
          (
            key: 'roof-$index',
            id: 'roof-$index',
            title: '阁楼 $index',
            shortTitle: '阁楼 $index',
            share: '20%',
            duration: const Duration(hours: 10),
            color: _barColor,
          ),
      ],
    );
    await tester.pump(const Duration(milliseconds: 681));
    expect((await _capture(tester)).warmCount(), 0);
    await tester.pump(const Duration(milliseconds: 700));
    final facadeLit = await _capture(tester);
    expect(facadeLit.warmCount(top: 55), greaterThan(0));
    expect(facadeLit.warmCount(bottom: 55), 0, reason: '阁楼和塔尖不能与底层一起点亮');
    await tester.pump(const Duration(milliseconds: 80));
    expect((await _capture(tester)).warmCount(bottom: 55), greaterThan(0));
  });

  testWidgets('颗粒仍对应真实格子，重组 1 秒并与点灯错开 0.2 秒', (tester) async {
    await _pumpChart(
      tester,
      animations: true,
      bars: _mixedBars,
      timeBars: _timeBuckets(),
    );
    await tester.tap(_key('chart-mode'));
    await tester.pump();
    final particles =
        (tester.widget<CustomPaint>(_key('morph')).painter! as dynamic)
                .particles
            as List<Object>;
    // 两根书柱分别为 11 层、8 层，每层两面各 3 格，共 114 格。
    expect(particles, hasLength(114));
    expect(
      particles.where(
        (particle) => ((particle as dynamic).key as String) == 'a',
      ),
      hasLength(66),
    );
    expect(
      particles.where(
        (particle) => ((particle as dynamic).key as String) == 'b',
      ),
      hasLength(48),
    );
    await tester.pump(const Duration(milliseconds: 330));
    final scattered = await _capture(tester);
    expect(
      scattered.visibleFragments(),
      greaterThanOrEqualTo(30),
      reason: '相邻小块可能接触，但真实画面仍需显示清楚的拆解颗粒',
    );
    expect(scattered.warmCount(), 0);
    await tester.pump(const Duration(milliseconds: 289));
    expect(_key('morph'), findsOneWidget);
    expect((await _capture(tester)).warmCount(), 0);
    await tester.pump(const Duration(milliseconds: 81));
    expect(_key('morph'), findsOneWidget);
    expect((await _capture(tester)).warmCount(), greaterThan(0));
    await tester.pump(const Duration(milliseconds: 301));
    expect(_key('morph'), findsNothing);
    expect((await _capture(tester)).warmCount(), greaterThan(0));
    await tester.pumpAndSettle();
    expect((await _capture(tester)).warmCount(), greaterThan(0));
    await tester.tap(_key('chart-mode'));
    await tester.pump();
    final reversed =
        (tester.widget<CustomPaint>(_key('morph')).painter! as dynamic)
                .particles
            as List<Object>;
    expect(reversed, hasLength(particles.length), reason: '反向重组使用相同数量的真实小块');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('短柱按一层格块拆解，不再强制生成一大批最低数量的颗粒', (tester) async {
    const short = (
      key: 'short',
      id: 'short',
      title: '短柱',
      shortTitle: '短柱',
      share: '<1%',
      duration: Duration(minutes: 1),
      color: Color(0xFF33AA66),
    );
    final buckets = _timeBuckets();
    buckets[0] = (
      key: '0-2',
      label: '0-2',
      duration: const Duration(hours: 10, minutes: 1),
      segments: [
        ...buckets[0].segments,
        (
          key: short.key,
          title: short.title,
          color: short.color,
          duration: short.duration,
        ),
      ],
    );
    await _pumpChart(
      tester,
      animations: true,
      bars: [..._mixedBars, short],
      timeBars: buckets,
    );
    await tester.tap(_key('chart-mode'));
    await tester.pump();
    final particles =
        (tester.widget<CustomPaint>(_key('morph')).painter! as dynamic)
                .particles
            as List<Object>;
    expect(
      particles.where(
        (particle) => ((particle as dynamic).key as String) == short.key,
      ),
      hasLength(6),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('约一半窗格随机亮灯，书籍排名变化后保持原有明暗分布', (tester) async {
    final bars = [
      for (var index = 0; index < 5; index++)
        (
          key: 'book-$index',
          id: 'book-$index',
          title: '书籍 $index',
          shortTitle: '书籍 $index',
          share: '20%',
          duration: const Duration(hours: 10),
          color: _barColor,
        ),
    ];
    await _pumpChart(tester, bars: bars);
    final before = await _capture(tester);
    final patterns = [
      for (var index = 0; index < bars.length; index++)
        before.bookWindowLights(index, bars.length),
    ];
    final windows = patterns.expand((pattern) => pattern).toList();
    final litRatio = windows.where((lit) => lit).length / windows.length;
    expect(litRatio, inInclusiveRange(.42, .58), reason: '亮窗约占一半，不再强制每层右侧亮灯');
    for (final pattern in patterns) {
      expect(pattern, contains(true));
      expect(pattern, contains(false));
    }
    await _pumpChart(tester, bars: bars.reversed.toList());
    final reordered = await _capture(tester);
    for (var index = 0; index < bars.length; index++) {
      expect(
        reordered.bookWindowLights(index, bars.length),
        patterns[bars.length - index - 1],
      );
    }
  });

  testWidgets('增长和点灯逐帧只重绘画布，不重建柱体触控与标签', (tester) async {
    await _pumpChart(tester, animations: true, settle: false);
    final interaction = tester.widget<GestureDetector>(_key('bar-a'));
    final label = tester.widget<Text>(find.text(_defaultBars.first.shortTitle));
    final paint = tester.widget<CustomPaint>(_key('plot'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      identical(tester.widget<GestureDetector>(_key('bar-a')), interaction),
      isTrue,
    );
    expect(
      identical(
        tester.widget<Text>(find.text(_defaultBars.first.shortTitle)),
        label,
      ),
      isTrue,
    );
    expect(identical(tester.widget<CustomPaint>(_key('plot')), paint), isTrue);
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump(const Duration(milliseconds: 200));
    expect((await _capture(tester)).warmCount(top: 144), greaterThan(0));
    expect(
      identical(tester.widget<GestureDetector>(_key('bar-a')), interaction),
      isTrue,
    );
    expect(identical(tester.widget<CustomPaint>(_key('plot')), paint), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('柱体增长不再整层跳高，相邻帧连续变化且顶面保持完整', (tester) async {
    await _pumpChart(tester, animations: true, settle: false);
    await tester.pump(const Duration(milliseconds: 180));
    final first = (await _capture(tester)).barProfile();
    await tester.pump(const Duration(milliseconds: 16));
    final next = (await _capture(tester)).barProfile();
    expect(first.topRow - next.topRow, inInclusiveRange(1, 11));
    expect(next.topWidth, lessThan(next.maxWidth * .4));
    await tester.pumpAndSettle();
  });

  testWidgets('重组中数据更新立即显示新柱体，旧重组不再恢复或提前点灯', (tester) async {
    await _pumpChart(
      tester,
      animations: true,
      bars: _mixedBars,
      timeBars: _timeBuckets(),
    );
    await tester.tap(_key('chart-mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(_key('morph'), findsOneWidget);
    final updated = _timeBuckets();
    updated[0] = (
      key: '0-2',
      label: '0-2',
      duration: const Duration(hours: 6),
      segments: [updated[0].segments.first],
    );
    await _pumpChart(
      tester,
      animations: true,
      settle: false,
      bars: [_mixedBars.first],
      timeBars: updated,
    );
    expect(_key('morph'), findsNothing);
    final snapshot = await _capture(tester);
    expect(snapshot.barProfile().topRow, lessThan(snapshot.plot.top + 70));
    expect(snapshot.warmCount(), 0);
    await tester.pumpAndSettle();
    expect(_key('time-bar-0-2'), findsOneWidget);
    expect((await _capture(tester)).warmCount(), greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('同值数据刷新和点选不重播点灯', (tester) async {
    await _pumpChart(tester, animations: true);
    await _pumpChart(
      tester,
      animations: true,
      settle: false,
      bars: List.of(_defaultBars),
      selectedBookId: 'a',
    );
    expect((await _capture(tester)).warmCount(bottom: 110), greaterThan(0));
    expect(_key('morph'), findsNothing);
  });

  testWidgets('减少动态效果时直接展示完整柱体与灯光，运行中启用也立即结束重组', (tester) async {
    await _pumpChart(tester, bars: _mixedBars, timeBars: _timeBuckets());
    await tester.tap(_key('chart-mode'));
    await tester.pump();
    expect(_key('morph'), findsNothing);
    expect(_key('time-bar-0-2'), findsOneWidget);
    expect((await _capture(tester)).warmCount(bottom: 110), greaterThan(0));
    await _pumpChart(
      tester,
      animations: true,
      bars: _mixedBars,
      timeBars: _timeBuckets(),
    );
    await tester.tap(_key('chart-mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_key('morph'), findsOneWidget);
    await _pumpChart(
      tester,
      bars: _mixedBars,
      timeBars: _timeBuckets(),
      settle: false,
    );
    expect(_key('morph'), findsNothing);
    expect(_key('bar-a'), findsOneWidget);
    expect((await _capture(tester)).warmCount(bottom: 110), greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
