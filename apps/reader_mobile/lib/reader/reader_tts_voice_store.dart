import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../rea_micro/rea_micro_models.dart';

/// 阅微离线音色的模型家族。
enum ReaderOfflineModelKind {
  /// VITS / Piper 模型。
  vits,

  /// Matcha 声学模型加声码器。
  matcha,

  /// Kokoro 多语言模型。
  kokoro,

  /// Kitten 模型。
  kitten;

  /// 从持久化值解析。
  static ReaderOfflineModelKind? fromId(String value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

/// 已下载或可下载的离线音色。
class ReaderOfflineVoice {
  /// 创建音色。
  const ReaderOfflineVoice({
    required this.id,
    required this.downloadUrl,
    this.name = '',
    this.language = '',
    this.quality = '',
    this.speakerCount = 1,
    this.sampleRate = 0,
    this.installed = false,
    this.localPath = '',
  });

  /// 音色标识。
  final String id;

  /// 音色包下载地址。
  final String downloadUrl;

  /// 显示名称。
  final String name;

  /// 语言。
  final String language;

  /// 音质描述。
  final String quality;

  /// 说话人数量。
  final int speakerCount;

  /// 采样率。
  final int sampleRate;

  /// 是否已安装。
  final bool installed;

  /// 本地音色目录。
  final String localPath;

  /// 界面显示名称。
  String get displayName => name.trim().isEmpty ? id : name;

  /// 界面音色说明。
  String get detail {
    final values = <String>[
      if (language.trim().isNotEmpty) language.trim(),
      if (quality.trim().isNotEmpty) quality.trim(),
      if (speakerCount > 1) '$speakerCount 位说话人',
      if (sampleRate > 0) '$sampleRate Hz',
    ];
    return values.join(' · ');
  }

  /// 从阅微接口音色映射；接口只给标识和地址时使用官方预设补齐。
  factory ReaderOfflineVoice.fromCatalog(ReaMicroTtsVoice voice) {
    final preset = presetForId(voice.id);
    return ReaderOfflineVoice(
      id: voice.id,
      downloadUrl: voice.downloadUrl.trim().isNotEmpty
          ? voice.downloadUrl.trim()
          : voice.fallbackDownloadUrl.trim().isNotEmpty
          ? voice.fallbackDownloadUrl.trim()
          : preset.downloadUrl,
      name: voice.name.trim().isNotEmpty ? voice.name.trim() : preset.name,
      language: voice.language.trim().isNotEmpty
          ? voice.language.trim()
          : preset.language,
      quality: voice.quality.trim().isNotEmpty
          ? voice.quality.trim()
          : preset.quality,
      speakerCount: voice.numberOfSpeakers > 0
          ? voice.numberOfSpeakers
          : preset.speakerCount,
      sampleRate: _parseSampleRate(voice.sampleRate),
    );
  }

  /// 按标识补全官方音色预设。
  static ReaderOfflineVoice presetForId(String id) {
    for (final voice in officialVoices) {
      if (voice.id == id) return voice;
    }
    final derived = _deriveVoiceFromId(id);
    return ReaderOfflineVoice(id: id, downloadUrl: '', name: derived.name);
  }

  /// 切换安装状态。
  ReaderOfflineVoice copyWith({
    String? downloadUrl,
    String? name,
    String? language,
    String? quality,
    int? speakerCount,
    int? sampleRate,
    bool? installed,
    String? localPath,
  }) => ReaderOfflineVoice(
    id: id,
    downloadUrl: downloadUrl ?? this.downloadUrl,
    name: name ?? this.name,
    language: language ?? this.language,
    quality: quality ?? this.quality,
    speakerCount: speakerCount ?? this.speakerCount,
    sampleRate: sampleRate ?? this.sampleRate,
    installed: installed ?? this.installed,
    localPath: localPath ?? this.localPath,
  );

  /// 官方内置音色；未登录时也可直接下载。
  static const List<ReaderOfflineVoice> officialVoices = <ReaderOfflineVoice>[
    ReaderOfflineVoice(
      id: 'vits-piper-zh_CN-chaowen-medium',
      name: '超文',
      language: '中文',
      quality: '中等质量',
      speakerCount: 1,
      sampleRate: 22050,
      downloadUrl:
          'https://minio.zhendong.ltd/reamicro/'
          'vits-piper-zh_CN-chaowen-medium.tar.bz2',
    ),
    ReaderOfflineVoice(
      id: 'vits-piper-zh_CN-xiao_ya-medium',
      name: '小雅',
      language: '中文',
      quality: '中等质量',
      speakerCount: 1,
      sampleRate: 22050,
      downloadUrl:
          'https://minio.zhendong.ltd/reamicro/'
          'vits-piper-zh_CN-xiao_ya-medium.tar.bz2',
    ),
  ];
}

/// 本地音色包的模型文件描述。
class ReaderOfflineVoiceModel {
  /// 创建模型描述。
  const ReaderOfflineVoiceModel({
    required this.kind,
    required this.model,
    required this.tokens,
    this.voices = '',
    this.acousticModel = '',
    this.vocoder = '',
    this.lexicons = const <String>[],
    this.dataDir = '',
    this.ruleFsts = const <String>[],
    this.speakerCount = 1,
    this.sampleRate = 0,
    this.name = '',
    this.language = '',
    this.quality = '',
  });

  /// 模型家族。
  final ReaderOfflineModelKind kind;

  /// 主模型相对路径。
  final String model;

  /// tokens 相对路径。
  final String tokens;

  /// Kokoro / Kitten 的 voices 文件。
  final String voices;

  /// Matcha 声学模型。
  final String acousticModel;

  /// Matcha 声码器。
  final String vocoder;

  /// 词典文件。
  final List<String> lexicons;

  /// espeak-ng 数据目录。
  final String dataDir;

  /// 文本正则 FST 文件。
  final List<String> ruleFsts;

  /// 说话人数量。
  final int speakerCount;

  /// 采样率。
  final int sampleRate;

  /// 模型卡中的名称。
  final String name;

  /// 模型卡中的语言。
  final String language;

  /// 模型卡中的音质。
  final String quality;

  /// 从 JSON 还原。
  factory ReaderOfflineVoiceModel.fromJson(Map<String, Object?> json) {
    final kind = ReaderOfflineModelKind.fromId(
      json['kind'] is String ? json['kind']! as String : '',
    );
    if (kind == null) throw const FormatException('未知的离线音色模型');
    return ReaderOfflineVoiceModel(
      kind: kind,
      model: json['model'] is String ? json['model']! as String : '',
      tokens: json['tokens'] is String ? json['tokens']! as String : '',
      voices: json['voices'] is String ? json['voices']! as String : '',
      acousticModel: json['acousticModel'] is String
          ? json['acousticModel']! as String
          : '',
      vocoder: json['vocoder'] is String ? json['vocoder']! as String : '',
      lexicons: _stringList(json['lexicons']),
      dataDir: json['dataDir'] is String ? json['dataDir']! as String : '',
      ruleFsts: _stringList(json['ruleFsts']),
      speakerCount: json['speakerCount'] is num
          ? (json['speakerCount']! as num).toInt().clamp(1, 999)
          : 1,
      sampleRate: json['sampleRate'] is num
          ? (json['sampleRate']! as num).toInt()
          : 0,
      name: json['name'] is String ? json['name']! as String : '',
      language: json['language'] is String ? json['language']! as String : '',
      quality: json['quality'] is String ? json['quality']! as String : '',
    );
  }

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'model': model,
    'tokens': tokens,
    'voices': voices,
    'acousticModel': acousticModel,
    'vocoder': vocoder,
    'lexicons': lexicons,
    'dataDir': dataDir,
    'ruleFsts': ruleFsts,
    'speakerCount': speakerCount,
    'sampleRate': sampleRate,
    'name': name,
    'language': language,
    'quality': quality,
  };

  /// 校验模型文件在当前目录中仍完整存在。
  bool isCompleteIn(String rootPath) {
    bool exists(String value) =>
        value.trim().isNotEmpty && File(p.join(rootPath, value)).existsSync();
    if (!exists(model) || !exists(tokens)) return false;
    switch (kind) {
      case ReaderOfflineModelKind.vits:
        return true;
      case ReaderOfflineModelKind.matcha:
        return exists(acousticModel) && exists(vocoder);
      case ReaderOfflineModelKind.kokoro:
      case ReaderOfflineModelKind.kitten:
        return exists(voices);
    }
  }
}

/// 本地离线音色仓库：下载、校验、解压和模型识别。
class ReaderTtsVoiceStore {
  /// 创建仓库。
  ReaderTtsVoiceStore({
    this.rootDirectory,
    this.rootProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// 测试或自定义存储根目录。
  final Directory? rootDirectory;

  /// 延迟读取存储根目录。
  final Future<Directory> Function()? rootProvider;

  final http.Client _client;

  /// 单个音色包最大下载字节数。
  static const int maxDownloadBytes = 1200 * 1024 * 1024;

  /// 单个音色包最大解压字节数。
  static const int maxExtractBytes = 2400 * 1024 * 1024;

  /// 元数据文件名。
  static const String metadataName = 'rea_micro_voice.json';

  Future<Directory> _root() async {
    final injected = rootDirectory;
    if (injected != null) {
      await injected.create(recursive: true);
      return injected;
    }
    final provider = rootProvider;
    if (provider != null) {
      final directory = await provider();
      await directory.create(recursive: true);
      return directory;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'read_aloud_voices'));
    await directory.create(recursive: true);
    return directory;
  }

  /// 返回已安装音色。
  Future<List<ReaderOfflineVoice>> listInstalled() async {
    final root = await _root();
    final result = <ReaderOfflineVoice>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final voice = await _readInstalledVoice(entity);
      if (voice != null) result.add(voice);
    }
    result.sort((left, right) => left.displayName.compareTo(right.displayName));
    return result;
  }

  /// 读取指定音色的模型；未安装或文件缺失时返回 null。
  Future<ReaderOfflineVoiceModel?> modelFor(String id) async {
    final safe = _safeDirectoryName(id);
    if (safe.isEmpty) return null;
    final root = await _root();
    final directory = Directory(p.join(root.path, safe));
    final voice = await _readInstalledVoice(directory);
    if (voice == null || !voice.installed) return null;
    final metadata = await _readMetadata(directory);
    final model = metadata?.model;
    if (model == null || !model.isCompleteIn(directory.path)) return null;
    return model;
  }

  /// 返回本地安装目录。
  Future<String> localPathFor(String id) async {
    final root = await _root();
    return p.join(root.path, _safeDirectoryName(id));
  }

  /// 合并官方、远端与本地音色，同一标识以远端地址和本地状态为准。
  Future<List<ReaderOfflineVoice>> availableVoices({
    Iterable<ReaMicroTtsVoice> remote = const <ReaMicroTtsVoice>[],
  }) async {
    final installed = await listInstalled();
    final installedById = <String, ReaderOfflineVoice>{
      for (final voice in installed) voice.id: voice,
    };
    final merged = <String, ReaderOfflineVoice>{};
    for (final voice in ReaderOfflineVoice.officialVoices) {
      merged[voice.id] = voice;
    }
    for (final voice in remote) {
      if (voice.id.trim().isEmpty) continue;
      merged[voice.id] = ReaderOfflineVoice.fromCatalog(voice);
    }
    for (final entry in installedById.entries) {
      final existing = merged[entry.key];
      merged[entry.key] = existing == null
          ? entry.value
          : entry.value.copyWith(
              downloadUrl: existing.downloadUrl,
              name: existing.name.trim().isEmpty
                  ? entry.value.name
                  : existing.name,
              language: existing.language.trim().isEmpty
                  ? entry.value.language
                  : existing.language,
              quality: existing.quality.trim().isEmpty
                  ? entry.value.quality
                  : existing.quality,
            );
    }
    final result =
        merged.values
            .where(
              (voice) => voice.downloadUrl.trim().isNotEmpty || voice.installed,
            )
            .toList(growable: false)
          ..sort((left, right) {
            if (left.installed != right.installed) {
              return left.installed ? -1 : 1;
            }
            return left.displayName.compareTo(right.displayName);
          });
    return result;
  }

  /// 下载并安装音色包。
  Future<ReaderOfflineVoice> download(
    ReaderOfflineVoice voice, {
    void Function(double progress)? onProgress,
  }) async {
    final url = voice.downloadUrl.trim();
    if (url.isEmpty) throw const FormatException('该音色没有下载地址');
    final safe = _safeDirectoryName(voice.id);
    if (safe.isEmpty) throw const FormatException('音色标识无效');
    final root = await _root();
    final archiveFile = File(
      p.join(
        root.path,
        '.download-$safe-${DateTime.now().microsecondsSinceEpoch}.tar.bz2',
      ),
    );
    Directory? temp;
    try {
      await _downloadToFile(url, archiveFile, onProgress: onProgress);
      temp = Directory(
        p.join(
          root.path,
          '.install-$safe-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await temp.create(recursive: true);
      final extracted = await Isolate.run(
        () => _extractVoicePackage(
          archivePath: archiveFile.path,
          outputPath: temp!.path,
        ),
      );
      final modelRoot = extracted.modelRoot;
      final model = ReaderOfflineVoiceModel.fromJson(extracted.model);
      if (!model.isCompleteIn(modelRoot)) {
        throw const FormatException('音色包缺少完整或受支持的 sherpa-onnx 模型');
      }
      final target = Directory(p.join(root.path, safe));
      if (target.existsSync()) await target.delete(recursive: true);
      final sourceDirectory = Directory(modelRoot);
      if (p.equals(sourceDirectory.path, temp.path)) {
        await temp.rename(target.path);
      } else {
        await sourceDirectory.rename(target.path);
      }
      final installedVoice = ReaderOfflineVoice(
        id: voice.id,
        downloadUrl: url,
        name: voice.name.trim().isEmpty ? model.name : voice.name,
        language: voice.language.trim().isEmpty
            ? model.language
            : voice.language,
        quality: voice.quality.trim().isEmpty ? model.quality : voice.quality,
        speakerCount: math.max(1, model.speakerCount),
        sampleRate: model.sampleRate > 0 ? model.sampleRate : voice.sampleRate,
        installed: true,
        localPath: target.path,
      );
      await _writeMetadata(target, installedVoice, model);
      return installedVoice;
    } finally {
      if (archiveFile.existsSync()) await archiveFile.delete();
      if (temp != null && temp.existsSync()) {
        await temp.delete(recursive: true);
      }
    }
  }

  /// 删除已安装音色。
  Future<void> delete(String id) async {
    final root = await _root();
    final safe = _safeDirectoryName(id);
    if (safe.isEmpty) return;
    final directory = Directory(p.join(root.path, safe));
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  /// 释放网络客户端。
  void close() => _client.close();

  Future<void> _downloadToFile(
    String url,
    File destination, {
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('音色下载地址无效');
    }
    final request = http.Request('GET', uri);
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('音色下载失败（HTTP ${response.statusCode}）');
    }
    final total = response.contentLength ?? 0;
    if (total > maxDownloadBytes) {
      throw const FormatException('音色包超过允许的最大体积');
    }
    final sink = destination.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > maxDownloadBytes) {
          throw const FormatException('音色包超过允许的最大体积');
        }
        sink.add(chunk);
        if (total > 0) onProgress?.call((received / total).clamp(0, 1));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received == 0) throw const FormatException('音色包为空');
    onProgress?.call(1);
  }

  Future<ReaderOfflineVoice?> _readInstalledVoice(Directory directory) async {
    if (!await directory.exists()) return null;
    final metadata = await _readMetadata(directory);
    if (metadata == null) {
      final model = _detectVoiceModel(directory);
      if (model == null || !model.isCompleteIn(directory.path)) return null;
      final voice = ReaderOfflineVoice(
        id: p.basename(directory.path),
        downloadUrl: '',
        name: model.name.trim().isEmpty
            ? ReaderOfflineVoice.presetForId(p.basename(directory.path)).name
            : model.name,
        language: model.language,
        quality: model.quality,
        speakerCount: math.max(1, model.speakerCount),
        sampleRate: model.sampleRate,
        installed: true,
        localPath: directory.path,
      );
      await _writeMetadata(directory, voice, model);
      return voice;
    }
    if (metadata.model == null ||
        !metadata.model!.isCompleteIn(directory.path)) {
      return null;
    }
    return metadata.voice.copyWith(
      speakerCount: math.max(1, metadata.model!.speakerCount),
      sampleRate: metadata.model!.sampleRate > 0
          ? metadata.model!.sampleRate
          : metadata.voice.sampleRate,
      installed: true,
      localPath: directory.path,
    );
  }

  Future<_VoiceMetadata?> _readMetadata(Directory directory) async {
    final file = File(p.join(directory.path, metadataName));
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      final id = decoded['id'] is String ? decoded['id']! as String : '';
      final voiceMap = decoded['voice'];
      final modelMap = decoded['model'];
      if (id.isEmpty ||
          voiceMap is! Map<String, Object?> ||
          modelMap is! Map<String, Object?>) {
        return null;
      }
      return _VoiceMetadata(
        voice: ReaderOfflineVoice(
          id: id,
          downloadUrl: voiceMap['downloadUrl'] is String
              ? voiceMap['downloadUrl']! as String
              : '',
          name: voiceMap['name'] is String ? voiceMap['name']! as String : '',
          language: voiceMap['language'] is String
              ? voiceMap['language']! as String
              : '',
          quality: voiceMap['quality'] is String
              ? voiceMap['quality']! as String
              : '',
          speakerCount: voiceMap['speakerCount'] is num
              ? (voiceMap['speakerCount']! as num).toInt()
              : 1,
          sampleRate: voiceMap['sampleRate'] is num
              ? (voiceMap['sampleRate']! as num).toInt()
              : 0,
        ),
        model: ReaderOfflineVoiceModel.fromJson(modelMap),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMetadata(
    Directory directory,
    ReaderOfflineVoice voice,
    ReaderOfflineVoiceModel model,
  ) async {
    await File(p.join(directory.path, metadataName)).writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'version': 1,
        'id': voice.id,
        'voice': <String, Object?>{
          'downloadUrl': voice.downloadUrl,
          'name': voice.name,
          'language': voice.language,
          'quality': voice.quality,
          'speakerCount': voice.speakerCount,
          'sampleRate': voice.sampleRate,
        },
        'model': model.toJson(),
      }),
      flush: true,
    );
  }
}

class _VoiceMetadata {
  const _VoiceMetadata({required this.voice, required this.model});

  final ReaderOfflineVoice voice;
  final ReaderOfflineVoiceModel? model;
}

class _ExtractedVoice {
  const _ExtractedVoice({required this.modelRoot, required this.model});

  final String modelRoot;
  final Map<String, Object?> model;
}

_ExtractedVoice _extractVoicePackage({
  required String archivePath,
  required String outputPath,
}) {
  final output = Directory(outputPath)..createSync(recursive: true);
  final input = InputFileStream(archivePath);
  var extractedBytes = 0;
  var entries = 0;
  try {
    final decompressed = BZip2Decoder().decodeLazy(input, verify: true);
    TarDecoder().decodeStream(
      decompressed,
      storeData: true,
      keepEntries: false,
      callback: (entry) {
        entries++;
        if (entries > 4000) throw const FormatException('音色包文件数量异常');
        final normalized = entry.name.replaceAll('\\', '/');
        if (!_isSafeArchivePath(normalized)) {
          throw const FormatException('音色包包含不安全路径');
        }
        final relative = normalized.startsWith('./')
            ? normalized.substring(2)
            : normalized;
        if (relative.isEmpty) return;
        final target = File(p.join(output.path, relative));
        final canonical = target.absolute.path;
        if (!p.isWithin(output.absolute.path, canonical) &&
            !p.equals(output.absolute.path, canonical)) {
          throw const FormatException('音色包包含越界路径');
        }
        if (entry.isFile) {
          if (entry.symbolicLink != null) {
            throw const FormatException('音色包不能包含链接文件');
          }
          final parent = target.parent;
          parent.createSync(recursive: true);
          final sink = target.openSync(mode: FileMode.write);
          try {
            final stream = entry.getContent();
            if (stream == null) {
              throw const FormatException('音色包文件内容缺失');
            }
            while (!stream.isEOS) {
              final chunk = stream.readBytes(64 * 1024).toUint8List();
              if (chunk.isEmpty) break;
              extractedBytes += chunk.length;
              if (extractedBytes > ReaderTtsVoiceStore.maxExtractBytes) {
                throw const FormatException('音色包解压后超过允许的最大体积');
              }
              sink.writeFromSync(chunk);
            }
          } finally {
            sink.closeSync();
          }
        } else {
          target.parent.createSync(recursive: true);
        }
      },
    );
  } finally {
    input.closeSync();
  }
  final children = output.listSync(followLinks: false);
  final modelRoot = children.length == 1 && children.single is Directory
      ? children.single.path
      : output.path;
  final model = _detectVoiceModel(Directory(modelRoot));
  if (model == null) {
    throw const FormatException('音色包缺少完整或受支持的 sherpa-onnx 模型');
  }
  return _ExtractedVoice(modelRoot: modelRoot, model: model.toJson());
}

ReaderOfflineVoiceModel? _detectVoiceModel(Directory directory) {
  if (!directory.existsSync()) return null;
  final files = directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList(growable: false);
  String relative(FileSystemEntity entity) =>
      p.relative(entity.path, from: directory.path).replaceAll('\\', '/');
  File? findExact(String name) {
    for (final file in files) {
      if (p.basename(file.path).toLowerCase() == name.toLowerCase()) {
        return file;
      }
    }
    return null;
  }

  final tokens = findExact('tokens.txt');
  if (tokens == null) return null;
  final onnx = files
      .where((file) => p.extension(file.path).toLowerCase() == '.onnx')
      .toList(growable: false);
  final modelFile = findExact('model.onnx');
  final voiceFile = findExact('voices.bin');
  final rootName = p.basename(directory.path).toLowerCase();
  final maxSpeakers = _readSpeakerCount(directory, files);
  final sampleRate = _readSampleRate(directory, files);
  final card = _readModelCard(directory);

  ReaderOfflineVoiceModel build({
    required ReaderOfflineModelKind kind,
    File? model,
    String acoustic = '',
    String vocoder = '',
    List<File> lexicons = const <File>[],
    Directory? dataDir,
  }) => ReaderOfflineVoiceModel(
    kind: kind,
    model: model == null ? '' : relative(model),
    tokens: relative(tokens),
    voices: voiceFile == null ? '' : relative(voiceFile),
    acousticModel: acoustic,
    vocoder: vocoder,
    lexicons: <String>[for (final file in lexicons) relative(file)],
    dataDir: dataDir == null ? '' : relative(dataDir),
    ruleFsts: <String>[
      for (final file in files)
        if (p.extension(file.path).toLowerCase() == '.fst') relative(file),
    ],
    speakerCount: math.max(1, maxSpeakers),
    sampleRate: sampleRate,
    name: card.name,
    language: card.language,
    quality: card.quality,
  );

  final dataDirectory = <Directory>[
    for (final name in const <String>['espeak-ng-data', 'data'])
      if (Directory(p.join(directory.path, name)).existsSync())
        Directory(p.join(directory.path, name)),
  ];
  final dataDir = dataDirectory.isEmpty ? null : dataDirectory.first;
  final lexiconFiles = <File>[
    for (final file in files)
      if (p.extension(file.path).toLowerCase() == '.txt' &&
          p.basename(file.path).toLowerCase().startsWith('lexicon'))
        file,
  ];

  if (rootName.contains('zipvoice') ||
      rootName.contains('pocket') ||
      (findExact('encoder.onnx') != null &&
          findExact('decoder.onnx') != null &&
          modelFile == null)) {
    return null;
  }

  if (voiceFile != null && modelFile != null) {
    if (rootName.contains('kitten')) {
      return build(
        kind: ReaderOfflineModelKind.kitten,
        model: modelFile,
        dataDir: dataDir,
      );
    }
    return build(
      kind: ReaderOfflineModelKind.kokoro,
      model: modelFile,
      lexicons: lexiconFiles,
      dataDir: dataDir,
    );
  }

  File? vocoder;
  File? acoustic;
  for (final file in onnx) {
    final name = p.basename(file.path).toLowerCase();
    if (name.contains('vocos') || name.contains('vocoder')) {
      vocoder ??= file;
    }
    if (name.contains('model-steps') || name.contains('acoustic')) {
      acoustic ??= file;
    }
  }
  if (acoustic != null && vocoder != null) {
    return build(
      kind: ReaderOfflineModelKind.matcha,
      acoustic: relative(acoustic),
      vocoder: relative(vocoder),
      lexicons: lexiconFiles,
      dataDir: dataDir,
    );
  }

  final vitsModel =
      modelFile ??
      (onnx.isEmpty
          ? null
          : onnx.firstWhere((file) {
              final name = p.basename(file.path).toLowerCase();
              return !name.contains('vocoder') && !name.contains('vocos');
            }, orElse: () => onnx.first));
  if (vitsModel == null) return null;
  return build(
    kind: ReaderOfflineModelKind.vits,
    model: vitsModel,
    lexicons: lexiconFiles,
    dataDir: dataDir,
  );
}

class _ModelCard {
  const _ModelCard({this.name = '', this.language = '', this.quality = ''});

  final String name;
  final String language;
  final String quality;
}

_ModelCard _readModelCard(Directory directory) {
  final candidates = <String>['MODEL_CARD', 'README.md', 'README'];
  String? text;
  for (final name in candidates) {
    final file = File(p.join(directory.path, name));
    if (file.existsSync()) {
      try {
        text = file.readAsStringSync();
        break;
      } catch (_) {
        continue;
      }
    }
  }
  if (text == null) return const _ModelCard();
  final nameMatch = RegExp(
    r'^#\s*model\s+card\s+for\s+(.+?)(?:\s*\(|\s*$)',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(text);
  final languageMatch = RegExp(
    r'^\*\s*language:\s*([^\s(]+)',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(text);
  final qualityMatch = RegExp(
    r'^\*\s*quality:\s*(.+)$',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(text);
  return _ModelCard(
    name: nameMatch?.group(1)?.trim() ?? '',
    language: _displayLanguage(languageMatch?.group(1)?.trim() ?? ''),
    quality: _displayQuality(qualityMatch?.group(1)?.trim() ?? ''),
  );
}

int _readSpeakerCount(Directory directory, List<File> files) {
  final card = File(p.join(directory.path, 'MODEL_CARD'));
  if (card.existsSync()) {
    try {
      final match = RegExp(
        r'^\*\s*speakers:\s*(\d+)',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(card.readAsStringSync());
      final value = int.tryParse(match?.group(1) ?? '');
      if (value != null && value > 0) return value;
    } catch (_) {
      // 模型卡损坏时继续读 ONNX 配置。
    }
  }
  for (final file in files) {
    final name = p.basename(file.path).toLowerCase();
    if (name != 'config.json' && !name.endsWith('.onnx.json')) continue;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) continue;
      for (final key in const <String>[
        'num_speakers',
        'n_speakers',
        'speaker_count',
        'numSpeakers',
      ]) {
        final value = decoded[key];
        if (value is num && value > 0) return value.toInt();
      }
    } catch (_) {
      continue;
    }
  }
  return 1;
}

int _readSampleRate(Directory directory, List<File> files) {
  for (final file in files) {
    final name = p.basename(file.path).toLowerCase();
    if (name != 'config.json' && !name.endsWith('.onnx.json')) continue;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) continue;
      final audio = decoded['audio'];
      if (audio is Map<String, Object?>) {
        for (final key in const <String>[
          'sample_rate',
          'sampling_rate',
          'sampleRate',
        ]) {
          final value = audio[key];
          if (value is num && value > 0) return value.toInt();
        }
      }
      for (final key in const <String>[
        'sample_rate',
        'sampling_rate',
        'sampleRate',
      ]) {
        final value = decoded[key];
        if (value is num && value > 0) return value.toInt();
      }
    } catch (_) {
      continue;
    }
  }
  final card = File(p.join(directory.path, 'MODEL_CARD'));
  if (card.existsSync()) {
    try {
      final match =
          RegExp(
            r'^\*\s*sample\s*rate:\s*([\d,]+)',
            caseSensitive: false,
            multiLine: true,
          ).firstMatch(card.readAsStringSync()) ??
          RegExp(
            r'^\*\s*samplerate:\s*([\d,]+)',
            caseSensitive: false,
            multiLine: true,
          ).firstMatch(card.readAsStringSync());
      return int.tryParse((match?.group(1) ?? '').replaceAll(',', '')) ?? 0;
    } catch (_) {
      return 0;
    }
  }
  return 0;
}

String _displayLanguage(String value) {
  final lower = value.toLowerCase();
  if (lower.isEmpty) return '';
  if (lower.startsWith('zh') || lower == 'chinese') return '中文';
  if (lower.startsWith('en') || lower == 'english') return '英文';
  if (lower.startsWith('ja') || lower == 'japanese') return '日文';
  if (lower.startsWith('ko') || lower == 'korean') return '韩文';
  if (lower == 'multi-lang' || lower == 'multilingual') return '多语言';
  return value;
}

String _displayQuality(String value) {
  switch (value.toLowerCase()) {
    case 'low':
      return '低质量';
    case 'medium':
      return '中等质量';
    case 'high':
      return '高质量';
    default:
      return value;
  }
}

int _parseSampleRate(String value) {
  final normalized = value.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(normalized) ?? 0;
}

bool _isSafeArchivePath(String name) {
  if (name.isEmpty || name.startsWith('/') || name.contains('\u0000')) {
    return false;
  }
  if (RegExp(r'^[A-Za-z]:').hasMatch(name)) return false;
  for (final part in name.split('/')) {
    if (part == '..') return false;
  }
  return true;
}

String _safeDirectoryName(String id) {
  final value = id.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  if (value.isEmpty || value == '.' || value == '..') return '';
  return value.length > 120 ? value.substring(0, 120) : value;
}

List<String> _stringList(Object? value) => <String>[
  if (value is List<Object?>)
    for (final item in value)
      if (item is String) item,
];

({String name, String language}) _deriveVoiceFromId(String id) {
  final value = id.toLowerCase();
  if (value.contains('zh_cn-chaowen')) {
    return (name: '超文', language: '中文');
  }
  if (value.contains('zh_cn-xiao_ya')) {
    return (name: '小雅', language: '中文');
  }
  if (value.contains('multi-lang')) {
    return (name: 'Kokoro 多语言', language: '多语言');
  }
  if (value.contains('kitten')) return (name: 'Kitten', language: '英文');
  if (value.contains('matcha')) return (name: 'Matcha', language: '中文');
  if (value.contains('kokoro')) return (name: 'Kokoro', language: '英文');
  return (name: id, language: '');
}
