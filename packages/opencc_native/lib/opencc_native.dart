import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>(
  symbol: 'spectacular_opencc_convert',
)
external Pointer<Utf8> _convert(Pointer<Utf8> config, Pointer<Utf8> text);

@Native<Void Function(Pointer<Utf8>)>(symbol: 'spectacular_opencc_free')
external void _free(Pointer<Utf8> text);

/// 原生转换结果；每一级记录来源片段与目标片段的 UTF-16 长度。
typedef NativeOpenccResult = ({String text, List<List<(int, int)>> stages});

/// 由 OpenCC 的实际分词与转换轨迹提供偏移，不根据转换后全文猜测位置。
NativeOpenccResult convertOpencc(String configPath, String text) {
  if (text.isEmpty) return (text: text, stages: const []);
  final config = configPath.toNativeUtf8();
  final input = text.toNativeUtf8();
  Pointer<Utf8> result = nullptr;
  try {
    result = _convert(config, input);
    if (result == nullptr) throw StateError('OpenCC 无法分配转换结果');
    final json = jsonDecode(result.toDartString());
    if (json is Map<String, dynamic>) {
      throw StateError('OpenCC 转换失败：${json['error']}');
    }
    final values = json as List<dynamic>;
    return (
      text: values[0] as String,
      stages: [
        for (final stage in values[1] as List<dynamic>)
          [
            for (final pair in stage as List<dynamic>)
              ((pair as List<dynamic>)[0] as int, pair[1] as int),
          ],
      ],
    );
  } finally {
    if (result != nullptr) _free(result);
    calloc.free(config);
    calloc.free(input);
  }
}
