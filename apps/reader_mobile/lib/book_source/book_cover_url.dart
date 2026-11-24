/// 规整第三方封面；番茄使用原图路径，避免签名过期和旧尺寸模板失效。
String? normalizeBookCoverUrl(String? value, {DateTime? now}) {
  var url = value?.trim().replaceAll('&amp;', '&') ?? '';
  if (url.startsWith('//')) url = 'https:$url';
  final relative = RegExp(
    r'^(?:/?origin/)?(novel-(?:pic|images|static)/[^?~]+)',
  ).firstMatch(url);
  if (relative != null) {
    return 'https://p6-novel.byteimg.com/origin/${relative.group(1)}';
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (RegExp(r'^img\d+\.doubanio\.com$').hasMatch(host)) {
    return uri.replace(scheme: 'https', host: 'img3.doubanio.com').toString();
  }
  final fanqie = [
    'byteimg.com',
    'fqnovelpic.com',
    'fqnovel.com',
    'fanqienovel.com',
  ].any((domain) => host == domain || host.endsWith('.$domain'));
  if (fanqie) {
    final path = RegExp(r'(novel-(?:pic|images|static)/[^?~]+)')
        .firstMatch(uri.path)
        ?.group(1);
    if (path != null) return 'https://p6-novel.byteimg.com/origin/$path';
  }
  // 参考项目已失效的起点代理，书号来自接口本身。
  if (host == 'shenmoxs.top' && uri.path == '/cover' && uri.userInfo.isEmpty) {
    final id = uri.queryParameters['bookId'] ?? '';
    if (RegExp(r'^\d{5,15}$').hasMatch(id)) {
      return 'https://bookcover.yuewen.com/qdbimg/349573/$id/600';
    }
  }
  return url;
}

/// 豆瓣不同图片节点的拦截策略不同，失败时保留同一图片路径重试。
List<String> bookCoverCandidates(String url) {
  final uri = Uri.parse(url);
  return [
    url,
    if (RegExp(r'^img\d+\.doubanio\.com$').hasMatch(uri.host)) ...[
      for (final host in ['img1.doubanio.com', 'img2.doubanio.com'])
        if (uri.host != host) uri.replace(host: host).toString(),
    ],
  ];
}

Map<String, String> bookCoverHeaders(String url) =>
    Uri.parse(url).host.toLowerCase().endsWith('.doubanio.com')
    ? const {
        'Referer': 'https://book.douban.com/',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
      }
    : const {};
