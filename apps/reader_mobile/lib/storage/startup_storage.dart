import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';

/// 清理当前书库孤儿；文件不可读时记录错误并让应用继续启动。
Future<void> prepareLibraryStorage(LibraryStore library, ReaderLog log) async {
  try {
    final swept = await library.sweepOrphans();
    if (swept.removed > 0) {
      await log.log(
        'library_swept',
        fields: {'entries': swept.removed, 'bytes': swept.bytes},
      );
    }
  } catch (error, stack) {
    await log.log(
      'library_prepare_failed',
      fields: {'error': error, 'stack': stack},
    );
  }
}
