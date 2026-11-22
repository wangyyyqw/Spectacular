/// 手动关联草稿，沿用扩展项目的平台白名单及必填项规则。
class ReaMicroManualAssociation {
  const ReaMicroManualAssociation({
    required this.name,
    required this.author,
    required this.intro,
    required this.publisher,
    required this.wordCount,
    required this.status,
    required this.cover,
  });

  final String name;
  final String author;
  final String intro;
  final String publisher;
  final String wordCount;
  final String status;
  final String cover;

  static const platforms = [
    '起点中文网',
    '纵横中文网',
    '息壤中文网',
    '有毒小说网',
    '独阅读',
    '飞卢小说网',
    '晋江文学城',
    '刺猬猫阅读',
    '番茄小说',
    '次元姬',
    '长佩文学',
    'QQ阅读',
    '少年梦',
    '菠萝包轻小说',
    '寒武纪年',
    '不可能的世界',
  ];
  static const statuses = ['连载', '完结'];

  /// 表单与提交共用校验，防止绕过界面创建不完整条目。
  String? get error {
    if (name.trim().isEmpty) return '书名不能为空';
    if (author.trim().isEmpty) return '作者不能为空';
    if (!platforms.contains(publisher.trim())) return '请选择支持的来源平台';
    if (wordCount.trim().isEmpty) return '字数不能为空';
    if (!statuses.contains(status.trim())) return '请选择连载或完结状态';
    final url = Uri.tryParse(cover.trim());
    if (url == null ||
        !const ['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty ||
        cover.trim().contains(RegExp(r'[\s\x00-\x1f]'))) {
      return '请输入有效的 HTTP 或 HTTPS 封面地址';
    }
    if (intro.trim().isEmpty) return '简介不能为空';
    if (intro.trim().length > 2000) return '简介不能超过 2000 字';
    return null;
  }
}
