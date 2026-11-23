import 'package:flutter/painting.dart';

bool _readerTextWarmedUp = false;

/// 预热正文所需的内置中文字体。
///
/// Flutter 首次用某个字族排版中文时会同步解析字体，真机上单个字族的
/// 首次排版可占用主线程数百毫秒。启动阶段先用正文常见字号排一行，
/// 把这次一次性成本放到首帧之前，避免打开书籍时出现长帧。
void warmUpReaderTextRendering() {
  if (_readerTextWarmedUp) {
    return;
  }
  final painter = TextPainter(
    text: const TextSpan(
      text: '第一章',
      style: TextStyle(
        fontFamily: 'builtin_song',
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  try {
    painter.layout(maxWidth: 344);
  } finally {
    painter.dispose();
  }
  _readerTextWarmedUp = true;
}
