import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/css_chapter_book.dart';
import 'support/layout_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('章节职责迁移保留正文、CFI、混排行和容器几何', () async {
    final source = await openCssChapter(
      body:
          '<h2>章节基线</h2><div class="frame"><p>甲乙，丙丁。'
          '<span class="small">混排小字</span>戊己庚辛壬癸。</p>'
          '<p>第二段，<q>引号内容</q>与<strong>粗体内容</strong>。</p></div>'
          '<ol><li>第一项</li><li>第二项<ul><li>嵌套项</li></ul></li></ol>'
          '<p class="fixed">固定页注</p><p>结尾正文。</p>',
      css:
          'body{font-family:Ahem;font-size:16px;line-height:1.5}'
          '.frame{padding:4px;border:1px solid #000}'
          '.small{font-size:12px}.fixed{position:fixed;top:10px;left:5px}'
          'p{margin:3px 0}',
      contentWidth: 180,
      contentHeight: 180,
    );
    addTearDown(source.close);
    final snapshot = snapshotPages(await source.loadChapter(0));
    final fixture = File('test/reader/fixtures/chapter_layout_baseline.json');
    // 显式环境开关仅供首次固定基线或已登记的语义更新，不在测试中自动修复。
    if (Platform.environment['UPDATE_EPUB_LAYOUT_BASELINE'] == '1') {
      fixture.parent.createSync(recursive: true);
      fixture.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n',
      );
    }
    expect(snapshot, jsonDecode(fixture.readAsStringSync()));
    expect(snapshotPages(await source.loadChapter(0)), snapshot);
  });
}
