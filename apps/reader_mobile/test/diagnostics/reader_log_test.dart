import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_exception.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';

enum _LogStatus { ready }

const _privateTitle = '私密书籍标题';
const _privateQuery = '私密检索意图';
const _privateQuote = '私密摘录内容';
const _technicalStack =
    '#0 parse (package:reader_core/epub/epub_document.dart:12:3)\n'
    'FormatException: $_privateQuote\n'
    '#1 open (/books/$_privateTitle.epub:1:2)\n'
    '#2 open (package:reader_core/PrivateBook.epub:1:2)\n'
    '#3 work (dart:async/future_impl.dart:20:4)';

ReaderLog _fileLog(Directory directory) => ReaderLog(
  directoryProvider: () async => directory,
  deviceInfoProvider: () async => const {'device_model': 'UnitTestPhone'},
);

void _expectNoReadingContent(String text) {
  for (final content in [_privateTitle, _privateQuery, _privateQuote]) {
    expect(text, isNot(contains(content)));
  }
}

void main() {
  final sharedClockLog = ReaderLog();
  test('日志初始化、追加、导出文件', () async {
    final dir = Directory.systemTemp.createTempSync('reader_log_test');
    final log = ReaderLog(
      directoryProvider: () async => dir,
      deviceInfoProvider: () async => <String, String>{
        'device_model': 'UnitTestPhone',
        'android_version': '14',
      },
    );
    await log.initialize();
    await log.log(
      'page_turn',
      fields: <String, Object?>{'spine': 3, 'page': 7, 'mode': 'simulation3d'},
    );
    final text = await log.exportText();
    expect(text, contains('device_model=UnitTestPhone'));
    expect(text, contains('page_turn'));
    expect(text, contains('spine=3'));
    final path = await log.exportFile();
    expect(path, isNotNull);
    final fileText = File(path!).readAsStringSync();
    expect(fileText, contains('page_turn'));
    expect(fileText, contains('mode=simulation3d'));
    expect(fileText, contains('device_model=UnitTestPhone'));
    expect(log.lineCount, greaterThan(0));
    expect(log.isReady, isTrue);
    log.resetForTest();
    expect(log.lineCount, 0);
    dir.deleteSync(recursive: true);
  });

  test('重新启动后仍保留上次会话的日志', () async {
    final dir = Directory.systemTemp.createTempSync('reader_log_history');
    Map<String, String> info() => <String, String>{
      'device_model': 'UnitTestPhone',
    };

    final first = ReaderLog(
      directoryProvider: () async => dir,
      deviceInfoProvider: () async => info(),
    );
    await first.initialize();
    await first.log('first_session_event', fields: <String, Object?>{'v': 1});
    first.resetForTest();

    final second = ReaderLog(
      directoryProvider: () async => dir,
      deviceInfoProvider: () async => info(),
    );
    await second.initialize();
    await second.log('second_session_event');
    final text = await second.exportText();

    expect(text, contains('first_session_event'), reason: '上次会话的日志要保留');
    expect(text, contains('second_session_event'));
    expect('=== 新会话'.allMatches(text).length, 2, reason: '两次启动各有一个会话头');
    final exported = File((await second.exportFile())!).readAsStringSync();
    expect(exported, contains('first_session_event'), reason: '导出不能用内存覆盖历史');
    expect(exported, contains('second_session_event'));
    second.resetForTest();
    dir.deleteSync(recursive: true);
  });

  test('清理日志后导出为空且保留会话头', () async {
    final dir = Directory.systemTemp.createTempSync('reader_log_clear');
    final log = ReaderLog(
      directoryProvider: () async => dir,
      deviceInfoProvider: () async => <String, String>{
        'device_model': 'UnitTestPhone',
      },
    );
    await log.initialize();
    await log.log('to_be_cleared');
    expect(await log.exportText(), contains('to_be_cleared'));

    await log.clear();
    final after = await log.exportText();
    expect(after, isNot(contains('to_be_cleared')));
    log.resetForTest();
    dir.deleteSync(recursive: true);
  });

  test('日志移除阅读内容和异常正文，保留类型、技术帧和状态', () async {
    final directory = Directory.systemTemp.createTempSync(
      'reader-log-private-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final log = _fileLog(directory);
    final prints = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) prints.add(message);
    };
    addTearDown(() => debugPrint = previousPrint);
    await log.log(
      'search_scan',
      fields: {
        'query': _privateQuery,
        'book': _privateTitle,
        'book_id': '00112233445566778899aabbccddeeff',
        'context': _privateQuote,
        'error': const FormatException(_privateQuote),
        'message': _privateTitle,
        'stack': StackTrace.fromString(_technicalStack),
        'details': {'quote': _privateQuote},
        'state': _LogStatus.ready,
        'source': 'file',
        'hits': 2,
      },
    );
    await log.log(
      'epub_error',
      fields: {'error': const EpubException('E_OPF_XML', _privateTitle)},
    );
    final text = await log.exportText();
    _expectNoReadingContent(text);
    _expectNoReadingContent(prints.join('\n'));
    expect(text, contains('query_length=${_privateQuery.length}'));
    expect(text, contains('book_id=00112233'));
    expect(text, contains('error_type=FormatException'));
    expect(text, contains('error_code=E_OPF_XML'));
    expect(text, contains('epub_document.dart:12:3'));
    expect(text, contains('future_impl.dart:20:4'));
    expect(text, isNot(contains('PrivateBook.epub')));
    expect(text, contains('state_enum=ready'));
    expect(text, contains('source=file'));
    expect(text, contains('hits=2'));
    _expectNoReadingContent(File((await log.exportFile())!).readAsStringSync());
  });

  test('旧日志和导出前追加的明文内容都过滤，保留历史事件', () async {
    final directory = Directory.systemTemp.createTempSync('reader-log-legacy-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/reader_log.txt');
    const old =
        '2026-11-15T10:00:00 | previous_event | '
        'query=$_privateQuery | book=$_privateTitle | hits=1\n'
        '$_privateQuote\n';
    file.writeAsStringSync(old);
    final log = _fileLog(directory);
    await log.log('current_event');
    _expectNoReadingContent(file.readAsStringSync());
    file.writeAsStringSync(
      '2026-11-15T10:00:01 | late_event | error=FormatException: $_privateQuote\n',
      mode: FileMode.append,
    );
    final exported = File((await log.exportFile())!).readAsStringSync();
    _expectNoReadingContent(exported);
    expect(exported, contains('previous_event'));
    expect(exported, contains('current_event'));
    expect(exported, contains('late_event'));
    expect(exported, contains('error_type=FormatException'));
  });

  test('内存只保留最近行并计数，清空后重置计数', () async {
    final previousPrint = debugPrint;
    debugPrint = (_, {wrapWidth}) {};
    addTearDown(() => debugPrint = previousPrint);
    final log = ReaderLog();
    await log.initialize();
    final headerLines = log.lineCount;
    const count = ReaderLog.maxCachedLines + 7;
    for (var i = 0; i < count; i++) {
      await log.log('bounded_event', fields: {'seq': i});
    }
    expect(log.lineCount, ReaderLog.maxCachedLines);
    expect(log.droppedLineCount, headerLines + 7);
    final text = await log.exportText();
    expect(text, contains('seq=${count - 1}'));
    expect(text, isNot(contains(' | seq=0\n')));
    expect(text, contains('[内存日志已丢弃最早 ${headerLines + 7} 行]'));
    await log.clear();
    expect(log.lineCount, 0);
    expect(log.droppedLineCount, 0);
    expect(await log.exportText(), isEmpty);
  });

  test('并发追加与导出按序执行，追加阶段就遵守文件预算', () async {
    final directory = Directory.systemTemp.createTempSync('reader-log-budget-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final previousPrint = debugPrint;
    debugPrint = (_, {wrapWidth}) {};
    addTearDown(() => debugPrint = previousPrint);
    final log = _fileLog(directory);
    await log.initialize();
    final file = File(log.filePath!);
    const old = '2026-11-15T10:00:00 | old_event | seq=0\n';
    final copies = (ReaderLog.maxLogBytes - 100) ~/ old.length;
    file.writeAsStringSync(List.filled(copies, old).join());
    final pending = [
      for (var i = 0; i < 30; i++) log.log('queued_event', fields: {'seq': i}),
    ];
    final exported = log.exportFile();
    await Future.wait(pending);
    expect(file.lengthSync(), lessThanOrEqualTo(ReaderLog.maxLogBytes));
    final text = File((await exported)!).readAsStringSync();
    final actual = RegExp(r'queued_event \| seq=(\d+)')
        .allMatches(text)
        .map((match) => int.parse(match.group(1)!))
        .toList();
    expect(actual, List.generate(30, (i) => i));
    expect(text, contains('old_event'), reason: '轮转保留预算内的最近历史');
    expect(text, contains('[日志已截断，'));
  });

  test('超大多字节旧日志有界读取，不导出截断字符或阅读内容', () async {
    final directory = Directory.systemTemp.createTempSync(
      'reader-log-unicode-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/reader_log.txt');
    final copies =
        ReaderLog.maxLogBytes ~/ utf8.encode(_privateQuote).length + 9;
    file.writeAsStringSync(List.filled(copies, _privateQuote).join());
    final log = _fileLog(directory);
    await log.log('after_rotation');
    final text = await log.exportText();
    _expectNoReadingContent(text);
    expect(text, isNot(contains('\uFFFD')));
    expect(text, contains('after_rotation'));
    expect(file.lengthSync(), lessThanOrEqualTo(ReaderLog.maxLogBytes));
  });

  test('初始化失败的控制台诊断不包含异常正文，内存日志仍可使用', () async {
    final prints = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) prints.add(message);
    };
    addTearDown(() => debugPrint = previousPrint);
    final log = ReaderLog(
      directoryProvider: () async =>
          throw const FileSystemException(_privateTitle),
    );
    await log.log('memory_fallback');
    expect(log.isReady, isTrue);
    expect(await log.exportText(), contains('memory_fallback'));
    expect(prints.join('\n'), contains('FileSystemException'));
    _expectNoReadingContent(prints.join('\n'));
  });

  testWidgets('共享日志首次初始化并完成追加', (tester) async {
    var completed = false;
    unawaited(
      sharedClockLog.log('first_test_clock').then((_) => completed = true),
    );
    await tester.pump();

    expect(sharedClockLog.isReady, isTrue);
    expect(completed, isTrue);
  });

  testWidgets('共享日志在新测试时钟中仍完成追加', (tester) async {
    var completed = false;
    unawaited(
      sharedClockLog.log('second_test_clock').then((_) => completed = true),
    );
    await tester.pump();

    expect(completed, isTrue);
    expect(await sharedClockLog.exportText(), contains('second_test_clock'));
  });
}
