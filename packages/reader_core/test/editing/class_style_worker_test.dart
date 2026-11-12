import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';

import 'edit_fixture.dart';

Future<EpubEditSession> _session() async {
  final directory = await Directory.systemTemp.createTemp('class-worker-');
  addTearDown(() => directory.delete(recursive: true));
  final session = await EpubEditSession.open(
    await createEditingFixture(directory),
  );
  addTearDown(session.close);
  return session;
}

void main() {
  test('异步应用继承正文草稿和资源，归属与样式作为一步发布并可撤销', () async {
    final session = await _session();
    final image = Uint8List(1024 * 1024)..[0] = 127;
    session.transaction('准备未保存草稿', (tx) {
      tx.writeText(
        'OPS/chapter.xhtml',
        tx
            .readText('OPS/chapter.xhtml')
            .replaceFirst('另一段', '尚未保存的正文')
            .replaceFirst(
              '<p id="p"',
              '<p style="color: black !important" id="p"',
            ),
      );
      tx.writeBytes('OPS/image.png', image);
      tx.metadata['custom'] = {'note': '保留归属之外的元数据'};
    });
    final before = session.readText('OPS/chapter.xhtml');
    final inspected = await inspectClassStyleAsync(
      session,
      'note',
      proposed: {'color': 'red'},
    );
    expect(inspected.elementCount, 1);
    expect(inspected.conflicts, isNotEmpty);
    final revision = session.revision;
    var events = 0;
    final listener = session.changes.listen((_) => events++);
    addTearDown(listener.cancel);
    await applyClassStyleAsync(session, 'note', {
      'color': 'red',
    }, unifyConflicts: true);
    expect(session.revision, revision + 1);
    expect(events, 1);
    expect(session.readText('OPS/chapter.xhtml'), contains('尚未保存的正文'));
    expect(session.readText('OPS/chapter.xhtml'), contains('red !important'));
    expect(session.readBytes('OPS/image.png'), image);
    expect(session.metadata['classStyleOwners'], isNotEmpty);
    expect(session.metadata['custom'], {'note': '保留归属之外的元数据'});
    session.undo();
    expect(session.readText('OPS/chapter.xhtml'), before);
    expect(session.metadata.containsKey('classStyleOwners'), isFalse);
  });

  test('检查与应用任务都拒绝在新编辑版本上发布旧结果', () async {
    for (final apply in [false, true]) {
      final session = await _session();
      final pending = apply
          ? applyClassStyleAsync(session, 'note', {'color': 'red'})
          : inspectClassStyleAsync(session, 'note');
      session.transaction(
        '继续输入',
        (tx) => tx.writeText(
          'OPS/chapter.xhtml',
          tx.readText('OPS/chapter.xhtml').replaceFirst('另一段', '后来的编辑'),
        ),
      );
      final latest = session.revision;
      await expectLater(
        pending,
        throwsA(
          isA<EpubEditException>().having(
            (error) => error.message,
            '原因',
            contains('编辑内容已变化'),
          ),
        ),
      );
      expect(session.revision, latest);
      expect(session.readText('OPS/chapter.xhtml'), contains('后来的编辑'));
      expect(session.metadata.containsKey('classStylesheet'), isFalse);
    }
  });

  test('取消与关闭会话都阻止后台结果发布', () async {
    for (final close in [false, true]) {
      final session = await _session();
      var cancelled = false;
      final pending = applyClassStyleAsync(session, 'note', {
        'color': 'red',
      }, isCancelled: () => cancelled);
      final revision = session.revision;
      if (close) {
        session.close();
      } else {
        cancelled = true;
      }
      await expectLater(
        pending,
        throwsA(
          isA<EpubEditException>().having(
            (error) => error.message,
            '原因',
            contains('取消'),
          ),
        ),
      );
      expect(session.revision, revision);
      if (!close) expect(session.changedPaths, isEmpty);
    }
  });

  test('后台 CSS 校验失败保持原文和事务历史', () async {
    final session = await _session();
    final before = session.readText('OPS/chapter.xhtml');
    await expectLater(
      applyClassStyleAsync(session, 'note', {'color': 'red; display:none'}),
      throwsA(isA<FormatException>()),
    );
    expect(session.revision, 0);
    expect(session.readText('OPS/chapter.xhtml'), before);
    expect(session.canUndo, isFalse);
  });

  test('后台检查按调用方宽度返回当前媒体规则的生效值', () async {
    final session = await _session();
    session.transaction(
      '添加媒体规则',
      (tx) => tx.writeText(
        'OPS/style.css',
        'p.note { color: #112233; } @media (min-width: 800px) { p.note { color: #445566; } }',
      ),
    );
    final revision = session.revision;
    final narrow = await inspectClassStyleAsync(
      session,
      'note',
      viewportWidth: 360,
    );
    final wide = await inspectClassStyleAsync(
      session,
      'note',
      viewportWidth: 1000,
    );
    expect(narrow.effectiveValues['color'], ['#112233']);
    expect(wide.effectiveValues['color'], ['#445566']);
    expect(session.revision, revision);
  });
}
