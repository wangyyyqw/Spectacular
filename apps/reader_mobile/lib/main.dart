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
import 'home/startup_splash.dart';
import 'library/library_store.dart';
import 'reader/reader_font_store.dart';
import 'reader/reader_route.dart';
import 'reader/reader_text_warmup.dart';
import 'storage/startup_storage.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
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
  assert(readerCorePackageName == 'reader_core');
  assert(readerUiPackageName == 'reader_ui');
  // 原生启动画面保持可见，直到 Flutter 开屏图标已解码并能直接绘制。
  await preloadStartupSplashIcon();
  final storage = StartupStorage(log: log);
  runApp(
    LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      child: ReaderApp.withStorage(
        storage: storage,
        initialize: () async {
          // 先呈现带标识的开屏，再执行插件、数据库与字体初始化。
          await binding.waitUntilFirstFrameRasterized;
          await _initializeApp(storage, log);
        },
      ),
    ),
  );
}

Future<void> _initializeApp(StartupStorage storage, ReaderLog log) async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await setReaderSystemBars(statusBar: true, navigationBar: true);
  await log.initialize();
  await log.log('app_start');
  // 数据库不可用时仍可启动，界面显示临时模式并提供同一路径的重试。
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
}

/// 应用壳：四底栏（书架/统计/书评/我的）+ EPUB 导入 + 阅读页。
class ReaderApp extends StatefulWidget {
  /// 创建应用。
  const ReaderApp({
    super.key,
    required this.library,
    required this.progressStore,
  }) : _startupStorage = null,
       initialize = null;

  /// 正式启动入口，监听数据库失败与恢复后的存储替换。
  ReaderApp.withStorage({
    super.key,
    required StartupStorage storage,
    this.initialize,
  }) : library = storage.library,
       progressStore = storage.progressStore,
       _startupStorage = storage;

  /// 构造时传入的书架存储；正式恢复入口在监听中使用最新启动存储。
  final LibraryStore library;

  /// 构造时传入的进度存储，与对应书库绑定同一数据库。
  final ReaderProgressStore progressStore;

  final StartupStorage? _startupStorage;

  /// 首帧开屏显示后执行；完成前不构建临时空书架。
  final Future<void> Function()? initialize;

  @override
  State<ReaderApp> createState() => _ReaderAppState();
}

class _ReaderAppState extends State<ReaderApp> {
  late bool _initialized;
  bool _bookshelfReady = false;
  bool _splashFinished = false;

  @override
  void initState() {
    super.initState();
    final initialize = widget.initialize;
    _initialized = initialize == null;
    if (initialize != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_initialize(initialize));
      });
    }
  }

  Future<void> _initialize(Future<void> Function() initialize) async {
    try {
      await initialize();
    } catch (error, stackTrace) {
      recordAppError('app_startup_failed', error, stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _initialized = true);
    }
  }

  void _onBookshelfReady() {
    if (mounted && !_bookshelfReady) setState(() => _bookshelfReady = true);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    alignment: Alignment.topLeft,
    children: [
      _initialized ? _buildReaderApp() : const SizedBox.shrink(),
      if (!_splashFinished) _buildStartupSplash(context),
    ],
  );

  Widget _buildReaderApp() {
    final storage = widget._startupStorage;
    if (storage == null) {
      return _buildApp(widget.library, widget.progressStore);
    }
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
    onBookshelfReady: _onBookshelfReady,
  );

  Widget _buildStartupSplash(BuildContext context) => Theme(
    data: buildAppTheme(
      brightness: WidgetsBinding.instance.platformDispatcher.platformBrightness,
    ),
    child: Builder(
      builder: (context) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery.fromView(
          view: View.of(context),
          child: StartupSplash(
            ready: _bookshelfReady,
            onFinished: () {
              if (mounted) setState(() => _splashFinished = true);
            },
          ),
        ),
      ),
    ),
  );
}

class _ThemedReaderApp extends StatefulWidget {
  const _ThemedReaderApp({
    super.key,
    required this.library,
    required this.progressStore,
    required this.onBookshelfReady,
    this.recovery,
  });

  final LibraryStore library;
  final ReaderProgressStore progressStore;
  final StartupStorage? recovery;
  final VoidCallback onBookshelfReady;

  @override
  State<_ThemedReaderApp> createState() => _ThemedReaderAppState();
}

class _ThemedReaderAppState extends State<_ThemedReaderApp>
    with WidgetsBindingObserver {
  static const _themeModeKey = 'app.themeMode';
  static const _window = OptionalMethodChannel(
    'com.spectacular.reader_mobile/window',
  );
  late final _readerWindowObserver = _ReaderWindowChromeObserver();

  late final ReaderFontStore _fontStore = ReaderFontStore(widget.library);
  late Future<_AppPreferences> _savedPreferences = _loadPreferences();
  ThemeMode? _selectedMode;
  ThemeMode? _loadedMode;
  AppThemePreset? _selectedPreset;
  String? _selectedFontFamily;
  double _windowTopInset = 0;

  void _reloadSyncedPreferences() {
    if (!mounted) return;
    setState(() {
      _selectedMode = null;
      _selectedPreset = null;
      _selectedFontFamily = null;
      _savedPreferences = _loadPreferences();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _window.setMethodCallHandler((call) async {
        if (call.method != 'windowInsetsChanged') return;
        final arguments = call.arguments;
        final top = arguments is Map<Object?, Object?>
            ? (arguments['top'] as num?)?.toDouble()
            : null;
        if (top != null && mounted && top != _windowTopInset) {
          setState(() => _windowTopInset = top);
        }
      });
      unawaited(_loadWindowInsets());
    }
  }

  Future<void> _loadWindowInsets() async {
    try {
      final insets = await _window.invokeMethod<Map<Object?, Object?>>(
        'getWindowInsets',
      );
      final top = (insets?['top'] as num?)?.toDouble();
      if (top != null && mounted && top != _windowTopInset) {
        setState(() => _windowTopInset = top);
      }
    } catch (_) {
      // 原生窗口未实现时保持无额外顶部内边距。
    }
  }

  @override
  void dispose() {
    _readerWindowObserver.reset();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final mode = _selectedMode ?? _loadedMode;
    if (mode == ThemeMode.system) unawaited(_syncWindow(ThemeMode.system));
  }

  Future<_AppPreferences> _loadPreferences() async {
    final mode = _loadMode();
    final preset = _loadThemePreset();
    final fontFamily = _loadFontFamily();
    return _AppPreferences(
      mode: await mode,
      preset: await preset,
      fontFamily: await fontFamily,
    );
  }

  Future<AppThemePreset> _loadThemePreset() async {
    try {
      final value = await widget.library.getSetting(AppThemePreset.settingKey);
      return AppThemePreset.byId(value);
    } catch (error) {
      unawaited(
        ReaderLog.instance.log(
          'app_theme_preset_load_failed',
          fields: {'error': error},
        ),
      );
      return AppThemePreset.clearBlue;
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
    await _syncWindow(mode);
  }

  Future<void> _setPreset(AppThemePreset preset) async {
    await widget.library.setSetting(AppThemePreset.settingKey, preset.id);
    if (!mounted) return;
    setState(() => _selectedPreset = preset);
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
    builder: (context, snapshot) =>
        snapshot.hasData ? _buildApp(snapshot.data!) : const SizedBox.shrink(),
  );

  Widget _buildApp(_AppPreferences preferences) {
    final mode = _selectedMode ?? preferences.mode;
    final preset = _selectedPreset ?? preferences.preset;
    final fontFamily = _selectedFontFamily ?? preferences.fontFamily;
    return MaterialApp(
      title: '墨屿',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(preset: preset, fontFamily: fontFamily),
      darkTheme: buildAppTheme(
        brightness: Brightness.dark,
        preset: preset,
        fontFamily: fontFamily,
      ),
      themeMode: mode,
      themeAnimationDuration: Duration.zero,
      navigatorObservers: [_readerWindowObserver],
      builder: (context, child) {
        return AppThemeScope(
          mode: mode,
          onModeChanged: _setMode,
          preset: preset,
          onPresetChanged: _setPreset,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: readerSystemBarStyle(
              Theme.of(context).scaffoldBackgroundColor,
            ),
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Padding(
                padding: EdgeInsets.only(
                  top: defaultTargetPlatform == TargetPlatform.macOS
                      ? _windowTopInset
                      : 0,
                ),
                child: child!,
              ),
            ),
          ),
        );
      },
      home: HomeShell(
        library: widget.library,
        progressStore: widget.progressStore,
        storageRecovery: widget.recovery,
        themeMode: mode,
        onThemeModeChanged: _setMode,
        themePreset: preset,
        onThemePresetChanged: _setPreset,
        appFontFamily: fontFamily,
        appFontStore: _fontStore,
        onAppFontFamilyChanged: _setFontFamily,
        onBookshelfReady: widget.onBookshelfReady,
        onSyncPreferences: _reloadSyncedPreferences,
        windowTopInset: _windowTopInset,
      ),
    );
  }
}

class _AppPreferences {
  const _AppPreferences({
    required this.mode,
    required this.preset,
    required this.fontFamily,
  });

  final ThemeMode mode;
  final AppThemePreset preset;
  final String fontFamily;
}

class _ReaderWindowChromeObserver extends NavigatorObserver {
  static const _window = OptionalMethodChannel(
    'com.spectacular.reader_mobile/window',
  );

  Route<dynamic>? _currentRoute;
  bool _readerVisible = false;

  void _update(Route<dynamic>? route) {
    _currentRoute = route;
    final readerVisible = route?.settings.name == readerWindowRouteName;
    if (readerVisible == _readerVisible) return;
    _readerVisible = readerVisible;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      unawaited(
        _window.invokeMethod<void>('setReaderWindowMode', readerVisible),
      );
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _update(
      newRoute ?? (identical(oldRoute, _currentRoute) ? null : _currentRoute),
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, _currentRoute)) _update(previousRoute);
  }

  void reset() => _update(null);
}
