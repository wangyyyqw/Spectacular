import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/storage/file_progress_store.dart';
import 'package:reader_ui/reader_session.dart';

void main() {
  test('进度写入文件后可由新实例恢复', () async {
    final dir = Directory.systemTemp.createTempSync('reader_progress_test');
    final first = FileReaderProgressStore(directoryProvider: () async => dir);
    await first.save(
      'book-a',
      const ReaderProgress(
        spineIndex: 12,
        pageIndex: 3,
        finished: true,
        scrollOffset: 37.25,
      ),
    );
    expect(File('${dir.path}/reader_progress.json').existsSync(), isTrue);

    final second = FileReaderProgressStore(directoryProvider: () async => dir);
    expect(
      await second.load('book-a'),
      const ReaderProgress(
        spineIndex: 12,
        pageIndex: 3,
        finished: true,
        scrollOffset: 37.25,
      ),
    );
    expect(await second.load('missing'), isNull);
    dir.deleteSync(recursive: true);
  });
}
