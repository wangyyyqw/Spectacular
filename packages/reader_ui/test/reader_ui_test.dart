import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/reader_ui.dart';

void main() {
  test('UI 包可被加载', () {
    expect(readerUiPackageName, 'reader_ui');
  });

  test('UI 包转出核心 API', () {
    expect(CancelToken().isCancelled, isFalse);
  });
}
