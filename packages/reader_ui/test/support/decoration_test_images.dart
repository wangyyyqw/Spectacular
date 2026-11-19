import 'dart:typed_data';
import 'dart:ui' as ui;

Future<Uint8List> ninePatchTestBytes({int width = 32, int height = 22}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(1, 1, width - 2.0, height - 2.0),
    ui.Paint()..color = const ui.Color(0xFFCCCCCC),
  );
  for (final (rect, color) in [
    (const ui.Rect.fromLTWH(1, 1, 5, 5), 0xFFFF0000),
    (ui.Rect.fromLTWH(width - 6.0, 1, 5, 5), 0xFF0000FF),
    (ui.Rect.fromLTWH(1, height - 6.0, 5, 5), 0xFF00FF00),
    (ui.Rect.fromLTWH(width - 6.0, height - 6.0, 5, 5), 0xFFFFFF00),
  ]) {
    canvas.drawRect(rect, ui.Paint()..color = ui.Color(color));
  }
  for (final rect in [
    ui.Rect.fromLTWH(6, 0, width - 12.0, 1),
    ui.Rect.fromLTWH(0, 6, 1, height - 12.0),
    ui.Rect.fromLTWH(9, height - 1.0, width - 18.0, 1),
    ui.Rect.fromLTWH(width - 1.0, 8, 1, height - 16.0),
  ]) {
    canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFF000000));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}
