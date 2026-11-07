import 'package:flutter_test/flutter_test.dart';

import '../support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('原文与伪元素计算字族共同进入章节字体依赖', () async {
    final source = await openCssChapter(
      body: '<p style="--font:user_inline;font-family:var(--font)">甲乙正文</p>',
      css:
          'p::before {content:"前";font-family:user_pseudo}'
          'p::first-letter {font-family:user_initial}',
    );
    addTearDown(source.close);
    await source.loadChapter(0);
    final dependency = source.layoutDependencyForSpine(0);
    for (final family in ['user_inline', 'user_pseudo', 'user_initial']) {
      expect(dependency, contains('$family=$family'));
    }
  });
}
