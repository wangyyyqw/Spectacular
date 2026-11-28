import 'dart:convert';
import 'dart:math';

import 'sync_layout.dart';
import 'sync_models.dart';

/// 状态只落在本机；待发送批次在发布成功前不会移除。
class SyncState {
  SyncState({required this.device});
  final String device;
  int clock = 0;
  int sequence = 0;
  final heads = <String, SyncRecord>{};
  final baselines = <String, String>{};
  final cursors = <String, int>{};
  final pending = <Map<String, dynamic>>[];
  final objects = <String>{};
  final conflicts = <String, Map<String, SyncRecord>>{};
  final deferred = <String, List<SyncRecord>>{};

  /// 暂停类别保留未应用的因果分支，不能提前并入本机已观察版本。
  void defer(SyncRecord incoming) {
    clock = max(clock, incoming.clock);
    final records = deferred.putIfAbsent(incoming.key, () => []);
    if (records.any((record) => record.covers(incoming))) return;
    records.removeWhere(incoming.covers);
    records.add(incoming);
  }

  SyncRecord change(SyncEntity entity) {
    final previous = heads[entity.key];
    clock = max(clock, previous?.clock ?? 0) + 1;
    final record = SyncRecord(
      entity.key,
      entity.data,
      deleted: entity.deleted,
      device: device,
      clock: clock,
      vector: {...?previous?.vector, device: clock},
    );
    heads[entity.key] = record;
    baselines[entity.key] = entity.digest;
    return record;
  }

  /// 因果较旧的副本不能覆盖较新数据；并发删除优先，恢复须是新操作。
  bool receive(SyncRecord incoming, {bool preserveConcurrent = false}) {
    clock = max(clock, incoming.clock);
    final current = heads[incoming.key];
    if (current == null || incoming.covers(current)) {
      heads[incoming.key] = incoming;
      conflicts.remove(incoming.key);
      return true;
    }
    if (current.covers(incoming)) return false;
    // 只替换新操作已覆盖的分支，不能用合并后的代表版本清除其他冲突。
    final versions = {
      ...?conflicts[incoming.key],
      if (!conflicts.containsKey(incoming.key)) current.version: current,
    }..removeWhere((_, record) => incoming.covers(record));
    versions[incoming.version] = incoming;
    final winner = versions.values.reduce(_winner);
    heads[incoming.key] = versions.values.fold(
      winner,
      (merged, record) => merged.observed(record),
    );
    final keepChoice =
        preserveConcurrent ||
        (conflicts.containsKey(incoming.key) &&
            const {'setting', 'user_fonts'}.contains(incoming.type));
    if (versions.values.any(
      (record) => keepChoice
          ? winner.digest != record.digest
          : _needsChoice(winner, record),
    )) {
      conflicts[incoming.key] = versions;
      return false;
    }
    conflicts.remove(incoming.key);
    return true;
  }

  SyncRecord _winner(SyncRecord a, SyncRecord b) {
    if (a.deleted != b.deleted) return a.deleted ? a : b;
    final order = a.clock.compareTo(b.clock);
    return order > 0 || (order == 0 && a.device.compareTo(b.device) > 0)
        ? a
        : b;
  }

  bool _needsChoice(SyncRecord a, SyncRecord b) {
    if (a.deleted || b.deleted || a.digest == b.digest) return false;
    if (!const {
      'book',
      'reading_progress',
      'annotations',
      'book_reviews',
      'decorations',
      'list',
      'decoration_style',
    }.contains(a.type)) {
      return false;
    }
    final first = Map<String, dynamic>.of(a.data)
      ..remove('created_at')
      ..remove('updated_at')
      ..remove('aliases');
    final second = Map<String, dynamic>.of(b.data)
      ..remove('created_at')
      ..remove('updated_at')
      ..remove('aliases');
    if (a.type == 'book') {
      first.remove('uuid');
      second.remove('uuid');
    }
    return syncDigest(first) != syncDigest(second);
  }

  void enqueue(List<SyncRecord> records) {
    if (records.isEmpty) return;
    pending.add({
      'v': syncProtocolVersion,
      'device': device,
      'sequence': ++sequence,
      'directories': {
        for (final record in records)
          record.key: syncRecordDirectory(record, heads),
      },
      'records': records.map((record) => record.toJson()).toList(),
    });
  }

  String encode() => jsonEncode({
    'device': device,
    'clock': clock,
    'sequence': sequence,
    'heads': heads.map((key, value) => MapEntry(key, value.toJson())),
    'baselines': baselines,
    'cursors': cursors,
    'pending': pending,
    'objects': objects.toList(),
    'deferred': deferred.map(
      (key, records) =>
          MapEntry(key, records.map((record) => record.toJson()).toList()),
    ),
    'conflicts': conflicts.map(
      (key, values) => MapEntry(
        key,
        values.map((version, record) => MapEntry(version, record.toJson())),
      ),
    ),
  });

  factory SyncState.decode(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    final state = SyncState(device: json['device'] as String)
      ..clock = json['clock'] as int
      ..sequence = json['sequence'] as int;
    state.heads.addAll(
      (json['heads'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(key, SyncRecord.fromJson(value as Map<String, dynamic>)),
      ),
    );
    state.baselines.addAll(Map<String, String>.from(json['baselines'] as Map));
    state.cursors.addAll(Map<String, int>.from(json['cursors'] as Map));
    state.pending.addAll(
      (json['pending'] as List).cast<Map<String, dynamic>>(),
    );
    state.objects.addAll((json['objects'] as List).cast<String>());
    for (final entry
        in (json['deferred'] as Map<String, dynamic>? ?? {}).entries) {
      state.deferred[entry.key] = [
        for (final record in entry.value as List)
          SyncRecord.fromJson(record as Map<String, dynamic>),
      ];
    }
    for (final entry in (json['conflicts'] as Map<String, dynamic>).entries) {
      state.conflicts[entry.key] = (entry.value as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(key, SyncRecord.fromJson(value as Map<String, dynamic>)),
      );
    }
    return state;
  }
}
