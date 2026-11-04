/// 书架排序方式（P4-08）。
enum BookSortOrder {
  /// 最近阅读优先（默认）。
  recent('最近阅读', 'recent'),

  /// 导入时间倒序。
  added('导入时间', 'added'),

  /// 书名升序。
  title('书名', 'title');

  const BookSortOrder(this.label, this.value);

  /// 菜单文案。
  final String label;

  /// 持久化值。
  final String value;

  /// 按持久化值还原，未知值回退最近阅读。
  static BookSortOrder fromValue(String? value) {
    for (final order in values) {
      if (order.value == value) {
        return order;
      }
    }
    return recent;
  }
}

/// 书架排序设置键。
const bookshelfSortKey = 'bookshelf.sort';
