import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_painter.dart';
import 'package:reader_ui/reader_session.dart';

const _size = Size(200, 300);

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

PageTurnController _controller(WidgetTester tester) {
  final session = ReaderSession(
    source: _Source(),
    store: MemoryReaderProgressStore(),
    bookId: '纸面绘制',
  );
  final origin = _splitImage(const Color(0xFFFFFF00), const Color(0xFF00FF00));
  final target = _splitImage(const Color(0xFFFF0000), const Color(0xFF0000FF));
  final controller =
      PageTurnController(
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

void main() {
  for (final rtl in [false, true]) {
    for (final next in [false, true]) {
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
            ..point = Offset(next ? 180 : 20, y);
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
}
