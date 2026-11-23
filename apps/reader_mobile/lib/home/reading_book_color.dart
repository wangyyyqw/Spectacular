import 'package:flutter/material.dart';

const _bookPalette = [
  Color(0xFF397665),
  Color(0xFF417786),
  Color(0xFF95634F),
  Color(0xFFA3413F),
  Color(0xFF70658E),
  Color(0xFF77723F),
];

/// 同一本书在阅读日历与时长图表中使用一致的识别色。
Color readingBookColor(
  String bookId, {
  Brightness brightness = Brightness.light,
}) {
  var hash = 0;
  for (final unit in bookId.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  final color = _bookPalette[hash % _bookPalette.length];
  return brightness == Brightness.dark
      ? Color.lerp(color, Colors.white, .3)!
      : color;
}
