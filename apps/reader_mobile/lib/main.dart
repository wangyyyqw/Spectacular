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
import 'reader/reader_font_store.dart';
import 'reader/reader_text_warmup.dart';
import 'storage/startup_storage.dart';
import 'theme/app_theme.dart';
import 'theme/startup_theme_cache.dart';
import 'theme/theme_color_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 保留系统启动窗口，直到偏好恢复后的应用首屏完成绘制。
  WidgetsBinding.instance.deferFirstFrame();
  var firstFrameAllowed = false;
  final startupTheme = StartupThemeCache.read();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await setReaderSystemBars(statusBar: true, navigationBar: true);
  final log = ReaderLog.instance;
  ReaderUiDiagnostics.onEvent = (event, fields) {
    unawaited(log.log(event, fields: fields));
  };
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
      child: ReaderApp.withStorage(
        storage: storage,
        startupTheme: await startupTheme,
        onStartupReady: () {
          if (firstFrameAllowed) return;
          firstFrameAllowed = true;
          WidgetsBinding.instance.allowFirstFrame();
        },
      ),
    ),
  );
}

/// 应用壳：书架、发现、统计、书评与我的，以及 EPUB 导入和阅读页。
class ReaderApp extends StatelessWidget {
  /// 创建应用。
  const ReaderApp({
    super.key,
    required this.library,
    required this.progressStore,
    this.showWelcomeAnnouncement = false,
    this.startupTheme,
    this.onStartupReady,
  }) : _startupStorage = null;

  /// 正式启动入口，监听数据库失败与恢复后的存储替换。
  ReaderApp.withStorage({
    super.key,
    required StartupStorage storage,
    this.startupTheme,
    this.onStartupReady,
  }) : library = storage.library,
       progressStore = storage.progressStore,
       showWelcomeAnnouncement = true,
       _startupStorage = storage;

  /// 构造时传入的书架存储；正式恢复入口在监听中使用最新启动存储。
  final LibraryStore library;

  /// 构造时传入的进度存储，与对应书库绑定同一数据库。
  final ReaderProgressStore progressStore;

  final StartupStorage? _startupStorage;
  final bool showWelcomeAnnouncement;
  final StartupThemeCache? startupTheme;
  final VoidCallback? onStartupReady;

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
    showWelcomeAnnouncement: showWelcomeAnnouncement,
    startupTheme: startupTheme,
    onStartupReady: onStartupReady,
  );
}

class _ThemedReaderApp extends StatefulWidget {
  const _ThemedReaderApp({
    super.key,
    required this.library,
    required this.progressStore,
    this.recovery,
    required this.showWelcomeAnnouncement,
    this.startupTheme,
    this.onStartupReady,
  });

  final LibraryStore library;
  final ReaderProgressStore progressStore;
  final StartupStorage? recovery;
  final bool showWelcomeAnnouncement;
  final StartupThemeCache? startupTheme;
  final VoidCallback? onStartupReady;

  @override
  State<_ThemedReaderApp> createState() => _ThemedReaderAppState();
}

class _ThemedReaderAppState extends State<_ThemedReaderApp>
    with WidgetsBindingObserver {
  static const _themeModeKey = 'app.themeMode';
  static const _window = OptionalMethodChannel(
    'com.spectacular.reader_mobile/window',
  );

  late final ReaderFontStore _fontStore = ReaderFontStore(widget.library);
  late final ThemeColorSettings _themeColors = ThemeColorSettings(
    widget.library,
    startupTheme: widget.startupTheme,
  );
  late final Future<_AppPreferences> _savedPreferences = _loadPreferences();
  ThemeMode? _selectedMode;
  ThemeMode? _loadedMode;
  AppUiStyle? _selectedUiStyle;
  String? _selectedFontFamily;
  bool _startupReadyReported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeColors.addListener(_colorsChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeColors.removeListener(_colorsChanged);
    _themeColors.dispose();
    super.dispose();
  }

  void _colorsChanged() {
    if (mounted) {
      setState(() {});
      unawaited(_cacheStartupTheme());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_themeColors.refreshWallpaper());
    }
  }

  @override
  void didChangePlatformBrightness() {
    final mode = _selectedMode ?? _loadedMode;
    if (mode == ThemeMode.system) unawaited(_syncWindow(ThemeMode.system));
  }

  Future<_AppPreferences> _loadPreferences() async {
    final mode = _loadMode();
    final fontFamily = _loadFontFamily();
    final uiStyle = _loadUiStyle();
    await _themeColors.initialize();
    final preferences = _AppPreferences(
      mode: await mode,
      fontFamily: await fontFamily,
      uiStyle: await uiStyle,
    );
    unawaited(_cacheStartupTheme());
    return preferences;
  }

  Future<AppUiStyle> _loadUiStyle() async {
    try {
      return AppUiStyle.fromSetting(
        await widget.library.getSetting(AppUiStyle.settingKey),
      );
    } catch (error) {
      unawaited(
        ReaderLog.instance.log(
          'app_ui_style_load_failed',
          fields: {'error': error},
        ),
      );
      return AppUiStyle.classic;
    }
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

  Future<String> _loadFontFamily() async {
    String? stored;
    try {
      stored = await widget.library.getSetting(AppFonts.settingKey);
      if (stored == null || stored.isEmpty) return AppFonts.defaultFamily;
      if (stored == AppFonts.defaultFamily) return stored;
      if (!stored.startsWith('user_')) {
        throw const FormatException('应用字体标识无效');
      }
      await _fontStore.load(stored);
      return stored;
    } catch (error, stackTrace) {
      await ReaderLog.instance.log(
        'app_font_load_failed',
        fields: {'family': stored, 'error': error, 'stack': stackTrace},
      );
      if (stored != null && stored.isNotEmpty) {
        try {
          await _saveFontFamily(AppFonts.defaultFamily);
        } catch (saveError, saveStack) {
          await ReaderLog.instance.log(
            'app_font_reset_failed',
            fields: {'error': saveError, 'stack': saveStack},
          );
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: saveError,
              stack: saveStack,
              library: 'reader_mobile',
              context: ErrorDescription('恢复默认应用字体'),
            ),
          );
        }
      }
      return AppFonts.defaultFamily;
    }
  }

  Future<void> _setMode(ThemeMode mode) async {
    await widget.library.setSetting(_themeModeKey, mode.name);
    if (!mounted) return;
    setState(() => _selectedMode = mode);
    await _cacheStartupTheme();
    await _syncWindow(mode);
  }

  Future<void> _setUiStyle(AppUiStyle style) async {
    await widget.library.setSetting(AppUiStyle.settingKey, style.name);
    if (!mounted) return;
    setState(() => _selectedUiStyle = style);
  }

  Future<void> _cacheStartupTheme() async {
    final mode = _selectedMode ?? _loadedMode;
    if (!_themeColors.initialized || mode == null) return;
    await StartupThemeCache(
      wallpaperEnabled: _themeColors.wallpaperEnabled,
      mode: mode,
      seed: _themeColors.wallpaperSeed,
    ).save();
  }

  Future<void> _setFontFamily(String family) async {
    if (family != AppFonts.defaultFamily) await _fontStore.load(family);
    await _saveFontFamily(family);
    if (!mounted) return;
    setState(() => _selectedFontFamily = family);
  }

  Future<void> _saveFontFamily(String family) =>
      widget.library.setSetting(AppFonts.settingKey, family);

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
  Widget build(BuildContext context) => FutureBuilder<_AppPreferences>(
    future: _savedPreferences,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const SizedBox.shrink();
      if (!_startupReadyReported) {
        _startupReadyReported = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onStartupReady?.call();
        });
      }
      return _buildApp(snapshot.data!);
    },
  );

  Widget _buildApp(_AppPreferences preferences) {
    final mode = _selectedMode ?? preferences.mode;
    final fontFamily = _selectedFontFamily ?? preferences.fontFamily;
    final uiStyle = _selectedUiStyle ?? preferences.uiStyle;
    return MaterialApp(
      title: '阅微Extend',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(
        fontFamily: fontFamily,
        colorScheme: _themeColors.wallpaperScheme(Brightness.light),
        uiStyle: uiStyle,
      ),
      darkTheme: buildAppTheme(
        brightness: Brightness.dark,
        fontFamily: fontFamily,
        colorScheme: _themeColors.wallpaperScheme(Brightness.dark),
        uiStyle: uiStyle,
      ),
      themeMode: mode,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => AppThemeScope(
        mode: mode,
        onModeChanged: _setMode,
        uiStyle: uiStyle,
        onUiStyleChanged: _setUiStyle,
        child: ThemeColorScope(
          settings: _themeColors,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: readerSystemBarStyle(
              Theme.of(context).scaffoldBackgroundColor,
            ),
            child: child!,
          ),
        ),
      ),
      home: HomeShell(
        library: widget.library,
        progressStore: widget.progressStore,
        storageRecovery: widget.recovery,
        themeMode: mode,
        onThemeModeChanged: _setMode,
        appFontFamily: fontFamily,
        appFontStore: _fontStore,
        onAppFontFamilyChanged: _setFontFamily,
        uiStyle: uiStyle,
        onUiStyleChanged: _setUiStyle,
        showWelcomeAnnouncement: widget.showWelcomeAnnouncement,
      ),
    );
  }
}

class _AppPreferences {
  const _AppPreferences({
    required this.mode,
    required this.fontFamily,
    required this.uiStyle,
  });

  final ThemeMode mode;
  final String fontFamily;
  final AppUiStyle uiStyle;
}
