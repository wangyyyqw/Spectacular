/// 跨模块公共接口与数据模型。
///
/// 只放跨层契约，不放实现细节；平台插件与宿主包不允许出现在本包。
library;

export 'src/api/interfaces.dart';
export 'src/api/models.dart';
export 'layout/image_gallery.dart';
export 'text/reader_text_overlay.dart';
export 'position/book_progress_index.dart';
