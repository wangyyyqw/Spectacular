import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_ui/reader_ui.dart';
import 'package:reader_ui/system_ui.dart';

import 'diagnostics/reader_log.dart';
import 'home/home_shell.dart';
import 'library/library_store.dart';
import 'reader/reader_text_warmup.dart';
import 'storage/startup_storage.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await setReaderSystemBars(statusBar: true, navigationBar: true);
  final log = ReaderLog.instance;
  FlutterError.onError = (details) {
    unawaited(
      log.log(
        'flutter_error',
        fields: <String, Object?>{
          'message': details.exceptionAsString(),
          'library': details.library,
          'context': details.context,
        },
      ),
    );
    FlutterError.presentError(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      log.log(
        'platform_error',
        fields: <String, Object?>{'error': error, 'stack': stack},
      ),
    );
    return false;
  };
  await log.initialize();
  await log.log('app_start');
  assert(readerCorePackageName == 'reader_core');
  assert(readerUiPackageName == 'reader_ui');
  // 数据库不可用时仍可启动，界面显示临时模式并提供同一路径的重试。
  final storage = StartupStorage(log: log);
  await storage.retry();
  try {
    warmUpReaderTextRendering();
  } catch (error, stack) {
    unawaited(
      log.log(
        'text_warmup_failed',
        fields: <String, Object?>{'error': '$error', 'stack': '$stack'},
      ),
    );
  }
  runApp(
    LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      child: ReaderApp.withStorage(storage: storage),
    ),
  );
}

/// 应用壳：四底栏（书架/统计/书评/我的）+ EPUB 导入 + 阅读页。
class ReaderApp extends StatelessWidget {
  /// 创建应用。
  const ReaderApp({
    super.key,
    required this.library,
    required this.progressStore,
  }) : _startupStorage = null;

  /// 正式启动入口，监听数据库失败与恢复后的存储替换。
  ReaderApp.withStorage({super.key, required StartupStorage storage})
    : library = storage.library,
      progressStore = storage.progressStore,
      _startupStorage = storage;

  /// 构造时传入的书架存储；正式恢复入口在监听中使用最新启动存储。
  final LibraryStore library;

  /// 构造时传入的进度存储，与对应书库绑定同一数据库。
  final ReaderProgressStore progressStore;

  final StartupStorage? _startupStorage;

  @override
  Widget build(BuildContext context) {
    final storage = _startupStorage;
    if (storage == null) return _buildApp(library, progressStore);
    return ListenableBuilder(
      listenable: storage,
      builder: (context, child) => _buildApp(
        storage.library,
        storage.progressStore,
        recovery: storage.isTemporary ? storage : null,
      ),
    );
  }

  Widget _buildApp(
    LibraryStore library,
    ReaderProgressStore progressStore, {
    StartupStorage? recovery,
  }) => _ThemedReaderApp(
    key: ObjectKey(library),
    library: library,
    progressStore: progressStore,
    recovery: recovery,
  );
}

class _ThemedReaderApp extends StatefulWidget {
  const _ThemedReaderApp({
    super.key,
    required this.library,
    required this.progressStore,
    this.recovery,
  });

  final LibraryStore library;
  final ReaderProgressStore progressStore;
  final StartupStorage? recovery;

  @override
  State<_ThemedReaderApp> createState() => _ThemedReaderAppState();
}

class _ThemedReaderAppState extends State<_ThemedReaderApp>
    with WidgetsBindingObserver {
  static const _themeModeKey = 'app.themeMode';
  static const _window = OptionalMethodChannel(
    'com.spectacular.reader_mobile/window',
  );
  static final _day = buildAppTheme();
  static final _night = buildAppTheme(brightness: Brightness.dark);

  late final Future<ThemeMode> _savedMode = _loadMode();
  ThemeMode? _selectedMode;
  ThemeMode? _loadedMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final mode = _selectedMode ?? _loadedMode;
    if (mode == ThemeMode.system) unawaited(_syncWindow(ThemeMode.system));
  }

  Future<ThemeMode> _loadMode() async {
    var mode = ThemeMode.system;
    try {
      final value = await widget.library.getSetting(_themeModeKey);
      if (value == ThemeMode.light.name) mode = ThemeMode.light;
      if (value == ThemeMode.dark.name) mode = ThemeMode.dark;
      if (value == ThemeMode.system.name) mode = ThemeMode.system;
    } catch (error) {
      unawaited(
        ReaderLog.instance.log(
          'app_theme_load_failed',
          fields: {'error': error},
        ),
      );
    }
    if (mounted) {
      _loadedMode = mode;
      await _syncWindow(mode);
    }
    return mode;
  }

  Future<void> _setMode(ThemeMode mode) async {
    await widget.library.setSetting(_themeModeKey, mode.name);
    if (!mounted) return;
    setState(() => _selectedMode = mode);
    await _syncWindow(mode);
  }

  Future<void> _syncWindow(ThemeMode mode) async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      final dark =
          mode == ThemeMode.dark ||
          (mode == ThemeMode.system &&
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.dark);
      await _window.invokeMethod<void>(
        'setDarkMode',
        defaultTargetPlatform == TargetPlatform.macOS &&
                mode == ThemeMode.system
            ? null
            : dark,
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ThemeMode>(
    future: _savedMode,
    builder: (context, snapshot) =>
        snapshot.connectionState == ConnectionState.done
        ? _buildApp(_selectedMode ?? snapshot.data ?? ThemeMode.system)
        : const SizedBox.shrink(),
  );

  Widget _buildApp(ThemeMode mode) => MaterialApp(
    title: 'Spectacular Reader',
    debugShowCheckedModeBanner: false,
    theme: _day,
    darkTheme: _night,
    themeMode: mode,
    themeAnimationDuration: Duration.zero,
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: readerSystemBarStyle(Theme.of(context).scaffoldBackgroundColor),
      child: child!,
    ),
    home: HomeShell(
      library: widget.library,
      progressStore: widget.progressStore,
      storageRecovery: widget.recovery,
      themeMode: mode,
      onThemeModeChanged: _setMode,
    ),
  );
}
