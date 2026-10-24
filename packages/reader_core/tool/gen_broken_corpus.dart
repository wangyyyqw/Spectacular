// 生成破损书样本集到 test_corpus/broken/（P3-28）。
//
// 运行：cd packages/reader_core && dart run tool/gen_broken_corpus.dart
//
// 样本构造与 test/support/broken_samples.dart 共享（单一来源），
// 期望分级见该文件的 brokenExpectations；回归断言在
// test/epub/broken_corpus_test.dart（可重复运行）。
import 'dart:io';

import '../test/support/broken_samples.dart';

void main() {
  final out = Directory('../../test_corpus/broken');
  out.createSync(recursive: true);
  for (final entry in brokenSamples.entries) {
    final file = File('${out.path}/${entry.key}');
    file.writeAsBytesSync(entry.value);
    // ignore: avoid_print
    print('写入 ${file.path}（${entry.value.length} 字节）');
  }
  // ignore: avoid_print
  print('完成：${brokenSamples.length} 本 → ${out.path}');
}
