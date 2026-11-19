import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/text_cfi_map.dart';

import 'decoration_rule_preview.dart';
import 'decoration_rules.dart';
import 'rule_match_worker.dart';

/// 规则命中只驻留内存，不产生手工装饰或标注记录。
class ReaderDecorationRuleMatch {
  /// 创建规则命中。
  const ReaderDecorationRuleMatch({
    required this.ruleId,
    required this.startCfi,
    required this.endCfi,
    required this.text,
    required this.style,
  });

  /// 来源规则。
  final String ruleId;

  /// 原文区间。
  final String startCfi;
  final String endCfi;

  /// 命中片段。
  final String text;

  /// 图片与高亮样式；横排点九背景会预留布局空间。
  final ReaderDecorationRuleStyle style;
}

/// 章节级规则缓存与会话错误隔离。
class ReaderDecorationRuleEngine extends ChangeNotifier {
  final DecorationRuleMatcher _matcher = DecorationRuleMatcher();
  final LinkedHashMap<String, Future<List<ReaderDecorationRuleMatch>>> _cache =
      LinkedHashMap();
  final Map<String, (String, String)> _failed = {};
  final Map<String, String> _errorMessages = {};
  late final Map<String, String> _errorView = UnmodifiableMapView(
    _errorMessages,
  );
  bool _disposed = false;

  /// 当前会话中被跳过的规则，编辑其匹配条件后自动恢复。
  Map<String, String> get errors => _errorView;

  /// 全局非默认、全局默认、本书非默认、本书默认，组内按规则排序。
  static List<ReaderDecorationRule> orderedRules({
    required List<ReaderDecorationRuleGroup> groups,
    required List<ReaderDecorationRule> rules,
    required String bookId,
  }) {
    final enabled =
        groups
            .where(
              (group) =>
                  group.enabled &&
                  (group.bookId == null || group.bookId == bookId),
            )
            .toList()
          ..sort((left, right) {
            final scope = (left.bookId == null ? 0 : 1).compareTo(
              right.bookId == null ? 0 : 1,
            );
            if (scope != 0) return scope;
            final defaults = (left.isDefault ? 1 : 0).compareTo(
              right.isDefault ? 1 : 0,
            );
            if (defaults != 0) return defaults;
            final order = left.sortOrder.compareTo(right.sortOrder);
            return order == 0 ? left.id.compareTo(right.id) : order;
          });
    final result = <ReaderDecorationRule>[];
    for (final group in enabled) {
      final items =
          rules
              .where((rule) => rule.enabled && rule.groupId == group.id)
              .toList()
            ..sort((left, right) {
              final order = left.sortOrder.compareTo(right.sortOrder);
              return order == 0 ? left.id.compareTo(right.id) : order;
            });
      result.addAll(items);
    }
    return result;
  }

  /// 同章节原文与规则版本只计算一次，字体重排复用相同 CFI 命中。
  Future<List<ReaderDecorationRuleMatch>> matchChapter({
    required List<PageContent> pages,
    required List<ReaderDecorationRuleGroup> groups,
    required List<ReaderDecorationRule> rules,
    required String bookId,
  }) {
    final ordered = orderedRules(groups: groups, rules: rules, bookId: bookId);
    if (ordered.isEmpty) return Future.value(const []);
    final blocks = textBlocks(pages);
    final key = jsonEncode([
      for (final block in blocks)
        [
          block.cfi,
          block.text,
          [
            for (final run in block.textCfis?.runs ?? const <TextCfiRun>[])
              [
                run.start,
                run.end,
                run.cfi.serialize(),
                run.sourceStart,
                run.sourceEnd,
              ],
          ],
          [
            for (final range in block.excluded) [range.$1, range.$2],
          ],
        ],
      for (final rule in ordered)
        [rule.id, _fingerprint(rule), rule.style.toJson()],
    ]);
    final existing = _cache[key];
    if (existing != null) return existing;
    final future = _matchOrdered(blocks, ordered);
    _cache[key] = future;
    while (_cache.length > 8) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  Future<List<ReaderDecorationRuleMatch>> _matchOrdered(
    List<DecorationRuleTextBlock> blocks,
    List<ReaderDecorationRule> rules,
  ) async {
    final matches = <ReaderDecorationRuleMatch>[];
    for (final rule in rules) {
      if (_disposed) break;
      final fingerprint = _fingerprint(rule);
      if (_failed[rule.id]?.$1 == fingerprint) continue;
      _clearFailure(rule.id);
      try {
        matches.addAll(await _run(rule, blocks));
      } on FormatException catch (error) {
        _recordFailure(rule, error.message);
      }
    }
    return matches;
  }

  /// 预览当前章前 50 条，不访问存储，也不改变已保存规则。
  Future<List<ReaderDecorationRulePreview>> preview(
    ReaderDecorationRule rule,
    List<PageContent> pages,
  ) async {
    try {
      final matches = await _run(rule, textBlocks(pages), limit: 50);
      _clearFailure(rule.id);
      return [
        for (final match in matches)
          ReaderDecorationRulePreview(
            startCfi: match.startCfi,
            endCfi: match.endCfi,
            text: match.text,
            style: match.style,
          ),
      ];
    } on FormatException catch (error) {
      _recordFailure(rule, error.message);
      rethrow;
    }
  }

  Future<List<ReaderDecorationRuleMatch>> _run(
    ReaderDecorationRule rule,
    List<DecorationRuleTextBlock> blocks, {
    int? limit,
  }) async {
    final hits = await _matcher.match(
      pattern: rule.pattern,
      isRegex: rule.isRegex,
      caseSensitive: rule.caseSensitive,
      blocks: blocks,
      limit: limit,
    );
    final matches = <ReaderDecorationRuleMatch>[];
    for (final hit in hits) {
      final block = blocks[hit.block];
      final start = block.cfiAt(hit.start);
      final end = block.cfiAt(hit.end, end: true);
      if (start == null ||
          end == null ||
          EpubCfi.parse(start)!.compareTo(EpubCfi.parse(end)!) >= 0) {
        continue;
      }
      matches.add(
        ReaderDecorationRuleMatch(
          ruleId: rule.id,
          startCfi: start,
          endCfi: end,
          text: block.text.substring(hit.start, hit.end),
          style: rule.style,
        ),
      );
    }
    return matches;
  }

  static String _fingerprint(ReaderDecorationRule rule) =>
      jsonEncode([rule.pattern, rule.isRegex, rule.caseSensitive]);

  void _recordFailure(ReaderDecorationRule rule, String message) {
    _failed[rule.id] = (_fingerprint(rule), message);
    if (_errorMessages[rule.id] == message) return;
    _errorMessages[rule.id] = message;
    if (!_disposed) notifyListeners();
  }

  void _clearFailure(String id) {
    _failed.remove(id);
    if (_errorMessages.remove(id) != null && !_disposed) notifyListeners();
  }

  /// 清除章缓存；同条件的超时错误仍在本会话跳过。
  void clearCache() => _cache.clear();

  /// 释放后台 isolate。
  @override
  void dispose() {
    _disposed = true;
    _cache.clear();
    _matcher.dispose();
    super.dispose();
  }

  /// 正文和标题匹配；跳过脚注、表格、图片、注音与页家具。
  static List<DecorationRuleTextBlock> textBlocks(List<PageContent> pages) {
    final seen = <PageBlock>{};
    final segments = <Object, List<DecorationRuleTextBlock>>{};
    for (final page in pages) {
      for (final slice in page.slices) {
        final block = slice.block;
        final cfi = block.startCfi;
        if (cfi == null ||
            !seen.add(block) ||
            !block.textRuleEligible ||
            block.table != null ||
            block.layout.text.isEmpty) {
          continue;
        }
        final text = block.layout.text;
        final item = DecorationRuleTextBlock(
          cfi: cfi,
          text: text,
          textCfis: block.textCoordinates,
          excluded: [
            for (final footnote in block.footnotes)
              (footnote.start, footnote.end),
            for (var index = 0; index < text.length; index++)
              if (text.codeUnitAt(index) == 0xFFFC) (index, index + 1),
          ],
        );
        (segments[block.textCfis?.origin ?? cfiBase(cfi)] ??= []).add(item);
      }
    }
    return [for (final parts in segments.values) ..._mergeSegments(parts)];
  }

  static List<DecorationRuleTextBlock> _mergeSegments(
    List<DecorationRuleTextBlock> parts,
  ) {
    parts.sort(
      (left, right) =>
          EpubCfi.parse(left.cfiAt(0) ?? left.cfi)!
              .compareTo(EpubCfi.parse(right.cfiAt(0) ?? right.cfi)!),
    );
    final result = <DecorationRuleTextBlock>[];
    for (final part in parts) {
      final merged = result.isEmpty ? null : _mergeSegment(result.last, part);
      if (merged == null) {
        result.add(part);
      } else {
        result[result.length - 1] = merged;
      }
    }
    return result;
  }

  static DecorationRuleTextBlock? _mergeSegment(
    DecorationRuleTextBlock previous,
    DecorationRuleTextBlock part,
  ) {
    final offset = part.textCoordinates?.offsetFrom(previous.textCoordinates!);
    if (offset == null || offset < 0 || offset > previous.text.length) {
      return null;
    }
    final overlap = previous.text.length - offset;
    final shared = overlap < part.text.length ? overlap : part.text.length;
    if (previous.text.substring(offset, offset + shared) !=
        part.text.substring(0, shared)) {
      return null;
    }
    final suffix = overlap >= part.text.length
        ? ''
        : part.text.substring(overlap);
    return DecorationRuleTextBlock(
      cfi: previous.cfi,
      text: previous.text + suffix,
      textCfis: _joinedMap(previous, part, overlap),
      excluded: [
        ...previous.excluded,
        for (final range in part.excluded)
          (range.$1 + offset, range.$2 + offset),
      ],
    );
  }

  static TextCfiMap? _joinedMap(
    DecorationRuleTextBlock first,
    DecorationRuleTextBlock next,
    int overlap,
  ) {
    final previous = first.textCoordinates;
    final incoming = next.textCoordinates;
    if (previous == null || incoming == null) return null;
    final appended = overlap.clamp(0, next.text.length);
    final builder = TextCfiMapBuilder()
      ..addMap(previous)
      ..addMap(
        incoming.slice(appended, next.text.length),
        offset: first.text.length,
      );
    return builder.build(
      first.text.length + next.text.length - appended,
      parent: previous.origin,
      originStart: previous.originStart,
    );
  }
}
