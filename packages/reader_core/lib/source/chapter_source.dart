/// 阅读来源的跨层契约。
///
/// 核心引擎提供章节、位置与可取消任务，阅读会话负责调度与交互。
/// 此处仅描述现有来源能力，不依赖应用或 UI 的实现。
library;

import '../css/reader_overrides.dart';
import '../layout/paginator.dart' show PageContent;
import '../position/location_anchor.dart' show AnchorChapter;
import '../src/api/models.dart' show TocEntry;

/// 章节页来源。
abstract interface class ReaderChapterSource {
  /// 章节数。
  int get chapterCount;

  /// 加载一章的页。
  Future<List<PageContent>> loadChapter(int spineIndex);
}

/// 排版任务优先级；当前阅读始终优先于预取和后台任务。
enum ChapterLayoutPriority { reading, prefetch, background }

/// 等待者主动取消；用于区别可忽略的过期请求与真实读取失败。
class ChapterLoadCancelled implements Exception {
  const ChapterLoadCancelled();

  @override
  String toString() => '章节排版请求已取消';
}

/// 单个等待者持有的任务句柄；取消不影响其他等待者。
abstract interface class ChapterLoadHandle {
  Future<List<PageContent>> get result;
  void cancel();
}

/// 稳定页只追加；[result] 始终代表完整章节，取消由各等待者独立持有。
abstract interface class ProgressiveChapterLoadHandle
    implements ChapterLoadHandle {
  Future<List<PageContent>> get firstPages;
  List<PageContent> get availablePages;

  /// 仅稳定页追加或完整页面交付时发送，不用于通知页数统计。
  Stream<List<PageContent>> get updates;

  /// 完整页界确定后即可提供准确总数；未知为 null，不代表完整结果已交付。
  int? get pageCount;

  /// 准确总数独立发布，可早于首页；不得借此把章节标为完整。
  Stream<int> get pageCountUpdates;

  /// 仅完整章节成功交付时为 true；取消和失败不构成章节完成。
  bool get isComplete;
  ChapterLayoutPriority get priority;
  void setPriority(ChapterLayoutPriority priority);
}

/// 分页阅读可以先取得稳定首页，滚动与位置定位仍等待完整章节。
abstract interface class ProgressiveChapterSource
    implements ScheduledChapterSource {
  ProgressiveChapterLoadHandle scheduleProgressiveChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    bool retainResult = true,
  });
}

/// 翻页活动期间暂停低优先级排版，当前目标页的前台请求仍可执行。
abstract interface class BackgroundLayoutChapterSource {
  void setBackgroundLayoutPaused(bool paused);
}

/// 可取消、可按优先级调度的章节源。
abstract interface class ScheduledChapterSource implements ReaderChapterSource {
  ChapterLoadHandle scheduleChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    bool retainResult = true,
  });

  void cancelPendingLayouts();
}

/// 只准备原文锚点，不进行文字测量或分页。
abstract interface class AnchorChapterSource implements ReaderChapterSource {
  Future<AnchorChapter> loadAnchorChapter(int spineIndex);
}

/// 位置准备的独立等待者，取消不会影响同键的装饰核验或章节排版。
abstract interface class ReaderPreparationHandle<T> {
  Future<T> get result;
  void cancel();
}

abstract interface class ScheduledAnchorChapterSource
    implements AnchorChapterSource {
  ReaderPreparationHandle<AnchorChapter> scheduleAnchorChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  });
}

/// 每章冻结排版输入前先核验该章装饰与字体。
abstract interface class PreparedChapterSource implements AnchorChapterSource {
  /// 准备目标章原文装饰与字体；不得借此调用章节分页。
  void setChapterPreparer(Future<void> Function(int)? preparer);

  /// 存储读取后更新书级请求度量指纹，不随逐章核验或字体就绪而改变。
  void setBookTypographyFingerprint(String fingerprint);
}

/// 全书手工装饰请求的字体族；登记依赖不提前加载其他章节的字体。
abstract interface class BookTypographyFontSource {
  void setBookTypographyFamilies(Set<String> families);

  /// 目标章实际加载后的结果；尚未尝试的字体保持未确认状态。
  /// 加载失败须覆盖同进程中残留的注册状态，但不改变原始字体请求集合。
  void setBookTypographyFontAvailability(String family, bool available);
}

/// 可接收当前阅读章节的章节源；用于固定当前章缓存。
abstract interface class CurrentReadingChapterSource
    implements ReaderChapterSource {
  void setCurrentReadingChapter(int spineIndex);
}

/// 能提供目录的章节源（P4-11）：章节数之外的目录树。
abstract interface class TocChapterSource implements ReaderChapterSource {
  /// 目录项（嵌套结构，每项自带目标 spine 序号）。
  List<TocEntry> get toc;
}

/// 支持按设置重排的章节源（P2-24）：字号/行高/页边距变化后原地重排。
abstract interface class RestylableChapterSource
    implements ReaderChapterSource {
  /// 应用阅读器覆盖设置；调用方随后应重新加载章节。
  Future<void> applyOverrides(ReaderOverrides overrides);
}

/// 能报告影响正文度量的源状态（字体注册、字体缩放等）。
///
/// 该值只用于判断滚动位置能否复用精确像素偏移；为空时仍按 CFI 恢复。
abstract interface class LayoutDependencyChapterSource
    implements ReaderChapterSource {
  /// 当前字体/度量依赖的稳定指纹。
  String get layoutDependency;
}

/// 字体按章加载时只比较目标章的度量，避免访问其他章改变恢复指纹。
abstract interface class SpineLayoutDependencyChapterSource
    implements LayoutDependencyChapterSource {
  String layoutDependencyForSpine(int spineIndex);
}

/// 能区分“章节文件确认缺失”和普通解析/IO 错误的章节源。
///
/// 缺章返回空页，分页器按可读章节顺序跳过；未知异常仍向上抛出。
abstract interface class MissingChapterSource implements ReaderChapterSource {
  /// 指定 spine 是否已确认缺失。
  bool isChapterMissing(int spineIndex);
}

/// 能按原文位置计算全书进度，并在比例与 CFI 之间双向转换的章节源。
///
/// UI 只消费 0～1 的比例；章节源负责把 CFI 解析到章内字符偏移，并使用
/// 与书库一致的进度权重（排除目录、非正文与缺失章节）。
abstract interface class PositionedChapterSource
    implements ReaderChapterSource {
  /// CFI 对应的全书正文比例（0～1）；无法定位或章节尚未准备时返回 null。
  double? readingPercentForCfi(String? cfi);

  /// 全书正文比例对应的 CFI；没有可读正文时返回 null。
  String? cfiForReadingPercent(double percent);

  /// 目录项应跳转的 CFI：优先目录自带 CFI，其次解析 fragment，最后章首。
  String? cfiForTocEntry(TocEntry entry);
}

/// 百分比跳转先定位目标章，再异步准备该章原文索引。
abstract interface class AsyncPositionedChapterSource
    implements PositionedChapterSource {
  Future<String?> prepareCfiForReadingPercent(double percent);
}

abstract interface class ScheduledPositionedChapterSource
    implements AsyncPositionedChapterSource {
  ReaderPreparationHandle<String?> scheduleCfiForReadingPercent(double percent);
}

/// 正文区相对整页的实际左右内缩，独立于阅读设置中的默认页边距。
typedef ContentSideInsets = ({double left, double right});

/// 可应用正文区尺寸的章节源（旋转/窗口变化，P2-31）。
abstract interface class ResizableChapterSource implements ReaderChapterSource {
  /// 应用正文区尺寸及整页到正文的上内缩（含安全区与页眉槽）。
  /// [sideInsets] 供出血图片测量；未传时沿用设置页边距。
  /// 返回是否真的发生变化，变化后调用方重新加载章节。
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
    ContentSideInsets? sideInsets,
  });
}
