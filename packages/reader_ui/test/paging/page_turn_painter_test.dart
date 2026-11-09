import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/bessel_geometry.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_painter.dart';
import 'package:reader_ui/reader_session.dart';

const _size = Size(200, 300);

class _InvalidGeometry extends Fake implements BesselGeometry {
  @override
  Size get size => _size;

  @override
  Path frontPath() => throw StateError('模拟曲线路径运算失败');
}

class _Controller extends PageTurnController {
  _Controller({
    required super.session,
    required super.vsync,
    required super.acquireImage,
  });

  bool invalidGeometry = false;
  double opacity = 1;

  @override
  double get targetOpacity => opacity;

  @override
  BesselGeometry? get besselGeometry =>
      invalidGeometry ? _InvalidGeometry() : super.besselGeometry;
}

class _Source implements ReaderChapterSource {
  @override
  int get chapterCount => 0;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [];
}

ui.Image _splitImage(Color left, Color right) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 300), Paint()..color = left);
  canvas.drawRect(
    const Rect.fromLTWH(100, 0, 100, 300),
    Paint()..color = right,
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(200, 300);
  picture.dispose();
  return image;
}

Future<ByteData> _render(PageTurnController controller) async {
  final recorder = ui.PictureRecorder();
  PageTurnPainter(
    controller,
    paperColor: const Color(0xFFFFFFFF),
  ).paint(Canvas(recorder), _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 300);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!;
}

List<int> _pixel(ByteData data, int x, int y) {
  final offset = (y * 200 + x) * 4;
  return List<int>.generate(4, (index) => data.getUint8(offset + index));
}

_Controller _controller(WidgetTester tester, {bool solid = false}) {
  final session = ReaderSession(
    source: _Source(),
    store: MemoryReaderProgressStore(),
    bookId: '纸面绘制',
  );
  final origin = _splitImage(
    const Color(0xFFFFFF00),
    Color(solid ? 0xFFFFFF00 : 0xFF00FF00),
  );
  final target = _splitImage(
    const Color(0xFFFF0000),
    Color(solid ? 0xFFFF0000 : 0xFF0000FF),
  );
  final controller =
      _Controller(
          session: session,
          vsync: tester,
          acquireImage: (_) async => null,
        )
        ..size = _size
        ..mode = PageTurnMode.simulationBessel
        ..phase = PageTurnPhase.dragging
        ..progress = 0.05
        ..originImage = origin
        ..targetImage = target;
  addTearDown(() {
    controller.dispose();
    session.dispose();
    origin.dispose();
    target.dispose();
  });
  return controller;
}

void _expectMirrored(ByteData forward, ByteData backward) {
  var error = 0;
  var edgeSamples = 0;
  for (var y = 0; y < 300; y++) {
    for (var x = 0; x < 200; x++) {
      final source = _pixel(forward, x, y);
      final mirrored = _pixel(backward, 199 - x, y);
      for (var channel = 0; channel < 4; channel++) {
        final difference = (mirrored[channel] - source[channel]).abs();
        error += difference;
        if (difference > 2) edgeSamples++;
      }
    }
  }
  // 镜像栅格化的亚像素边缘会有差异；整帧平均误差 <0.1/255，
  // 至少 99.9% 的颜色通道误差 <=2，防止只比较少数采样点漏掉形变差异。
  expect(error / forward.lengthInBytes, lessThan(0.1));
  expect(edgeSamples / forward.lengthInBytes, lessThan(0.001));
}

void main() {
  for (final mode in [
    PageTurnMode.simulationBessel,
    PageTurnMode.cover,
    PageTurnMode.coverStack,
    PageTurnMode.slideHorizontal,
  ]) {
    testWidgets('${mode.label}冷目标首帧与等待帧像素一致且渐入不透明', (tester) async {
      final controller = _controller(tester)
        ..mode = mode
        ..progress = 0.08
        ..point = const Offset(168, 220);
      final target = controller.targetImage;
      controller.targetImage = null;
      final waiting = await tester.runAsync(() => _render(controller));
      controller.targetImage = target;
      controller.opacity = 0;
      final first = await tester.runAsync(() => _render(controller));
      expect(first!.buffer.asUint8List(), waiting!.buffer.asUint8List());
      controller.opacity = 0.5;
      final middle = await tester.runAsync(() => _render(controller));
      final bytes = middle!.buffer.asUint8List();
      for (var index = 3; index < bytes.length; index += 4) {
        expect(bytes[index], 255, reason: '接续合成不能出现透明裂隙');
      }
    });
  }

  for (final mode in [
    PageTurnMode.cover,
    PageTurnMode.coverStack,
    PageTurnMode.simulationBessel,
    PageTurnMode.slideHorizontal,
  ]) {
    testWidgets('${mode.label} 冷目标等待期间原页轻抬仍铺满纸面', (tester) async {
      final controller = _controller(tester, solid: true)
        ..mode = mode
        ..phase = PageTurnPhase.preparing
        ..targetImage = null
        ..progress = 0.08
        ..point = const Offset(168, 240);
      final data = (await tester.runAsync(() => _render(controller)))!;
      expect(_pixel(data, 60, 150), [255, 255, 0, 255]);
      for (var y = 0; y < 300; y += 10) {
        for (var x = 0; x < 200; x += 10) {
          expect(_pixel(data, x, y).last, 255, reason: '准备期间不能露出透明空白');
        }
      }
    });
  }
  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'RTL' : 'LTR'} 上中下起卷全程与下一页互为左右镜像', (tester) async {
      final forward = _controller(tester, solid: true)..rtl = rtl;
      final backward = _controller(tester, solid: true)
        ..rtl = rtl
        ..next = false;
      for (final y in <double>[60, 150, 240]) {
        for (final x in <double>[180, 100, 0, -100, -180]) {
          for (final controller in [forward, backward]) {
            controller
              ..top = y < 150
              ..horizontal = y == 150
              ..point = Offset(x, y)
              ..progress = (200 - x) / 400;
          }
          final frames = await tester.runAsync(
            () async => [await _render(forward), await _render(backward)],
          );
          _expectMirrored(frames![0], frames[1]);
        }
      }
    });

    for (final next in [false, true]) {
      for (final invalidGeometry in [false, true]) {
        testWidgets('${rtl ? 'RTL' : 'LTR'} ${next ? '下一页' : '上一页'}'
            '${invalidGeometry ? '路径异常' : '几何为空'}降级仍按相反轴翻动原页', (tester) async {
          final controller = _controller(tester)
            ..rtl = rtl
            ..next = next
            ..invalidGeometry = invalidGeometry
            ..progress = 0.2;
          final data = await tester.runAsync(() => _render(controller));
          final fromRight = next != rtl;

          expect(
            _pixel(data!, fromRight ? 1 : 198, 150),
            fromRight ? [255, 255, 0, 255] : [0, 255, 0, 255],
          );
          expect(
            _pixel(data, fromRight ? 198 : 1, 150),
            fromRight ? [0, 0, 255, 255] : [255, 0, 0, 255],
            reason: '降级时仍显露对应侧的目标页，避免回到覆盖模式的反向铺页',
          );
        });
      }

      testWidgets('${rtl ? 'RTL' : 'LTR'} ${next ? '下一页' : '上一页'}起卷保留原页与图片方向', (
        tester,
      ) async {
        final controller = _controller(tester)
          ..rtl = rtl
          ..next = next;

        for (final y in <double>[60, 150, 240]) {
          controller
            ..top = y < 150
            ..horizontal = y == 150
            ..point = Offset(180, y);
          final data = await tester.runAsync(() => _render(controller));
          final fromRight = next != rtl;

          expect(
            _pixel(data!, fromRight ? 1 : 198, 150),
            fromRight ? [255, 255, 0, 255] : [0, 255, 0, 255],
            reason: '起卷初期未翻动的一侧仍为原页，文字方向保持正向',
          );
          expect(
            _pixel(
              data,
              fromRight ? 198 : 1,
              y == 150 ? 150 : (y < 150 ? 1 : 298),
            ),
            fromRight ? [0, 0, 255, 255] : [255, 0, 0, 255],
            reason: '翻动的一侧显露目标页，图片不能随几何镜像',
          );
        }
      });
    }
  }

  for (final rtl in [false, true]) {
    for (final next in [false, true]) {
      testWidgets('${rtl ? 'RTL' : 'LTR'} ${next ? '下一页' : '上一页'}'
          '堆叠覆盖保持页面大小并从侧边慢速跟随', (tester) async {
        final controller = _controller(tester)
          ..mode = PageTurnMode.coverStack
          ..rtl = rtl
          ..next = next
          ..progress = 0.5;
        final data = await tester.runAsync(() => _render(controller));
        final exit = (next ? -1.0 : 1.0) * (rtl ? -1.0 : 1.0);
        final targetDx = -exit * 0.08 * (1 - controller.progress) * _size.width;
        final boundary = _size.width / 2 + targetDx;
        final red = _pixel(data!, (boundary - 2).round(), 10);
        final blue = _pixel(data, (boundary + 2).round(), 10);

        expect(red[0], greaterThan(red[2] + 80), reason: '目标页应整体平移，不能缩放');
        expect(blue[2], greaterThan(blue[0] + 80), reason: '目标页应整体平移，不能缩放');

        final masked = _pixel(data, exit < 0 ? 170 : 30, 10);
        expect(masked[1], greaterThan(0), reason: '下一页应叠加半透明灰色遮罩');
        expect(masked[3], 255, reason: '遮罩不能改变页面透明度');

        final originX = exit < 0 ? 50 : 150;
        expect(
          _pixel(data, originX, 10),
          exit < 0 ? const [0, 255, 0, 255] : const [255, 255, 0, 255],
          reason: '当前页应覆盖在目标页上方并先滑出',
        );
      });
    }
  }

  testWidgets('堆叠覆盖灰色遮罩随当前页滑出逐渐变淡', (tester) async {
    final controller = _controller(tester)
      ..mode = PageTurnMode.coverStack
      ..rtl = false
      ..next = true
      ..progress = 0.1;
    final start = _pixel(
      (await tester.runAsync(() => _render(controller)))!,
      170,
      10,
    );
    controller.progress = 0.8;
    final middle = _pixel(
      (await tester.runAsync(() => _render(controller)))!,
      170,
      10,
    );
    controller.progress = 1;
    final done = _pixel(
      (await tester.runAsync(() => _render(controller)))!,
      170,
      10,
    );

    expect(start[1], greaterThan(middle[1]), reason: '遮罩应随翻页进度变浅');
    expect(middle[1], greaterThan(0), reason: '滑出前仍应保留灰色遮罩');
    expect(done, const [0, 0, 255, 255], reason: '完全滑出后应取消遮罩');
  });
}
