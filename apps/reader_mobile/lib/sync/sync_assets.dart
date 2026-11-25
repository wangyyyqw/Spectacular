import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'sync_crypto.dart';
import 'sync_layout.dart';
import 'sync_models.dart';
import 'sync_storage.dart';

/// 只同步应用持有的文件；线上的引用不包含绝对路径。
class SyncAssets {
  SyncAssets(this.root, this.crypto);
  final Directory root;
  final SyncCrypto crypto;
  final files = <String, File>{};
  static const folders = {
    'books',
    'covers',
    'reader_fonts',
    'reader_backgrounds',
    'decoration_images',
  };

  Directory get cache => Directory(p.join(root.path, 'sync', 'objects'));

  Future<Map<String, dynamic>> stage(
    String path, {
    String? digest,
    String? folder,
    bool image = false,
  }) async {
    final source = File(path);
    final targetFolder =
        folder ?? p.split(p.relative(path, from: root.path)).first;
    if (!p.isWithin(p.normalize(root.path), p.normalize(path)) ||
        !folders.contains(targetFolder)) {
      throw const FormatException('不能同步应用目录之外的文件');
    }
    final hash =
        digest ?? (await sha256.bind(source.openRead()).first).toString();
    await cache.create(recursive: true);
    final staged = File(p.join(cache.path, hash));
    if (!await staged.exists()) {
      final part = File('${staged.path}.part');
      await source.copy(part.path);
      await crypto.verifyFile(part, hash);
      await part.rename(staged.path);
    }
    files[hash] = staged;
    return {
      '\$file': hash,
      'size': await staged.length(),
      'folder': targetFolder,
      'extension': path.endsWith('.9.png') ? '.9.png' : p.extension(path),
      'image': image,
    };
  }

  Future<Object?> capture(
    Object? value, {
    String? field,
    bool fileValue = false,
  }) async {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key as String: await capture(
            entry.value,
            field: entry.key as String,
          ),
      };
    }
    if (value is List) {
      return [for (final item in value) await capture(item, field: field)];
    }
    if (value is! String) return value;
    if (!fileValue &&
        !const {
          'file_path',
          'backgroundImagePath',
          'backgroundId',
          'imagePath',
        }.contains(field)) {
      return value;
    }
    final image = value.startsWith('image:');
    final path = image ? value.substring(6) : value;
    if (!p.isAbsolute(path)) return value;
    if (!await File(path).exists()) {
      throw const FileSystemException('需要同步的素材文件已丢失');
    }
    return stage(path, image: image);
  }

  Iterable<Map<String, dynamic>> references(Object? value) sync* {
    if (value is Map<String, dynamic>) {
      if (value.containsKey('\$file')) {
        yield value;
        return;
      }
      for (final item in value.values) {
        yield* references(item);
      }
    } else if (value is List) {
      for (final item in value) {
        yield* references(item);
      }
    }
  }

  Object? withRemotePaths(Object? value, String directory) {
    if (value is List) {
      return [for (final item in value) withRemotePaths(item, directory)];
    }
    if (value is! Map<String, dynamic>) return value;
    if (!value.containsKey('\$file')) {
      return {
        for (final entry in value.entries)
          entry.key: withRemotePaths(entry.value, directory),
      };
    }
    final folder = value['folder'];
    final location = switch (folder) {
      'reader_fonts' => 'personal/resources/fonts',
      'reader_backgrounds' => 'personal/resources/backgrounds',
      _ => directory,
    };
    validateSyncDirectory(location);
    final name =
        '${crypto.objectId(value['\$file'] as String)}'
        '${value['extension']}${crypto.encrypted ? '.enc' : ''}';
    return {
      ...value,
      'path': '$location/${folder == 'books' ? '' : 'files/'}$name',
    };
  }

  Future<void> upload(Map<String, dynamic> ref, SyncStorage storage) async {
    _validate(ref);
    final digest = ref['\$file'] as String;
    final key = ref['path'] as String;
    // 本机缓存是不可变的已验证快照，原书随后编辑或删除不影响待发送批次。
    final source = files[digest] ?? File(p.join(cache.path, digest));
    final encoded = File('${source.path}.upload');
    try {
      await crypto.verifyFile(source, digest);
      await crypto.encodeFile(source, encoded, digest);
      await storage.upload(key, encoded);
    } finally {
      if (await encoded.exists()) await encoded.delete();
    }
  }

  Future<void> download(Map<String, dynamic> ref, SyncStorage storage) async {
    _validate(ref);
    final digest = ref['\$file'] as String;
    final target = File(p.join(cache.path, digest));
    if (await target.exists()) {
      files[digest] = target;
      return;
    }
    await cache.create(recursive: true);
    final encoded = File('${target.path}.download');
    final decoded = File('${target.path}.part');
    try {
      await storage.download(ref['path'] as String, encoded);
      await crypto.decodeFile(encoded, decoded, digest, ref['size'] as int);
      await crypto.verifyFile(decoded, digest);
      if (await decoded.length() != ref['size']) {
        throw const FormatException('同步对象的大小不一致');
      }
      await decoded.rename(target.path);
      files[digest] = target;
    } finally {
      for (final file in [encoded, decoded]) {
        if (await file.exists()) await file.delete();
      }
    }
  }

  void _validate(Map<String, dynamic> ref) {
    final extension = ref['extension'];
    if (ref['\$file'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(ref['\$file'] as String) ||
        ref['size'] is! int ||
        (ref['size'] as int) < 0 ||
        !folders.contains(ref['folder']) ||
        extension is! String ||
        !RegExp(r'^(\.[a-zA-Z0-9]+){0,2}$').hasMatch(extension) ||
        ref['image'] is! bool ||
        ref['path'] is! String) {
      throw const FormatException('同步文件引用无效');
    }
    final path = ref['path'] as String;
    validateSyncPath(path);
    final directory = p.posix.dirname(path);
    validateSyncDirectory(
      directory.endsWith('/files')
          ? directory.substring(0, directory.length - '/files'.length)
          : directory,
    );
    final name =
        '${crypto.objectId(ref['\$file'] as String)}'
        '$extension${crypto.encrypted ? '.enc' : ''}';
    if (p.posix.basename(path) != name) {
      throw const FormatException('同步文件路径与内容身份不一致');
    }
  }

  Future<Object?> resolve(Object? value) async {
    if (value is List) return [for (final item in value) await resolve(item)];
    if (value is! Map<String, dynamic>) return value;
    if (!value.containsKey('\$file')) {
      return {
        for (final entry in value.entries)
          entry.key: await resolve(entry.value),
      };
    }
    _validate(value);
    final digest = value['\$file'] as String;
    final folder = value['folder'] as String;
    if (folder == 'books') return File(p.join(cache.path, digest)).path;
    final prefix = folder == 'decoration_images'
        ? 'decoration-sync-'
        : folder == 'reader_backgrounds'
        ? 'background-sync-'
        : '';
    final directory = Directory(p.join(root.path, folder));
    await directory.create(recursive: true);
    final target = File(
      p.join(directory.path, '$prefix$digest${value['extension']}'),
    );
    if (!await target.exists()) {
      await File(p.join(cache.path, digest)).copy(target.path);
    }
    return '${value['image'] == true ? 'image:' : ''}${target.path}';
  }
}

Object? decodeSyncSetting(String value) {
  if (!value.startsWith('{') && !value.startsWith('[')) return value;
  return jsonDecode(value);
}
