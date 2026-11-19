import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

enum ChineseConversion { simplifiedToTraditional, traditionalToSimplified }

class ChineseDictionary {
  ChineseDictionary(this.entries)
    : maxLength = entries.keys.fold(
        1,
        (length, key) => key.length > length ? key.length : length,
      );

  final Map<String, String> entries;
  final int maxLength;

  static Future<ChineseDictionary> load(ChineseConversion conversion) async {
    final prefix = conversion == ChineseConversion.simplifiedToTraditional
        ? 'ST'
        : 'TS';
    final entries = <String, String>{};
    for (final suffix in ['Characters', 'Phrases']) {
      final data = await rootBundle.load(
        'packages/spectacular_epub_tools/assets/opencc/$prefix$suffix.txt.gz',
      );
      final text = utf8.decode(
        GZipDecoder().decodeBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
      for (final line in const LineSplitter().convert(text)) {
        if (line.startsWith('#')) continue;
        final columns = line.split('\t');
        if (columns.length < 2 || columns.first.isEmpty) continue;
        entries[columns.first] = columns[1].trim().split(RegExp(r'\s+')).first;
      }
    }
    return ChineseDictionary(entries);
  }

  String convert(String text) {
    final result = StringBuffer();
    var offset = 0;
    while (offset < text.length) {
      String? replacement;
      var length = (text.length - offset).clamp(1, maxLength);
      for (; length > 0; length--) {
        replacement = entries[text.substring(offset, offset + length)];
        if (replacement != null) break;
      }
      result.write(replacement ?? text[offset]);
      offset += replacement == null ? 1 : length;
    }
    return result.toString();
  }
}
