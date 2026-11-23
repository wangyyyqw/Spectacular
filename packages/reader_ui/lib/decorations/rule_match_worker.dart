import 'dart:async';
import 'dart:isolate';

import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/text_cfi_map.dart';

import 'decoration_rules.dart';
import 'decoration_rule_matching.dart';

/// 正文匹配输入，不携带 UI 或数据库对象。
class DecorationRuleTextBlock {
  /// 创建文本块，排除区间使用块内 UTF-16 偏移。
  const DecorationRuleTextBlock({
    required this.cfi,
    required this.text,
    this.excluded = const [],
    this.textCfis,
    this.protected = const [],
    this.boundary = 0,
  });

  /// 原文块起点。
  final String cfi;

  /// 正文，不包含 ruby 注音或图片替代文字。
  final String text;

  /// 脚注引用、图片占位等不可匹配区间。
  final List<(int, int)> excluded;
  final TextCfiMap? textCfis;

  /// 作者明确样式仅排除对话染色，固定词和单引号仍可覆盖。
  final List<(int, int)> protected;

  /// 表格、不可匹配块等断开跨段上下文。
  final int boundary;

  TextCfiMap? get textCoordinates {
    if (textCfis != null) return textCfis;
    final point = EpubCfi.parse(cfi);
    return point == null ? null : TextCfiMap.linear(point, text.length);
  }

  String? cfiAt(int offset, {bool end = false}) =>
      textCoordinates?.cfiAt(offset, end: end);
}

/// 单条命中的输入块与偏移。
class DecorationRuleHit {
  /// 创建命中。
  const DecorationRuleHit(this.block, this.start, this.end);

  /// 输入块下标。
  final int block;

  /// 块内半开区间。
  final int start;
  final int end;
}

/// 父 isolate 持有截止计时器，可终止正在回溯的正则。
class DecorationRuleMatcher {
  final Set<_RuleRun> _runs = {};
  bool _disposed = false;

  /// 单规则超时后杀掉工作 isolate，调用方仍可继续其他规则。
  Future<List<DecorationRuleHit>> match({
    required String pattern,
    required bool isRegex,
    required bool caseSensitive,
    required List<DecorationRuleTextBlock> blocks,
    int? limit,
    Duration timeout = const Duration(seconds: 1),
    ReaderDecorationRuleType? type,
    bool allowCrossParagraph = false,
    bool excludeSingleQuotes = false,
  }) async {
    if (_disposed) throw StateError('规则匹配器已关闭');
    final run = _RuleRun();
    _runs.add(run);
    try {
      final completed = await run.start(
        _RuleRequest(
          run.messages.sendPort,
          pattern,
          isRegex,
          caseSensitive,
          [
            for (final block in blocks)
              DecorationRuleTextBlock(
                cfi: block.cfi,
                text: block.text,
                excluded: block.excluded,
                protected: block.protected,
                boundary: block.boundary,
              ),
          ],
          limit,
          type ??
              (isRegex
                  ? ReaderDecorationRuleType.regex
                  : ReaderDecorationRuleType.fixedText),
          allowCrossParagraph,
          excludeSingleQuotes,
        ),
        timeout,
      );
      if (completed.error != null) throw FormatException(completed.error!);
      return completed.hits;
    } finally {
      _runs.remove(run);
    }
  }

  /// 结束页面时停止所有未完成的计算。
  void dispose() {
    _disposed = true;
    for (final run in _runs) {
      run.cancel();
    }
    _runs.clear();
  }
}

class _RuleRun {
  final ReceivePort messages = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final Completer<_RuleResult> _result = Completer();
  Isolate? _worker;

  Future<_RuleResult> start(_RuleRequest request, Duration timeout) async {
    messages.listen((Object? message) {
      if (message is _RuleResult) _complete(message);
    });
    _errors.listen((Object? error) {
      _complete(const _RuleResult([], '规则执行失败，本次会话已跳过'));
    });
    final timer = Timer(timeout, () {
      _worker?.kill(priority: Isolate.immediate);
      _complete(const _RuleResult([], '规则执行超过 1 秒，本次会话已跳过'));
    });
    try {
      _worker = await Isolate.spawn(
        _matchRule,
        request,
        onError: _errors.sendPort,
      );
      if (_result.isCompleted) _worker?.kill(priority: Isolate.immediate);
      return await _result.future;
    } finally {
      timer.cancel();
      messages.close();
      _errors.close();
      _worker?.kill(priority: Isolate.immediate);
    }
  }

  void _complete(_RuleResult result) {
    if (!_result.isCompleted) _result.complete(result);
  }

  void cancel() {
    _worker?.kill(priority: Isolate.immediate);
    _complete(const _RuleResult([], '规则计算已取消'));
  }
}

class _RuleRequest {
  const _RuleRequest(
    this.port,
    this.pattern,
    this.isRegex,
    this.caseSensitive,
    this.blocks,
    this.limit,
    this.type,
    this.allowCrossParagraph,
    this.excludeSingleQuotes,
  );
  final SendPort port;
  final String pattern;
  final bool isRegex;
  final bool caseSensitive;
  final List<DecorationRuleTextBlock> blocks;
  final int? limit;
  final ReaderDecorationRuleType type;
  final bool allowCrossParagraph;
  final bool excludeSingleQuotes;
}

class _RuleResult {
  const _RuleResult(this.hits, [this.error]);
  final List<DecorationRuleHit> hits;
  final String? error;
}

void _matchRule(_RuleRequest request) {
  try {
    final error = validateDecorationRule(request.type, request.pattern);
    if (error != null) {
      request.port.send(_RuleResult([], error));
      return;
    }
    final regex = request.type == ReaderDecorationRuleType.regex;
    final expression =
        request.type.needsPattern &&
            request.type != ReaderDecorationRuleType.range
        ? RegExp(
            regex
                ? decorationRegexSource(request.pattern)
                : RegExp.escape(request.pattern),
            unicode: true,
            caseSensitive: request.caseSensitive,
            dotAll: regex && request.allowCrossParagraph,
          )
        : null;
    final hits = <DecorationRuleHit>[];
    final cross =
        request.type == ReaderDecorationRuleType.doubleQuoteDialogue ||
        request.type.supportsCrossParagraph && request.allowCrossParagraph;
    for (var index = 0; index < request.blocks.length; index++) {
      final block = request.blocks[index];
      final radius = cross ? decorationRuleParagraphLimit - 1 : 0;
      var first = index;
      var last = index;
      while (first > 0 &&
          index - first < radius &&
          request.blocks[first - 1].boundary == block.boundary) {
        first--;
      }
      while (last + 1 < request.blocks.length &&
          last - index < radius &&
          request.blocks[last + 1].boundary == block.boundary) {
        last++;
      }
      final text = request.blocks
          .sublist(first, last + 1)
          .map((b) => b.text)
          .join('\n');
      var offset = 0;
      for (var before = first; before < index; before++) {
        offset += request.blocks[before].text.length + 1;
      }
      if (regex && text.length > decorationRuleMaxInput) {
        throw const FormatException('正则输入超过 32768 字符，本段已跳过');
      }
      final ranges = switch (request.type) {
        ReaderDecorationRuleType.doubleQuoteDialogue => decorationQuoteRanges(
          text,
          single: false,
          maxParagraphs: decorationRuleParagraphLimit,
        ),
        ReaderDecorationRuleType.singleQuotePhrase => decorationQuoteRanges(
          text,
          single: true,
        ),
        ReaderDecorationRuleType.range => decorationDelimiterRanges(
          text,
          request.pattern,
          cross ? decorationRuleParagraphLimit : 1,
        ),
        _ => [
          for (final match in expression!.allMatches(text))
            (match.start, match.end),
        ],
      };
      if (regex && ranges.length > decorationRuleMaxResults) {
        throw const FormatException('正则结果超过 1024 项，本段已跳过');
      }
      final singleRanges = request.excludeSingleQuotes
          ? decorationQuoteRanges(block.text, single: true)
          : const <(int, int)>[];
      for (final range in ranges) {
        if (cross &&
            '\n'.allMatches(text.substring(range.$1, range.$2)).length >=
                decorationRuleParagraphLimit) {
          continue;
        }
        final start = (range.$1 - offset).clamp(0, block.text.length);
        final end = (range.$2 - offset).clamp(0, block.text.length);
        if (start == end ||
            block.excluded.any((range) => range.$1 < end && range.$2 > start)) {
          continue;
        }
        final retained =
            request.type == ReaderDecorationRuleType.doubleQuoteDialogue
            ? subtractDecorationRanges(
                (start, end),
                [...block.protected, ...singleRanges],
              )
            : [(start, end)];
        for (final (from, to) in retained) {
          hits.add(DecorationRuleHit(index, from, to));
          if (request.limit != null && hits.length >= request.limit!) {
            request.port.send(_RuleResult(hits));
            return;
          }
        }
      }
    }
    request.port.send(_RuleResult(hits));
  } on StackOverflowError {
    request.port.send(const _RuleResult([], '规则栈溢出，本次会话已跳过'));
  } on FormatException catch (error) {
    request.port.send(_RuleResult([], error.message));
  } catch (_) {
    request.port.send(const _RuleResult([], '规则执行失败，本次会话已跳过'));
  }
}
