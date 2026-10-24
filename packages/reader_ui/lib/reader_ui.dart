/// 阅读器 UI 公共导出。
library;

export 'package:reader_core/api.dart';

export 'page_cache.dart';
export 'reader_view.dart';
export 'virtual_pager.dart';
export 'reader_session.dart';
export 'reader_page.dart';
export 'loading_skeleton.dart';
export 'image_preview_page.dart';
export 'theme/reader_theme.dart';

/// 阅读器 UI 包标识，用于启动期确认依赖连通。
const String readerUiPackageName = 'reader_ui';
