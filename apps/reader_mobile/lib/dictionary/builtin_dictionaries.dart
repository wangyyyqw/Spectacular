/// 应用提供的本地词典下载信息；原文件与校验值固定配对。
class BuiltInDictionary {
  const BuiltInDictionary({
    required this.id,
    required this.name,
    required this.url,
    required this.size,
    required this.digest,
  });

  final String id, name, url, digest;
  final int size;
}

const builtInDictionaries = [
  BuiltInDictionary(
    id: 'new-century',
    name: '新世纪汉英大词典',
    url: 'https://streamshare.wireway.ch/download/inwa4gij',
    size: 56303376,
    digest: '33506d5773b556848fef41e615598892dd738efd8a40db15df7622b6a5ca9ca3',
  ),
  BuiltInDictionary(
    id: 'dacihai',
    name: '大辞海',
    url: 'https://streamshare.wireway.ch/download/wix31o55',
    size: 133349531,
    digest: '44bff9f0e0a5d977cbb6c1eecd04e89430f5ba40b27b8e89d211ca7c461d5590',
  ),
];
