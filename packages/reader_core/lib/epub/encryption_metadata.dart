import 'archive_reader.dart';
import 'epub_exception.dart';
import 'font_obfuscation.dart';
import 'resource_index.dart';

/// EPUB 容器的加密声明。字体混淆是可读资源，不按 DRM 拒绝。
class EpubEncryptionMetadata {
  const EpubEncryptionMetadata(this.fonts, {this.drm});

  final FontEncryptionMap fonts;
  final String? drm;

  static EpubEncryptionMetadata read(EpubArchive archive) {
    final hasDeclaration = archive.contains('META-INF/encryption.xml');
    final xml = archive.readString('META-INF/encryption.xml');
    final fonts = xml == null
        ? hasDeclaration
              ? const FontEncryptionMap.invalid()
              : const FontEncryptionMap.empty()
        : FontEncryptionMap.parse(xml);
    final resources = ResourceIndex.build(
      archive: archive,
      manifest: const [],
      opfPath: 'package.opf',
    );
    final encryptedExists = fonts.encryptedResources.any(
      (uri) => uri == '未注明资源路径' || resources.resolve(uri, baseDir: '') != null,
    );
    final drm = archive.contains('META-INF/sinf.xml')
        ? 'Apple FairPlay'
        : archive.contains('META-INF/license.lcpl')
        ? 'Readium LCP'
        : encryptedExists
        ? '资源加密'
        : null;
    return EpubEncryptionMetadata(fonts, drm: drm);
  }

  /// 在 OPF、目录和章节解析之前拒绝不支持的加密，避免报成格式损坏。
  void requireReadable() {
    if (drm == null) return;
    throw EpubException('E_EPUB_ENCRYPTED', '检测到 $drm，当前不支持解密，请使用支持该加密方式的阅读器');
  }
}
