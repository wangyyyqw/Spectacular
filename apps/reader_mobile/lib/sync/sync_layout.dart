import 'sync_models.dart';

const syncLogDirectory = 'personal/_sync/logs';

/// 每条业务记录只有一个归属；笔记页从各书标注汇总，不重复存正文。
String syncRecordDirectory(
  SyncEntity entity,
  Map<String, SyncEntity> entities,
) {
  final book = entity.data['book_id'] as String?;
  return switch (entity.type) {
    'book' => 'book/${entity.id}/content',
    'reading_progress' => 'book/$book/progress',
    'annotations' => 'book/$book/annotations',
    'decorations' => 'book/$book/decorations',
    'decoration_selection' => 'book/${entity.id}/decorations',
    'decoration_rule_groups' =>
      book == null
          ? 'personal/resources/decorations'
          : 'book/$book/decorations',
    'decoration_rules' => syncRecordDirectory(
      entities['decoration_rule_groups/${entity.data['group_id']}'] ??
          (throw const FormatException('装饰规则缺少所属分组')),
      entities,
    ),
    'activity' || 'reading_sessions' || 'book_color' => 'personal/statistics',
    'book_reviews' || 'list' || 'list_member' => 'personal/notes',
    'shelf_groups' ||
    'shelf_group_books' ||
    'book_tags' ||
    'book_tag_links' => 'personal/bookshelf',
    'setting' => 'personal/preferences',
    'user_fonts' => 'personal/resources/fonts',
    'decoration_style' => 'personal/resources/decorations',
    _ => throw const FormatException('同步数据包含未知类型'),
  };
}

void validateSyncDirectory(String directory) {
  if (!RegExp(r'^book/[a-f0-9]{64}/(content|annotations|decorations|progress)$')
          .hasMatch(directory) &&
      !const {
        'personal/statistics',
        'personal/notes',
        'personal/bookshelf',
        'personal/preferences',
        'personal/resources/fonts',
        'personal/resources/backgrounds',
        'personal/resources/decorations',
      }.contains(directory)) {
    throw const FormatException('同步数据目录无效');
  }
}
