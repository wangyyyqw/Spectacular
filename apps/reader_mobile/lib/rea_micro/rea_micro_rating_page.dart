import 'package:reader_ui/rating/reader_rating.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_switch.dart';

import 'rea_micro_controller.dart';
import 'rea_micro_models.dart';

/// 阅微评分、书评与读完里程碑。
class ReaMicroRatingPage extends StatefulWidget {
  /// 创建页面。
  const ReaMicroRatingPage({super.key, required this.controller});

  /// 阅微状态控制器。
  final ReaMicroController controller;

  @override
  State<ReaMicroRatingPage> createState() => _ReaMicroRatingPageState();
}

class _ReaMicroRatingPageState extends State<ReaMicroRatingPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.pageRefresh.addListener(_refresh);
    unawaited(widget.controller.initialize());
    unawaited(widget.controller.refreshMilestones());
  }

  @override
  void dispose() {
    widget.controller.pageRefresh.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    await widget.controller.refreshMilestones();
  }

  Future<void> _deleteMilestone(ReaMicroMilestone milestone) async {
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: const Text('删除读完里程碑？'),
        content: Text('将删除《${milestone.name}》的阅微评分、书评与里程碑记录。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await widget.controller.deleteMilestone(milestone.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _editReview(ReaMicroBookLink link) async {
    final message = await showReaderDialog<String>(
      context: context,
      builder: (context) =>
          _ReviewEditorDialog(controller: widget.controller, link: link),
    );
    if (!mounted || message == null || message.trim().isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final links = controller.links.values.toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));
        return Scaffold(
          appBar: AppBar(
            title: const Text('书评与里程碑'),
            actions: <Widget>[
              IconButton(
                tooltip: '刷新里程碑',
                onPressed: controller.loadingMilestones ? null : _refresh,
                icon: controller.loadingMilestones
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              if (controller.milestonesError != null)
                _Banner(
                  text: controller.milestonesError!,
                  color: Theme.of(context).colorScheme.error,
                ),
              _SectionTitle(
                title: '读完里程碑',
                detail: '${controller.milestones.length} 条',
              ),
              if (controller.loadingMilestones && controller.milestones.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.milestones.isEmpty)
                const _EmptyHint('还没有读完里程碑。标记读完后会同步到阅微。')
              else
                for (final milestone in controller.milestones)
                  _MilestoneCard(
                    milestone: milestone,
                    onDelete: () => _deleteMilestone(milestone),
                  ),
              const SizedBox(height: 24),
              _SectionTitle(title: '为已关联书籍写书评', detail: '${links.length} 本'),
              if (links.isEmpty)
                const _EmptyHint('先在阅微同步页关联本地书籍，再写评分与书评。')
              else
                Card(
                  child: Column(
                    children: <Widget>[
                      for (var index = 0; index < links.length; index++) ...[
                        if (index > 0) const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.rate_review_outlined),
                          title: Text(links[index].name),
                          subtitle: Text(
                            links[index].author.trim().isEmpty
                                ? '阅微书籍 #${links[index].cloudBookId}'
                                : links[index].author,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _editReview(links[index]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReviewEditorDialog extends StatefulWidget {
  const _ReviewEditorDialog({required this.controller, required this.link});

  final ReaMicroController controller;
  final ReaMicroBookLink link;

  @override
  State<_ReviewEditorDialog> createState() => _ReviewEditorDialogState();
}

class _ReviewEditorDialogState extends State<_ReviewEditorDialog> {
  final _comment = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _publish = true;
  int _rating = 0;
  String? _error;
  String? _interactionError;
  bool _loadingInteractions = true;
  bool _liking = false;
  bool _liked = false;
  int _likeCount = 0;
  int _actorTotal = 0;
  List<ReaMicroReviewActor> _actors = const <ReaMicroReviewActor>[];
  List<ReaMicroBookReview> _flow = const <ReaMicroBookReview>[];
  ReaMicroBookReview? _review;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final review = await widget.controller.loadBookReview(
      widget.link.cloudBookId,
    );
    if (!mounted) return;
    setState(() {
      _review = review;
      _rating = review?.rating.clamp(0, 10) ?? 0;
      _comment.text = review?.comment ?? '';
      _publish = review == null || !review.statusKnown || review.published;
      _likeCount = review?.likeCount ?? 0;
      _loading = false;
    });
    await _loadInteractions(review);
  }

  Future<void> _loadInteractions(ReaMicroBookReview? review) async {
    if (!mounted) return;
    setState(() {
      _loadingInteractions = true;
      _interactionError = null;
    });
    var flow = const <ReaMicroBookReview>[];
    var actors = const <ReaMicroReviewActor>[];
    var actorTotal = 0;
    var liked = false;
    String? failure;
    try {
      flow = await widget.controller.loadReviewFlow(
        cloudBookId: widget.link.cloudBookId,
      );
    } catch (error) {
      failure = error.toString();
    }
    if (review != null && review.id > 0) {
      try {
        final state = await widget.controller.loadReviewAction(review.id);
        liked = state.liked;
      } catch (error) {
        failure ??= error.toString();
      }
      try {
        final page = await widget.controller.loadReviewActors(review.id);
        actors = page.items;
        actorTotal = page.total;
      } catch (error) {
        failure ??= error.toString();
      }
    }
    if (!mounted) return;
    setState(() {
      _flow = flow;
      _actors = actors;
      _actorTotal = actorTotal;
      _liked = liked;
      _interactionError = failure;
      _loadingInteractions = false;
    });
  }

  Future<void> _toggleLike() async {
    final review = _review;
    if (_liking || review == null || review.id <= 0) return;
    setState(() {
      _liking = true;
      _interactionError = null;
    });
    final next = !_liked;
    final result = await widget.controller.setReviewLiked(review.id, next);
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _liking = false;
        _interactionError = result.message;
      });
      return;
    }
    setState(() {
      _liked = next;
      _likeCount = (_likeCount + (next ? 1 : -1)).clamp(0, 1 << 31).toInt();
    });
    await _loadInteractions(review);
    if (!mounted) return;
    setState(() => _liking = false);
  }

  Future<void> _save() async {
    if (_rating <= 0) {
      setState(() => _error = '请选择 1～10 分评分');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.controller.saveReview(
      cloudBookId: widget.link.cloudBookId,
      rating: _rating,
      comment: _comment.text,
      publish: _publish,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _saving = false;
        _error = result.message;
      });
      return;
    }
    Navigator.of(context).pop(result.message);
  }

  @override
  Widget build(BuildContext context) {
    return ReaderFrostedAlertDialog(
      title: Text('评价《${widget.link.name}》'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('评分'),
                    const SizedBox(height: 4),
                    ReaderRatingPicker(
                      rating: _rating == 0 ? null : _rating / 2,
                      keyPrefix: 'reamicro-rating',
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _rating = ((value ?? 0) * 2).round(),
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _rating <= 0 ? '尚未评分' : '已选 ${_rating / 2} 星（满分 5 星）',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey<String>('reamicro-review-comment'),
                      controller: _comment,
                      enabled: !_saving,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: 5000,
                      decoration: const InputDecoration(
                        labelText: '书评',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    ReaderSwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('公开发布'),
                      subtitle: const Text('关闭后仅保存到阅微，不进入公开书评流'),
                      value: _publish,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _publish = value),
                    ),
                    const Divider(height: 24),
                    Row(
                      children: <Widget>[
                        IconButton(
                          key: const ValueKey<String>('reamicro-review-like'),
                          tooltip: _liked ? '取消点赞' : '点赞',
                          onPressed:
                              _liking || _review == null || _review!.id <= 0
                              ? null
                              : () => unawaited(_toggleLike()),
                          icon: Icon(
                            _liked ? Icons.favorite : Icons.favorite_border,
                            color: _liked ? Colors.redAccent : null,
                          ),
                        ),
                        Text('$_likeCount 人点赞'),
                        if (_actorTotal > 0) ...<Widget>[
                          const SizedBox(width: 10),
                          Text('· $_actorTotal 人互动'),
                        ],
                        const Spacer(),
                        if (_loadingInteractions)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    if (_actors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '互动用户：${_actors.take(8).map((item) => item.userName).where((name) => name.isNotEmpty).join('、')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (_interactionError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _interactionError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      '本书书评动态',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    if (_flow.isEmpty)
                      Text(
                        _loadingInteractions ? '正在读取书评动态…' : '还没有公开书评',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      for (final item in _flow.take(5))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      item.userName.isEmpty
                                          ? '阅微读者'
                                          : item.userName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    '${item.rating / 2}/5',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                              if (item.comment.trim().isNotEmpty)
                                Text(
                                  item.comment,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading || _saving ? null : _save,
          child: Text(_saving ? '正在提交…' : '保存到阅微'),
        ),
      ],
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({required this.milestone, required this.onDelete});

  final ReaMicroMilestone milestone;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey<String>('reamicro-milestone-${milestone.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        milestone.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (milestone.author.trim().isNotEmpty)
                        Text(
                          milestone.author,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '删除里程碑',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                ReaderRatingStars(rating: milestone.rating / 2, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${milestone.rating / 2}/5',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTimestamp(milestone.ratingTime),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (milestone.comment.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                milestone.comment,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                _Metric(
                  label: '累计阅读',
                  value: _formatDuration(milestone.totalReadTimeSeconds),
                ),
                _Metric(label: '阅读天数', value: '${milestone.readDays} 天'),
                if (milestone.listeningDurationSeconds > 0)
                  _Metric(
                    label: '听书',
                    value: _formatDuration(milestone.listeningDurationSeconds),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: ReaderUiStyle.chipRadiusOf(Theme.of(context)),
      ),
      child: Text(
        '$label $value',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}

String _formatDuration(int seconds) {
  if (seconds <= 0) return '0 分钟';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return minutes <= 0 ? '<1 分钟' : '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
}

String _formatTimestamp(int milliseconds) {
  if (milliseconds <= 0) return '';
  final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
