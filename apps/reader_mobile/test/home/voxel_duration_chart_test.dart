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

Future<void> _pumpChart(
  WidgetTester tester, {
  bool rooftops = false,
  bool animations = false,
  bool settle = true,
  List<DurationBarData> bars = _defaultBars,
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
                timeBars: const [],
                total: const Duration(hours: 10),
                bookCount: bars.length,
                selectedBookId: null,
                onSelected: (_) {},
                showRooftops: rooftops,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

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
}
