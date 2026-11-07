import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'cfi.dart';

/// 当前正文聚合与锚点坐标语义版本。
///
/// 解析、行内块提升或空白处理变化时递增；旧锚点读取后先用原文证据
/// 核验，不能仅凭旧 CFI 当作精确位置。
const String currentAnchorSemanticVersion = 'text-2';

/// 阅读器实际使用的文本块；CFI 偏移沿用现有块内 UTF-16 坐标。
class AnchorBlock {
  const AnchorBlock({required this.cfi, required this.text});

  final String cfi;
  final String text;
}

/// 匹配文本与原始阅读文本之间的偏移映射。
class NormalizedAnchorText {
  NormalizedAnchorText(String source) {
    final output = StringBuffer();
    var previousSpace = false;
    for (var i = 0; i < source.length; i++) {
      final space = _space.hasMatch(source[i]);
      if (space && previousSpace) {
        _ends[_ends.length - 1] = i + 1;
        continue;
      }
      output.write(space ? ' ' : source[i]);
      _starts.add(i);
      _ends.add(i + 1);
      previousSpace = space;
    }
    text = output.toString();
    sourceLength = source.length;
  }

  static final _space = RegExp(r'\s|\u00a0', unicode: true);
  late final String text;
  late final int sourceLength;
  final List<int> _starts = [];
  final List<int> _ends = [];

  int rawStart(int offset) => offset >= text.length
      ? sourceLength
      : _starts[offset.clamp(0, text.length)];

  int rawEnd(int offset) =>
      offset <= 0 ? 0 : _ends[offset.clamp(0, text.length) - 1];

  int normalizedOffset(int rawOffset) {
    var low = 0;
    var high = _starts.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_starts[middle] < rawOffset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

String normalizeAnchorText(String text) => NormalizedAnchorText(text).text;

String anchorFingerprint(String text) =>
    sha256.convert(utf8.encode(normalizeAnchorText(text))).toString();

/// 以实际章节文本构造索引，不需要分页或排版全书。
class AnchorChapter {
  AnchorChapter({
    required this.spineIndex,
    required this.href,
    this.title = '',
    required List<AnchorBlock> blocks,
    this.readable = true,
  }) : blocks = List.unmodifiable(blocks) {
    var offset = 0;
    for (final block in blocks) {
      blockStarts.add(offset);
      offset += block.text.length;
    }
    text = blocks.map((block) => block.text).join();
    normalized = NormalizedAnchorText(text);
    fingerprint = anchorFingerprint(text);
    paragraphFingerprints = List.unmodifiable(
      blocks.map((block) => anchorFingerprint(block.text)),
    );
  }

  final int spineIndex;
  final String href;
  final String title;
  final bool readable;
  final List<AnchorBlock> blocks;
  final List<int> blockStarts = [];
  late final String text;
  late final NormalizedAnchorText normalized;
  late final String fingerprint;
  late final List<String> paragraphFingerprints;

  int? offsetFor(String cfi) {
    final base = cfiBase(cfi);
    final offset = cfiCharOffset(cfi) ?? 0;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (cfiBase(block.cfi) != base) continue;
      final local = offset - (cfiCharOffset(block.cfi) ?? 0);
      if (local >= 0 && local <= block.text.length) {
        return blockStarts[i] + local;
      }
    }
    return null;
  }

  String? cfiAt(int offset, {bool end = false}) {
    if (blocks.isEmpty || offset < 0 || offset > text.length) return null;
    final safe = utf16Boundary(text, offset, forward: end);
    for (var i = 0; i < blocks.length; i++) {
      final length = blocks[i].text.length;
      final local = safe - blockStarts[i];
      if (local < 0 || local > length) continue;
      if (local == length && !end && i + 1 < blocks.length) continue;
      return cfiWithCharOffset(
        blocks[i].cfi,
        local + (cfiCharOffset(blocks[i].cfi) ?? 0),
      );
    }
    return null;
  }

  String paragraphFingerprintAt(int offset) {
    for (var i = blocks.length - 1; i >= 0; i--) {
      if (offset >= blockStarts[i]) return paragraphFingerprints[i];
    }
    return '';
  }
}

/// 所有偏移均指向原始文本，查找归一化后的文字时必须反向映射。
class AnchorPoint {
  const AnchorPoint({
    required this.cfi,
    required this.spineIndex,
    required this.href,
    required this.title,
    required this.chapterFingerprint,
    required this.paragraphFingerprint,
    required this.charOffset,
    required this.chapterLength,
    required this.quote,
    required this.contextBefore,
    required this.contextAfter,
  });

  final String cfi;
  final int spineIndex;
  final String href;
  final String title;
  final String chapterFingerprint;
  final String paragraphFingerprint;
  final int charOffset;
  final int chapterLength;
  final String quote;
  final String contextBefore;
  final String contextAfter;

  Map<String, Object?> toJson() => {
    'cfi': cfi,
    'spineIndex': spineIndex,
    'href': href,
    'title': title,
    'chapterFingerprint': chapterFingerprint,
    'paragraphFingerprint': paragraphFingerprint,
    'charOffset': charOffset,
    'chapterLength': chapterLength,
    'quote': quote,
    'contextBefore': contextBefore,
    'contextAfter': contextAfter,
  };

  factory AnchorPoint.fromJson(Map<String, dynamic> json) {
    final offset = json['charOffset'] as int;
    final length = json['chapterLength'] as int;
    final spine = json['spineIndex'] as int;
    if (offset < 0 || length < 0 || offset > length || spine < 0) {
      throw const FormatException('锚点偏移不合法');
    }
    return AnchorPoint(
      cfi: json['cfi'] as String,
      spineIndex: spine,
      href: json['href'] as String,
      title: json['title'] as String,
      chapterFingerprint: json['chapterFingerprint'] as String,
      paragraphFingerprint: json['paragraphFingerprint'] as String,
      charOffset: offset,
      chapterLength: length,
      quote: json['quote'] as String,
      contextBefore: json['contextBefore'] as String,
      contextAfter: json['contextAfter'] as String,
    );
  }
}

class LocationAnchor {
  const LocationAnchor({
    required this.revision,
    required this.start,
    this.end,
    required this.quote,
    this.approximate = false,
  });

  final String revision;
  final AnchorPoint start;
  final AnchorPoint? end;
  final String quote;
  final bool approximate;
  bool get isRange => end != null;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'start': start.toJson(),
    'end': end?.toJson(),
    'quote': quote,
    'approximate': approximate,
  };

  factory LocationAnchor.fromJson(Map<String, dynamic> json) => LocationAnchor(
    revision: json['revision'] as String,
    start: AnchorPoint.fromJson(json['start'] as Map<String, dynamic>),
    end: json['end'] == null
        ? null
        : AnchorPoint.fromJson(json['end'] as Map<String, dynamic>),
    quote: json['quote'] as String,
    approximate: json['approximate'] == true,
  );
}

/// 首次锚点永久保留；最近一次定位失败也不丢失上次成功的锚点。
class AnchorRecord {
  const AnchorRecord({
    required this.original,
    this.current,
    this.status = 'verified',
    this.reason,
    this.semanticVersion,
  });

  final LocationAnchor original;
  final LocationAnchor? current;
  final String status;
  final String? reason;

  /// 创建锚点时的正文语义版本；旧记录为空。
  final String? semanticVersion;
  LocationAnchor get effective => current ?? original;
  bool get isResolved => status == 'verified' || status == 'relocated';

  Map<String, Object?> toJson() => {
    'version': 1,
    'original': original.toJson(),
    'current': current?.toJson(),
    'status': status,
    'reason': reason,
    if (semanticVersion != null) 'semanticVersion': semanticVersion,
  };

  String encode() => jsonEncode(toJson());

  static AnchorRecord? decode(String? source) {
    if (source == null) return null;
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      if (json['version'] != 1) return null;
      final status = json['status'] as String;
      if (!{
        'verified',
        'relocated',
        'approximate',
        'pending',
      }.contains(status)) {
        return null;
      }
      return AnchorRecord(
        original: LocationAnchor.fromJson(
          json['original'] as Map<String, dynamic>,
        ),
        current: json['current'] == null
            ? null
            : LocationAnchor.fromJson(json['current'] as Map<String, dynamic>),
        status: status,
        reason: json['reason'] as String?,
        semanticVersion: json['semanticVersion'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class AnchorBook {
  AnchorBook({required this.revision, required List<AnchorChapter> chapters})
    : chapters = List.unmodifiable(
        <AnchorChapter>[...chapters]
          ..sort((a, b) => a.spineIndex.compareTo(b.spineIndex)),
      ) {
    for (final chapter in this.chapters) {
      if (_chapters.containsKey(chapter.spineIndex)) {
        throw ArgumentError('章节序号不能重复');
      }
      _chapters[chapter.spineIndex] = chapter;
    }
  }

  final String revision;
  final List<AnchorChapter> chapters;
  final Map<int, AnchorChapter> _chapters = {};

  AnchorChapter? chapter(int index) => _chapters[index];

  AnchorPoint? pointForCfi(String cfi) {
    final parsed = EpubCfi.parse(cfi);
    if (parsed == null) return null;
    final spine = spineIndexOfCfi(parsed);
    if (spine == null) return null;
    final source = chapter(spine);
    final offset = source?.offsetFor(cfi);
    return source == null || offset == null ? null : _point(source, offset);
  }

  LocationAnchor? capture(
    String startCfi, {
    String? endCfi,
    bool approximate = false,
  }) {
    final start = pointForCfi(startCfi);
    final end = endCfi == null ? null : pointForCfi(endCfi);
    if (start == null || (endCfi != null && end == null)) return null;
    return _location(start, end, approximate);
  }

  /// 旧标注只使用保存的原文证据；当前文件的内容不能反过来证明旧 CFI 正确。
  LocationAnchor? legacyRange({
    required String startCfi,
    required String endCfi,
    required String quote,
    String contextBefore = '',
    String contextAfter = '',
  }) {
    if (quote.isEmpty) return null;
    final start = _legacyPoint(startCfi, contextBefore, quote + contextAfter);
    final end = _legacyPoint(endCfi, contextBefore + quote, contextAfter);
    if (start == null || end == null) return null;
    return LocationAnchor(
      revision: 'legacy',
      start: start,
      end: end,
      quote: quote,
    );
  }

  AnchorPoint? _legacyPoint(String cfi, String before, String following) {
    final parsed = EpubCfi.parse(cfi);
    final spine = parsed == null ? null : spineIndexOfCfi(parsed);
    if (spine == null) return null;
    final candidate = pointForCfi(cfi);
    final offset = candidate?.charOffset ?? 0;
    final quoteEnd = utf16Boundary(following, 64);
    return AnchorPoint(
      cfi: cfi,
      spineIndex: spine,
      href: candidate?.href ?? '',
      title: candidate?.title ?? '',
      chapterFingerprint: '',
      paragraphFingerprint: '',
      charOffset: offset,
      chapterLength: candidate?.chapterLength ?? 0,
      quote: following.substring(0, quoteEnd),
      contextBefore: before.substring(
        utf16Boundary(before, before.length - 64, forward: true),
      ),
      contextAfter: following.substring(
        quoteEnd,
        utf16Boundary(following, quoteEnd + 64),
      ),
    );
  }

  LocationAnchor? anchorAt(
    int spineIndex,
    int chapterOffset, {
    bool approximate = false,
  }) {
    final source = chapter(spineIndex);
    if (source == null ||
        chapterOffset < 0 ||
        chapterOffset > source.text.length) {
      return null;
    }
    return _location(_point(source, chapterOffset), null, approximate);
  }

  LocationAnchor? rangeAt(AnchorPoint start, AnchorPoint end) =>
      _location(start, end, false);

  String? textFor(LocationAnchor anchor) {
    if (anchor.revision != revision) return null;
    return _rangeText(anchor.start, anchor.end);
  }

  LocationAnchor? _location(
    AnchorPoint? start,
    AnchorPoint? end,
    bool approximate,
  ) {
    if (start == null) return null;
    final text = _rangeText(start, end);
    if (text == null) return null;
    return LocationAnchor(
      revision: revision,
      start: start,
      end: end,
      quote: text,
      approximate: approximate,
    );
  }

  AnchorPoint? _point(AnchorChapter chapter, int rawOffset) {
    final offset = utf16Boundary(chapter.text, rawOffset);
    final cfi = chapter.cfiAt(offset);
    if (cfi == null) return null;
    final quoteEnd = utf16Boundary(chapter.text, offset + 64);
    return AnchorPoint(
      cfi: cfi,
      spineIndex: chapter.spineIndex,
      href: chapter.href,
      title: chapter.title,
      chapterFingerprint: chapter.fingerprint,
      paragraphFingerprint: chapter.paragraphFingerprintAt(offset),
      charOffset: offset,
      chapterLength: chapter.text.length,
      quote: chapter.text.substring(offset, quoteEnd),
      contextBefore: chapter.text.substring(
        utf16Boundary(chapter.text, offset - 64, forward: true),
        offset,
      ),
      contextAfter: chapter.text.substring(
        quoteEnd,
        utf16Boundary(chapter.text, quoteEnd + 64),
      ),
    );
  }

  String? _rangeText(AnchorPoint start, AnchorPoint? end) {
    final source = chapter(start.spineIndex);
    if (source == null ||
        start.charOffset < 0 ||
        start.charOffset > source.text.length) {
      return null;
    }
    if (end == null) return _point(source, start.charOffset)?.quote;
    if (end.spineIndex < start.spineIndex ||
        (end.spineIndex == start.spineIndex &&
            end.charOffset < start.charOffset)) {
      return null;
    }
    final target = chapter(end.spineIndex);
    if (target == null ||
        end.charOffset < 0 ||
        end.charOffset > target.text.length) {
      return null;
    }
    final result = StringBuffer();
    for (final item in chapters) {
      if (item.spineIndex < start.spineIndex ||
          item.spineIndex > end.spineIndex) {
        continue;
      }
      final from = item.spineIndex == start.spineIndex ? start.charOffset : 0;
      final to = item.spineIndex == end.spineIndex
          ? end.charOffset
          : item.text.length;
      result.write(item.text.substring(from, to));
    }
    return result.toString();
  }
}

/// 向内收缩窗口边界，不把 UTF-16 代理对截成半个字符。
int utf16Boundary(String text, int value, {bool forward = false}) {
  final offset = value.clamp(0, text.length);
  if (offset == 0 || offset == text.length) return offset;
  final previous = text.codeUnitAt(offset - 1);
  final current = text.codeUnitAt(offset);
  if (previous >= 0xd800 &&
      previous <= 0xdbff &&
      current >= 0xdc00 &&
      current <= 0xdfff) {
    return forward ? offset + 1 : offset - 1;
  }
  return offset;
}
