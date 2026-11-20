import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/curl3d_geometry.dart';
import 'package:reader_ui/paging/curl3d_painter.dart';
import 'package:reader_ui/paging/duokan_curl_shader.dart';

/// 单独观察正式绘制入口的阴影，避免纸面遮住公共边上的漏画。
class _ShadowGeometry extends Curl3dGeometry {
  _ShadowGeometry(Curl3dGeometry geometry, List<Curl3dShadowSample> samples)
    : _samples = samples,
      super(size: geometry.size, grab: geometry.grab, touch: geometry.touch);

  final List<Curl3dShadowSample> _samples;

  @override
  List<Curl3dStrip> get strips => const [];

  @override
  List<Curl3dShadowSample> get dropShadow => _samples;

  @override
  List<Curl3dShadowSample> get selfShadow => const [];
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

double? _alphaAt(List<Curl3dShadowSample> triangle, Offset point) {
  final a = triangle[0];
  final b = triangle[1].position - a.position;
  final c = triangle[2].position - a.position;
  final area = _cross(b, c);
  if (area.abs() < 1e-8) return null;
  final p = point - a.position;
  final v = _cross(p, c) / area;
  final w = _cross(b, p) / area;
  if (v < 0 || w < 0 || v + w > 1) return null;
  return a.alpha +
      v * (triangle[1].alpha - a.alpha) +
      w * (triangle[2].alpha - a.alpha);
}

/// 检查公共边附近的像素是否只混合一次，兼顾白色漏缝与黑色重叠。
Future<void> verifyCurlShadowSeams({
  Future<void> Function(String, ui.Image)? capture,
}) async {
  await DuokanCurlShader.load();
  const size = Size(768, 830);
  const ratio = 1.75;
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  final picture = recorder.endRecording();
  final paper = picture.toImageSync(768, 830);
  picture.dispose();
  try {
    for (final dx in [0.0, 0.37, 0.74]) {
      final geometry = Curl3dGeometry(
        size: size,
        grab: const Offset(768, 800),
        touch: Offset(470 + dx, 570 + dx),
      );
      for (final self in [false, true]) {
        final samples = self ? geometry.selfShadow : geometry.dropShadow;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(ratio);
        Curl3dPainter(paperColor: const Color(0xFFFFFFFF)).paint(
          canvas,
          paper,
          paper,
          geometry: _ShadowGeometry(geometry, samples),
          mirror: false,
        );
        final picture = recorder.endRecording();
        final width = (size.width * ratio).ceil();
        final image = await picture.toImage(
          width,
          (size.height * ratio).ceil(),
        );
        picture.dispose();
        try {
          await capture?.call('${self ? 'self' : 'drop'}-$dx', image);
          final data = (await image.toByteData())!;
          var checked = 0;
          for (var edge = 2; edge < samples.length - 1; edge++) {
            final a = samples[edge - 1].position;
            final b = samples[edge].position;
            for (var step = 1; step < 40; step++) {
              final p = Offset.lerp(a, b, step / 40)!;
              final x = (p.dx * ratio).floor();
              final y = (p.dy * ratio).floor();
              if (x < 1 ||
                  y < 1 ||
                  x >= width - 1 ||
                  y >= (size.height * ratio).floor() - 1) {
                continue;
              }
              final center = Offset((x + 0.5) / ratio, (y + 0.5) / ratio);
              double? alpha;
              var owners = 0;
              for (var index = 2; index < samples.length; index++) {
                final value = _alphaAt(
                  samples.sublist(index - 2, index + 1),
                  center,
                );
                if (value != null) {
                  alpha = value;
                  owners++;
                }
              }
              if (owners != 1 || alpha! < 0.03) continue;
              final expected = 255 - (alpha * 255).round();
              final actual = data.getUint8((y * width + x) * 4);
              expect(
                (actual - expected).abs(),
                lessThanOrEqualTo(2),
                reason:
                    '${self ? '自阴影' : '投影'}帧 $dx 公共边 $edge ($x,$y)，'
                    '应只混合一次，实际 $actual，预期 $expected',
              );
              checked++;
            }
          }
          expect(checked, greaterThan(100));
        } finally {
          image.dispose();
        }
      }
    }
  } finally {
    paper.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('高 DPI 卷页的两类阴影公共边连续且不重复混合', verifyCurlShadowSeams);
}
