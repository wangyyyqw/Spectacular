import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';

import 'edit_fixture.dart';

Future<EpubEditSession> _fixture(String body) async {
  final directory = await Directory.systemTemp.createTemp('style-ownership-');
  addTearDown(() => directory.delete(recursive: true));
  final file = await createEditingFixture(
    directory,
    chapterBytes: utf8.encode(
      '<html xmlns="http://www.w3.org/1999/xhtml">'
      '<head><title>归属测试</title></head><body>$body</body></html>',
    ),
  );
  final session = await EpubEditSession.open(file);
  addTearDown(session.close);
  return session;
}

void main() {
  test('同元素的多个 class 依次删除覆盖后恢复作者原值', () async {
    final session = await _fixture(
      '<p id="p" class="a b" style="color: blue;">正文</p>',
    );
    final editor = ClassStyleEditor(session);
    editor.apply('a', {'color': 'red'}, unifyConflicts: true);
    editor.apply('b', {'color': 'green'}, unifyConflicts: true);
    editor.apply('a', {'color': ''});
    editor.apply('b', {'color': ''});
    final node = session
        .editableDocument('OPS/chapter.xhtml')
        .elements
        .firstWhere((element) => element.attributes['id'] == 'p');
    expect(node.attributes['style'], 'color: blue;');
  });

  test('父子同 class 的归属不会因受管理的子节点 style 变化而丢失', () async {
    final session = await _fixture(
      '<div id="parent" class="a" style="color: blue;">'
      '<p id="child" class="a" style="color: blue;">正文</p></div>',
    );
    final editor = ClassStyleEditor(session);
    editor.apply('a', {'color': 'red'}, unifyConflicts: true);
    editor.apply('a', {'color': ''});
    final nodes = session
        .editableDocument('OPS/chapter.xhtml')
        .elements
        .where((element) => element.classes.contains('a'));
    expect(nodes, hasLength(2));
    for (final node in nodes) {
      expect(
        node.attributes['style'],
        'color: blue;',
        reason: '节点 ${node.attributes['id']} 应恢复作者值',
      );
    }
  });

  test('管理 CSS 中由源码加入的高优先级规则仍报告冲突', () async {
    final session = await _fixture('<p id="p" class="a">正文</p>');
    final editor = ClassStyleEditor(session);
    editor.apply('a', {'color': 'red'});
    editor.writeSource(
      editor.stylesheetPath,
      '${session.readText(editor.stylesheetPath)}\n#p { color: blue !important; }',
    );
    final report = editor.inspect('a', proposed: {'color': 'green'});
    expect(
      report.conflicts.where((conflict) => conflict.selector == '#p'),
      isNotEmpty,
    );
  });
}
