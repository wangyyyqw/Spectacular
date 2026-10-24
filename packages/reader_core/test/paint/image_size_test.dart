import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/image_size.dart';

Uint8List _png(int width, int height) {
  final data = ByteData(24)
    ..setUint8(0, 0x89)
    ..setUint8(1, 0x50)
    ..setUint8(2, 0x4E)
    ..setUint8(3, 0x47)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return data.buffer.asUint8List();
}

Uint8List _jpeg(int width, int height) {
  final data = ByteData(15)
    ..setUint8(0, 0xFF)
    ..setUint8(1, 0xD8) // SOI
    ..setUint8(2, 0xFF)
    ..setUint8(3, 0xC0) // SOF0
    ..setUint16(4, 11) // 段长
    ..setUint16(7, height)
    ..setUint16(9, width)
    ..setUint8(13, 0xFF)
    ..setUint8(14, 0xDA); // SOS（截断即可，只读头）
  return data.buffer.asUint8List();
}

Uint8List _gif(int width, int height) {
  final data = ByteData(12)
    ..setUint8(0, 0x47)
    ..setUint8(1, 0x49)
    ..setUint8(2, 0x46) // 'GIF'
    ..setUint16(6, width, Endian.little)
    ..setUint16(8, height, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _bmp(int width, int height) {
  final data = ByteData(26)
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4D) // 'BM'
    ..setUint32(18, width, Endian.little)
    ..setUint32(22, height, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _webpVp8x(int width, int height) {
  final data = ByteData(30)
    ..setUint8(0, 0x52)
    ..setUint8(1, 0x49)
    ..setUint8(2, 0x46)
    ..setUint8(3, 0x46) // 'RIFF'
    ..setUint8(8, 0x57)
    ..setUint8(9, 0x45)
    ..setUint8(10, 0x42)
    ..setUint8(11, 0x50) // 'WEBP'
    ..setUint8(12, 0x56)
    ..setUint8(13, 0x50)
    ..setUint8(14, 0x38)
    ..setUint8(15, 0x58) // 'VP8X'
    ..setUint8(24, (width - 1) & 0xFF)
    ..setUint8(25, ((width - 1) >> 8) & 0xFF)
    ..setUint8(26, ((width - 1) >> 16) & 0xFF)
    ..setUint8(27, (height - 1) & 0xFF)
    ..setUint8(28, ((height - 1) >> 8) & 0xFF)
    ..setUint8(29, ((height - 1) >> 16) & 0xFF);
  return data.buffer.asUint8List();
}

Uint8List _webpVp8(int width, int height) {
  final data = ByteData(30)
    ..setUint8(0, 0x52)
    ..setUint8(1, 0x49)
    ..setUint8(2, 0x46)
    ..setUint8(3, 0x46) // RIFF
    ..setUint8(8, 0x57)
    ..setUint8(9, 0x45)
    ..setUint8(10, 0x42)
    ..setUint8(11, 0x50) // WEBP
    ..setUint8(12, 0x56)
    ..setUint8(13, 0x50)
    ..setUint8(14, 0x38)
    ..setUint8(15, 0x20) // 'VP8 '
    ..setUint8(23, 0x9D)
    ..setUint8(24, 0x01)
    ..setUint8(25, 0x2A) // 起始码
    ..setUint16(26, width, Endian.little)
    ..setUint16(28, height, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _webpVp8l(int width, int height) {
  final data = ByteData(30)
    ..setUint8(0, 0x52)
    ..setUint8(1, 0x49)
    ..setUint8(2, 0x46)
    ..setUint8(3, 0x46)
    ..setUint8(8, 0x57)
    ..setUint8(9, 0x45)
    ..setUint8(10, 0x42)
    ..setUint8(11, 0x50)
    ..setUint8(12, 0x56)
    ..setUint8(13, 0x50)
    ..setUint8(14, 0x38)
    ..setUint8(15, 0x4C) // 'VP8L'
    ..setUint8(20, 0x2F) // 签名
    ..setUint32(21, ((height - 1) << 14) | (width - 1), Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  group('readImageSize 头解析（P3-07）', () {
    test('五种格式头解析', () {
      expect(ImageSizeParser.readImageSize(_png(300, 200))!.width, 300);
      expect(ImageSizeParser.readImageSize(_png(300, 200))!.height, 200);
      expect(ImageSizeParser.readImageSize(_jpeg(640, 480))!.width, 640);
      expect(ImageSizeParser.readImageSize(_jpeg(640, 480))!.height, 480);
      expect(ImageSizeParser.readImageSize(_gif(88, 31))!.height, 31);
      expect(ImageSizeParser.readImageSize(_bmp(100, 50))!.width, 100);
      expect(ImageSizeParser.readImageSize(_webpVp8x(1000, 7))!.height, 7);
      expect(ImageSizeParser.readImageSize(_webpVp8(320, 240))!.width, 320);
      expect(ImageSizeParser.readImageSize(_webpVp8l(500, 300))!.height, 300);
    });

    test('不支持/损坏/空字节返回 null', () {
      expect(ImageSizeParser.readImageSize(Uint8List(0)), isNull);
      expect(
        ImageSizeParser.readImageSize(Uint8List.fromList(List.filled(64, 1))),
        isNull,
      );
      expect(ImageSizeParser.readImageSize(_png(0, 100)), isNull,
          reason: '宽 0 视为无效头');
      expect(ImageSizeParser.readImageSize(_png(100, 0)), isNull);
      expect(ImageSizeParser.readImageSize(Uint8List.fromList(_png(10, 10).sublist(0, 16))),
          isNull, reason: '头截断');
    });
  });

  group('computeImageDisplaySize 四类验收（P3-07）', () {
    test('有宽高：直接使用', () {
      final size = ImageDisplaySizing.compute(
        maxWidth: 320,
        intrinsicWidth: 200,
        intrinsicHeight: 100,
        cssWidth: 80,
        cssHeight: 40,
      );
      expect(size.width, 80);
      expect(size.height, 40);
    });

    test('单边：另一维按原始比例推出', () {
      final byWidth = ImageDisplaySizing.compute(
        maxWidth: 320,
        intrinsicWidth: 200,
        intrinsicHeight: 100,
        cssWidth: 160,
      );
      expect(byWidth.width, 160);
      expect(byWidth.height, 80);
      final byHeight = ImageDisplaySizing.compute(
        maxWidth: 320,
        intrinsicWidth: 200,
        intrinsicHeight: 100,
        cssHeight: 50,
      );
      expect(byHeight.width, 100);
      expect(byHeight.height, 50);
    });

    test('auto：原始尺寸，不放大，超容器缩到贴边', () {
      final fits = ImageDisplaySizing.compute(
        maxWidth: 320,
        intrinsicWidth: 200,
        intrinsicHeight: 100,
      );
      expect(fits.width, 200);
      expect(fits.height, 100);
      final shrunk = ImageDisplaySizing.compute(
        maxWidth: 150,
        intrinsicWidth: 200,
        intrinsicHeight: 100,
      );
      expect(shrunk.width, 150);
      expect(shrunk.height, 75);
      final noIntrinsic = ImageDisplaySizing.compute(maxWidth: 300);
      expect(noIntrinsic.width, 300);
      expect(noIntrinsic.height, 150, reason: '无原始尺寸按 2:1 默认占位');
    });

    test('超容器：指定尺寸也按比例缩到贴边（含高度约束）', () {
      final size = ImageDisplaySizing.compute(
        maxWidth: 320,
        maxHeight: 200,
        intrinsicWidth: 200,
        intrinsicHeight: 100,
        cssWidth: 640,
        cssHeight: 480,
      );
      // 先按宽缩：320×240，再按高缩：266.7×200。
      expect(size.width, closeTo(266.67, 0.01));
      expect(size.height, 200);
    });

    test('单边指定但无原始尺寸：另一维取同值（正方形占位）', () {
      final size = ImageDisplaySizing.compute(
        maxWidth: 320,
        cssWidth: 120,
      );
      expect(size.width, 120);
      expect(size.height, 120);
    });
  });
}
