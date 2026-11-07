import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

Uint8List _corpusBook(String name) {
  var directory = Directory.current;
  while (true) {
    final candidate = Directory('${directory.path}/test_corpus');
    if (candidate.existsSync()) {
      return File('${candidate.path}/$name').readAsBytesSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('缺少 test_corpus/$name');
    }
    directory = parent;
  }
}

Future<void> _pumpReader(
  WidgetTester tester, {
  required ReaderChapterSource source,
  required bool accessible,
  required void Function(ReaderSession) onSession,
}) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(accessibleNavigation: accessible),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 520,
              child: ReaderPage(
                source: source,
                store: MemoryReaderProgressStore(),
                bookId: 'announce-$accessible',
                onSessionReady: (value) {
                  session = value;
                  onSession(value);
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await pumpReaderUntilComplete(
    tester,
    () => !session.loading && session.hasContent,
    description: '播报首屏正文',
  );
}

void main() {
  testWidgets('无障碍开启：翻页播报页码（P4-29，§67.5）', (tester) async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    final announced = <String>[];
    const channelName = 'flutter/accessibility';
    const codec = StandardMessageCodec();
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(channelName, (
      message,
    ) async {
      final payload = codec.decodeMessage(message);
      if (payload is Map && payload['type'] == 'announce') {
        final data = payload['data'];
        if (data is Map) {
          announced.add('${data['message']}');
        }
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        channelName,
        null,
      ),
    );

    late ReaderSession session;
    await _pumpReader(
      tester,
      source: source,
      accessible: true,
      onSession: (value) => session = value,
    );
    announced.clear();
    await pumpReaderTask(tester, session.next());
    expect(announced, isNotEmpty, reason: '无障碍模式下翻页有播报');
    expect(announced.last, contains('页'), reason: '播报文案含页码');
    await tester.pumpWidget(const SizedBox.shrink());
    source.close();
    await tester.pump();
  });

  testWidgets('无障碍关闭：翻页不播报（P4-29）', (tester) async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    final announced = <String>[];
    const channelName = 'flutter/accessibility';
    const codec = StandardMessageCodec();
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(channelName, (
      message,
    ) async {
      final payload = codec.decodeMessage(message);
      if (payload is Map && payload['type'] == 'announce') {
        final data = payload['data'];
        if (data is Map) {
          announced.add('${data['message']}');
        }
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        channelName,
        null,
      ),
    );

    late ReaderSession session;
    await _pumpReader(
      tester,
      source: source,
      accessible: false,
      onSession: (value) => session = value,
    );
    announced.clear();
    await pumpReaderTask(tester, session.next());
    expect(announced, isEmpty, reason: '普通用户不被打扰');
    await tester.pumpWidget(const SizedBox.shrink());
    source.close();
    await tester.pump();
  });
}
