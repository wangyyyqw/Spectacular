import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/epub/epub_exception.dart';
import 'package:share_plus/share_plus.dart';

/// 应用诊断日志：自动记录设备/版本/阅读事件，可导出分享。
class ReaderLog {
  /// 创建日志器；[directoryProvider] 与 [deviceInfoProvider] 供测试注入。
  ReaderLog({
    Future<Directory> Function()? directoryProvider,
    Future<Map<String, String>> Function()? deviceInfoProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _deviceInfoProvider = deviceInfoProvider ?? _collectDeviceInfo,
       _customDirectory = directoryProvider != null;

  /// 全局实例。
  static final ReaderLog instance = ReaderLog();

  final Future<Directory> Function() _directoryProvider;
  final Future<Map<String, String>> Function() _deviceInfoProvider;
  final bool _customDirectory;
  final ListQueue<String> _lines = ListQueue<String>();
  int _droppedLineCount = 0;
  File? _file;
  Future<void>? _initializing;
  Future<void> _fileWork = Future<void>.value();
  bool _ready = false;

  /// 日志文件路径（初始化后可用）。
  String? get filePath => _file?.path;

  /// 已缓存行数。
  int get lineCount => _lines.length;

  /// 内存最多保留最近 1024 行；文件历史另受 [maxLogBytes] 约束。
  static const int maxCachedLines = 1024;

  /// 单行限长，避免异常技术堆栈挤占全部文件预算。
  static const int maxLineCharacters = 8192;

  /// 本次运行因内存容量丢弃的最早日志行数。
  int get droppedLineCount => _droppedLineCount;

  /// 初始化：建立文件并写入环境头。
  Future<void> initialize() {
    if (_ready) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final isFlutterTest = Platform.environment['FLUTTER_TEST'] == 'true';
      if (isFlutterTest && !_customDirectory) {
        // widget test 没有 path_provider/device_info 插件，保留内存日志。
        _cacheLines([
          '=== Spectacular Reader log ===',
          'started_at=${DateTime.now().toIso8601String()}',
          'privacy_version=1',
          'test_mode=true',
          '--- events ---',
        ]);
      } else {
        await _initializeFile();
      }
    } catch (error, stackTrace) {
      _reportLogFailure('初始化', error, stackTrace);
    } finally {
      _ready = true;
    }
  }

  Future<void> _initializeFile() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final file = _file = File('${directory.path}/reader_log.txt');
    await file.create(recursive: true);
    await _trimIfOversize(file);
    await _sanitizeFile(file);
    final info = await _deviceInfoProvider();
    final header = [
      '',
      '=== 新会话 ${DateTime.now().toIso8601String()} ===',
      'privacy_version=1',
      for (final entry in info.entries) _safeHeader(entry.key, entry.value),
      '--- events ---',
    ];
    _cacheLines(header);
    await file.writeAsString(
      '${header.join('\n')}\n',
      mode: FileMode.append,
      flush: true,
    );
    await _trimIfOversize(file);
  }

  void _cacheLines(Iterable<String> lines) {
    for (final line in lines) {
      if (_lines.length == maxCachedLines) {
        _lines.removeFirst();
        _droppedLineCount++;
      }
      _lines.addLast(line);
    }
  }

  /// 记录固定事件标识；阅读内容只保留长度，异常只保留类型与技术帧。
  Future<void> log(
    String event, {
    Map<String, Object?> fields = const {},
  }) async {
    await initialize();
    final line = _formatEvent(DateTime.now().toIso8601String(), event, fields);
    _cacheLines([line]);
    debugPrint(line);
    await _append(line);
  }

  /// 导出为文本：包含历史会话（读文件全量，内存行只是兜底）。
  Future<String> exportText() async {
    await initialize();
    if (_file == null) return _memoryText();
    return _queueFile(() async {
      final file = _file;
      if (file != null) {
        try {
          await _trimIfOversize(file);
          await _sanitizeFile(file);
          return await file.readAsString();
        } catch (error, stackTrace) {
          _reportLogFailure('读取', error, stackTrace);
        }
      }
      return _memoryText();
    });
  }

  String _memoryText() => [
    if (_droppedLineCount > 0) '[内存日志已丢弃最早 $_droppedLineCount 行]',
    ..._lines,
  ].join('\n');

  /// 清空日志文件、内存缓存与丢弃计数。
  Future<void> clear() async {
    await initialize();
    _lines.clear();
    _droppedLineCount = 0;
    if (_file == null) return;
    await _queueFile(() async {
      final file = _file;
      if (file == null) return;
      try {
        await file.writeAsString('', flush: true);
      } catch (error, stackTrace) {
        _reportLogFailure('清空', error, stackTrace);
      }
    });
  }

  /// 历史日志上限：超过就只保留末尾一半，避免无限增长。
  static const int maxLogBytes = 512 * 1024;

  Future<void> _trimIfOversize(File file) async {
    final length = await file.length();
    if (length <= maxLogBytes) return;
    final handle = await file.open();
    late String tail;
    try {
      await handle.setPosition(length - maxLogBytes ~/ 2);
      tail = utf8.decode(
        await handle.read(maxLogBytes ~/ 2),
        allowMalformed: true,
      );
    } finally {
      await handle.close();
    }
    final kept = tail.substring(tail.indexOf('\n') + 1);
    await file.writeAsString('[日志已截断，保留最近 256KB]\n$kept', flush: true);
  }

  Future<void> _sanitizeFile(File file) async {
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    final safe = _sanitizeText(text);
    if (safe != text) await file.writeAsString(safe, flush: true);
    await _trimIfOversize(file);
  }

  Future<T> _queueFile<T>(Future<T> Function() operation) {
    final result = _fileWork.then((_) => operation());
    _fileWork = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// 确保日志文件存在并返回路径。
  Future<String?> exportFile() async {
    await initialize();
    if (_file == null) return null;
    return _queueFile(() async {
      final file = _file;
      if (file == null) return null;
      if (!await file.exists()) {
        await file.writeAsString('${_memoryText()}\n', flush: true);
      }
      await _trimIfOversize(file);
      await _sanitizeFile(file);
      return file.path;
    });
  }

  /// 调起系统分享面板导出日志文件。
  Future<ShareResult> share() async {
    final path = await exportFile();
    if (path == null) {
      throw StateError('日志文件不可用');
    }
    return SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path, mimeType: 'text/plain')],
        subject: 'Spectacular Reader 日志',
        text: '诊断日志已移除书名、检索词和异常正文，请检查后再分享。',
      ),
    );
  }

  Future<void> _append(String line) async {
    if (_file == null) return;
    await _queueFile(() async {
      final file = _file;
      if (file == null) return;
      try {
        await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
        await _trimIfOversize(file);
      } catch (error, stackTrace) {
        _reportLogFailure('追加', error, stackTrace);
      }
    });
  }

  /// 测试/关闭时释放文件状态（不删除文件）。
  void resetForTest() {
    _lines.clear();
    _droppedLineCount = 0;
    _file = null;
    _initializing = null;
    _fileWork = Future<void>.value();
    _ready = false;
  }

  /// 是否已初始化。
  bool get isReady => _ready;

  static Future<Map<String, String>> _collectDeviceInfo() async {
    final info = <String, String>{
      'flutter_version': '3.47.5',
      'dart_version': Platform.version,
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
    };
    try {
      final package = await PackageInfo.fromPlatform();
      info['app_name'] = package.appName;
      info['app_version'] = package.version;
      info['build_number'] = package.buildNumber;
      info['package_name'] = package.packageName;
    } catch (error) {
      info['package_info_error'] = _errorType(error);
    }
    try {
      final device = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await device.androidInfo;
        info['device_manufacturer'] = android.manufacturer;
        info['device_model'] = android.model;
        info['android_version'] = android.version.release;
        info['android_sdk'] = '${android.version.sdkInt}';
      } else if (Platform.isIOS) {
        final ios = await device.iosInfo;
        info['device_model'] = ios.utsname.machine;
        info['ios_version'] = ios.systemVersion;
      } else {
        info['device_model'] = Platform.localHostname;
      }
    } catch (error) {
      info['device_info_error'] = _errorType(error);
    }
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      info['screen_physical'] =
          '${view.physicalSize.width}x${view.physicalSize.height}';
      info['device_pixel_ratio'] = '${view.devicePixelRatio}';
    } catch (error) {
      info['screen_info_error'] = _errorType(error);
    }
    return info;
  }
}

const _contentFields = {
  'query',
  'book',
  'title',
  'booktitle',
  'chaptertitle',
  'author',
  'context',
  'text',
  'quote',
  'snippet',
  'path',
  'sourcepath',
  'filename',
  'identifier',
  'content',
};
const _errorFields = {'error', 'message', 'exception'};
const _knownErrorTypes = {
  'String',
  'Error',
  'Exception',
  'StateError',
  'FormatException',
  'RangeError',
  'ArgumentError',
  'TypeError',
  'FileSystemException',
  'SqliteException',
  'PlatformException',
  'MissingPluginException',
  'EpubException',
};
const _stateValues = {
  'source': {'file', 'memory'},
  'dir': {'next', 'prev'},
  'mode': {
    'cover',
    'coverStack',
    'simulationBessel',
    'simulation3d',
    'scroll',
    'slideHorizontal',
    'none',
  },
  'panel': {'toc', 'theme', 'type', 'settings'},
  'theme': {'white', 'sepia', 'pink', 'green', 'black', 'gray', 'dark'},
  'background': {'none', 'paper', 'linen', 'parchment'},
  'status': {
    'ready',
    'pending',
    'stale',
    'missing',
    'saved',
    'cancelled',
    'failed',
  },
};
const _tapZones = {
  'topLeft',
  'topCenter',
  'topRight',
  'middleLeft',
  'center',
  'middleRight',
  'bottomLeft',
  'bottomCenter',
  'bottomRight',
};
const _tapActions = {'previousPage', 'nextPage', 'openMenu', 'none'};
const _environmentFields = {
  'flutter_version',
  'dart_version',
  'os',
  'os_version',
  'locale',
  'app_name',
  'app_version',
  'build_number',
  'package_name',
  'device_manufacturer',
  'device_model',
  'android_version',
  'android_sdk',
  'ios_version',
  'screen_physical',
  'device_pixel_ratio',
  'package_info_error',
  'device_info_error',
  'screen_info_error',
  'started_at',
  'test_mode',
  'privacy_version',
};
const _hiddenLegacyLine = '[旧日志内容已隐藏]';
final _fixedIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$');
final _technicalType = RegExp(r'^[A-Za-z_][A-Za-z0-9_<>, ?]{0,127}$');
final _bookIdentity = RegExp(r'^[0-9a-fA-F]{8,64}$');
final _customTheme = RegExp(r'^custom:[0-9a-fA-F]{6}:[0-9a-fA-F]{6}$');
final _technicalFrame = RegExp(
  r'^#\d+\s+[A-Za-z0-9_.$<> =?/-]+\s+'
  r'\((?:package:|dart:)[A-Za-z0-9_./-]+\.dart(?::\d+){0,2}\)$',
);

String _formatEvent(
  String timestamp,
  String event,
  Map<String, Object?> fields,
) {
  final name = _fixedIdentifier.hasMatch(event) ? event : 'hidden_event';
  final buffer = StringBuffer('$timestamp | $name');
  for (final entry in _safeFields(fields)) {
    buffer.write(' | ${entry.key}=${entry.value}');
  }
  final line = buffer.toString();
  return line.length <= ReaderLog.maxLineCharacters
      ? line
      : line.substring(0, ReaderLog.maxLineCharacters);
}

Iterable<MapEntry<String, Object?>> _safeFields(
  Map<String, Object?> fields,
) sync* {
  for (final entry in fields.entries) {
    yield _safeField(entry.key, entry.value);
    final value = entry.value;
    final code = value is EpubException ? value.spec?.code : null;
    if (code != null) yield MapEntry('error_code', code);
  }
}

MapEntry<String, Object?> _safeField(String name, Object? value) {
  final key = _fixedIdentifier.hasMatch(name) ? name : 'hidden_field';
  final normalized = name.toLowerCase().replaceAll('_', '');
  if (normalized == 'stack' || normalized == 'stacktrace') {
    return MapEntry(key, _technicalFrames(value));
  }
  if (_errorFields.contains(normalized)) {
    return MapEntry('${key}_type', _errorType(value));
  }
  if (_contentFields.contains(normalized)) {
    return value is String
        ? MapEntry('${key}_length', value.length)
        : MapEntry('${key}_type', value.runtimeType.toString());
  }
  return _safeScalarField(key, value);
}

MapEntry<String, Object?> _safeScalarField(String key, Object? value) {
  if (value is Enum) return MapEntry('${key}_enum', value.name);
  if (value is String) return _safeStringField(key, value);
  if (value == null || value is num || value is bool) {
    return MapEntry(key, value);
  }
  return MapEntry('${key}_type', value.runtimeType.toString());
}

MapEntry<String, Object?> _safeStringField(String key, String value) {
  if (_technicalStringValue(key, value) || _stateStringValue(key, value)) {
    return MapEntry(key, value);
  }
  if (key.toLowerCase().replaceAll('_', '') == 'bookid' &&
      _bookIdentity.hasMatch(value)) {
    return MapEntry(key, value.substring(0, 8).toLowerCase());
  }
  return MapEntry('${key}_length', value.length);
}

bool _technicalStringValue(String key, String value) =>
    (key.endsWith('_type') && _technicalType.hasMatch(value)) ||
    (key.endsWith('_enum') && _fixedIdentifier.hasMatch(value)) ||
    (key == 'error_code' && EpubCodeTable.byCode(value) != null);

bool _stateStringValue(String key, String value) =>
    (_stateValues[key]?.contains(value) ?? false) ||
    (_tapZones.contains(key) && _tapActions.contains(value)) ||
    (key == 'theme' && _customTheme.hasMatch(value));

String _errorType(Object? value) {
  if (value is! String) return value.runtimeType.toString();
  if (value.startsWith('Bad state:')) return 'StateError';
  if (value.startsWith('Invalid argument')) return 'ArgumentError';
  for (final type in _knownErrorTypes) {
    if (value == type ||
        value.startsWith('$type:') ||
        value.startsWith('$type(')) {
      return type;
    }
  }
  return 'String';
}

String _technicalFrames(Object? value) {
  final source = value is StackTrace
      ? value.toString()
      : value is String
      ? value
      : '';
  final limited = source.length > 16384 ? source.substring(0, 16384) : source;
  final frames = limited
      .replaceAll(r'\n', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => _technicalFrame.hasMatch(line))
      .take(20);
  return frames.isEmpty ? '[无可公开的技术帧]' : frames.join(r'\n');
}

void _reportLogFailure(String operation, Object error, StackTrace stack) {
  debugPrint(
    'ReaderLog $operation 失败：${_errorType(error)} | '
    'stack=${_technicalFrames(stack)}',
  );
}

String _safeHeader(String key, String value) {
  if (!_environmentFields.contains(key)) return _hiddenLegacyLine;
  final safe = key.endsWith('_error') ? _errorType(value) : value;
  final line = '$key=${safe.replaceAll('\r', r'\r').replaceAll('\n', r'\n')}';
  return line.length <= 512 ? line : line.substring(0, 512);
}

String _sanitizeText(String text) =>
    text.split('\n').map(_sanitizeStoredLine).join('\n');

String _sanitizeStoredLine(String line) {
  const literalLines = {
    '',
    _hiddenLegacyLine,
    '--- events ---',
    '=== Spectacular Reader log ===',
  };
  if (literalLines.contains(line)) return line;
  if (line.startsWith('[日志已截断，')) return '[日志已截断，保留最近 256KB]';
  final session = _sessionHeader(line);
  if (session != null) return session;
  final parts = line.split(' | ');
  if (parts.length >= 2 && DateTime.tryParse(parts.first) != null) {
    return _formatEvent(parts.first, parts[1], _storedFields(parts.skip(2)));
  }
  if (_technicalFrame.hasMatch(line.trim())) return line.trim();
  final equals = line.indexOf('=');
  return equals < 0
      ? _hiddenLegacyLine
      : _safeHeader(line.substring(0, equals), line.substring(equals + 1));
}

String? _sessionHeader(String line) {
  if (!line.startsWith('=== 新会话 ') || !line.endsWith(' ===')) return null;
  final time = line.substring(8, line.length - 4);
  return DateTime.tryParse(time) != null ? line : null;
}

Map<String, Object?> _storedFields(Iterable<String> entries) {
  final fields = <String, Object?>{};
  for (final entry in entries) {
    final equals = entry.indexOf('=');
    if (equals < 0) continue;
    final key = entry.substring(0, equals);
    final value = entry.substring(equals + 1);
    final identity = key.toLowerCase().replaceAll('_', '') == 'bookid';
    fields[key] = identity
        ? value
        : switch (value) {
            'true' => true,
            'false' => false,
            'null' => null,
            _ => num.tryParse(value) ?? value,
          };
  }
  return fields;
}
