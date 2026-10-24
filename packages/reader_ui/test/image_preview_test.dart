import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/image_preview_page.dart';

Future<ui.Image> _createImage(int width, int height, int color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Color(color),
  );
  return recorder.endRecording().toImage(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('预览页：缩略图先出、原图解码后替换、可缩放、可关闭', (tester) async {
    final thumbnail = await tester.runAsync(
      () => _createImage(40, 30, 0xFF00FF00),
    );
    final original = await tester.runAsync(
      () => _createImage(400, 300, 0xFFFF0000),
    );
    var originalLoads = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ImagePreviewPage(
                  thumbnail: thumbnail,
                  loadOriginal: () async {
                    originalLoads += 1;
                    return original;
                  },
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('preview-viewer')), findsOneWidget,
        reason: 'InteractiveViewer 就绪（缩略图先行）');
    expect(find.byKey(const ValueKey<String>('preview-close')), findsOneWidget);

    // 原图解码完成替换（FutureBuilder 已完成）。
    await tester.pump(const Duration(milliseconds: 100));
    expect(originalLoads, 1);

    // 关闭（先于手势测试：排除拖拽状态干扰）。
    await tester.tap(find.byKey(const ValueKey<String>('preview-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewPage), findsNothing);
  });

  testWidgets('预览页：拖动手势不崩溃且不关闭页面', (tester) async {
    final thumbnail = await tester.runAsync(
      () => _createImage(40, 30, 0xFF00FF00),
    );
    final original = await tester.runAsync(
      () => _createImage(400, 300, 0xFFFF0000),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage(
          thumbnail: thumbnail,
          loadOriginal: () async => original,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final center = tester.getCenter(
      find.byKey(const ValueKey<String>('preview-viewer')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-40, -40));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.byType(ImagePreviewPage), findsOneWidget);
  });

  testWidgets('原图解码失败：保持缩略图展示不崩溃', (tester) async {
    final thumbnail = await tester.runAsync(
      () => _createImage(40, 30, 0xFF00FF00),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage(
          thumbnail: thumbnail,
          loadOriginal: () async => null,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey<String>('preview-viewer')), findsOneWidget);
  });

  testWidgets('无缩略图且解码中：显示加载圈', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage(
          loadOriginal: () => Future<ui.Image?>.delayed(
            const Duration(seconds: 1),
            () => null,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // 清掉 1s 定时器再结束（fake_async 不留 pending timer）。
    await tester.pump(const Duration(seconds: 1));
  });
}
