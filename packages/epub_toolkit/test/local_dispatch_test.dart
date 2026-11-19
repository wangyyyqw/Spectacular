import 'package:flutter_test/flutter_test.dart';
import 'package:spectacular_epub_tools/local_epub_tools.dart';

void main() {
  test('用户入口只包含 EPUB 编辑功能，不包含 TXT 或内部指令', () {
    final visible = LocalEpubTool.visible.toList();
    expect(visible, isNotEmpty);
    expect(visible.any((tool) => tool.label.contains('TXT')), isFalse);
    expect(visible, isNot(contains(LocalEpubTool.repair)));
    expect(visible, isNot(contains(LocalEpubTool.saveNavigation)));
    expect(visible.map((tool) => tool.category).toSet(), {
      '转换',
      '结构',
      '图片',
      '字体',
      '注释与正文',
    });
  });
}
