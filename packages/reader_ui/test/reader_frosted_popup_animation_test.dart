import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';

void main() {
  for (final theme in [
    ReaderTheme.white,
    ReaderTheme.black,
    ReaderTheme.sepia,
  ]) {
    testWidgets('${theme.name}居中弹窗完全不透明且入场末帧与退场首帧不突变', (tester) async {
      // 真机 1080×2400、450 dpi 对应的逻辑视口。
      await tester.binding.setSurfaceSize(const Size(384, 2560 / 3));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData(
            brightness: theme == ReaderTheme.black
                ? Brightness.dark
                : Brightness.light,
          ),
          builder: (context, child) =>
              RepaintBoundary(key: boundary, child: child),
          home: ReaderPanelTheme(
            theme: theme,
            child: CustomPaint(
              painter: _StripeBackground(),
              child: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showReaderDialog<void>(
                      context: context,
                      builder: (_) => const ReaderFrostedDialog(
                        child: SizedBox(width: 280, height: 240),
                      ),
                    ),
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pump();
      final route = ModalRoute.of(
        tester.element(find.byType(ReaderFrostedDialog)),
      )!;
      await tester.pump(
        route.transitionDuration - const Duration(milliseconds: 10),
      );
      final entering = await _samples(tester, boundary);
      await tester.pump(const Duration(milliseconds: 10));
      final settled = await _samples(tester, boundary);
      final color = Theme.of(tester.element(find.byType(ReaderFrostedDialog)))
          .colorScheme
          .surface;
      expect(
        settled,
        everyElement(closeTo(color.r * 255, 1)),
        reason: '底板覆盖黑白背景，颜色不得混入背景或遮罩',
      );
      expect(find.byType(BackdropFilter), findsNothing);
      _expectContinuous(entering, settled, '入场末帧');
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      _expectContinuous(await _samples(tester, boundary), settled, '退场首帧');
      await tester.pumpAndSettle();
      expect(find.byType(ReaderFrostedDialog), findsNothing);
    });
  }

  for (final sheet in [false, true]) {
    testWidgets('${sheet ? '底部抽屉' : '居中弹窗'}开合动画复用整块底板和内容的绘制结果', (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 2560 / 3));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  if (sheet) {
                    showReaderBottomSheet<void>(
                      context: context,
                      builder: (_) => const SizedBox(height: 300),
                    );
                  } else {
                    showReaderDialog<void>(
                      context: context,
                      builder: (_) => const ReaderFrostedDialog(
                        child: SizedBox(width: 280, height: 240),
                      ),
                    );
                  }
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pump();
      final surface = tester.renderObject(
        find
            .descendant(
              of: find.byType(ReaderFrostedSurface),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      var paints = 0;
      final previous = debugOnProfilePaint;
      debugOnProfilePaint = (object) {
        previous?.call(object);
        if (identical(object, surface)) paints++;
      };
      try {
        for (final closing in [false, true]) {
          if (closing) navigator.currentState!.pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 32));
          final painted = paints;
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(paints, painted, reason: '位移和缩放不应逐帧重绘底板、阴影和内容');
          await tester.pumpAndSettle();
        }
      } finally {
        debugOnProfilePaint = previous;
      }
      expect(find.byType(ReaderFrostedSurface), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<List<int>> _samples(WidgetTester tester, GlobalKey key) async {
  final rect = tester.getRect(find.byType(ReaderFrostedSurface));
  final image = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(key))
      .toImageSync();
  final bytes = (await tester.runAsync(image.toByteData))!;
  // 取底板内部相邻黑白条纹，避开内容、圆角和边缘阴影。
  final y = (rect.center.dy + 60).round();
  final samples = [
    for (final x in [164, 172, 180, 188])
      bytes.getUint8((y * image.width + x) * 4),
  ];
  image.dispose();
  return samples;
}

void _expectContinuous(List<int> frame, List<int> settled, String phase) {
  for (var i = 0; i < settled.length; i++) {
    expect(frame[i], closeTo(settled[i], 5), reason: '$phase底板不得突变');
  }
}

class _StripeBackground extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 8, size.height),
        Paint()..color = (x ~/ 8).isEven ? Colors.black : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_StripeBackground oldDelegate) => false;
}
