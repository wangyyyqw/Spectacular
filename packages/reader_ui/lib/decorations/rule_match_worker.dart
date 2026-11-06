import 'dart:async';
import 'dart:isolate';

/// 正文匹配输入，不携带 UI 或数据库对象。
class DecorationRuleTextBlock {
  /// 创建文本块，排除区间使用块内 UTF-16 偏移。
  const DecorationRuleTextBlock({
    required this.cfi,
    required this.text,
    this.excluded = const [],
  });

  /// 原文块起点。
  final String cfi;

  /// 正文，不包含 ruby 注音或图片替代文字。
  final String text;

  /// 脚注引用、图片占位等不可匹配区间。
  final List<(int, int)> excluded;
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
          blocks,
          limit,
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
  );
  final SendPort port;
  final String pattern;
  final bool isRegex;
  final bool caseSensitive;
  final List<DecorationRuleTextBlock> blocks;
  final int? limit;
}

class _RuleResult {
  const _RuleResult(this.hits, [this.error]);
  final List<DecorationRuleHit> hits;
  final String? error;
}

void _matchRule(_RuleRequest request) {
  try {
    final expression = RegExp(
      request.isRegex ? request.pattern : RegExp.escape(request.pattern),
      unicode: true,
      caseSensitive: request.caseSensitive,
    );
    final hits = <DecorationRuleHit>[];
    for (var index = 0; index < request.blocks.length; index++) {
      final block = request.blocks[index];
      for (final match in expression.allMatches(block.text)) {
        if (match.start == match.end ||
            block.excluded.any(
              (range) => range.$1 < match.end && range.$2 > match.start,
            )) {
          continue;
        }
        hits.add(DecorationRuleHit(index, match.start, match.end));
        if (request.limit != null && hits.length >= request.limit!) {
          request.port.send(_RuleResult(hits));
          return;
        }
      }
    }
    request.port.send(_RuleResult(hits));
  } on StackOverflowError {
    request.port.send(const _RuleResult([], '规则栈溢出，本次会话已跳过'));
  } on FormatException {
    request.port.send(const _RuleResult([], '正则格式无效，请修改规则后重新生成预览'));
  } catch (_) {
    request.port.send(const _RuleResult([], '规则执行失败，本次会话已跳过'));
  }
}
