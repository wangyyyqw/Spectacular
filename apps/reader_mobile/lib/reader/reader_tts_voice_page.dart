import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';

import 'reader_tts_voice_store.dart';

/// 离线音色管理：下载、查看进度和删除已安装音色。
class ReaderTtsVoiceLibraryPage extends StatefulWidget {
  /// 创建页面。
  const ReaderTtsVoiceLibraryPage({
    super.key,
    required this.store,
    required this.voices,
  });

  /// 本地音色仓库。
  final ReaderTtsVoiceStore store;

  /// 可下载与已安装音色。
  final List<ReaderOfflineVoice> voices;

  @override
  State<ReaderTtsVoiceLibraryPage> createState() =>
      _ReaderTtsVoiceLibraryPageState();
}

class _ReaderTtsVoiceLibraryPageState extends State<ReaderTtsVoiceLibraryPage> {
  late List<ReaderOfflineVoice> _voices = widget.voices;
  String? _busyId;
  double _progress = 0;

  Future<void> _download(ReaderOfflineVoice voice) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = voice.id;
      _progress = 0;
    });
    try {
      final installed = await widget.store.download(
        voice,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _voices = <ReaderOfflineVoice>[
          for (final item in _voices)
            if (item.id == installed.id) installed else item,
        ];
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已下载 ${installed.displayName}')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyId = null;
          _progress = 0;
        });
      }
    }
  }

  Future<void> _delete(ReaderOfflineVoice voice) async {
    if (_busyId != null) return;
    setState(() => _busyId = voice.id);
    try {
      await widget.store.delete(voice.id);
      if (!mounted) return;
      setState(() {
        _voices = <ReaderOfflineVoice>[
          for (final item in _voices)
            if (item.id == voice.id)
              item.copyWith(installed: false, localPath: '')
            else
              item,
        ];
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('离线音色')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              if (_voices.isEmpty)
                const ReaderEmptyState(
                  icon: AppGlyph.voice,
                  title: '暂无可用离线音色',
                  subtitle: '当前没有可下载的离线语音包，可稍后再试。',
                )
              else
                ReaderSectionCard(
                  children: <Widget>[
                    for (final voice in _voices) _voiceTile(context, voice),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _voiceTile(BuildContext context, ReaderOfflineVoice voice) {
    final busy = _busyId == voice.id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      title: Text(voice.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (voice.detail.isNotEmpty) Text(voice.detail),
          if (busy && _progress > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(value: _progress.clamp(0, 1)),
            ),
        ],
      ),
      trailing: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : voice.installed
          ? IconButton(
              tooltip: '删除',
              onPressed: () => _delete(voice),
              icon: const AppIcon(AppGlyph.delete),
            )
          : FilledButton(
              onPressed: voice.downloadUrl.trim().isEmpty
                  ? null
                  : () => _download(voice),
              child: const Text('下载'),
            ),
    );
  }
}
