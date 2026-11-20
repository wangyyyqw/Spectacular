import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';

import 'txt_models.dart';

/// 失败重试展示各编码的可读前缀，完整正文仍使用严格解码。
List<TxtEncodingCandidate> txtEncodingCandidates(Uint8List sample) {
  final result = <TxtEncodingCandidate>[];
  for (final name in ['UTF-8', 'UTF-16LE', 'UTF-16BE', 'GBK', 'Big5']) {
    try {
      final text = name == 'UTF-8'
          ? utf8.decode(sample)
          : _decodeSample(sample, name);
      if (_readability(text) < 0 && name != 'UTF-8') continue;
      result.add(
        TxtEncodingCandidate(
          name: name,
          sample: text.substring(0, _safeEnd(text, 300)),
        ),
      );
    } on FormatException {
      // 此编码连样例都不能解码，不列为自动推荐项。
    }
  }
  return result;
}

String selectTxtEncoding(Uint8List sample, String? requested) {
  if (requested != null) {
    return switch (requested.toUpperCase().replaceAll('_', '-')) {
      'UTF8' || 'UTF-8' => 'UTF-8',
      'UTF16LE' || 'UTF-16LE' => 'UTF-16LE',
      'UTF16BE' || 'UTF-16BE' => 'UTF-16BE',
      'GBK' || 'GB2312' => 'GBK',
      'BIG5' || 'BIG-5' => 'Big5',
      _ => throw const TxtConversionException('E_TXT_ENCODING', '不支持所选 TXT 编码'),
    };
  }
  if (sample.length >= 2) {
    if (sample[0] == 0xff && sample[1] == 0xfe) return 'UTF-16LE';
    if (sample[0] == 0xfe && sample[1] == 0xff) return 'UTF-16BE';
  }
  if (sample.length >= 3 &&
      sample[0] == 0xef &&
      sample[1] == 0xbb &&
      sample[2] == 0xbf) {
    return 'UTF-8';
  }
  // 前缀可能位于多字节字符中间；最多回退三个字节，完整流仍严格校验。
  final maximumTail = sample.length == 65536 ? 3 : 0;
  for (var tail = 0; tail <= maximumTail && tail < sample.length; tail++) {
    try {
      final text = utf8.decode(sample.sublist(0, sample.length - tail));
      if (!text.contains('\u0000')) return 'UTF-8';
    } on FormatException {
      // 当前候选不成立，继续检测其余字符集。
    }
  }
  final candidates = <({String name, String text, double score})>[];
  for (final name in ['UTF-16LE', 'UTF-16BE', 'GBK', 'Big5']) {
    for (var trim = 0; trim <= (maximumTail == 0 ? 0 : 1); trim++) {
      try {
        final text = _decodeSample(
          sample.sublist(0, sample.length - trim),
          name,
        );
        final score = _readability(text);
        if (score >= 0) candidates.add((name: name, text: text, score: score));
        break;
      } on FormatException {
        // 仅试解码前缀，不允许非法字符进入正式正文。
      }
    }
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  if (candidates.length == 1 ||
      candidates.length > 1 &&
          candidates.first.score - candidates[1].score >= 0.12) {
    return candidates.first.name;
  }
  throw TxtConversionException(
    'E_TXT_ENCODING_AMBIGUOUS',
    '无法确定 TXT 编码，请根据正文样例选择',
    encodingCandidates: [
      for (final candidate in candidates)
        TxtEncodingCandidate(
          name: candidate.name,
          sample: candidate.text.substring(0, _safeEnd(candidate.text, 300)),
        ),
    ],
  );
}

String _decodeSample(List<int> bytes, String encoding) {
  final String text;
  if (encoding == 'GBK') {
    text = const GbkCodec().decode(bytes);
  } else if (encoding == 'Big5') {
    text = const Big5Codec().decode(bytes);
  } else {
    text = _decodeUtf16(bytes, encoding == 'UTF-16LE');
  }
  // Big5 库对未映射双字节仍返回替代符；Unicode 编码中的真实 U+FFFD 保留。
  if (encoding == 'Big5' && text.contains('\ufffd')) {
    throw const FormatException('无法解码的 Big5 字符');
  }
  return text;
}

double _readability(String text) {
  if (text.isEmpty || text.contains('\u0000')) return -1;
  const common =
      '的一是不了在人有我他这這个個们們中来來上大为為和国國地到以说說时時要就出会會可也你对對生能而子那得于於着著下自之年过過发發后後作里裡用道行所然家种種事成方多经經么麼去法学學如都同现現当當没沒动動面起看定天分还還进進好小部其些主样樣理心她本前开開但因只从從想实實日军軍者意无無力它与與长長把机機十民第公此已工使情明性知全三又关關点點正业業外将將两兩高间間由问問很最重并並物手应應战戰向头頭文体體政美相见見被利什二等产產或新己制身果加西斯月话話合回特代内內信表化老给給世位次度门門任常先海通教儿兒原东東声聲提立及比员員解水名真论論处處走义義各入几幾口认認条條平系气氣题題活尔爾更别別打女变變四神总總何电電数數安少报報才结結反受目太量再感建务務做接必场場件计計管期市直德资資命山金指克许許统統区區保至队隊形社便空决決治展马馬科司五基眼书書非则則听聽白却卻界达達光放强強即像难難且权權思王象完设設式色路记記南品住告类類求据據程北边邊死张張该該交规規万萬取拉格望觉覺术術领領共确確传傳师師观觀清今切院让讓识識候带帶导導争運笑飞飛风風云雲章卷节節回夜梦夢雨红紅黄黃龙龍';
  var readable = 0, frequent = 0, count = 0;
  for (final rune in text.runes) {
    count++;
    if (rune < 32 && rune != 9 && rune != 10 && rune != 13) return -1;
    if (rune == 0xfffd || rune >= 0xe000 && rune <= 0xf8ff) return -1;
    if (rune >= 32 && rune < 127 ||
        rune == 9 ||
        rune == 10 ||
        rune == 13 ||
        rune >= 0x3000 && rune <= 0x9fff ||
        rune >= 0xff01 && rune <= 0xffef) {
      readable++;
    }
    if (common.contains(String.fromCharCode(rune))) frequent++;
  }
  return readable / count * 0.4 + frequent / count * 0.6;
}

Stream<String> decodeTxtStream(Stream<List<int>> input, String encoding) {
  if (encoding == 'UTF-8') return utf8.decoder.bind(input);
  if (encoding == 'GBK') return const GbkCodec().decoder.bind(input);
  return _decodeChunks(input, encoding);
}

Stream<String> _decodeChunks(Stream<List<int>> input, String encoding) async* {
  var pending = <int>[];
  await for (final bytes in input) {
    final chunk = [...pending, ...bytes];
    var end = chunk.length;
    if (encoding == 'Big5') {
      var position = 0;
      while (position < end) {
        position += chunk[position] < 0x80 ? 1 : 2;
      }
      if (position > end) end--;
    } else {
      end -= end % 2;
      if (end >= 2) {
        final last = encoding == 'UTF-16LE'
            ? chunk[end - 2] | chunk[end - 1] << 8
            : chunk[end - 2] << 8 | chunk[end - 1];
        if (last >= 0xd800 && last <= 0xdbff) end -= 2;
      }
    }
    pending = chunk.sublist(end);
    if (end == 0) continue;
    yield _decodeSample(chunk.sublist(0, end), encoding);
  }
  if (pending.isNotEmpty) throw const FormatException('文件末尾含不完整字符');
}

String _decodeUtf16(List<int> bytes, bool littleEndian) {
  if (bytes.length.isOdd) throw const FormatException('UTF-16 字节数不完整');
  final units = <int>[];
  for (var i = 0; i < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | bytes[i + 1] << 8
          : bytes[i] << 8 | bytes[i + 1],
    );
  }
  for (var i = 0; i < units.length; i++) {
    if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
      if (++i == units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        throw const FormatException('UTF-16 代理对不完整');
      }
    } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
      throw const FormatException('UTF-16 代理对不完整');
    }
  }
  return String.fromCharCodes(units);
}

int _safeEnd(String text, int end) {
  end = end.clamp(0, text.length);
  if (end > 0 &&
      end < text.length &&
      text.codeUnitAt(end - 1) >= 0xd800 &&
      text.codeUnitAt(end - 1) <= 0xdbff) {
    return end - 1;
  }
  return end;
}
