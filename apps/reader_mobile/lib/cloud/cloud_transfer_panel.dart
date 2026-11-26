import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'cloud_import_controller.dart';

/// 目录页保留当前进度，完整任务列表按需展开。
class CloudTransferPanel extends StatelessWidget {
  const CloudTransferPanel({
    super.key,
    required this.controller,
    required this.onRetry,
    required this.onRelogin,
  });

  final CloudImportController controller;
  final ValueChanged<CloudImportItem> onRetry;
  final VoidCallback onRelogin;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final items = controller.items;
      if (items.isEmpty) return const SizedBox.shrink();
      final active = items
          .where(
            (item) => {
              CloudImportStatus.downloading,
              CloudImportStatus.importing,
            }.contains(item.status),
          )
          .firstOrNull;
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          onTap: () => _showTasks(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summary(context, active),
                if (active != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: active.progress,
                    semanticsLabel: '${active.file.name}，${active.label}',
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _summary(BuildContext context, CloudImportItem? active) => Row(
    children: [
      AppIcon(controller.busy ? AppGlyph.save : AppGlyph.checklist),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              active?.file.name ?? '下载与导入',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              active == null ? _summaryText : '${active.label} · $_summaryText',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      const Text('查看任务'),
      const SizedBox(width: 4),
      const AppIcon(AppGlyph.chevronRight, size: 18),
    ],
  );

  String get _summaryText {
    final completed = controller.items
        .where((item) => item.status == CloudImportStatus.completed)
        .length;
    final failed = controller.items
        .where((item) => item.status == CloudImportStatus.failed)
        .length;
    final cancelled = controller.items
        .where((item) => item.status == CloudImportStatus.cancelled)
        .length;
    return [
      '已导入 $completed / ${controller.items.length}',
      if (failed > 0) '失败 $failed',
      if (cancelled > 0) '已取消 $cancelled',
    ].join(' · ');
  }

  void _showTasks(BuildContext context) => showReaderDrawer<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: .72,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          children: [
            _sheetHeader(context),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: controller.items.length,
                separatorBuilder: (_, _) =>
                    const Divider(indent: 16, endIndent: 16),
                itemBuilder: (context, index) =>
                    _task(context, controller.items[index]),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  '下载完成后自动加入书架。请保持应用运行。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _sheetHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('下载与导入', style: Theme.of(context).textTheme.titleLarge),
              Text(_summaryText, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (controller.busy)
          TextButton(onPressed: controller.cancel, child: const Text('取消剩余')),
        IconButton(
          tooltip: '关闭任务列表',
          onPressed: () => Navigator.pop(context),
          icon: const AppIcon(AppGlyph.close),
        ),
      ],
    ),
  );

  Widget _task(BuildContext context, CloudImportItem item) {
    final active = {
      CloudImportStatus.downloading,
      CloudImportStatus.importing,
    }.contains(item.status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.file.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: item.status == CloudImportStatus.failed
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              _taskAction(context, item),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: item.progress,
              semanticsLabel: item.label,
            ),
            if (item.status == CloudImportStatus.downloading) ...[
              const SizedBox(height: 4),
              Text(
                '${cloudFileSize(item.received)}${item.total > 0 ? ' / ${cloudFileSize(item.total)}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _taskAction(BuildContext context, CloudImportItem item) {
    if (item.status == CloudImportStatus.completed) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: AppIcon(AppGlyph.checkCircle),
      );
    }
    if (!{
      CloudImportStatus.failed,
      CloudImportStatus.cancelled,
    }.contains(item.status)) {
      return const SizedBox.shrink();
    }
    return TextButton(
      onPressed: controller.busy
          ? null
          : () {
              Navigator.pop(context);
              if (item.loginRequired) {
                onRelogin();
              } else {
                onRetry(item);
              }
            },
      child: Text(
        item.loginRequired
            ? '重新登录'
            : item.job?.encodingCandidates.isNotEmpty == true
            ? '选择编码'
            : '重试',
      ),
    );
  }
}

String cloudFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}
