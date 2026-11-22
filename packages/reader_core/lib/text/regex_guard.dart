import 'dart:async';
import 'dart:isolate';

/// 用户可配置正则的运行时守卫（P7-16）：超时后挂起匹配，不阻塞 UI。
///
/// Dart 的 RegExp 不可中断，超时守卫必须在 isolate 中执行：
/// 模式与输入以字符串传入（RegExp/Match 不可跨 isolate 发送），
/// 超时即放弃该次匹配并返回 null，调用方记录诊断后挂起该规则。
abstract final class RegexGuard {
  /// 默认运行预算。
  static const Duration defaultBudget = Duration(seconds: 1);

  /// 在预算内执行 [pattern] 对 [input] 的首次匹配；返回匹配区间
  /// （start/end），超时或 isolate 异常返回 null。
  ///
  /// [multiline]/[caseSensitive]/[unicode] 控制模式标志，避免向
  /// isolate 传递 RegExp 对象。
  static Future<({int start, int end})?> firstMatch(
    String pattern,
    String input, {
    Duration budget = defaultBudget,
    bool multiline = false,
    bool caseSensitive = true,
    bool unicode = false,
  }) async {
    try {
      return await Isolate.run(() {
        final regex = RegExp(
          pattern,
          multiLine: multiline,
          caseSensitive: caseSensitive,
          unicode: unicode,
        );
        final match = regex.firstMatch(input);
        if (match == null) {
          return null;
        }
        return (start: match.start, end: match.end);
      }).timeout(budget);
    } on TimeoutException {
      return null;
    } catch (_) {
      // 模式非法或 isolate 失败：调用方按「规则挂起」处理。
      return null;
    }
  }

  /// 同步校验模式可编译（规则录入期的第一道闸）。
  static bool isValidPattern(String pattern) {
    try {
      RegExp(pattern);
      return true;
    } on FormatException {
      return false;
    }
  }
}
