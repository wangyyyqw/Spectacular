import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';

void main() {
  test('CancelToken 可取消且幂等', () {
    final token = CancelToken();
    expect(token.isCancelled, isFalse);
    token.cancel();
    token.cancel();
    expect(token.isCancelled, isTrue);
  });

  test('ImportReport 默认值符合契约', () {
    const report = ImportReport(ok: true);
    expect(report.warnings, isEmpty);
    expect(report.readabilityLevel, 0);
    expect(report.errorCode, isNull);
  });

  test('BookMeta 为不可变数据对象', () {
    const meta = BookMeta(
      title: '示例',
      author: '作者',
      language: 'zh-CN',
      identifier: 'urn:uuid:1',
    );
    expect(meta.title, '示例');
    expect(meta.language, 'zh-CN');
  });
}
