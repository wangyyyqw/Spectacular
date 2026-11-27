import 'dart:convert';
import 'dart:io';

import 'sync_assets.dart';
import 'sync_crypto.dart';
import 'sync_journal.dart';
import 'sync_layout.dart';
import 'sync_models.dart';
import 'sync_repository.dart';
import 'sync_state.dart';
import 'sync_storage.dart';

typedef _SyncBatch = ({String device, int sequence, List<SyncRecord> records});

class SyncOutcome {
  const SyncOutcome({
    required this.uploaded,
    required this.downloaded,
    required this.conflicts,
    this.deferred = false,
  });
  final int uploaded;
  final int downloaded;
  final int conflicts;
  final bool deferred;
  String get message => deferred
      ? '本机变更已上传，退出阅读或编辑后接收远端更新'
      : '同步完成：发送 $uploaded 批，接收 $downloaded 批'
            '${conflicts == 0 ? '' : '，$conflicts 项冲突待处理'}';
}

/// 一台设备只写自己的顺序日志，不覆盖其他设备的索引或整个书库。
class SyncEngine {
  SyncEngine({
    required this.repository,
    required this.storage,
    required this.profile,
    required this.credentials,
    this.onStatus,
  });
  final SyncRepository repository;
  final SyncStorage storage;
  final SyncProfile profile;
  final SyncCredentials credentials;
  final void Function(String)? onStatus;
  late SyncCrypto crypto;
  late SyncAssets assets;
  late SyncJournal journal;
  late SyncState state;
  late String collection;

  Future<String> create({
    required bool encrypted,
    Future<void> Function()? beforePublish,
  }) async {
    if (await storage.read('library.json') != null) {
      throw const FormatException('此目录已有同步库，请选择加入，不要覆盖创建');
    }
    for (final directory in ['book', 'personal']) {
      if ((await storage.list(directory)).isNotEmpty) {
        throw const FormatException('此目录保留了同步数据，请加入原库或使用新目录');
      }
    }
    final id = newSyncId();
    final recovery = encrypted
        ? (credentials.recovery.isEmpty
              ? await SyncCrypto.generateKey()
              : credentials.recovery)
        : '';
    final cipher = SyncCrypto(id, recovery);
    final check = await cipher.encode(
      utf8.encode('spectacular-sync-v$syncProtocolVersion'),
      'key-check',
    );
    await beforePublish?.call();
    await _uploadBytes(
      'library.json',
      utf8.encode(
        jsonEncode({
          'v': syncProtocolVersion,
          'id': id,
          'encrypted': encrypted,
          'check': base64Encode(check),
        }),
      ),
      createOnly: true,
    );
    return recovery;
  }

  Future<void> connect() async {
    if (!repository.available) throw StateError('临时模式不能同步');
    final bytes = await storage.read('library.json');
    if (bytes == null) throw const FormatException('此目录没有同步库，请先创建');
    final metadata = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (metadata['v'] != syncProtocolVersion ||
        metadata['id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(metadata['id'] as String)) {
      throw const FormatException('不支持的同步库协议');
    }
    collection = metadata['id'] as String;
    final encrypted = metadata['encrypted'] as bool;
    if (encrypted && credentials.recovery.isEmpty) {
      throw const FormatException('此同步库已加密，请填写恢复密钥');
    }
    crypto = SyncCrypto(collection, encrypted ? credentials.recovery : '');
    final check = await crypto.decode(
      base64Decode(metadata['check'] as String),
      'key-check',
    );
    if (utf8.decode(check) != 'spectacular-sync-v$syncProtocolVersion') {
      throw const FormatException('同步库密钥校验失败');
    }
    assets = SyncAssets(await repository.directory(), crypto);
    journal = SyncJournal(storage, crypto, _uploadBytes);
    state = await repository.load(collection);
  }

  Future<SyncOutcome> sync() async {
    await connect();
    await _restoreNewScopes();
    onStatus?.call('收集本机变更…');
    await _capture();
    final uploaded = await _push();
    if (repository.busy) {
      return SyncOutcome(
        uploaded: uploaded,
        downloaded: 0,
        conflicts: state.conflicts.length,
        deferred: true,
      );
    }
    final downloaded = await _pull();
    return SyncOutcome(
      uploaded: uploaded,
      downloaded: downloaded,
      conflicts: state.conflicts.length,
      deferred: repository.busy,
    );
  }

  Future<void> _capture() async {
    final snapshot = await repository.snapshot(profile, assets);
    final changes = <SyncRecord>[];
    for (final entity in snapshot.values) {
      if (!syncKeyEnabled(entity.key, profile) ||
          state.conflicts.containsKey(entity.key) ||
          state.baselines[entity.key] == entity.digest) {
        continue;
      }
      changes.add(state.change(entity));
    }
    for (final entry in state.baselines.entries.toList()) {
      if (!syncKeyEnabled(entry.key, profile) ||
          snapshot.containsKey(entry.key) ||
          state.heads[entry.key]?.deleted == true ||
          state.conflicts.containsKey(entry.key)) {
        continue;
      }
      changes.add(
        state.change(
          SyncEntity(entry.key, state.heads[entry.key]!.data, deleted: true),
        ),
      );
    }
    for (var index = 0; index < changes.length; index += 128) {
      state.enqueue(changes.skip(index).take(128).toList());
    }
    if (changes.isNotEmpty) await repository.save(collection, state);
  }

  Future<int> _push() async {
    var count = 0;
    while (state.pending.isNotEmpty) {
      final batch = state.pending.first;
      onStatus?.call('发送本机变更 ${batch['sequence']}…');
      await _pushAssets(batch['records'] as List);
      await journal.publish(batch);
      state.pending.removeAt(0);
      await repository.save(collection, state);
      count++;
    }
    return count;
  }

  Future<void> _pushAssets(List<dynamic> records) async {
    final previousCount = state.objects.length;
    try {
      for (final raw in records) {
        final record = SyncRecord.fromJson(raw as Map<String, dynamic>);
        if (record.deleted && record.type != 'book') continue;
        final refs = assets.references(
          record.deleted ? record.data['cover_path'] : record.data,
        );
        for (final ref in refs) {
          final path = ref['path'] as String;
          if (!state.objects.contains(path)) {
            await assets.upload(ref, storage);
            state.objects.add(path);
          }
        }
      }
    } finally {
      // 后续对象或日志失败时复用已成功传输的文件，整批日志仍留待重试。
      if (state.objects.length != previousCount) {
        await repository.save(collection, state);
      }
    }
  }

  Future<int> _pull() async {
    var count = 0;
    final logs = <String, Iterator<String>>{};
    final pending = <String, _SyncBatch>{};
    for (final directory in await storage.list(syncLogDirectory)) {
      final device = directory.split('/').last;
      if (device == state.device) continue;
      logs[device] = (await storage.list(directory)).iterator;
    }
    while (logs.isNotEmpty) {
      if (repository.busy) return count;
      for (final entry in logs.entries.toList()) {
        if (pending.containsKey(entry.key)) continue;
        final batch = await _nextBatch(entry.key, entry.value);
        if (batch == null) {
          logs.remove(entry.key);
        } else {
          pending[entry.key] = batch;
        }
      }
      if (pending.isEmpty || repository.busy) return count;
      // 跨设备依赖先于后续操作；每台设备只预读一批，游标仍逐批提交。
      final batch = pending.values.reduce(
        (a, b) => a.records.first.clock <= b.records.first.clock ? a : b,
      );
      final device = batch.device;
      onStatus?.call(
        '接收设备 ${device.length > 6 ? device.substring(0, 6) : device} 的变更…',
      );
      await _receive(batch);
      pending.remove(device);
      count++;
    }
    return count;
  }

  Future<_SyncBatch?> _nextBatch(String device, Iterator<String> logs) async {
    while (logs.moveNext()) {
      final key = logs.current;
      final sequence = int.tryParse(key.split('/').last.split('.').first);
      if (sequence == null || sequence <= (state.cursors[device] ?? 0)) {
        continue;
      }
      if (sequence != (state.cursors[device] ?? 0) + 1) {
        throw const FormatException('设备日志不完整，未推进同步游标');
      }
      return (
        device: device,
        sequence: sequence,
        records: await _readRecords(key, device, sequence),
      );
    }
    return null;
  }

  Future<List<SyncRecord>> _readRecords(
    String key,
    String device,
    int sequence,
  ) async {
    final records = await journal.read(key, device, sequence);
    var clock = 0;
    for (final record in records) {
      if (record.device != device || record.clock <= clock) {
        throw const FormatException('操作设备身份或日志版本顺序无效');
      }
      clock = record.clock;
    }
    if (records.isEmpty) throw const FormatException('设备日志不包含操作');
    return records;
  }

  Future<void> _receive(_SyncBatch batch) async {
    final records = batch.records;
    for (final record in records.where(
      (record) => !record.deleted || record.type == 'book',
    )) {
      if (!syncKeyEnabled(record.key, profile)) continue;
      for (final ref in assets.references(
        record.deleted ? record.data['cover_path'] : record.data,
      )) {
        await assets.download(ref, storage);
        state.objects.add(ref['path'] as String);
      }
    }
    // 网络传输期间的本地修改先持久化，不能被下载前的旧快照覆盖。
    await _capture();
    final accepted = <SyncRecord>[];
    for (final record in records) {
      final changed = state.receive(record);
      if (changed && syncKeyEnabled(record.key, profile)) {
        accepted.add(state.heads[record.key]!);
      }
    }
    state.cursors[batch.device] = batch.sequence;
    await repository.apply(collection, accepted, state, assets, profile);
  }

  Future<void> resolve(String key, SyncRecord? selected) async {
    await connect();
    if (repository.busy) throw StateError('请先退出阅读或编辑');
    final snapshot = await repository.snapshot(profile, assets);
    final entity = selected ?? snapshot[key];
    if (entity == null) throw StateError('冲突内容已不存在');
    if (!entity.deleted) {
      for (final ref in assets.references(entity.data)) {
        await assets.download(ref, storage);
      }
    }
    final record = state.change(entity);
    state.conflicts.remove(key);
    state.enqueue([record]);
    await repository.apply(collection, [record], state, assets, profile);
  }

  Future<void> restoreBook(String uuid) async {
    await connect();
    final key = await repository.bookKey(uuid);
    final record = state.heads[key];
    if (record == null || record.deleted) throw StateError('此书尚未上传或已全端移除');
    if (state.conflicts.containsKey(key)) throw StateError('请先处理此书的同步冲突');
    for (final ref in assets.references(record.data)) {
      await assets.download(ref, storage);
    }
    await repository.apply(collection, [record], state, assets, profile);
  }

  Future<void> clearLocalBook(String uuid) async {
    await connect();
    if (repository.busy) throw StateError('请先退出阅读或编辑');
    await _capture();
    if (state.pending.isNotEmpty) throw StateError('此书库有未发送变更，请先完成同步');
    final key = await repository.bookKey(uuid);
    final record = state.heads[key];
    if (record == null || record.deleted || state.conflicts.containsKey(key)) {
      throw StateError('此书尚未上传或有冲突，不能清理本机副本');
    }
    await repository.clearBookFile(uuid);
    final ref = record.data['source_path'] as Map<String, dynamic>;
    final file = File('${assets.cache.path}/${ref['\$file']}');
    if (await file.exists()) await file.delete();
  }

  Future<void> _uploadBytes(
    String key,
    List<int> bytes, {
    bool createOnly = false,
  }) async {
    final directory = Directory(
      '${(await repository.directory()).path}/sync/transfers',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/${newSyncId()}');
    try {
      await file.writeAsBytes(bytes, flush: true);
      await storage.upload(key, file, createOnly: createOnly);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _restoreNewScopes() async {
    if (repository.busy) return;
    final snapshot = await repository.snapshot(profile, assets);
    final restore = state.heads.values
        .where(
          (record) =>
              syncKeyEnabled(record.key, profile) &&
              !state.baselines.containsKey(record.key) &&
              !snapshot.containsKey(record.key) &&
              !state.conflicts.containsKey(record.key),
        )
        .toList();
    if (restore.isEmpty) return;
    for (final record in restore.where((record) => !record.deleted)) {
      for (final ref in assets.references(record.data)) {
        await assets.download(ref, storage);
      }
    }
    await repository.apply(collection, restore, state, assets, profile);
  }
}
