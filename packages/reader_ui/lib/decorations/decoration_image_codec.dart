import 'dart:typed_data';
import 'dart:ui' as ui;

import 'decoration_nine_slice.dart';

class ReaderDecorationDecodedImage {
  const ReaderDecorationDecodedImage(this.image, {this.nineSlice});
  final ui.Image image;
  final ReaderDecorationNineSlice? nineSlice;
}

abstract final class ReaderDecorationImageCodec {
  static ReaderDecorationNineSlice pixelAligned(
    ui.Image image,
    ReaderDecorationNineSlice nineSlice,
  ) {
    ui.Rect align(ui.Rect rect) {
      final horizontal = _marker(rect.left, rect.right, image.width);
      final vertical = _marker(rect.top, rect.bottom, image.height);
      return ui.Rect.fromLTRB(
        horizontal.$1 / image.width,
        vertical.$1 / image.height,
        horizontal.$2 / image.width,
        vertical.$2 / image.height,
      );
    }

    return ReaderDecorationNineSlice(
      slice: align(nineSlice.slice),
      content: align(nineSlice.content),
      scale: nineSlice.scale,
    );
  }

  static Future<Uint8List> encodeNinePatch(
    ui.Image image,
    ReaderDecorationNineSlice nineSlice,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(image, const ui.Offset(1, 1), ui.Paint());
    final marks = [
      _marker(nineSlice.slice.left, nineSlice.slice.right, image.width),
      _marker(nineSlice.slice.top, nineSlice.slice.bottom, image.height),
      _marker(nineSlice.content.left, nineSlice.content.right, image.width),
      _marker(nineSlice.content.top, nineSlice.content.bottom, image.height),
    ];
    final black = ui.Paint()..color = const ui.Color(0xFF000000);
    for (final rect in [
      ui.Rect.fromLTWH(
        marks[0].$1 + 1.0,
        0,
        marks[0].$2 - marks[0].$1 + 0.0,
        1,
      ),
      ui.Rect.fromLTWH(
        0,
        marks[1].$1 + 1.0,
        1,
        marks[1].$2 - marks[1].$1 + 0.0,
      ),
      ui.Rect.fromLTWH(
        marks[2].$1 + 1.0,
        image.height + 1.0,
        marks[2].$2 - marks[2].$1 + 0.0,
        1,
      ),
      ui.Rect.fromLTWH(
        image.width + 1.0,
        marks[3].$1 + 1.0,
        1,
        marks[3].$2 - marks[3].$1 + 0.0,
      ),
    ]) {
      canvas.drawRect(rect, black);
    }
    final picture = recorder.endRecording();
    final marked = await picture.toImage(image.width + 2, image.height + 2);
    try {
      final bytes = (await marked.toByteData(format: ui.ImageByteFormat.png))!;
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      picture.dispose();
      marked.dispose();
    }
  }

  static (int, int) _marker(double start, double end, int length) {
    final first = (start * length).round().clamp(0, length - 1);
    return (first, (end * length).round().clamp(first + 1, length));
  }

  static Future<ReaderDecorationDecodedImage> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    late ui.Image image;
    try {
      image = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    if (image.width < 3 || image.height < 3) {
      return ReaderDecorationDecodedImage(image);
    }
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final nineSlice = data == null
        ? null
        : _readMarks(data, image.width, image.height);
    if (nineSlice == null) return ReaderDecorationDecodedImage(image);
    final recorder = ui.PictureRecorder();
    final size = ui.Size(image.width - 2.0, image.height - 2.0);
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(1, 1, size.width, size.height),
      ui.Offset.zero & size,
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
    final picture = recorder.endRecording();
    try {
      final cropped = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      return ReaderDecorationDecodedImage(cropped, nineSlice: nineSlice);
    } finally {
      picture.dispose();
      image.dispose();
    }
  }

  static ReaderDecorationNineSlice? _readMarks(
    ByteData data,
    int width,
    int height,
  ) {
    bool transparent(int left, int top) =>
        data.getUint8((top * width + left) * 4 + 3) == 0;
    if (!transparent(0, 0) ||
        !transparent(width - 1, 0) ||
        !transparent(0, height - 1) ||
        !transparent(width - 1, height - 1)) {
      return null;
    }
    final horizontal = _edge(data, width, width - 2, horizontal: true);
    final vertical = _edge(data, width, height - 2, horizontal: false);
    if (horizontal == null ||
        vertical == null ||
        horizontal.isEmpty ||
        vertical.isEmpty) {
      return null;
    }
    final contentX = _edge(
      data,
      width,
      width - 2,
      horizontal: true,
      opposite: height - 1,
    );
    final contentY = _edge(
      data,
      width,
      height - 2,
      horizontal: false,
      opposite: width - 1,
    );
    if (contentX == null || contentY == null) return null;
    final slice = ui.Rect.fromLTRB(
      horizontal.first / (width - 2),
      vertical.first / (height - 2),
      (horizontal.last + 1) / (width - 2),
      (vertical.last + 1) / (height - 2),
    );
    final content = ui.Rect.fromLTRB(
      contentX.isEmpty ? 0 : contentX.first / (width - 2),
      contentY.isEmpty ? 0 : contentY.first / (height - 2),
      contentX.isEmpty ? 1 : (contentX.last + 1) / (width - 2),
      contentY.isEmpty ? 1 : (contentY.last + 1) / (height - 2),
    );
    return ReaderDecorationNineSlice(slice: slice, content: content);
  }

  static List<int>? _edge(
    ByteData data,
    int width,
    int length, {
    required bool horizontal,
    int opposite = 0,
  }) {
    final marks = <int>[];
    var ended = false;
    for (var index = 0; index < length; index++) {
      final left = horizontal ? index + 1 : opposite;
      final top = horizontal ? opposite : index + 1;
      final offset = (top * width + left) * 4;
      final alpha = data.getUint8(offset + 3);
      if (alpha == 0) {
        if (marks.isNotEmpty) ended = true;
      } else if (alpha == 255 &&
          data.getUint8(offset) == 0 &&
          data.getUint8(offset + 1) == 0 &&
          data.getUint8(offset + 2) == 0 &&
          !ended) {
        marks.add(index);
      } else {
        return null;
      }
    }
    return marks;
  }
}
