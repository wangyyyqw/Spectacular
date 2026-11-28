import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_selection_ocr.dart';

void main() {
  test('相同行图复用在途及已完成结果，不同图像重新识别', () async {
    final pending =
        Completer<List<({String text, Rect bounds, double confidence})>>();
    var calls = 0;
    final ocr = ReaderSelectionOcr(
      recognize: (_) {
        calls++;
        return pending.future;
      },
    );
    final first = ocr.recognize(Uint8List.fromList([1, 2, 3]));
    final same = ocr.recognize(Uint8List.fromList([1, 2, 3]));
    expect(calls, 1);
    pending.complete([(text: '正确文字', bounds: Rect.zero, confidence: .99)]);
    expect(await first, '正确文字');
    expect(await same, '正确文字');
    expect(await ocr.recognize(Uint8List.fromList([1, 2, 3])), '正确文字');
    expect(calls, 1);
    await ocr.recognize(Uint8List.fromList([1, 2, 4]));
    expect(calls, 2, reason: '换字体或选区后图片不同，不得复用旧文字');
  });

  test('失败结果不缓存，成功缓存有上限', () async {
    var calls = 0;
    final ocr = ReaderSelectionOcr(
      recognize: (_) async {
        if (++calls == 1) throw StateError('模型失败');
        return [(text: '正常文字', bounds: Rect.zero, confidence: .99)];
      },
    );
    final image = Uint8List.fromList([0]);
    await expectLater(ocr.recognize(image), throwsStateError);
    expect(await ocr.recognize(image), '正常文字');
    expect(calls, 2);
    for (var i = 1; i <= 64; i++) {
      await ocr.recognize(Uint8List.fromList([i]));
    }
    await ocr.recognize(image);
    expect(calls, 67, reason: '超过 64 行时最早结果已淘汰');
  });

  test('低置信度不缓存，重试仍执行识别', () async {
    var calls = 0;
    final ocr = ReaderSelectionOcr(
      recognize: (_) async => [
        (text: '可能误字', bounds: Rect.zero, confidence: ++calls == 1 ? .5 : .99),
      ],
    );
    final image = Uint8List.fromList([7]);
    await expectLater(ocr.recognize(image), throwsFormatException);
    expect(await ocr.recognize(image), '可能误字');
    expect(calls, 2);
  });

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
