/// 错误分类：用稳定错误码、分类、严重度和可选偏移描述解析结果。
enum EpubErrorCategory { opening, layout, resource, annotation, tts, io, unknown }

/// 错误严重度。
///
/// [informational] 不等于没事：要显示在书籍详情里，只是不弹窗。
enum EpubErrorSeverity { fatal, recoverable, informational }

/// 码表条目：稳定码 + 分类 + 严重度 + 出处。
class EpubCodeSpec {
  /// 创建条目。
  const EpubCodeSpec(
    this.code,
    this.category,
    this.severity,
    this.source, {
    this.reservedFor,
  });

  /// 稳定错误码（大写下划线，跨版本不变）。
  final String code;

  /// 分类。
  final EpubErrorCategory category;

  /// 严重度。
  final EpubErrorSeverity severity;

  /// 出处（技术方案章节 / 验收记录）。
  final String source;

  /// 预留码的消费任务（空 = 已有消费方）。
  final String? reservedFor;

  /// 是否预留码（码表登记但当前代码尚未抛出）。
  bool get isReserved => reservedFor != null;
}

/// 诊断码表（P7-05）：唯一事实来源，单测防漂移
///（`test/epub/epub_code_table_test.dart` 扫描 lib 内全部码字面量）。
///
/// 三条纪律（§82.4）：
/// 1. code 稳定、不随文案变：本地化只改 message，code 永远不动；
/// 2. 只有需要分支处理的才升为 code，其余进 detail；
/// 3. informational 也要可见（书籍详情展示）。
abstract final class EpubCodeTable {
  /// 全量码表（现有 18 + 预留 12）。
  static const List<EpubCodeSpec> specs = <EpubCodeSpec>[
    // ---- 打开期：致命（§55.3 拒绝路径，L4 无效 EPUB）----
    EpubCodeSpec('E_OCF', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§5.1/§55.3 非法 OCF 容器'),
    EpubCodeSpec('E_ARCHIVE', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§55.3 非 ZIP/ZIP 解析失败'),
    EpubCodeSpec('E_CRC', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§5.1 CRC 校验失败'),
    EpubCodeSpec('E_CONTAINER_MISSING', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§55.3 缺 container.xml'),
    EpubCodeSpec('E_CONTAINER_XML', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§55.3 container.xml 损坏'),
    EpubCodeSpec('E_CONTAINER_ROOTFILE', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§55.3 rootfile 缺失/为空'),
    EpubCodeSpec('E_OPF_MISSING', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§55.3 OPF 不存在'),
    EpubCodeSpec('E_OPF_XML', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§55.3 OPF XML 损坏'),
    EpubCodeSpec('E_OPF_PACKAGE', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§55.3 缺 package 元素'),
    EpubCodeSpec('E_SPINE_EMPTY', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§55.3 spine 为空'),
    EpubCodeSpec('E_INTERNAL', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§55.3 未预期内部错误'),
    // ---- 打开期：可降级（§12 容错表；降级路径 P7-12/P7-13 接管）----
    EpubCodeSpec('E_SPINE_MISSING', EpubErrorCategory.resource, EpubErrorSeverity.recoverable, '§12 spine 项文件缺失→跳过并标记'),
    EpubCodeSpec('E_TOC_NCX_MISSING', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§35.2 回退链第 2 步'),
    EpubCodeSpec('E_TOC_NCX_XML', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§35.2 NCX 损坏回退 NAV'),
    EpubCodeSpec('E_TOC_NCX_EMPTY', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§35.2 navMap 缺失/为空回退'),
    EpubCodeSpec('E_TOC_NAV_MISSING', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§35.2 回退链第 3 步'),
    EpubCodeSpec('E_TOC_NAV_XML', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§35.2 NAV 损坏走退化目录'),
    EpubCodeSpec('E_TOC_NAV_EMPTY', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§35.2 toc 为空走退化目录'),
    EpubCodeSpec('E_DOCUMENT_TOLERANT_FALLBACK', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§12 XHTML 严格解析失败回退容错（P7-11 双路径）'),
    EpubCodeSpec('E_CONTAINER_FALLBACK', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§12 container.xml 不可用回退扫描 OPF（P7-12）'),
    // ---- 书库导入去重（打开路径之外的拒绝口径，文案见 EpubRejectionMessages）----
    EpubCodeSpec('E_DUPLICATE', EpubErrorCategory.io, EpubErrorSeverity.fatal, '§55.3 同标识书籍已存在，导入拒绝'),
    EpubCodeSpec('E_MANIFEST_MEDIA_TYPE_INFERRED', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§12 manifest 项缺 media-type 按扩展名推断（P7-12）'),
    EpubCodeSpec('E_TOC_TARGET_OUTSIDE_SPINE', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§35.2 目录项目标不在 spine 降级到最近章节（P7-13）'),
    EpubCodeSpec('E_SPINE_ALL_NON_LINEAR', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§35.2 spine 全部非 linear 退化目录包含全部项（P7-13）'),
    EpubCodeSpec('E_SPINE_FALLBACK', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§12 spine 为空时按 manifest/整库扫描恢复阅读顺序（对照 Ferrous fallback parser）'),
    // ---- ZIP 诊断四档（P7-15）----
    EpubCodeSpec('E_ZIP_EOCD_MISSING', EpubErrorCategory.opening, EpubErrorSeverity.fatal, '§55.3 EOCD/中心目录缺失（不可恢复档）'),
    EpubCodeSpec('E_ZIP_LOCAL_HEADER', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§55.3 局部头损坏/错位（偏移修补恢复档）'),
    EpubCodeSpec('E_ZIP_ENTRY_TRUNCATED', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§12 条目截断/损坏（跳过坏条目恢复档）'),
    EpubCodeSpec('E_ZIP_NAME_ENCODING', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§54 文件名传统编码错位（资源索引大小写容错兜底）'),
    EpubCodeSpec('E_ZIP_RESOURCE_LIMIT', EpubErrorCategory.resource, EpubErrorSeverity.recoverable, 'ZIP 单条目解压预算与异常压缩比诊断'),
    // ---- 压力防护（P7-16）----
    EpubCodeSpec('E_DOM_NESTING_TOO_DEEP', EpubErrorCategory.layout, EpubErrorSeverity.recoverable, '§12 DOM 嵌套超 500 层子树展平为文本'),
    EpubCodeSpec('E_ATTRIBUTE_TRUNCATED', EpubErrorCategory.layout, EpubErrorSeverity.recoverable, '§12 属性值超 65536 字符截断（SVG/data URI 炸弹防线）'),
    EpubCodeSpec('E_PAGINATION_TRUNCATED', EpubErrorCategory.layout, EpubErrorSeverity.recoverable, '§12 单章超 20000 页截断（渐进提示不中断）'),
    EpubCodeSpec('E_REGEX_SLOW_SUSPENDED', EpubErrorCategory.layout, EpubErrorSeverity.recoverable, '§12 用户正则超 1s 预算挂起（不卡 UI）'),
    EpubCodeSpec('E_READER_PRIVATE_IN_AUTHOR', EpubErrorCategory.opening, EpubErrorSeverity.recoverable, '§12 作者 CSS 使用阅读器私有钩子（-reader-*）被剥除/丢弃（P7-17）'),
    // ---- 预留：资源与字体（P3）----
    EpubCodeSpec('E_RESOURCE_MISSING', EpubErrorCategory.resource, EpubErrorSeverity.recoverable, '§54.3 资源找不到', reservedFor: 'P3-25'),
    EpubCodeSpec('E_RESOURCE_DECODE_FAILED', EpubErrorCategory.resource, EpubErrorSeverity.recoverable, '§50.2 图片/资源解码失败', reservedFor: 'P3-08'),
    EpubCodeSpec('E_FONT_UNSUPPORTED', EpubErrorCategory.resource, EpubErrorSeverity.informational, '§68.6 ttc/woff 不支持（详情页展示，不弹窗）', reservedFor: 'P3-06'),
    EpubCodeSpec('E_FONT_OBFUSCATION_FAILED', EpubErrorCategory.resource, EpubErrorSeverity.recoverable, '§5.3 解混淆失败回退字体', reservedFor: 'P3-05'),
    EpubCodeSpec('E_FONT_LOAD_FAILED', EpubErrorCategory.resource, EpubErrorSeverity.recoverable, '§68.6 字体加载失败/缺失回退系统字体（提示只一次）', reservedFor: 'P3-06'),
    EpubCodeSpec('E_FAIRPLAY_ENCRYPTION', EpubErrorCategory.resource, EpubErrorSeverity.informational, '§5.3 Apple FairPlay 加密检测到，不支持解密', reservedFor: 'P3-05'),
    // ---- 预留：排版与渲染（P6）----
    EpubCodeSpec('E_LAYOUT_ABORTED', EpubErrorCategory.layout, EpubErrorSeverity.recoverable, '§71.5 分页被取消/异常', reservedFor: 'P6-12'),
    EpubCodeSpec('E_LAYOUT_RENDER_FAILED', EpubErrorCategory.layout, EpubErrorSeverity.recoverable, '§71.5 单页绘制异常', reservedFor: 'P6-12'),
    // ---- 预留：标注（P4）----
    EpubCodeSpec('E_ANNOTATION_RELOCATE_FAILED', EpubErrorCategory.annotation, EpubErrorSeverity.informational, '§30.4 CFI 失效且三级重定位无果（置灰保留）；三级实现在 position/relocator.dart（P7-14），码串消费在存储层', reservedFor: 'P4-17'),
    EpubCodeSpec('E_ANNOTATION_STORE_FAILED', EpubErrorCategory.annotation, EpubErrorSeverity.recoverable, '§30.2 写库失败', reservedFor: 'P4-17'),
    // ---- 预留：TTS（P6，暂缓）----
    EpubCodeSpec('E_TTS_NO_ENGINE', EpubErrorCategory.tts, EpubErrorSeverity.fatal, '§69.7 无 TTS 引擎', reservedFor: 'P6-04'),
    EpubCodeSpec('E_TTS_LANGUAGE_MISSING', EpubErrorCategory.tts, EpubErrorSeverity.fatal, '§69.7 缺语音包', reservedFor: 'P6-08'),
    EpubCodeSpec('E_TTS_UTTERANCE_FAILED', EpubErrorCategory.tts, EpubErrorSeverity.recoverable, '§69.7 单句合成失败', reservedFor: 'P6-08'),
    // ---- 预留：导入 IO（P4）----
    EpubCodeSpec('E_IO_DISK_FULL', EpubErrorCategory.io, EpubErrorSeverity.fatal, '§37.1 导入时空间不足', reservedFor: 'P4-03'),
  ];

  static final Map<String, EpubCodeSpec> _byCode = <String, EpubCodeSpec>{
    for (final spec in specs) spec.code: spec,
  };

  /// 按码查条目；未登记返回 null（防漂移单测会拦截未登记码）。
  static EpubCodeSpec? byCode(String code) => _byCode[code];
}

/// 一条结构化诊断记录（抛出与记录共用；[EpubException.toError] 生成）。
class EpubError {
  /// 创建记录。
  const EpubError({
    required this.code,
    required this.category,
    required this.severity,
    required this.message,
    this.detail = const <String, Object?>{},
    this.offset,
  });

  /// 稳定错误码。
  final String code;

  /// 分类。
  final EpubErrorCategory category;

  /// 严重度。
  final EpubErrorSeverity severity;

  /// 可读原因（本地化只改这里）。
  final String message;

  /// 细分原因（不参与分支，§82.4 纪律 2）。
  final Map<String, Object?> detail;

  /// 相关偏移（字节/字符，可空）。
  final int? offset;

  /// 是否致命（等价 severity == fatal 的便捷判断）。
  bool get isFatal => severity == EpubErrorSeverity.fatal;
}

/// EPUB 解析错误：带稳定错误码，供 [ImportReport] 与 UI 使用。
///
/// 分类与严重度不落字段，从 [EpubCodeTable] 派生（保持 const 构造与
/// 现有调用方兼容）；未登记的码按「unknown / fatal」兜底，防漂移单测
/// 会拦截。
class EpubException implements Exception {
  /// 创建错误。
  const EpubException(
    this.code,
    this.message, {
    this.detail = const <String, Object?>{},
    this.offset,
  });

  /// 稳定错误码（大写下划线）。
  final String code;

  /// 可读原因。
  final String message;

  /// 细分原因（可选）。
  final Map<String, Object?> detail;

  /// 相关偏移（可选）。
  final int? offset;

  /// 码表条目（未登记为 null）。
  EpubCodeSpec? get spec => EpubCodeTable.byCode(code);

  /// 分类（未登记码兜底 unknown）。
  EpubErrorCategory get category =>
      spec?.category ?? EpubErrorCategory.unknown;

  /// 严重度（未登记码兜底 fatal，宁严勿漏）。
  EpubErrorSeverity get severity => spec?.severity ?? EpubErrorSeverity.fatal;

  /// 转结构化诊断记录。
  EpubError toError() => EpubError(
    code: code,
    category: category,
    severity: severity,
    message: message,
    detail: detail,
    offset: offset,
  );

  @override
  String toString() => 'EpubException($code): $message';
}
