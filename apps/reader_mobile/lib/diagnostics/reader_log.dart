import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 应用诊断日志：自动记录设备/版本/阅读事件，可导出分享。
class ReaderLog {
  /// 创建日志器；[directoryProvider] 与 [deviceInfoProvider] 供测试注入。
  ReaderLog({
    Future<Directory> Function()? directoryProvider,
    Future<Map<String, String>> Function()? deviceInfoProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _deviceInfoProvider = deviceInfoProvider ?? _collectDeviceInfo;

  /// 全局实例。
  static final ReaderLog instance = ReaderLog();

  final Future<Directory> Function() _directoryProvider;
  final Future<Map<String, String>> Function() _deviceInfoProvider;
  final List<String> _lines = <String>[];
  File? _file;
  Future<void>? _initializing;
  bool _ready = false;

  /// 日志文件路径（初始化后可用）。
  String? get filePath => _file?.path;

  /// 已缓存行数。
  int get lineCount => _lines.length;

  /// 初始化：建立文件并写入环境头。
  Future<void> initialize() {
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final directory = await _directoryProvider();
      await directory.create(recursive: true);
      _file = File('${directory.path}/reader_log.txt');
      await _file!.create(recursive: true);
      _lines.add('=== Spectacular Reader log ===');
      _lines.add('started_at=${DateTime.now().toIso8601String()}');
      final info = await _deviceInfoProvider();
      for (final entry in info.entries) {
        _lines.add('${entry.key}=${entry.value}');
      }
      _lines.add('--- events ---');
      await _writeAll();
    } catch (error, stackTrace) {
      debugPrint('ReaderLog init failed: $error\n$stackTrace');
    } finally {
      _ready = true;
    }
  }

  /// 记录一条事件。
  Future<void> log(
    String event, {
    Map<String, Object?> fields = const {},
  }) async {
    await initialize();
    final buffer = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' | ')
      ..write(event);
    for (final entry in fields.entries) {
      buffer
        ..write(' | ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    final line = buffer.toString();
    _lines.add(line);
    debugPrint(line);
    await _append(line);
  }

  /// 导出为文本。
  Future<String> exportText() async {
    await initialize();
    return _lines.join('\n');
  }

  /// 确保日志文件存在并返回路径。
  Future<String?> exportFile() async {
    await initialize();
    if (_file == null) {
      return null;
    }
    await _writeAll();
    return _file!.path;
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
        text: '阅读器诊断日志',
      ),
    );
  }

  Future<void> _append(String line) async {
    final file = _file;
    if (file == null) {
      return;
    }
    try {
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (error) {
      debugPrint('ReaderLog append failed: $error');
    }
  }

  Future<void> _writeAll() async {
    final file = _file;
    if (file == null) {
      return;
    }
    try {
      await file.writeAsString('${_lines.join('\n')}\n', flush: true);
    } catch (error) {
      debugPrint('ReaderLog write failed: $error');
    }
  }

  /// 测试/关闭时释放文件状态（不删除文件）。
  void resetForTest() {
    _lines.clear();
    _file = null;
    _initializing = null;
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
      info['package_info_error'] = '$error';
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
      info['device_info_error'] = '$error';
    }
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      info['screen_physical'] =
          '${view.physicalSize.width}x${view.physicalSize.height}';
      info['device_pixel_ratio'] = '${view.devicePixelRatio}';
    } catch (error) {
      info['screen_info_error'] = '$error';
    }
    return info;
  }
}
