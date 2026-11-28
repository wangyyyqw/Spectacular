import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/cache/chapter_pagination_store.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_core/source/format_opener.dart';
import 'package:reader_core/text/reader_text_conversion.dart';
import 'package:reader_ui/loading_skeleton.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/decorations/decoration_image_store.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_margins.dart';
import 'package:reader_ui/theme/reader_environment.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';

import '../home/finish_book_sheet.dart';
import '../dictionary/dictionary_store.dart';
import '../dictionary/dictionary_sheet.dart';
import '../theme/app_theme.dart';
import '../library/library_store.dart';
import '../storage/book_review_store.dart';
import '../diagnostics/reader_log.dart';
import '../editing/book_edit_repository.dart';
import '../editing/book_editor_route.dart';
import '../txt/txt_book_service.dart';
import '../txt/txt_chapter_rule_page.dart';
import '../search/scan_search_service.dart';
import '../storage/reading_session_store.dart';
import '../storage/drift_progress_store.dart';

import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';

import 'reading_session_tracker.dart';
import 'paragraph_edit_sheet.dart';
import 'reader_settings.dart';
import 'reader_chinese_converter.dart';
import 'reader_background_store.dart';
import 'reader_font_store.dart';
import 'reader_tts_controller.dart';
import 'reader_tts_background.dart';
import 'reader_offline_tts.dart';
import 'reader_tts_voice_store.dart';
import 'reader_tts_voice_page.dart';
import 'reader_tts_text.dart';
import 'reader_tts_playback_sheet.dart';

import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';
import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

/// 默认阅读设置：段距 10dp，16dp 字号下约为 0.625em。
///
/// 字号/行高/对齐默认不覆盖，跟随书籍 CSS；用户设置面板接入后由
/// `ReaderOverrides` 覆盖作者声明（reader origin 高于 author）。
const ReaderOverrides defaultReaderOverrides = ReaderOverrides(
  paragraphSpacing: 10,
);

/// 内容已保存或恢复时，由打开器释放旧会话后重新读取书库版本。
enum EpubReaderExit { contentUpdated }

/// 从内存 EPUB 打开的最小阅读页。
class EpubReaderPage extends StatefulWidget {
  /// 创建页面。
  const EpubReaderPage({
    super.key,
    this.bytes,
    this.bytesFuture,
    this.sourcePath,
    this.sourceFuture,
    required this.bookId,
    required this.store,
    this.bookmarks,
    this.annotations,
    this.decorations,
    this.decorationRules,
    this.decorationImages,
    this.readingSessions,
    this.settings,
    this.settingsFuture,
    this.onSettingsChanged,
    this.bookTitle = '阅读',
    this.onMarginsChanged,
    this.fontStore,
    this.contentRevision,
    this.contentRevisionFuture,
    this.readingActive = true,
    this.onReady,
    this.onClosed,
    this.bookEditorRepository,
    this.book,
    this.reviewStore,
    this.dictionaryStore,
    this.ttsVoiceStore,
  });

  final BookEditRepository? bookEditorRepository;
  final BookEntry? book;
  final BookReviewStore? reviewStore;
  final DictionaryStore? dictionaryStore;

  /// 可注入的离线音色仓库；为空时由阅读页创建。
  final ReaderTtsVoiceStore? ttsVoiceStore;

  /// EPUB 字节（内存入口；与 [sourcePath] 二选一）。
  final Uint8List? bytes;

  /// 打开宿主读取一次的字节；与封面动画同时准备。
  final Future<Uint8List>? bytesFuture;

  /// EPUB 文件路径（阅读页默认入口，惰性读取，不常驻整本字节）。
  final String? sourcePath;

  /// 可共享的打开任务；本页唯一负责关闭已完成或取消后晚到的源。
  final Future<EpubChapterSource>? sourceFuture;

  /// 书籍标识。
  final String bookId;

  /// 进度存储。
  final ReaderProgressStore store;

  /// 书签存储（P4-13）；为 null 时菜单不显示书签入口。
  final ReaderBookmarkStore? bookmarks;

  /// 标注存储（P4-17）；为 null 时选区菜单不显示高亮/笔记。
  final ReaderAnnotationStore? annotations;

  /// 本书手工装饰。
  final ReaderDecorationStore? decorations;

  /// 本书与全局自动装饰规则。
  final ReaderDecorationRuleStore? decorationRules;

  /// 独立装饰图片存储。
  final ReaderDecorationImageStore? decorationImages;

  /// 阅读会话存储；用于统计前台阅读时长。
  final ReadingSessionStore? readingSessions;

  /// 初始阅读设置（P4-21）。
  final ReaderSettings? settings;

  /// 设置尚未读完时先挂载页面，首次排版仍等待设置和用户字体。
  final Future<ReaderSettings>? settingsFuture;

  /// 设置变化（调用方持久化）。
  final ValueChanged<ReaderSettings>? onSettingsChanged;

  /// 书名（菜单顶部栏用）。
  final String bookTitle;

  /// 页边距变化（边距调节器「保留」）。
  final ValueChanged<ReaderMargins>? onMarginsChanged;

  /// 自定义字体存储；宿主负责导入、注册和恢复。
  final ReaderFontStore? fontStore;

  /// 书库已存的原书 SHA-256；为 null 时才现算。
  final String? contentRevision;

  /// 旧书的流式摘要与源打开并行，首次排版前必须得到实际版本。
  final Future<String>? contentRevisionFuture;

  /// 封面已揭开后才记录前台阅读时长。
  final bool readingActive;

  /// 目标正文和进度数字已绘制，或打开失败可以展示错误时通知宿主。
  final VoidCallback? onReady;

  /// 阅读页退出动画结束后，保存检查已完成且章节源已释放。
  final VoidCallback? onClosed;

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage>
    with WidgetsBindingObserver {
  late ReaderSettings _settings = widget.settings ?? ReaderSettings.defaults;
  final _backgroundStore = ReaderBackgroundStore();
  final _bookmarkImages = ReaderBackgroundStore(
    directoryName: 'bookmark_images',
    filePrefix: 'bookmark',
  );
  String _contentRevision = '';
  List<ReaderFontOption> _customFonts = const [];
  bool _reportedClosingProgressFailure = false;
  final _chineseConverter = ReaderChineseConverter();
  bool _chineseConversionBusy = false;
  bool _chineseModeFallback = false;

  Future<void> _changeChineseMode(ReaderChineseMode mode) async {
    final source = _source;
    final session = _readerSession;
    if (_chineseConversionBusy ||
        source == null ||
        session == null ||
        mode == _settings.chineseMode) {
      return;
    }
    final previous = _settings.chineseMode;
    setState(() => _chineseConversionBusy = true);
    var applied = false;
    try {
      final conversion = await _chineseConverter.load(mode);
      await session.flushProgress();
      if (!mounted || _closing) return;
      source.applyTextConversion(conversion);
      applied = true;
      if (!await session.refreshLayout()) {
        throw StateError('转换后的章节未能完成排版');
      }
      if (!mounted || _closing) return;
      _changeSettings(_settings.copyWithChineseMode(mode));
    } catch (error, stackTrace) {
      recordAppError(
        'reader_chinese_conversion_failed',
        error,
        stackTrace: stackTrace,
      );
      if (applied && mounted && !_closing) {
        await _restoreChineseConversion(source, session, previous);
      }
      if (mounted && !_closing) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('简繁转换失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _chineseConversionBusy = false);
    }
  }

  /// 转换失败时恢复原显示；恢复本身失败只记录，避免掩盖首次错误。
  Future<void> _restoreChineseConversion(
    EpubChapterSource source,
    ReaderSession session,
    ReaderChineseMode mode,
  ) async {
    try {
      source.applyTextConversion(await _chineseConverter.load(mode));
      await session.refreshLayout();
    } catch (error, stackTrace) {
      recordAppError(
        'reader_chinese_conversion_restore_failed',
        error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _prepareInitialSettings() async {
    final pending = widget.settingsFuture;
    if (pending != null) {
      final settings = await pending;
      if (_openingCancelled) return;
      _settings = settings;
    }
    await _prepareFonts();
  }

  Future<void> _prepareFonts() async {
    final store = widget.fontStore;
    if (store == null || _openingCancelled) return;
    final fonts = await store.list();
    if (_openingCancelled) return;
    _customFonts = [
      for (final font in fonts)
        ReaderFontOption(family: font.family, label: font.displayName),
    ];
    if (!_settings.overrides.isCustomFont) return;
    try {
      await store.load(_settings.fontFamily!);
    } catch (error, stackTrace) {
      if (!mounted || _openingCancelled) return;
      _changeSettings(_settings.copyWithFont(null));
      recordAppError('reader_font_load_failed', error, stackTrace: stackTrace);
    }
  }

  Future<ReaderFontOption?> _pickFont() async {
    final font = await widget.fontStore!.pick();
    if (font == null) return null;
    await _refreshFontList();
    return ReaderFontOption(family: font.family, label: font.displayName);
  }

  Future<void> _refreshFontList() async {
    final fonts = await widget.fontStore!.list();
    if (!mounted) return;
    setState(
      () => _customFonts = [
        for (final font in fonts)
          ReaderFontOption(family: font.family, label: font.displayName),
      ],
    );
  }

  Future<ReaderFontOption> _renameFont(String family, String name) async {
    final font = await widget.fontStore!.rename(family, name);
    await _refreshFontList();
    return ReaderFontOption(family: font.family, label: font.displayName);
  }

  Future<void> _removeFont(String family) async {
    await widget.fontStore!.remove(family);
    if (mounted && _settings.fontFamily == family) {
      _changeSettings(_settings.copyWithFont(null));
    }
    await _refreshFontList();
  }

  void _changeSettings(ReaderSettings next) {
    setState(() => _settings = next);
    widget.onSettingsChanged?.call(next);
  }

  void _changeTheme(String themeId) {
    _changeSettings(_settings.copyWithTheme(themeId));
    final scope = AppThemeScope.maybeOf(context);
    if (scope == null) return;
    final dark = ReaderTheme.byId(themeId).isDark;
    if (dark == (Theme.of(context).brightness == Brightness.dark)) return;
    unawaited(scope.onModeChanged(dark ? ThemeMode.dark : ThemeMode.light));
  }

  void _toggleDayNight() {
    final scope = AppThemeScope.maybeOf(context)!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    unawaited(scope.onModeChanged(dark ? ThemeMode.light : ThemeMode.dark));
  }

  Future<void> _toggleTts() async {
    final session = _readerSession;
    if (session == null || !session.hasContent) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('正文尚未准备好')));
      }
      return;
    }
    final controller = _ensureTtsController();
    if (controller.hasSession) {
      setState(() {});
      return;
    }
    setState(() {});
    await _startTts(controller);
  }

  Future<bool> _startTts(ReaderTtsController controller) async {
    var settings = _settings.tts;
    if (settings.mode == ReaderTtsMode.offline) {
      if (!settings.hasOfflineVoice) {
        final selected = await _showTtsSettings();
        if (selected == null) return false;
        settings = selected;
      }
    } else if (settings.hasVoice) {
      // 系统音色被卸载时回退到系统默认语音，不阻塞开始。
      try {
        final voices = await controller.loadVoices();
        if (voices.isNotEmpty &&
            !voices.any(
              (voice) =>
                  voice.name == settings.voiceName &&
                  voice.locale == settings.voiceLocale,
            )) {
          settings = settings.copyWith(voiceName: '', voiceLocale: '');
        }
      } catch (_) {
        settings = settings.copyWith(voiceName: '', voiceLocale: '');
      }
    }
    if (!mounted) return false;
    _changeSettings(_settings.copyWithTts(settings));
    unawaited(
      controller.snapshot.phase == ReaderTtsPhase.failed
          ? controller.retry(settings)
          : controller.start(settings),
    );
    return true;
  }

  Future<void> _editTtsSettings(ReaderTtsController controller) async {
    final settings = await _showTtsSettings();
    if (settings == null || !mounted) return;
    _changeSettings(_settings.copyWithTts(settings));
    controller.updateSettings(settings);
  }

  /// 浮条语速按钮的当前值提示，系统 TTS 与离线模型含义不同。
  String _ttsSpeedLabel(ReaderTtsSettings settings) =>
      settings.mode == ReaderTtsMode.system
      ? '语速 · ${settings.rate.toStringAsFixed(1)} · '
            '音调 ${settings.pitch.toStringAsFixed(1)}'
      : '语速 · 旁白 ${settings.narratorSpeed.toStringAsFixed(1)}x · '
            '对白 ${settings.dialogueSpeed.toStringAsFixed(1)}x';

  /// 浮条里的语速快捷入口：按当前引擎调节系统语速/音调或离线旁白/对白语速。
  Future<void> _editTtsSpeed(ReaderTtsController controller) async {
    var draft = _settings.tts;
    final systemMode = draft.mode == ReaderTtsMode.system;
    final applied = await showReaderDrawer<ReaderTtsSettings>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => ReaderSheetForm(
          title: const Text('语速'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (systemMode) ...[
                _TtsSlider(
                  label: '语速',
                  value: draft.rate,
                  min: 0.2,
                  max: 1,
                  onChanged: (value) =>
                      setSheetState(() => draft = draft.copyWith(rate: value)),
                ),
                _TtsSlider(
                  label: '音调',
                  value: draft.pitch,
                  min: 0.5,
                  max: 2,
                  onChanged: (value) =>
                      setSheetState(() => draft = draft.copyWith(pitch: value)),
                ),
              ] else ...[
                _TtsSlider(
                  label: '旁白语速',
                  value: draft.narratorSpeed,
                  min: 0.5,
                  max: 2,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(narratorSpeed: value),
                  ),
                ),
                _TtsSlider(
                  label: '对白语速',
                  value: draft.dialogueSpeed,
                  min: 0.5,
                  max: 2,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(dialogueSpeed: value),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              key: const ValueKey<String>('tts-speed-apply'),
              onPressed: () => Navigator.of(sheetContext).pop(draft),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
    if (applied == null || !mounted) return;
    _changeSettings(_settings.copyWithTts(applied));
    controller.updateSettings(applied);
  }

  Future<void> _editTtsTimer() async {
    final selected = await showReaderDrawer<Duration?>(
      context: context,
      useSafeArea: true,
      builder: (context) => ReaderSheetForm(
        title: const Text('定时暂停'),
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final minutes in const [15, 30, 45, 60])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: ReaderOptionTile(
                  leading: const AppIcon(AppGlyph.timer),
                  title: '$minutes 分钟后暂停',
                  selected: _ttsSleepDuration == Duration(minutes: minutes),
                  onTap: () =>
                      Navigator.of(context).pop(Duration(minutes: minutes)),
                ),
              ),
            if (_ttsSleepDuration != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Divider(height: 1),
              ),
              ReaderOptionTile(
                leading: const AppIcon(AppGlyph.close),
                title: '取消定时',
                destructive: true,
                onTap: () => Navigator.of(context).pop(Duration.zero),
              ),
            ],
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _ttsSleepTimer?.cancel();
    if (selected == Duration.zero) {
      setState(() {
        _ttsSleepTimer = null;
        _ttsSleepDuration = null;
      });
      return;
    }
    setState(() => _ttsSleepDuration = selected);
    _ttsSleepTimer = Timer(selected, () {
      _ttsSleepTimer = null;
      if (!mounted) return;
      setState(() => _ttsSleepDuration = null);
      final controller = _ttsController;
      if (controller?.speaking ?? false) {
        unawaited(controller!.pause());
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('定时结束，已暂停朗读')));
      }
    });
  }

  void _onTtsStateChanged() {
    final phase = _ttsController?.snapshot.phase;
    if (phase != ReaderTtsPhase.idle &&
        phase != ReaderTtsPhase.completed &&
        phase != ReaderTtsPhase.failed) {
      return;
    }
    _ttsSleepTimer?.cancel();
    _ttsSleepTimer = null;
    if (_ttsSleepDuration == null) return;
    _ttsSleepDuration = null;
    if (mounted) setState(() {});
  }

  Future<ReaderTtsSettings?> _showTtsSettings() async {
    final store = _ensureTtsVoiceStore();
    var installedVoices = await store.listInstalled();
    var availableVoices = await store.availableVoices();
    var systemVoices = <ReaderTtsVoice>[];
    var systemVoicesUnavailable = false;
    try {
      systemVoices = await _ensureTtsController().loadVoices();
    } catch (_) {
      // 系统语音服务不可用时，仍可配置离线模型。
      systemVoicesUnavailable = true;
    }
    if (!mounted) return null;
    var draft = _settings.tts;
    if (draft.hasVoice &&
        !systemVoicesUnavailable &&
        !systemVoices.any(
          (voice) =>
              voice.name == draft.voiceName &&
              voice.locale == draft.voiceLocale,
        )) {
      draft = draft.copyWith(voiceName: '', voiceLocale: '');
    }
    if (!installedVoices.any((voice) => voice.id == draft.narratorVoiceId)) {
      draft = draft.copyWith(
        narratorVoiceId: installedVoices.isEmpty
            ? ''
            : installedVoices.first.id,
      );
    }
    if (draft.dialogueVoiceId.isNotEmpty &&
        !installedVoices.any((voice) => voice.id == draft.dialogueVoiceId)) {
      draft = draft.copyWith(dialogueVoiceId: '');
    }
    if (draft.dialogueVoiceId == draft.narratorVoiceId) {
      draft = draft.copyWith(dialogueVoiceId: '');
    }
    return showReaderDrawer<ReaderTtsSettings>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          ReaderOfflineVoice? selectedNarrator;
          for (final voice in installedVoices) {
            if (voice.id == draft.narratorVoiceId) {
              selectedNarrator = voice;
              break;
            }
          }
          return ReaderSheetForm(
            title: const Text('听书设置'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SegmentedButton<ReaderTtsMode>(
                  key: const ValueKey<String>('tts-mode'),
                  segments: const <ButtonSegment<ReaderTtsMode>>[
                    ButtonSegment<ReaderTtsMode>(
                      value: ReaderTtsMode.system,
                      label: Text('系统 TTS'),
                      icon: AppIcon(AppGlyph.voice, size: 18),
                    ),
                    ButtonSegment<ReaderTtsMode>(
                      value: ReaderTtsMode.offline,
                      label: Text('离线模型'),
                      icon: AppIcon(AppGlyph.offlineBolt, size: 18),
                    ),
                  ],
                  selected: <ReaderTtsMode>{draft.mode},
                  onSelectionChanged: (selection) => setSheetState(
                    () => draft = draft.copyWith(mode: selection.first),
                  ),
                ),
                const SizedBox(height: 12),
                if (draft.mode == ReaderTtsMode.system) ...<Widget>[
                  if (systemVoicesUnavailable)
                    Text(
                      '无法读取系统音色，将使用系统默认语音。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else
                    ReaderDropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'tts-system-voice-${draft.voiceName}-'
                        '${draft.voiceLocale}',
                      ),
                      initialValue: draft.hasVoice
                          ? '${draft.voiceName}|${draft.voiceLocale}'
                          : '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '音色'),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('系统默认音色'),
                        ),
                        for (final voice in systemVoices)
                          DropdownMenuItem<String>(
                            value: voice.key,
                            child: Text(
                              voice.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        if (value.isEmpty) {
                          setSheetState(
                            () => draft = draft.copyWith(
                              voiceName: '',
                              voiceLocale: '',
                            ),
                          );
                          return;
                        }
                        final voice = systemVoices.firstWhere(
                          (item) => item.key == value,
                          orElse: () => systemVoices.first,
                        );
                        setSheetState(
                          () => draft = draft.copyWith(
                            voiceName: voice.name,
                            voiceLocale: voice.locale,
                          ),
                        );
                      },
                    ),
                ] else if (installedVoices.isEmpty) ...<Widget>[
                  Text(
                    '尚未下载离线音色。下载后可使用离线模型，'
                    '模型较大，建议连接 Wi-Fi。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => ReaderTtsVoiceLibraryPage(
                            store: store,
                            voices: availableVoices,
                          ),
                        ),
                      );
                      if (!context.mounted) return;
                      final installed = await store.listInstalled();
                      final available = await store.availableVoices();
                      if (!context.mounted) return;
                      setSheetState(() {
                        installedVoices = installed;
                        availableVoices = available;
                        if (installed.isNotEmpty) {
                          draft = draft.copyWith(
                            narratorVoiceId: installed.first.id,
                          );
                        }
                      });
                    },
                    icon: const AppIcon(AppGlyph.download, size: 18),
                    label: const Text('管理离线音色'),
                  ),
                ] else ...<Widget>[
                  ReaderDropdownButtonFormField<String>(
                    key: ValueKey<String>(
                      'tts-narrator-${draft.narratorVoiceId}',
                    ),
                    initialValue: draft.narratorVoiceId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '旁白音色'),
                    items: <DropdownMenuItem<String>>[
                      for (final voice in installedVoices)
                        DropdownMenuItem<String>(
                          value: voice.id,
                          child: Text(
                            voice.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(
                        () => draft = draft.copyWith(
                          narratorVoiceId: value,
                          dialogueVoiceId: draft.dialogueVoiceId == value
                              ? ''
                              : draft.dialogueVoiceId,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  ReaderDropdownButtonFormField<String>(
                    key: ValueKey<String>(
                      'tts-dialogue-${draft.dialogueVoiceId}',
                    ),
                    initialValue: draft.dialogueVoiceId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '对白音色'),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('跟随旁白'),
                      ),
                      for (final voice in installedVoices)
                        if (voice.id != draft.narratorVoiceId)
                          DropdownMenuItem<String>(
                            value: voice.id,
                            child: Text(
                              voice.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(
                        () => draft = draft.copyWith(dialogueVoiceId: value),
                      );
                    },
                  ),
                  if ((selectedNarrator?.speakerCount ?? 1) > 1) ...[
                    ReaderDropdownButtonFormField<int>(
                      key: ValueKey<int>(draft.narratorSpeakerId),
                      initialValue: draft.narratorSpeakerId.clamp(
                        0,
                        (selectedNarrator?.speakerCount ?? 1) - 1,
                      ),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '旁白说话人'),
                      items: <DropdownMenuItem<int>>[
                        for (
                          var index = 0;
                          index < (selectedNarrator?.speakerCount ?? 1);
                          index++
                        )
                          DropdownMenuItem<int>(
                            value: index,
                            child: Text('说话人 ${index + 1}'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(
                          () =>
                              draft = draft.copyWith(narratorSpeakerId: value),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => ReaderTtsVoiceLibraryPage(
                              store: store,
                              voices: availableVoices,
                            ),
                          ),
                        );
                        if (!context.mounted) return;
                        final installed = await store.listInstalled();
                        final available = await store.availableVoices();
                        if (!context.mounted) return;
                        setSheetState(() {
                          installedVoices = installed;
                          availableVoices = available;
                          if (!installed.any(
                            (voice) => voice.id == draft.narratorVoiceId,
                          )) {
                            draft = draft.copyWith(
                              narratorVoiceId: installed.isEmpty
                                  ? ''
                                  : installed.first.id,
                            );
                          }
                          if (!installed.any(
                            (voice) => voice.id == draft.dialogueVoiceId,
                          )) {
                            draft = draft.copyWith(dialogueVoiceId: '');
                          }
                          if (draft.dialogueVoiceId == draft.narratorVoiceId) {
                            draft = draft.copyWith(dialogueVoiceId: '');
                          }
                        });
                      },
                      icon: const AppIcon(AppGlyph.download, size: 18),
                      label: const Text('管理离线音色'),
                    ),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('连续朗读后续页'),
                  value: draft.autoTurnPage,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(autoTurnPage: value),
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              FilledButton.icon(
                key: const ValueKey<String>('tts-apply-settings'),
                onPressed: () {
                  if (draft.mode == ReaderTtsMode.offline &&
                      !draft.hasOfflineVoice) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请先下载并选择离线旁白音色')),
                    );
                    return;
                  }
                  Navigator.of(context).pop(draft);
                },
                icon: const AppIcon(AppGlyph.headphones, size: 18),
                label: const Text('应用设置'),
              ),
            ],
          );
        },
      ),
    );
  }

  ReaderTtsController _ensureTtsController() {
    final existing = _ttsController;
    if (existing != null) return existing;
    final voiceStore = _ensureTtsVoiceStore();
    final link = ReaderTtsReaderLink(_readerSession!);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    unawaited(
      link.setScreenActive(
        lifecycle == null || lifecycle == AppLifecycleState.resumed,
      ),
    );
    _ttsReaderLink = link;
    final controller = ReaderTtsController(
      textSource: link,
      offlineSynthesizer: SherpaReaderOfflineTtsSynthesizer(),
      player: AudioplayersReaderTtsPlayer(
        externalAudioFocus: defaultTargetPlatform == TargetPlatform.android,
      ),
      backgroundPlayback: ReaderTtsBackgroundPlayback(
        bookTitle: widget.bookTitle,
      ),
      resolveOfflineVoice: (id) async {
        final model = await voiceStore.modelFor(id);
        if (model == null) return null;
        return ReaderOfflineVoiceInstance(
          id: id,
          rootPath: await voiceStore.localPathFor(id),
          model: model,
        );
      },
    );
    controller.onError = (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('听书失败：$error')));
    };
    controller.onPositionChanged = link.follow;
    controller.updateSettings(_settings.tts);
    _ttsController = controller;
    controller.state.addListener(_onTtsStateChanged);
    return controller;
  }

  ReaderTtsVoiceStore _ensureTtsVoiceStore() {
    final existing = _ttsVoiceStore;
    if (existing != null) return existing;
    final injected = widget.ttsVoiceStore;
    if (injected != null) {
      _ttsVoiceStore = injected;
      _ownsTtsVoiceStore = false;
      return injected;
    }
    final created = ReaderTtsVoiceStore();
    _ttsVoiceStore = created;
    _ownsTtsVoiceStore = true;
    return created;
  }

  @override
  void didUpdateWidget(covariant EpubReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settings != oldWidget.settings) {
      _settings = widget.settings ?? ReaderSettings.defaults;
    }
    if (widget.readingActive != oldWidget.readingActive) {
      _syncReadingActivity();
    }
  }

  EpubChapterSource? _source;
  ScanSearchService? _search;
  DecodedImageCache? _imageCache;
  ReadingSessionTracker? _readingTracker;
  final ValueNotifier<Duration> _readingDuration = ValueNotifier(Duration.zero);
  Duration _savedReadingDuration = Duration.zero;
  Timer? _readingDurationTimer;
  Timer? _ttsSleepTimer;
  Duration? _ttsSleepDuration;

  /// 底栏是否露出；听书浮条只在阅读菜单展开且没有抽屉时显示。
  bool _ttsBarVisible = false;

  Future<void> _loadReadingDuration(ReadingSessionStore store) async {
    try {
      final sessions = await store.list();
      if (!mounted) return;
      _savedReadingDuration = sessions
          .where(
            (session) =>
                session.bookId == widget.bookId &&
                !(_readingTracker?.ownsSession(session) ?? false),
          )
          .fold(Duration.zero, (total, session) => total + session.duration);
      _updateReadingDuration();
    } catch (error) {
      await ReaderLog.instance.log(
        'reading_duration_load_error',
        fields: {'error': error},
      );
    }
  }

  void _updateReadingDuration() {
    _readingDuration.value =
        _savedReadingDuration + (_readingTracker?.elapsed ?? Duration.zero);
  }

  ReaderSession? _readerSession;
  ReaderTtsController? _ttsController;
  ReaderTtsReaderLink? _ttsReaderLink;
  ReaderTtsVoiceStore? _ttsVoiceStore;
  bool _ownsTtsVoiceStore = false;
  late final Future<EpubChapterSource> _sourceTask;
  Future<void Function()>? _anchorBinding;
  Future<void>? _sourceCloseTask;
  Future<void> _backgroundFlush = Future<void>.value();
  int _trackedPageTurns = 0;
  int _trackedCharactersRead = 0;
  Object? _error;
  bool _loading = true;
  bool _closing = false;
  bool _openingFailed = false;
  bool _readable = false;
  bool _readyNotified = false;
  bool _readyScheduled = false;

  bool get _openingCancelled => _closing || _openingFailed;

  /// 打开书埋点（P4-31）：从 initState 到首帧渲染完成。
  ReaderTraceHandle? _openTrace;

  @override
  void initState() {
    super.initState();
    if (readerTraceEnabled) {
      _openTrace = ReaderTrace.instance.start(
        ReaderTraceName.bookOpen,
        bookId: widget.bookId,
      );
    }
    final sessionStore = widget.readingSessions;
    if (sessionStore != null) {
      _readingTracker = ReadingSessionTracker(
        store: sessionStore,
        bookId: widget.bookId,
      );
      unawaited(_loadReadingDuration(sessionStore));
      _readingDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _updateReadingDuration();
        unawaited(_readingTracker?.checkpoint() ?? Future<void>.value());
      });
    }
    WidgetsBinding.instance.addObserver(this);
    // 源打开与设置/字体准备并行，首屏排版等待二者和实际内容版本到齐。
    final watch = Stopwatch()..start();
    _sourceTask = widget.sourceFuture ?? _openSource();
    _sourceTask.ignore();
    unawaited(_open(watch));
    unawaited(_loadChapterRuleAvailability());
  }

  Future<void> _open(Stopwatch watch) async {
    try {
      final revision = _resolveContentRevision();
      revision.ignore();
      await Future.wait([
        _prepareInitialSettings(),
        _prepareSource(revision, watch),
      ], eagerError: true);
      if (!mounted || _closing) return;
      final mode = _settings.chineseMode;
      if (mode != ReaderChineseMode.original) {
        try {
          _source!.applyTextConversion(await _chineseConverter.load(mode));
        } catch (error, stackTrace) {
          // 转换不可用不能阻止开书；退回原文并同步偏好。
          recordAppError(
            'reader_chinese_conversion_open_failed',
            error,
            stackTrace: stackTrace,
          );
          _source!.applyTextConversion(null);
          _chineseModeFallback = true;
        }
      }
      if (!mounted || _closing) return;
      _showSource();
      if (!_chineseModeFallback) return;
      _chineseModeFallback = false;
      _changeSettings(
        _settings.copyWithChineseMode(ReaderChineseMode.original),
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('简繁转换不可用，已显示原文')));
    } catch (error) {
      _openingFailed = true;
      if (mounted && !_closing) {
        setState(() {
          _error = error;
          _loading = false;
        });
        _scheduleReady();
      }
      await _closeSource();
    }
  }

  void _showSource() {
    final source = _source!;
    setState(() {
      _search = ScanSearchService(
        source: source,
        onLog: (event, fields) =>
            unawaited(ReaderLog.instance.log(event, fields: fields)),
      );
      _imageCache = DecodedImageCache(
        // 1080×2400 真机的两页背景与画廊图需共同驻留，仍受双上限约束。
        maxEntries: 32,
        maxBytes: 32 << 20,
        loadBytes: (url) => _loadImageBytes(source, url),
      );
      _loading = false;
    });
  }

  Future<EpubChapterSource> _openSource() async {
    // 导入已经校验归档，阅读期间只按需读取目标章节。
    final ReaderFormatOpener<EpubChapterSource> opener = EpubFormatOpener(
      verifyCrc: false,
      networkImageCacheDirectoryProvider: getTemporaryDirectory,
      paginationStore: FileChapterPaginationStore(
        directoryProvider: getApplicationSupportDirectory,
      ),
    );
    final options = ReaderOpenOptions(contentVersion: widget.contentRevision);
    final path = widget.sourcePath;
    if (path != null) {
      return opener.openFile(File(path), options: options);
    }
    final bytes = widget.bytes ?? await widget.bytesFuture;
    if (bytes == null) throw StateError('阅读页缺少 EPUB 来源');
    return opener.openBytes(bytes, options: options);
  }

  Future<String> _resolveContentRevision() async {
    final pending = widget.contentRevisionFuture;
    if (pending != null) return pending;
    final known = widget.contentRevision;
    if (known != null && known.isNotEmpty) return known;
    final path = widget.sourcePath;
    if (path != null) {
      return (await sha256.bind(File(path).openRead()).first).toString();
    }
    final bytes = widget.bytes ?? await widget.bytesFuture;
    if (bytes == null) throw StateError('阅读页缺少 EPUB 内容版本');
    return sha256.convert(bytes).toString();
  }

  Future<void> _prepareSource(Future<String> revision, Stopwatch watch) async {
    final source = await _sourceTask;
    if (_openingCancelled) return;
    _source = source;
    source.bookIdForTrace = widget.bookId;
    unawaited(_logParsedSource(source, watch));
    _contentRevision = await revision;
    if (_openingCancelled) return;
    if (_contentRevision.isEmpty) throw StateError('阅读页缺少 EPUB 内容版本');
    source.setContentVersion(_contentRevision);
    if (widget.store case DriftProgressStore store) {
      _anchorBinding = store.bindSource(
        widget.bookId,
        source,
        _contentRevision,
      );
      await _anchorBinding;
    }
  }

  Future<void> _logParsedSource(
    EpubChapterSource source,
    Stopwatch watch,
  ) async {
    final elapsedMs = watch.elapsedMilliseconds;
    try {
      final length = widget.sourcePath == null
          ? (widget.bytes ?? await widget.bytesFuture)?.length ?? 0
          : await File(widget.sourcePath!).length();
      await ReaderLog.instance.log(
        'epub_parse',
        fields: {
          'kb': length ~/ 1024,
          'source': widget.sourcePath == null ? 'memory' : 'file',
          'chapters': source.chapterCount,
          'ms': elapsedMs,
        },
      );
    } catch (_) {
      // 日志晚到或来源已经释放，不影响页面退出。
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final tracker = _readingTracker;
    final follow = _ttsReaderLink?.setScreenActive(
      state == AppLifecycleState.resumed,
    );
    if (follow != null) {
      unawaited(
        follow.then<void>(
          (_) {},
          onError: (Object error) {
            recordAppError('tts_screen_follow_failed', error);
          },
        ),
      );
    }
    switch (state) {
      case AppLifecycleState.resumed:
        _syncReadingActivity();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(tracker?.pause() ?? Future<void>.value());
        if (!(_ttsController?.supportsBackgroundPlayback ?? false)) {
          unawaited(_ttsController?.pause() ?? Future<void>.value());
        }
        _flushProgressInBackground();
      case AppLifecycleState.detached:
        unawaited(tracker?.finish() ?? Future<void>.value());
        unawaited(_ttsController?.stop() ?? Future<void>.value());
        _flushProgressInBackground();
    }
  }

  @override
  void didHaveMemoryPressure() {
    _source?.clearNonCurrentLayouts();
  }

  void _flushProgressInBackground() {
    final session = _readerSession;
    _backgroundFlush = _backgroundFlush.then((_) => _flushStores(session));
    unawaited(_backgroundFlush);
  }

  Future<void> _flushStores(ReaderSession? session) async {
    try {
      await session?.flushProgress();
    } catch (error) {
      await ReaderLog.instance.log(
        'progress_save_error',
        fields: {'bookId': widget.bookId, 'error': error},
      );
      if (_closing) _reportClosingProgressError(error);
    }
  }

  void _reportClosingProgressError(Object error) {
    if (_reportedClosingProgressFailure) return;
    _reportedClosingProgressFailure = true;
    recordAppError('reader_progress_close_failed', error);
  }

  @override
  void dispose() {
    _closing = true;
    unawaited(_readingTracker?.pause() ?? Future<void>.value());
    _openTrace?.stop();
    _readingDurationTimer?.cancel();
    _ttsSleepTimer?.cancel();
    _readingDuration.dispose();
    final session = _readerSession;
    final onClosed = widget.onClosed;
    session?.removeListener(_syncReadingStats);
    _readerSession = null;
    _ttsReaderLink?.dispose();
    _ttsReaderLink = null;
    _ttsController?.state.removeListener(_onTtsStateChanged);
    unawaited(_ttsController?.dispose() ?? Future<void>.value());
    _ttsController = null;
    if (_ownsTtsVoiceStore) _ttsVoiceStore?.close();
    _ttsVoiceStore = null;
    WidgetsBinding.instance.removeObserver(this);
    _search?.dispose();
    _imageCache?.clear();
    unawaited(
      _finishClose(session).whenComplete(() {
        onClosed?.call();
      }),
    );
    super.dispose();
  }

  Future<void> _finishClose(ReaderSession? session) async {
    try {
      await _backgroundFlush;
      await _flushStores(session);
      await _readingTracker?.finish();
    } finally {
      // 保存可能仍需校验原始 CFI，进度落盘后才释放源。
      await _closeSource();
    }
  }

  Future<void> _closeSource() => _sourceCloseTask ??= _releaseSource();

  Future<void> _releaseSource() async {
    EpubChapterSource? source;
    try {
      source = await _sourceTask;
      final binding = _anchorBinding;
      if (binding != null) (await binding)();
    } catch (_) {
      // 打开或借用失败仍继续释放已经取得的归档。
    } finally {
      source?.close();
      await source?.preparationsStopped;
      _source = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 打开书期间先出骨架；就绪后由 ReaderPage 平滑接管（P2-27）。
    return Scaffold(
      key: const ValueKey<String>('epub-reader-scaffold'),
      backgroundColor: _pageTheme.background,
      // 阅读页自行处理安全区，并让正文始终铺满可用区域。
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: widget.readingActive
                ? const Duration(milliseconds: 250)
                : Duration.zero,
            child: _buildBody(),
          ),
          if (_ttsController case final controller?)
            Positioned(
              left: 16,
              // 浮条跟随阅读菜单：只在菜单展开时显示，停在菜单栏上方。
              bottom: readerMenuBarHeight(context) + 8,
              child: IgnorePointer(
                ignoring: !_ttsBarVisible,
                child: ExcludeSemantics(
                  excluding: !_ttsBarVisible,
                  child: AnimatedOpacity(
                    opacity: _ttsBarVisible ? 1 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    child: ReaderTtsPlaybackSheet(
                      controller: controller,
                      coverPath: widget.book?.coverPath,
                      speedLabel: _ttsSpeedLabel(_settings.tts),
                      timerLabel: _ttsSleepDuration == null
                          ? null
                          : '${_ttsSleepDuration!.inMinutes} 分钟',
                      onVoice: () => _editTtsSettings(controller),
                      onSpeed: () => _editTtsSpeed(controller),
                      onTimer: _editTtsTimer,
                      onCancel: controller.stop,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 深浅色跟随软件模式，分别恢复日间和夜间配色。
  ReaderTheme get _pageTheme {
    if (AppThemeScope.maybeOf(context) == null) return _settings.theme;
    return _settings.themeForBrightness(Theme.of(context).brightness);
  }

  Widget _buildBody() {
    if (_loading) {
      return ReaderLoadingSkeleton(title: widget.bookTitle);
    }
    final error = _error;
    if (error != null) {
      return Center(
        key: const ValueKey<String>('epub-open-error'),
        child: Text('打开失败：$error'),
      );
    }
    return Builder(builder: _buildReader);
  }

  Widget _buildReader(BuildContext panelContext) {
    final settings = _settings;
    return ReaderPage(
      key: const ValueKey<String>('reader-page'),
      readingDuration: _readingDuration,
      source: _source!,
      store: widget.store,
      bookId: widget.bookId,
      contentRevision: _contentRevision,
      imageCache: _imageCache,
      bookmarks: widget.bookmarks,
      bookmarkStyle: settings.bookmarkStyle,
      onBookmarkStyleChanged: (style) =>
          _changeSettings(_settings.copyWithBookmarkStyle(style)),
      footnoteStyle: settings.footnoteStyle,
      onFootnoteStyleChanged: (style) =>
          _changeSettings(_settings.copyWithFootnoteStyle(style)),
      onPickBookmarkImage: _bookmarkImages.pick,
      bookmarkImageLoader: _bookmarkImages.load,
      annotations: widget.annotations,
      decorations: widget.decorations,
      decorationRules: widget.decorationRules,
      decorationImages: widget.decorationImages,
      onDictionary: widget.dictionaryStore == null
          ? null
          : (text) => showDictionary(context, widget.dictionaryStore!, text),
      markSettings: settings.markSettings,
      onMarkSettingsChanged: (mark) =>
          _changeSettings(_settings.copyWithMarkSettings(mark)),
      overrides: settings.overrides,
      theme: _pageTheme,
      pageBrightness: AppThemeScope.maybeOf(context) == null
          ? null
          : Theme.of(context).brightness,
      customTheme: settings.customTheme,
      backgroundImageLoader: _backgroundStore.load,
      onPickBackgroundImage: _backgroundStore.pick,
      customFonts: _customFonts,
      onRenameFont: widget.fontStore == null ? null : _renameFont,
      onRemoveFont: widget.fontStore == null ? null : _removeFont,
      onPickFont: widget.fontStore == null ? null : _pickFont,
      onLoadFont: widget.fontStore == null
          ? null
          : (family) async {
              await widget.fontStore!.load(family);
            },
      backgroundId: settings.backgroundId,
      backgroundImageOpacity: settings.backgroundImageOpacity,
      inkMode: settings.inkMode,
      onOverridesChanged: (overrides) =>
          _changeSettings(_settings.copyWithOverrides(overrides)),
      onThemeChanged: _changeTheme,
      onToggleDayNight: AppThemeScope.maybeOf(context) == null
          ? null
          : _toggleDayNight,
      chineseMode: settings.chineseMode,
      onChineseModeChanged: (mode) => unawaited(_changeChineseMode(mode)),
      chineseConversionBusy: _chineseConversionBusy,
      onBackgroundChanged: (backgroundId) =>
          _changeSettings(_settings.copyWithBackground(backgroundId)),
      onBackgroundImageOpacityChanged: (opacity) =>
          _changeSettings(_settings.copyWithBackgroundImageOpacity(opacity)),
      onInkModeChanged: (enabled) =>
          _changeSettings(_settings.copyWithInkMode(enabled)),
      onSearch: _searchResults,
      bookTitle: widget.bookTitle,
      margins: settings.margins,
      cornerInfo: settings.cornerInfo,
      onCornerInfoChanged: (info) =>
          _changeSettings(_settings.copyWithCornerInfo(info)),
      onMarginsChanged: (margins) {
        _changeSettings(_settings.copyWithMargins(margins));
        widget.onMarginsChanged?.call(margins);
      },
      tapZones: settings.tapZones,
      onTapZonesChanged: (zones) =>
          _changeSettings(_settings.copyWithTapZones(zones)),
      pageTurnMode: settings.pageTurnMode,
      onPageTurnModeChanged: (mode) =>
          _changeSettings(_settings.copyWithPageTurnMode(mode)),
      keepScreenOn: settings.keepScreenOn,
      onKeepScreenOnChanged: (enabled) =>
          _changeSettings(_settings.copyWithKeepScreenOn(enabled)),
      volumeKeyPaging: settings.volumeKeyPaging,
      onVolumeKeyPagingChanged: (enabled) =>
          _changeSettings(_settings.copyWithVolumeKeyPaging(enabled)),
      onSessionReady: _bindReaderSession,
      onTts: _toggleTts,
      onMenuBarVisibleChanged: (visible) {
        if (_ttsBarVisible == visible) return;
        setState(() => _ttsBarVisible = visible);
      },
      readingHighlight: _ttsController?.highlight,
      onBookEnd: _openFinishPage,
      onOpenEditor: _canEditBook ? _openEditor : null,
      onChapterRules: _canRechapter ? _openChapterRules : null,
      onEditTarget: _canEditParagraph
          ? (target) => _editParagraph(panelContext, target)
          : null,
      onLog: (event, fields) =>
          unawaited(ReaderLog.instance.log(event, fields: fields)),
      onResolveSearchCfi: _resolveSearchCfi,
      onSearchStream: _searchStream,
    );
  }

  bool _editorOpen = false;
  bool _canRechapter = false;
  bool _finishPageOpen = false;

  Future<void> _loadChapterRuleAvailability() async {
    final library = widget.bookEditorRepository?.library;
    final book = widget.book;
    if (library == null || book == null) return;
    try {
      final enabled = await TxtBookService(library).canRechapter(book);
      if (mounted && !_closing) setState(() => _canRechapter = enabled);
    } catch (_) {
      // 原书读取错误由打开流程展示，不增加不可用的章节入口。
    }
  }

  Future<void> _openChapterRules() async {
    if (!_canRechapter || _editorOpen || _closing) return;
    final library = widget.bookEditorRepository!.library;
    final book = widget.book!;
    _editorOpen = true;
    _syncReadingActivity();
    var contentUpdated = false;
    try {
      await _readerSession?.flushProgress();
      if (!mounted || _closing) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => TxtChapterRulePage(entry: book, library: library),
        ),
      );
      if (saved == true && mounted) {
        contentUpdated = true;
        Navigator.of(context).pop(EpubReaderExit.contentUpdated);
      }
    } catch (error, stackTrace) {
      recordAppError(
        'chapter_rules_open_failed',
        error,
        stackTrace: stackTrace,
      );
    } finally {
      if (!contentUpdated) {
        _editorOpen = false;
        if (mounted) _syncReadingActivity();
      }
    }
  }

  Future<void> _openFinishPage(ReaderSession session, bool rtl) async {
    if (_finishPageOpen || _editorOpen || _closing) return;
    _finishPageOpen = true;
    _syncReadingActivity();
    try {
      await session.flushProgress();
      final review = (await widget.reviewStore?.snapshot())?[widget.bookId];
      if (!mounted || _closing) return;
      final saved = await Navigator.of(context)
          .push<bool>(_finishPageRoute(session, review, rtl));
      if (saved != null && mounted) {
        recordAppEvent(saved ? 'book_finished_review_saved' : 'book_finished');
      }
    } catch (error, stackTrace) {
      if (mounted && !_closing) {
        recordAppError(
          'book_finish_info_failed',
          error,
          stackTrace: stackTrace,
        );
      }
    } finally {
      _finishPageOpen = false;
      if (mounted) _syncReadingActivity();
    }
  }

  PageRoute<bool> _finishPageRoute(
    ReaderSession session,
    BookReview? review,
    bool rtl,
  ) => PageRouteBuilder<bool>(
    transitionDuration:
        MediaQuery.disableAnimationsOf(context) || _settings.inkMode
        ? Duration.zero
        : const Duration(milliseconds: 220),
    reverseTransitionDuration:
        MediaQuery.disableAnimationsOf(context) || _settings.inkMode
        ? Duration.zero
        : const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => _finishForm(session, review, rtl),
    transitionsBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(
        begin: Offset(rtl ? -1 : 1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );

  Widget _finishForm(ReaderSession session, BookReview? review, bool rtl) =>
      ReaderPanelTheme(
        theme: _pageTheme,
        child: FinishBookSheet(
          book:
              widget.book ??
              BookEntry(
                id: widget.bookId,
                title: widget.bookTitle,
                author: '',
                filePath: widget.sourcePath ?? '',
                addedAt: DateTime.now(),
              ),
          review: review,
          allowReview: widget.reviewStore != null,
          finished: session.progress?.finished ?? false,
          fullScreen: true,
          rtl: rtl,
          onCommit: (draft) => _finishBook(session, draft),
        ),
      );

  Future<void> _finishBook(
    ReaderSession session,
    FinishBookDraft? draft,
  ) async {
    final reviews = widget.reviewStore;
    final progress = widget.store;
    Future<void> saveReview() => reviews!.save(
      widget.bookId,
      rating: draft!.rating,
      content: draft.content,
    );
    if (draft != null && reviews != null && progress is DriftProgressStore) {
      await session.markFinished(
        saveWithReview: (value) =>
            progress.saveFinishedWithReview(widget.bookId, value, saveReview),
      );
    } else {
      await session.markFinished();
      if (draft != null && reviews != null) await saveReview();
    }
  }

  bool get _canEditParagraph =>
      widget.bookEditorRepository?.library.supportsPersistence == true &&
      widget.sourcePath != null;

  Future<void> _editParagraph(
    BuildContext panelContext,
    ReaderEditTarget target,
  ) async {
    if (_editorOpen || _closing) return;
    final repository = widget.bookEditorRepository!;
    final bookId = widget.bookId;
    final source = File(widget.sourcePath!);
    _editorOpen = true;
    _syncReadingActivity();
    var updated = false;
    try {
      final saved = await showReaderDrawer<bool>(
        context: panelContext,
        readerTheme: _settings.inkMode
            ? ReaderEnvironment.inkTheme
            : _pageTheme,
        // 本分支的原生抽屉拖动会直接退场；关闭统一经过表单的未保存检查。
        enableDrag: false,
        isDismissible: false,
        builder: (_) => ParagraphEditSheet(
          open: () async {
            await _ttsController?.pause();
            await _readerSession?.flushProgress();
            return repository.openParagraph(
              bookId,
              target.contentRevision ?? _contentRevision,
              source,
              target.spineIndex,
              target.cfi,
              target.endCfi ?? target.cfi,
            );
          },
          save: (edit, input, onStage) =>
              repository.saveParagraph(bookId, edit, input, onStage: onStage),
        ),
      );
      updated = saved == true;
      if (updated && mounted) {
        Navigator.of(context).pop(EpubReaderExit.contentUpdated);
      }
    } finally {
      if (!updated) {
        _editorOpen = false;
        if (mounted) _syncReadingActivity();
      }
    }
  }

  bool get _canEditBook =>
      widget.bookEditorRepository != null &&
      widget.sourcePath != null &&
      switch (defaultTargetPlatform) {
        TargetPlatform.macOS || TargetPlatform.windows => true,
        _ => false,
      };

  Future<void> _openEditor() async {
    if (!_canEditBook || _editorOpen) return;
    final repository = widget.bookEditorRepository;
    final path = widget.sourcePath;
    if (repository == null || path == null) return;
    _editorOpen = true;
    _syncReadingActivity();
    var contentUpdated = false;
    try {
      await _readerSession?.flushProgress();
      if (!mounted) return;
      final progress = _readerSession?.progress;
      final location = progress?.cfi == null
          ? null
          : ReaderEditTarget(
              spineIndex: progress!.spineIndex,
              cfi: progress.cfi!,
              contentRevision: _contentRevision,
            );
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => BookEditorRoute(
            repository: repository,
            bookId: widget.bookId,
            sourcePath: path,
            contentRevision: _contentRevision,
            title: widget.bookTitle,
            target: location,
            readingSettings: _settings,
          ),
        ),
      );
      if (saved == true && mounted) {
        contentUpdated = true;
        Navigator.of(context).pop(EpubReaderExit.contentUpdated);
      }
    } catch (error, stackTrace) {
      recordAppError(
        'reader_editor_open_failed',
        error,
        stackTrace: stackTrace,
      );
    } finally {
      // 旧版本退出动画期间继续暂停统计；新会话就绪后自行恢复。
      if (!contentUpdated) {
        _editorOpen = false;
        if (mounted) _syncReadingActivity();
      }
    }
  }

  void _bindReaderSession(ReaderSession session) {
    unawaited(_ttsController?.stop() ?? Future<void>.value());
    _readerSession?.removeListener(_syncReadingStats);
    _readerSession = session;
    _trackedPageTurns = session.pageTurns;
    _trackedCharactersRead = session.charactersRead;
    session.addListener(_syncReadingStats);
    _scheduleReady();
  }

  void _syncReadingStats() {
    final session = _readerSession;
    if (session == null) {
      return;
    }
    _scheduleReady();
    final pageTurns = session.pageTurns - _trackedPageTurns;
    final characters = session.charactersRead - _trackedCharactersRead;
    if (pageTurns <= 0 && characters <= 0) {
      return;
    }
    _trackedPageTurns = session.pageTurns;
    _trackedCharactersRead = session.charactersRead;
    _readingTracker?.recordPageTurn(count: pageTurns, characters: characters);
  }

  void _scheduleReady() {
    if (_readyNotified || _readyScheduled || _closing) return;
    final session = _readerSession;
    final failed = _error != null || session?.error != null;
    final complete = _hasPreparedFrame(session);
    if (!failed && !complete) return;
    _readyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readyScheduled = false;
      if (!mounted || _closing || _readyNotified) return;
      final session = _readerSession;
      if (_error == null && session?.error == null) {
        if (!_hasPreparedFrame(session)) return;
        _readable = true;
      }
      _readyNotified = true;
      _openTrace?.stop();
      _syncReadingActivity();
      widget.onReady?.call();
      if (_readable && _settings.tts.hasOfflineVoice) {
        unawaited(
          _ensureTtsController()
              .prepare(_settings.tts)
              .then<void>(
                (_) {},
                onError: (Object error) {
                  recordAppError('tts_prepare_failed', error);
                },
              ),
        );
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // 背景封面可能没有正文锚点，进度为空不影响已经准备好的首屏。
  bool _hasPreparedFrame(ReaderSession? session) =>
      session != null && !session.loading && session.hasContent;

  void _syncReadingActivity() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (_readable &&
        widget.readingActive &&
        foreground &&
        !_closing &&
        !_editorOpen &&
        !_finishPageOpen) {
      _readingTracker?.start();
    } else {
      unawaited(_readingTracker?.pause() ?? Future<void>.value());
      unawaited(_ttsController?.pause() ?? Future<void>.value());
    }
  }

  Future<List<SearchPanelResult>> _searchResults(String query) async => [
    for (final result in await _search!.search(query)) _panelResult(result),
  ];

  Stream<SearchProgress> _searchStream(String query) async* {
    await for (final progress in _search!.searchStream(query)) {
      yield SearchProgress(
        results: [for (final result in progress.results) _panelResult(result)],
        scanned: progress.scanned,
        total: progress.total,
      );
    }
  }

  Future<String?> _resolveSearchCfi(SearchPanelResult result) =>
      _search!.resolveCfi(
        SearchResult(
          spineIndex: result.spineIndex,
          charOffset: result.charOffset,
          chapterTitle: result.chapterTitle,
          context: result.context,
          matchLength: result.matchLength,
        ),
      );

  static SearchPanelResult _panelResult(SearchResult result) =>
      SearchPanelResult(
        spineIndex: result.spineIndex,
        charOffset: result.charOffset,
        chapterTitle: result.chapterTitle,
        context: result.context,
        matchLength: result.matchLength,
        cfi: result.cfi,
      );
}

/// 路径兼容与归档解压统一交给书籍资源，解压不再占用阅读界面线程。
Future<Uint8List?> _loadImageBytes(EpubChapterSource source, String url) =>
    source.readImageBytes(url);

class _TtsSlider extends StatelessWidget {
  const _TtsSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SizedBox(width: label.length > 2 ? 72 : 42, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 42,
        child: Text(value.toStringAsFixed(2), textAlign: TextAlign.end),
      ),
    ],
  );
}
