import 'chapter_rules.dart';
import 'txt_models.dart';
import 'txt_worker.dart';

abstract final class ChapterDetector {
  /// 编辑保存和实际检测共用语法及空行校验。
  static void validateRule(ChapterRule rule) {
    _compile(rule.pattern, rule);
    if (rule.volumePattern case final volume?) _compile(volume, rule);
  }

  static Future<ChapterDetectionResult> preview(
    List<String> blocks, {
    ChapterDetectionOptions options = const ChapterDetectionOptions(),
    Set<int>? candidateBlockIndexes,
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) => runTxtWorker<ChapterDetectionResult>(
    _previewWorker,
    (blocks: blocks, options: options, candidates: candidateBlockIndexes),
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  /// 供已经运行于后台 isolate 的转换器调用，块序号始终对应输入。
  static ChapterDetectionResult detect(
    List<String> blocks, {
    ChapterDetectionOptions options = const ChapterDetectionOptions(),
    Set<int>? candidateBlockIndexes,
    void Function(double)? onProgress,
  }) {
    final total = blocks.fold(0, (length, block) => length + block.length);
    if (blocks.isEmpty) return _result([], [], blocks, total);
    if (options.mode == ChapterDetectionMode.length) {
      return _result(_lengthSections(blocks), [], blocks, total);
    }
    final candidates = _scan(
      blocks,
      options,
      onProgress,
      candidateBlockIndexes,
    );
    final warnings = <String>[];
    if (options.mode == ChapterDetectionMode.auto) {
      _removeOpeningContents(candidates, blocks);
      final offsets = <int>[0];
      for (final block in blocks) {
        offsets.add(offsets.last + block.length);
      }
      final hasMainChapters = _filterChineseCandidates(candidates);
      _filterWeakCandidates(candidates, offsets, hasMainChapters);
      _filterUnnamedCandidates(candidates, offsets);
    }
    if (candidates.isEmpty) {
      if (options.mode == ChapterDetectionMode.custom) {
        return _result([], ['正则没有匹配到完整标题行'], blocks, total);
      }
      warnings.add('未识别到章节标题，已按长度分节');
      return _result(_lengthSections(blocks), warnings, blocks, total);
    }
    final boundaries = _boundaries(candidates, blocks);
    final split = _splitLongSections(boundaries, blocks);
    _addLengthWarnings(split, blocks, warnings);
    return _result(split, warnings, blocks, total);
  }
}

void _previewWorker(TxtWorkerRequest request) {
  try {
    final input =
        request.input
            as ({
              List<String> blocks,
              ChapterDetectionOptions options,
              Set<int>? candidates,
            });
    request.output.send(('watch', true));
    final result = ChapterDetector.detect(
      input.blocks,
      options: input.options,
      candidateBlockIndexes: input.candidates,
      onProgress: (progress) => request.output.send(('progress', progress)),
    );
    request.output.send(('result', result));
  } catch (error) {
    request.output.send(('error', error));
  }
}

class _Candidate {
  _Candidate(this.index, this.title, this.rule, this.volume);
  final int index;
  final String title;
  final ChapterRule rule;
  final bool volume;
  late final int? ordinal = _ordinal(title);
  late final RegExpMatch? chinese = _chinesePrefix.firstMatch(title);
  late final String? chapterStyle = chinese == null
      ? null
      : '${RegExp(r'^[0-9０-９]+$').hasMatch(chinese!.group(1)!) ? 'arabic' : 'han'}:${chinese!.group(2)}';
  bool get weak =>
      rule.id == 'builtin-numbered' ||
      rule.id == 'builtin-bracket-number' ||
      rule.id == 'builtin-number-only';
}

final _chinesePrefix = RegExp(
  '[【\\[（(「『]?[ \\t　]*第?[ \\t　]*'
  '([$chapterNumberCharacters]+)[ \\t　]*(章|节|節|回|话|話|幕|期|卷|部|册|冊|集|辑|輯|季)(.*)',
);

List<_Candidate> _scan(
  List<String> blocks,
  ChapterDetectionOptions options,
  void Function(double)? progress,
  Set<int>? allowed,
) {
  final custom = options.mode == ChapterDetectionMode.custom;
  if (custom && options.rule == null) {
    throw const TxtConversionException('E_TXT_RULE', '请选择章节规则');
  }
  final rules = custom
      ? [options.rule!]
      : [
          ...options.autoRules.where((rule) => rule.autoEnabled),
          ...builtInChapterRules.where((rule) => rule.autoEnabled),
        ];
  final patterns = [
    for (final rule in rules)
      (
        rule,
        _compile(rule.pattern, rule),
        rule.volumePattern == null ? null : _compile(rule.volumePattern!, rule),
      ),
  ];
  final result = <_Candidate>[];
  for (var i = 0; i < blocks.length; i++) {
    if (i % 64 == 0) progress?.call(i / blocks.length);
    if (allowed != null && !allowed.contains(i)) continue;
    final title = blocks[i].trim();
    if (title.isEmpty || (!custom && title.length > 100)) continue;
    for (final (rule, chapter, volume) in patterns) {
      final input = custom ? blocks[i] : title;
      final isVolume = volume?.hasMatch(input) == true;
      if (isVolume || chapter.hasMatch(input)) {
        final candidate = _Candidate(i, title, rule, isVolume);
        if (!custom && candidate.weak && _numericNoise.hasMatch(title)) {
          continue;
        }
        result.add(candidate);
        break;
      }
    }
  }
  progress?.call(1);
  return result;
}

final _numericNoise = RegExp(
  r'^(?:[0-9０-９]{2,4}[-/年][0-9０-９]{1,2}[-/月][0-9０-９]{1,2}日?'
  r'|[0-9０-９]+[.．][0-9０-９]+|[0-9０-９]+(?:楼|樓|[fF]))$',
);

RegExp _compile(String pattern, ChapterRule rule) {
  if (pattern.trim().isEmpty) {
    throw const TxtConversionException('E_TXT_RULE', '章节正则不能为空');
  }
  try {
    final expression = RegExp(
      '^(?:$pattern)\$',
      unicode: true,
      caseSensitive: rule.caseSensitive,
    );
    if (expression.hasMatch('')) {
      throw const TxtConversionException('E_TXT_RULE', '章节正则不能匹配空行');
    }
    return expression;
  } on FormatException catch (error) {
    throw TxtConversionException('E_TXT_RULE', '正则无效：${error.message}');
  }
}

/// 只有开头连续清单在后文完整重复时排除；清单文字不从正文删除。
void _removeOpeningContents(List<_Candidate> candidates, List<String> blocks) {
  if (candidates.length < 6) return;
  var end = 1;
  while (end < candidates.length &&
      candidates[end].index - candidates[end - 1].index <= 2) {
    final between = blocks.sublist(
      candidates[end - 1].index + 1,
      candidates[end].index,
    );
    if (between.any((line) => line.trim().isNotEmpty)) break;
    end++;
  }
  if (end < 3 || candidates.first.index > 30 || end == candidates.length) {
    return;
  }
  final opening = candidates
      .take(end)
      .map((candidate) => candidate.title)
      .toList();
  var seen = 0;
  for (final candidate in candidates.skip(end)) {
    if (candidate.title == opening[seen]) seen++;
    if (seen == opening.length) break;
  }
  if (seen == opening.length) candidates.removeRange(0, end);
}

/// 稳定的主章序列只排除夹在连续章号之间的异类标题，保留原文错号与重置。
bool _filterChineseCandidates(List<_Candidate> candidates) {
  candidates.removeWhere((candidate) {
    if (candidate.rule.id != 'builtin-chinese' || !candidate.volume) {
      return false;
    }
    final suffix = candidate.chinese?.group(3) ?? '';
    return suffix.isNotEmpty &&
        !RegExp(r'^[ \t　:：·、—_\-]').hasMatch(suffix) &&
        RegExp(r'[。！？!?；;]$').hasMatch(suffix);
  });
  final groups = <String, List<_Candidate>>{};
  for (final candidate in candidates) {
    if (candidate.rule.id == 'builtin-chinese' && !candidate.volume) {
      (groups[candidate.chapterStyle!] ??= []).add(candidate);
    }
  }
  if (groups.isEmpty) return false;
  final main = groups.values.reduce((a, b) => a.length >= b.length ? a : b);
  final chapterCount = groups.values.fold(
    0,
    (count, group) => count + group.length,
  );
  if (main.length < 3 || main.length * 2 <= chapterCount) return false;
  var continuous = 0;
  for (var i = 1; i < main.length; i++) {
    final previous = main[i - 1].ordinal;
    if (previous != null && main[i].ordinal == previous + 1) continuous++;
  }
  if (continuous / (main.length - 1) < .6) return false;
  var next = 0;
  candidates.removeWhere((candidate) {
    while (next < main.length && main[next].index < candidate.index) {
      next++;
    }
    return candidate.rule.id == 'builtin-chinese' &&
        !candidate.volume &&
        candidate.chapterStyle != main.first.chapterStyle &&
        next > 0 &&
        next < main.length &&
        main[next - 1].ordinal != null &&
        main[next].ordinal == main[next - 1].ordinal! + 1;
  });
  return true;
}

void _filterWeakCandidates(
  List<_Candidate> candidates,
  List<int> offsets,
  bool hasMainChapters,
) {
  final groups = <(String, int), List<_Candidate>>{};
  var volume = 0;
  for (final candidate in candidates) {
    if (candidate.volume) volume++;
    if (candidate.weak && !hasMainChapters) {
      (groups[(_weakStyle(candidate), volume)] ??= []).add(candidate);
    }
  }
  final byStyle = <String, List<_Candidate>>{};
  for (final entry in groups.entries) {
    final chain = _weakSequence(entry.value, offsets);
    if (chain.isEmpty) continue;
    (byStyle[entry.key.$1] ??= []).addAll(chain);
  }
  final accepted = {
    for (final group in byStyle.values)
      if (group.length >= 3) ...group,
  };
  candidates.removeWhere(
    (candidate) => candidate.weak && !accepted.contains(candidate),
  );
}

class _NumberSequence {
  _NumberSequence(this.candidate, this.previous, int quality)
    : count = (previous?.count ?? 0) + 1,
      quality = (previous?.quality ?? 0) + quality;
  final _Candidate candidate;
  final _NumberSequence? previous;
  final int count;
  final int quality;

  bool betterThan(_NumberSequence? other) =>
      other == null ||
      count > other.count ||
      count == other.count && quality > other.quality;
}

/// 只采用主编号链；正文清单不能借全书平均间距获得章节资格。
List<_Candidate> _weakSequence(List<_Candidate> group, List<int> offsets) {
  final bestByNumber = <int, _NumberSequence>{};
  _NumberSequence? best;
  for (var i = 0; i < group.length; i++) {
    final item = group[i];
    final number = item.ordinal;
    if (number == null) continue;
    final adjacent = bestByNumber[number - 1];
    final skipped = bestByNumber[number - 2];
    final previous = adjacent == null || skipped?.betterThan(adjacent) == true
        ? skipped
        : adjacent;
    final end = i + 1 < group.length ? group[i + 1].index : offsets.length - 1;
    final after = offsets[end] - offsets[item.index + 1];
    final before = i == 0
        ? after
        : offsets[item.index] - offsets[group[i - 1].index + 1];
    final quality = (before < after ? before : after).clamp(0, 10000);
    final sequence = _NumberSequence(item, previous, quality);
    if (sequence.betterThan(bestByNumber[number])) {
      bestByNumber[number] = sequence;
    }
    if (sequence.betterThan(best)) best = sequence;
  }
  final result = <_Candidate>[];
  for (var node = best; node != null; node = node.previous) {
    result.add(node.candidate);
  }
  final ordered = result.reversed.toList();
  if (ordered.length < 2) return [];
  var continuous = 0, totalGap = 0;
  for (var i = 1; i < ordered.length; i++) {
    if (ordered[i].ordinal == ordered[i - 1].ordinal! + 1) continuous++;
    totalGap += offsets[ordered[i].index] - offsets[ordered[i - 1].index + 1];
  }
  return continuous / (ordered.length - 1) >= .6 &&
          totalGap / (ordered.length - 1) >= 100
      ? ordered
      : [];
}

void _filterUnnamedCandidates(List<_Candidate> candidates, List<int> offsets) {
  final rejected = <_Candidate>{};
  for (var i = 0; i < candidates.length; i++) {
    final candidate = candidates[i];
    if (candidate.rule.id != 'builtin-unnamed') continue;
    final previous = i > 0 ? candidates[i - 1] : null;
    final next = i + 1 < candidates.length ? candidates[i + 1] : null;
    if (previous == null ||
        next == null ||
        previous.ordinal == null ||
        previous.rule.id != next.rule.id ||
        previous.chapterStyle != next.chapterStyle ||
        next.ordinal != previous.ordinal! + 2 ||
        previous.volume ||
        next.volume ||
        offsets[candidate.index] - offsets[previous.index + 1] < 100 ||
        offsets[next.index] - offsets[candidate.index + 1] < 100) {
      rejected.add(candidate);
    }
  }
  candidates.removeWhere(rejected.contains);
}

String _weakStyle(_Candidate candidate) {
  final separator =
      RegExp('[$chapterNumberCharacters]+([^$chapterNumberCharacters]?)')
          .firstMatch(candidate.title)
          ?.group(1)
          ?.trim() ??
      '';
  return '${candidate.rule.id}:$separator';
}

int? _ordinal(String title) {
  final number = RegExp('[$chapterNumberCharacters]+')
      .firstMatch(title)
      ?.group(0);
  if (number == null) return null;
  final normalized = String.fromCharCodes(
    number.runes.map(
      (rune) => rune >= 0xff10 && rune <= 0xff19 ? rune - 0xfee0 : rune,
    ),
  );
  final arabic = int.tryParse(normalized);
  if (arabic != null) return arabic;
  const digits = {
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '兩': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
    '壹': 1,
    '贰': 2,
    '貳': 2,
    '叁': 3,
    '參': 3,
    '肆': 4,
    '伍': 5,
    '陆': 6,
    '陸': 6,
    '柒': 7,
    '捌': 8,
    '玖': 9,
  };
  const units = {
    '十': 10,
    '拾': 10,
    '百': 100,
    '佰': 100,
    '千': 1000,
    '仟': 1000,
    '万': 10000,
    '萬': 10000,
    '亿': 100000000,
    '億': 100000000,
  };
  if (normalized.runes.every(
    (rune) => digits.containsKey(String.fromCharCode(rune)),
  )) {
    return int.parse(
      normalized.runes.map((rune) => digits[String.fromCharCode(rune)]).join(),
    );
  }
  var total = 0, section = 0, digit = 0;
  for (final rune in normalized.runes) {
    final character = String.fromCharCode(rune);
    if (digits.containsKey(character)) {
      digit = digits[character]!;
      continue;
    }
    if ({'廿': 20, '卅': 30, '卌': 40}[character] case final value?) {
      section += value;
      continue;
    }
    final unit = units[character];
    if (unit == null) return null;
    if (unit < 10000) {
      section += (digit == 0 ? 1 : digit) * unit;
    } else {
      total += (section + digit) * unit;
      section = 0;
    }
    digit = 0;
  }
  return total + section + digit;
}

List<ChapterBoundary> _boundaries(
  List<_Candidate> candidates,
  List<String> blocks,
) {
  final result = <ChapterBoundary>[];
  if (blocks
      .take(candidates.first.index)
      .any((block) => block.trim().isNotEmpty)) {
    result.add(
      const ChapterBoundary(blockIndex: 0, title: '前言', synthetic: true),
    );
  }
  result.addAll(
    candidates.map(
      (candidate) => ChapterBoundary(
        blockIndex: candidate.index,
        title: candidate.title,
        isVolume: candidate.volume,
      ),
    ),
  );
  return result;
}

List<ChapterBoundary> _lengthSections(List<String> blocks) {
  final result = <ChapterBoundary>[];
  var length = 0;
  for (var i = 0; i < blocks.length; i++) {
    if (i == 0 || length >= 10000) {
      result.add(
        ChapterBoundary(
          blockIndex: i,
          title: '第 ${result.length + 1} 节',
          synthetic: true,
        ),
      );
      length = 0;
    }
    length += blocks[i].length;
  }
  return result;
}

List<ChapterBoundary> _splitLongSections(
  List<ChapterBoundary> boundaries,
  List<String> blocks,
) {
  final result = <ChapterBoundary>[];
  for (var index = 0; index < boundaries.length; index++) {
    final boundary = boundaries[index];
    result.add(boundary);
    final end = index + 1 < boundaries.length
        ? boundaries[index + 1].blockIndex
        : blocks.length;
    var length = 0, part = 1;
    for (var i = boundary.blockIndex; i < end; i++) {
      if (length >= 50000) {
        result.add(
          ChapterBoundary(
            blockIndex: i,
            title: '${boundary.title}（续 ${++part}）',
            synthetic: true,
          ),
        );
        length = 0;
      }
      length += blocks[i].length;
    }
  }
  return result;
}

void _addLengthWarnings(
  List<ChapterBoundary> boundaries,
  List<String> blocks,
  List<String> warnings,
) {
  var short = 0, long = 0;
  for (var i = 0; i < boundaries.length; i++) {
    final boundary = boundaries[i];
    final end = i + 1 < boundaries.length
        ? boundaries[i + 1].blockIndex
        : blocks.length;
    final length = blocks
        .sublist(boundary.blockIndex, end)
        .fold(0, (sum, block) => sum + block.length);
    if (!boundary.isVolume && length <= 20) short++;
    if (length > 50000) long++;
  }
  if (short > 0) warnings.add('$short 个章节不足 21 字，请检查是否为有效短章');
  if (long > 0) warnings.add('$long 个章节包含无法在块间继续拆分的超长内容');
}

ChapterDetectionResult _result(
  List<ChapterBoundary> boundaries,
  List<String> warnings,
  List<String> blocks,
  int total,
) => ChapterDetectionResult(
  boundaries: List.unmodifiable(boundaries),
  warnings: List.unmodifiable(warnings),
  blockCount: blocks.length,
  totalLength: total,
);
