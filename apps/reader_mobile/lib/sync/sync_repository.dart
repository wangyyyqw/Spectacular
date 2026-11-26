import 'dart:io';

import 'sync_assets.dart';
import 'sync_models.dart';
import 'sync_state.dart';

abstract interface class SyncRepository {
  bool get available;
  bool get busy;
  Stream<void> get changes;
  Future<Directory> directory();
  Future<Map<String, SyncEntity>> snapshot(
    SyncProfile profile,
    SyncAssets assets,
  );
  Future<SyncState> load(String collection);
  Future<void> save(String collection, SyncState state);
  Future<String?> bookKey(String uuid);
  Future<void> clearBookFile(String uuid);
  Future<void> apply(
    String collection,
    List<SyncRecord> records,
    SyncState state,
    SyncAssets assets,
    SyncProfile profile,
  );
}

bool syncKeyEnabled(String key, SyncProfile profile) {
  if (key.startsWith('user_fonts/')) return profile.resources;
  if (!key.startsWith('setting/')) return true;
  if (!profile.preferences) return false;
  return profile.resources ||
      !const {
        'setting/reader.fontFamily',
        'setting/app.fontFamily',
        'setting/reader.backgroundId',
        'setting/reader.customThemeId',
        'setting/reader.dayBackground',
        'setting/reader.nightBackground',
      }.contains(key);
}
