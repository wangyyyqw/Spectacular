import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../library/library_store.dart';
import 'sync_engine.dart';
import 'sync_models.dart';
import 'sync_repository.dart';
import 'sync_s3.dart';
import 'sync_secrets.dart';
import 'sync_state.dart';
import 'sync_storage.dart';
import 'sync_webdav.dart';

/// 一个书库共用一个控制器，手动与自动请求合并，不阻塞本地保存。
class SyncController extends ChangeNotifier {
  SyncController(
    this.library, {
    SyncSecretStore? secrets,
    SyncStorage Function(SyncProfile, SyncCredentials)? storageFactory,
  }) : secrets = secrets ?? PlatformSyncSecrets(),
       repository = library.syncRepository(),
       storageFactory = storageFactory ?? _defaultStorage {
    library.addListener(_changed);
    library.setSyncRestore(restoreBook);
    library.setSyncSettingObserver(_changed);
  }

  final LibraryStore library;
  final SyncRepository repository;
  final SyncSecretStore secrets;
  final SyncStorage Function(SyncProfile, SyncCredentials) storageFactory;
  SyncProfile? profile;
  SyncState? state;
  String message = '尚未配置同步';
  DateTime? lastSync;
  int dataRevision = 0;
  bool _disposed = false;
  bool _foreground = true;
  bool _configuring = false;
  bool _automaticPending = false;
  Timer? _debounce;
  Timer? _periodic;
  Future<SyncOutcome?>? _task;
  Future<void>? _initialization;
  SyncStorage? _activeStorage;
  StreamSubscription<void>? _databaseChanges;
  bool get syncing => _task != null || _configuring;
  bool get available => repository.available;
  bool get _automaticAllowed =>
      !_disposed && available && profile?.automatic == true && _foreground;

  static SyncStorage _defaultStorage(
    SyncProfile profile,
    SyncCredentials credentials,
  ) => profile.provider == SyncProvider.s3
      ? SyncS3Storage(profile, credentials)
      : SyncWebDavStorage(profile, credentials);

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!available) {
      message = '临时模式不能同步';
      return;
    }
    _databaseChanges = repository.changes.listen((_) => _changed());
    try {
      final raw = await library.getSetting('sync.profile.v1');
      if (raw != null && raw.isNotEmpty) {
        profile = SyncProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        profile!.validate();
        final collection = await library.getSetting('sync.collection.v1');
        if (collection != null) state = await repository.load(collection);
        final time = await library.getSetting('sync.lastAt.v1');
        lastSync = time == null ? null : DateTime.tryParse(time);
        message = '等待同步';
      }
      _startAutomatic();
    } catch (error) {
      message = '同步配置加载失败：$error';
    }
    _notify();
  }

  Future<SyncCredentials> credentials() async => profile == null
      ? const SyncCredentials()
      : await secrets.read(profile!.identity) ?? const SyncCredentials();

  Future<void> saveProfile(SyncProfile selected, SyncCredentials credentials) =>
      _exclusive(() => _saveProfile(selected, credentials));

  Future<void> _saveProfile(
    SyncProfile selected,
    SyncCredentials credentials,
  ) async {
    _validateCredentials(selected, credentials);
    await secrets.write(selected.identity, credentials);
    await _rememberProfile(selected);
  }

  void _validateCredentials(SyncProfile selected, SyncCredentials credentials) {
    if (!available) throw StateError('临时模式不能配置同步');
    selected.validate();
    if (selected.provider == SyncProvider.s3 &&
        (credentials.access.trim().isEmpty || credentials.secret.isEmpty)) {
      throw const FormatException('请填写 S3 Access Key 和 Secret Key');
    }
  }

  Future<void> _rememberProfile(SyncProfile selected) async {
    await library.setSetting('sync.profile.v1', jsonEncode(selected.toJson()));
    // 相同连接或选项保存不清空 UUID、版本向量、墓碑与待发送队列。
    if (profile?.identity != selected.identity) state = null;
    profile = selected;
    message = '已保存连接，凭证仅保存在本机安全存储';
    _startAutomatic();
    _notify();
  }

  Future<void> createLibrary(
    SyncProfile selected,
    SyncCredentials credentials, {
    required bool encrypted,
  }) => _exclusive(() async {
    if (encrypted && credentials.recovery.isEmpty) {
      throw const FormatException('请先备份生成的恢复密钥');
    }
    _validateCredentials(selected, credentials);
    final storage = _openStorage(selected, credentials);
    try {
      await _engine(storage, selected, credentials).create(
        encrypted: encrypted,
        beforePublish: () => secrets.write(selected.identity, credentials),
      );
      await _rememberProfile(selected);
      state = null;
      message = '同步库已创建，其他设备可加入相同目录';
    } finally {
      storage.close();
    }
    _notify();
  });

  Future<void> join(SyncProfile selected, SyncCredentials credentials) =>
      _exclusive(() async {
        selected.validate();
        final storage = _openStorage(selected, credentials);
        try {
          final engine = _engine(storage, selected, credentials);
          await engine.connect();
          await _saveProfile(selected, credentials);
          state = engine.state;
          await library.setSetting('sync.collection.v1', engine.collection);
          message = '已加入同步库，首次同步合并本地和远端数据，不覆盖整个书库';
        } finally {
          storage.close();
        }
        _notify();
      });

  SyncEngine _engine(
    SyncStorage storage,
    SyncProfile profile,
    SyncCredentials credentials,
  ) => SyncEngine(
    repository: repository,
    storage: storage,
    profile: profile,
    credentials: credentials,
    onStatus: (status) {
      message = status;
      _notify();
    },
  );

  SyncStorage _openStorage(SyncProfile profile, SyncCredentials credentials) =>
      _activeStorage = storageFactory(profile, credentials);

  Future<SyncOutcome?> synchronize() {
    if (_configuring || _disposed) return Future<SyncOutcome?>.value(null);
    if (_task case final pending?) return pending;
    _debounce?.cancel();
    _automaticPending = false;
    final task = _task = Future<SyncOutcome?>.microtask(_run);
    _notify();
    return task;
  }

  Future<SyncOutcome?> _run() async {
    SyncStorage? storage;
    try {
      final selected = profile;
      if (selected == null) throw StateError('请先创建或加入同步库');
      final secret = await credentials();
      storage = _openStorage(selected, secret);
      final engine = _engine(storage, selected, secret);
      final outcome = await engine.sync();
      state = engine.state;
      lastSync = DateTime.now();
      await library.setSetting('sync.collection.v1', engine.collection);
      await library.setSetting('sync.lastAt.v1', lastSync!.toIso8601String());
      message = outcome.message;
      if (outcome.downloaded > 0) dataRevision++;
      return outcome;
    } catch (error) {
      message = '同步失败，未发送数据与下载游标已保留：$error';
      return null;
    } finally {
      storage?.close();
      _task = null;
      if (_automaticPending) _changed();
      _notify();
    }
  }

  Future<void> resolve(String key, SyncRecord? selected) =>
      _exclusive(() async {
        if (profile == null) throw StateError('请先配置同步');
        final secret = await credentials();
        final storage = _openStorage(profile!, secret);
        try {
          final engine = _engine(storage, profile!, secret);
          await engine.resolve(key, selected);
          state = engine.state;
          dataRevision++;
          message = '已采用所选版本，等待发送解决结果';
          _changed();
        } finally {
          storage.close();
        }
        _notify();
      });

  Future<void> restoreBook(String bookId) async {
    if (profile == null) throw StateError('本机 EPUB 已清理，请先配置同步');
    if (syncing) await _task;
    final secret = await credentials();
    final storage = _openStorage(profile!, secret);
    try {
      await _engine(storage, profile!, secret).restoreBook(bookId);
    } finally {
      storage.close();
    }
  }

  Future<void> testConnection(
    SyncProfile selected,
    SyncCredentials credentials,
  ) => _exclusive(() async {
    selected.validate();
    final storage = _openStorage(selected, credentials);
    final root = await repository.directory();
    final directory = Directory('${root.path}/sync/probes');
    await directory.create(recursive: true);
    final id = newSyncId();
    final key = 'probe-$id';
    final file = await File('${directory.path}/$id')
        .writeAsBytes([83, 89, 78, 67]);
    try {
      await storage.upload(key, file, createOnly: true);
      if (!listEquals(await storage.read(key), [83, 89, 78, 67])) {
        throw const FormatException('连接测试文件读写不一致');
      }
      await storage.list('');
      await storage.delete(key);
      message = '连接测试通过，临时探针已清理';
    } finally {
      storage.close();
      await file.delete();
    }
    _notify();
  });

  Future<void> clearLocalBook(String id) => _exclusive(() async {
    if (profile == null) throw StateError('请先配置同步');
    final secret = await credentials();
    final storage = _openStorage(profile!, secret);
    try {
      await _engine(storage, profile!, secret).clearLocalBook(id);
    } finally {
      storage.close();
    }
    message = '已清理本机 EPUB，阅读记录保留，联网打开时重新下载';
    _notify();
  });

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (syncing || _disposed) throw StateError('请等待当前同步操作结束');
    _configuring = true;
    _notify();
    try {
      return await action();
    } finally {
      _configuring = false;
      if (_automaticPending) _changed();
      _notify();
    }
  }

  void resumed() {
    _foreground = true;
    _startAutomatic();
    _changed();
  }

  void paused() {
    _foreground = false;
    _automaticPending = false;
    _periodic?.cancel();
    _debounce?.cancel();
  }

  void _startAutomatic() {
    _periodic?.cancel();
    _debounce?.cancel();
    _automaticPending = false;
    if (!_automaticAllowed) return;
    _periodic = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _syncAutomatically(),
    );
    _changed();
  }

  void _changed() {
    if (!_automaticAllowed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), _syncAutomatically);
  }

  void _syncAutomatically() {
    if (!_automaticAllowed) return;
    if (syncing) {
      // 慢速传输期间合并请求，结束后补收集本轮快照之后的本地修改。
      _automaticPending = true;
      return;
    }
    unawaited(synchronize());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _activeStorage?.close();
    unawaited(_databaseChanges?.cancel() ?? Future<void>.value());
    _periodic?.cancel();
    _debounce?.cancel();
    library.removeListener(_changed);
    library.setSyncRestore(null);
    library.setSyncSettingObserver(null);
    super.dispose();
  }
}
