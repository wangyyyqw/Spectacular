import 'dart:io';

import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import 'drift_progress_store.dart';

/// 迁移旧书库后才清理孤儿；迁移失败时保留旧文件并让应用继续启动。
Future<bool> prepareLibraryStorage(LibraryStore library, ReaderLog log) async {
  try {
    final migrated = await library.migrateLegacyJson();
    if (migrated > 0) {
      await log.log('library_migrated', fields: {'books': migrated});
    }
    final swept = await library.sweepOrphans();
    if (swept.removed > 0) {
      await log.log(
        'library_swept',
        fields: {'entries': swept.removed, 'bytes': swept.bytes},
      );
    }
    return true;
  } catch (error, stack) {
    await log.log(
      'library_prepare_failed',
      fields: {'error': error, 'stack': stack},
    );
    return false;
  }
}

/// 迁移旧进度；旧文件不可读时保留数据库存储并记录错误。
Future<void> prepareProgressStorage(
  DriftProgressStore store,
  Future<Directory> Function() supportDirectory,
  ReaderLog log,
) async {
  try {
    final support = await supportDirectory();
    final migrated = await store.migrateLegacyJson(
      File('${support.path}/reader_progress.json'),
    );
    if (migrated > 0) {
      await log.log('progress_migrated', fields: {'entries': migrated});
    }
  } catch (error, stack) {
    await log.log(
      'progress_migrate_failed',
      fields: {'error': error, 'stack': stack},
    );
  }
}
