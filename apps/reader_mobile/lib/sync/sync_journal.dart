import 'dart:convert';

import 'sync_crypto.dart';
import 'sync_layout.dart';
import 'sync_models.dart';
import 'sync_storage.dart';

/// 先发布分类数据，再发布批次索引；索引完整后才允许其他设备提交本批。
class SyncJournal {
  SyncJournal(this.storage, this.crypto, this.write);
  final SyncStorage storage;
  final SyncCrypto crypto;
  final Future<void> Function(String, List<int>) write;

  String _filename(Map<String, dynamic> batch) =>
      '${batch['device']}/'
      '${batch['sequence'].toString().padLeft(12, '0')}.json'
      '${crypto.encrypted ? '.enc' : ''}';

  Future<void> publish(Map<String, dynamic> batch) async {
    final groups = <String, List<Map<String, dynamic>>>{};
    final directories = Map<String, String>.from(batch['directories'] as Map);
    for (final raw in (batch['records'] as List).cast<Map<String, dynamic>>()) {
      final directory = directories[raw['key']]!;
      validateSyncDirectory(directory);
      groups.putIfAbsent(directory, () => []).add(raw);
    }
    final header = {
      'v': syncProtocolVersion,
      'device': batch['device'],
      'sequence': batch['sequence'],
    };
    final parts = <Map<String, String>>[];
    for (final entry in groups.entries) {
      final key = '${entry.key}/changes/${_filename(batch)}';
      final data = {...header, 'records': entry.value};
      await _writeJson(key, data);
      parts.add({'path': key, 'digest': syncDigest(data)});
    }
    await _writeJson('$syncLogDirectory/${_filename(batch)}', {
      ...header,
      'parts': parts,
    });
  }

  Future<List<SyncRecord>> read(String key, String device, int sequence) async {
    final manifest = await _readJson(key, device, sequence);
    final parts = (manifest['parts'] as List).cast<Map<String, dynamic>>();
    if (parts.isEmpty || parts.length > 128) {
      throw const FormatException('同步批次的分类文件数量无效');
    }
    final records = <SyncRecord>[];
    final suffix = '/changes/${_filename(manifest)}';
    for (final part in parts) {
      final path = part['path'] as String;
      if (!path.endsWith(suffix)) throw const FormatException('同步分类文件路径无效');
      validateSyncDirectory(path.substring(0, path.length - suffix.length));
      final data = await _readJson(path, device, sequence);
      if (syncDigest(data) != part['digest']) {
        throw const FormatException('同步分类文件校验失败，未推进同步游标');
      }
      records.addAll(
        (data['records'] as List).map(
          (raw) => SyncRecord.fromJson(raw as Map<String, dynamic>),
        ),
      );
    }
    return records..sort((a, b) => a.clock.compareTo(b.clock));
  }

  Future<void> _writeJson(String key, Map<String, dynamic> data) async =>
      write(key, await crypto.encode(utf8.encode(jsonEncode(data)), key));

  Future<Map<String, dynamic>> _readJson(
    String key,
    String device,
    int sequence,
  ) async {
    final bytes = await storage.read(key);
    if (bytes == null) throw const FormatException('同步批次文件缺失，未推进同步游标');
    final data = jsonDecode(
      utf8.decode(await crypto.decode(bytes, key)),
    ) as Map<String, dynamic>;
    if (data['v'] != syncProtocolVersion ||
        data['device'] != device ||
        data['sequence'] != sequence) {
      throw const FormatException('设备日志身份不一致');
    }
    return data;
  }
}
