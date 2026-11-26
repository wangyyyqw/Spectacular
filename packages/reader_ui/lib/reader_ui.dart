/// 阅读器 UI 公共导出。
library;

export 'package:reader_core/api.dart';

export 'page_cache.dart';
export 'reader_view.dart';
export 'tap_zones.dart';
export 'virtual_pager.dart';
export 'reader_session.dart';
export 'reader_page.dart';
export 'reader_ui_diagnostics.dart';
export 'paging/page_turn_mode.dart';
export 'loading_skeleton.dart';
export 'image_preview_page.dart';
export 'theme/reader_theme.dart';
export 'theme/reader_ui_components.dart';
export 'theme/reader_ui_style.dart';
export 'annotations/annotation.dart';
export 'annotations/mark_settings.dart';
export 'bookmarks/bookmark_style.dart';
export 'footnote_dialog.dart' show ReaderFootnoteStyle;
export 'decorations/decoration.dart';
export 'decorations/decoration_image_store.dart';
export 'decorations/decoration_rules.dart';
export 'decorations/decoration_rule_preview.dart';

/// 阅读器 UI 包标识，用于启动期确认依赖连通。
const String readerUiPackageName = 'reader_ui';
