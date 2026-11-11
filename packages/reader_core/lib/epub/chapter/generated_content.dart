import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/selector.dart';

/// `content` 值求值（W20）：字符串字面量、attr()、counter()/counters()、
/// open-quote/close-quote、url() 可任意拼接（CSS 2.1 §12.2）。
/// url() 生成 U+FFFC 占位符，并记录图片在图中的位置。
PseudoContent evaluateContentValue(
  String raw, {
  required List<SelectorElement> ancestors,
  required CssQuotes quotes,
  required int quoteDepth,
  required String Function(String name, String style) counterValue,
}) {
  final element = ancestors.isEmpty ? null : ancestors.last;
  (String, String) pairAt(int depth) {
    switch (quotes) {
      case CssQuotesNone():
        return ('', '');
      case CssQuotesPairs(:final pairs):
        final pair = pairs[depth.clamp(0, pairs.length - 1)];
        return (pair.open, pair.close);
      case CssQuotesAuto():
        return depth == 0 ? ('\u201C', '\u201D') : ('\u2018', '\u2019');
    }
  }

  final out = StringBuffer();
  final images = <PseudoContentImage>[];
  var i = 0;
  while (i < raw.length) {
    final ch = raw[i];
    if (ch == '"' || ch == "'") {
      final end = raw.indexOf(ch, i + 1);
      if (end < 0) {
        break;
      }
      out.write(raw.substring(i + 1, end));
      i = end + 1;
      continue;
    }
    if (ch.trim().isEmpty) {
      i += 1;
      continue;
    }
    final start = i;
    var depth = 0;
    while (i < raw.length) {
      final c = raw[i];
      if (c == '(') {
        depth += 1;
      } else if (c == ')') {
        depth -= 1;
      } else if (depth == 0 && c.trim().isEmpty) {
        break;
      }
      i += 1;
    }
    final token = raw.substring(start, i).trim();
    if (token.isEmpty) {
      continue;
    }
    final lowerToken = token.toLowerCase();
    if (token == 'open-quote') {
      out.write(pairAt(quoteDepth).$1);
    } else if (token == 'close-quote') {
      out.write(pairAt(quoteDepth).$2);
    } else if (token == 'no-open-quote' || token == 'no-close-quote') {
      continue;
    } else if (token.startsWith('attr(') && token.endsWith(')')) {
      final name = token.substring(5, token.length - 1).trim();
      out.write(element?.attributes[name] ?? '');
    } else if (token.startsWith('counter(') && token.endsWith(')')) {
      final args = token
          .substring(8, token.length - 1)
          .split(',')
          .map((part) => part.trim())
          .toList();
      out.write(
        counterValue(args.first, args.length > 1 ? args[1] : 'decimal'),
      );
    } else if (token.startsWith('counters(') && token.endsWith(')')) {
      final args = token
          .substring(9, token.length - 1)
          .split(',')
          .map((part) => part.trim())
          .toList();
      out.write(
        counterValue(args.first, args.length > 2 ? args[2] : 'decimal'),
      );
    } else if (lowerToken.startsWith('url(') && token.endsWith(')')) {
      var url = token.substring(4, token.length - 1).trim();
      if (url.length >= 2 &&
          ((url.startsWith('"') && url.endsWith('"')) ||
              (url.startsWith("'") && url.endsWith("'")))) {
        url = url.substring(1, url.length - 1).trim();
      }
      if (url.isEmpty || url.toLowerCase() == 'none') {
        continue;
      }
      out.write('\uFFFC');
      images.add(PseudoContentImage(offset: out.length - 1, url: url));
    }
  }
  return PseudoContent(
    text: out.toString(),
    images: List<PseudoContentImage>.unmodifiable(images),
  );
}

/// `counter(name, upper-alpha)` 之类的字母计数（1 起）。
String alphaCounter(int value) {
  if (value <= 0) {
    return '$value';
  }
  final codes = <int>[];
  var n = value;
  while (n > 0) {
    final rem = (n - 1) % 26;
    codes.add(65 + rem);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(codes.reversed);
}

/// `counter(name, upper-roman)` 的罗马数字（1..3999）。
String romanCounter(int value) {
  if (value <= 0 || value > 3999) {
    return '$value';
  }
  const numerals = <(int, String)>[
    (1000, 'M'),
    (900, 'CM'),
    (500, 'D'),
    (400, 'CD'),
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  final buffer = StringBuffer();
  var n = value;
  for (final (amount, symbol) in numerals) {
    while (n >= amount) {
      buffer.write(symbol);
      n -= amount;
    }
  }
  return buffer.toString();
}

bool isWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

/// `<q>` 生成的单个引号，用于同步扩写文本并重映射行内偏移。
class QuoteInsertion {
  const QuoteInsertion({
    required this.offset,
    required this.text,
    required this.depth,
    required this.opening,
  });

  final int offset;
  final String text;
  final int depth;
  final bool opening;
}

/// 生成内容的文本与图片占位位置。
class PseudoContent {
  const PseudoContent({required this.text, required this.images});

  final String text;
  final List<PseudoContentImage> images;
}

/// 生成内容中的单张图片；[offset] 指向文本里的 U+FFFC。
class PseudoContentImage {
  const PseudoContentImage({required this.offset, required this.url});

  final int offset;
  final String url;
}

/// 伪元素图片在扩写、浮动摘除和切片后的当前块内位置。
class PseudoImageMark {
  const PseudoImageMark({
    required this.offset,
    required this.url,
    required this.pseudo,
  });

  final int offset;
  final String url;
  final String pseudo;
}
