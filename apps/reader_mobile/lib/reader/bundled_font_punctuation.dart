import 'package:flutter/services.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/text/font_punctuation_metrics.dart';

const _songFaces = <(String, int)>[
  ('assets/fonts/SourceHanSerifCN-Regular.otf', 400),
  ('assets/fonts/SourceHanSerifCN-Bold.otf', 700),
];

/// 登记内置宋体的标点轮廓度量，供无 `halt` 特性的静态字库回退使用。
Future<void> registerBundledSongPunctuation({
  String family = FontFamilyAliases.song,
}) async {
  for (final (asset, weight) in _songFaces) {
    final data = await rootBundle.load(asset);
    FontPunctuationRegistry.register(
      family,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      weight: weight,
      italic: false,
      declaredWeight: weight,
    );
  }
}
