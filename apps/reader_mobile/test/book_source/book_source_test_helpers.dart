import 'package:reader_mobile/book_source/book_source_script.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';

typedef FakeScriptEvaluate = String Function(
  String code,
  String result,
  Map<String, String> variables,
  FakeBookSourceScriptSession session,
);

/// 测试用脚本会话：不启动 QuickJS，便于覆盖规则编排。
class FakeBookSourceScriptSession implements BookSourceScriptSession {
  FakeBookSourceScriptSession(this.onEvaluate);

  final FakeScriptEvaluate onEvaluate;
  final Map<String, String> _responses = <String, String>{};
  final List<BookSourcePendingRequest> _pending = <BookSourcePendingRequest>[];

  @override
  Map<String, String> get responses => _responses;

  void addPending(BookSourcePendingRequest request) => _pending.add(request);

  @override
  void rememberResponse(String key, String body) {
    _responses[key] = body;
  }

  @override
  List<BookSourcePendingRequest> takePendingRequests() {
    final requests = List<BookSourcePendingRequest>.of(_pending);
    _pending.clear();
    return requests;
  }

  @override
  String evaluate(
    String code, {
    required String result,
    required Map<String, String> variables,
    required String Function(String rule) resolveString,
    required List<String> Function(String rule) resolveList,
  }) {
    return onEvaluate(code, result, variables, this);
  }

  @override
  void dispose() {}
}

BookSourceScriptFactory fakeScriptFactory(FakeBookSourceScriptSession session) {
  return (_) => session;
}
