import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_selection_ocr.dart';

void main() {
  test('识别行按阅读顺序拼接，低置信度与空结果拒绝执行', () async {
    final ocr = ReaderSelectionOcr(
      recognize: (_) async => [
        (
          text: '第二行',
          bounds: const Rect.fromLTWH(0, 40, 80, 20),
          confidence: .99,
        ),
        (
          text: '第一行',
          bounds: const Rect.fromLTWH(0, 0, 80, 20),
          confidence: .99,
        ),
      ],
    );
    expect(await ocr.recognize(Uint8List(0)), '第一行第二行');
    for (final confidence in [.2, .74]) {
      final low = ReaderSelectionOcr(
        recognize: (_) async => [
          (
            text: '不可靠',
            bounds: const Rect.fromLTWH(0, 0, 40, 20),
            confidence: confidence,
          ),
        ],
      );
      await expectLater(low.recognize(Uint8List(0)), throwsFormatException);
    }
    await expectLater(
      ReaderSelectionOcr(recognize: (_) async => []).recognize(Uint8List(0)),
      throwsFormatException,
    );
  });
}
