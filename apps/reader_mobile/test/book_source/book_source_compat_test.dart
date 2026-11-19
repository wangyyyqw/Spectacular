import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/book_source_compat.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';

void main() {
  group('在线书籍字段兼容', () {
    test('字数单位与无效值归一', () {
      expect(normalizeOnlineWordCount('12.30万'), '12.3万字');
      expect(normalizeOnlineWordCount('123456'), '12.3万字');
      expect(normalizeOnlineWordCount('856'), '856字');
      expect(normalizeOnlineWordCount('一万字'), '');
      expect(normalizeOnlineWordCount('0'), '');
      expect(normalizeOnlineWordCount('约 100 万字'), '约 100 万字');
    });

    test('平台、章节数与更新时间标签', () {
      expect(normalizeOnlinePlatformLabel('番茄小说'), '番茄');
      expect(normalizeOnlinePlatformLabel('Fanqie Novel'), '番茄');
      expect(normalizeOnlinePlatformLabel('起点中文网'), '起点');
      expect(normalizeOnlinePlatformLabel('鲸落接口'), '鲸落接口');
      expect(parseOnlineChapterCount('1,234章'), 1234);
      expect(parseOnlineChapterCount('未知'), 0);

      final timestamp = DateTime(2025, 6, 11).millisecondsSinceEpoch ~/ 1000;
      expect(formatOnlineUpdateTime('$timestamp'), '2025 06 11');
      expect(formatOnlineUpdateTime('2025-06-11T12:00:00'), '2025 06 11');
      expect(formatOnlineUpdateTime('0'), '');

      expect(
        onlineSearchTagLine(
          sourceName: '番茄小说',
          status: '完结',
          wordCount: '1.3万字',
          chapterCount: 1,
          updateTime: '2025-06-11',
        ),
        '番茄 / 完结 / 1.3万字 / 1章 / 2025 06 11',
      );
      expect(
        onlineSearchTagLine(sourceName: '番茄', status: '番茄', wordCount: '1.3万字'),
        '番茄 / 1.3万字',
      );
      expect(onlineSearchTagLine(), '详情加载中');
    });

    test('状态文本与末章推断', () {
      expect(normalizeOnlineStatus('连载中'), '连载');
      expect(normalizeOnlineStatus('已下架'), '下架');
      expect(normalizeOnlineStatus('1'), '连载');
      expect(normalizeOnlineStatus('0'), '完结');
      expect(normalizeOnlineStatus('', lastChapter: '全书完'), '完结');
      expect(normalizeOnlineStatus('未知'), '');
    });

    test('章节标题与正文清理', () {
      expect(cleanOnlineChapterTitle('第 12 章（三更）'), '第 12 章');
      expect(cleanOnlineChapterContent('<p>正文（本章完）</p>'), '<p>正文 </p>');
      expect(
        normalizeOnlineIntro('&nbsp;&nbsp;书名 &amp; 作者\n\n\n简介&lrm;'),
        '书名 & 作者\n\n简介',
      );
    });

    test('正文失败原因识别', () {
      expect(chapterContentFailureReason(''), '章节正文为空');
      expect(chapterContentFailureReason('本章正在后台下载中'), '检测到下载占位正文');
      expect(
        chapterContentFailureReason('{"code":500,"msg":"站点繁忙"}'),
        contains('站点繁忙'),
      );
      expect(
        chapterContentFailureReason('{"code":0,"data":{"content":"正文"}}'),
        isNull,
      );
      expect(
        chapterContentFailureReason('<img src="https://example.com/a.jpg">'),
        isNull,
      );
    });

    test('base64 图片与 URL 请求参数解析', () {
      final png = Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 1, 2]);
      final dataUrl = 'data:image/png;base64,${base64Encode(png)}';
      expect(decodeDataUrlImage(dataUrl), png);
      expect(decodeDataUrlImage('data:text/plain;base64,AAAA'), isNull);
      expect(decodeDataUrlImage('data:image/png;base64,%%%'), isNull);

      final request = splitBookSourceUrlOptions(
        'https://example.com/book/1, {"headers":{"X-Test":"1"}}',
      );
      expect(request.url, 'https://example.com/book/1');
      expect(
        (request.options['headers'] as Map<String, Object?>)['X-Test'],
        '1',
      );
    });
  });
}
