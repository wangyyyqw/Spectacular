import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'class_style_editor.dart';
import 'editable_document.dart';
import 'epub_edit_session.dart';

/// 全书查找在后台执行；结果只适用于发起时的编辑版本。
Future<ClassStyleReport> inspectClassStyleAsync(
  EpubEditSession session,
  String name, {
  Map<String, String> proposed = const {},
  double viewportWidth = 360,
  bool Function()? isCancelled,
}) => _dispatch(session, name, proposed, (
  apply: false,
  unify: false,
  viewportWidth: viewportWidth,
), isCancelled: isCancelled);

/// 后台完成校验后，主线程一次发布资源与归属元数据，保留一步撤销语义。
/// 参数沿用同步命令并增加生命周期回调；取消丢弃结果，不中断后台文件读取。
Future<ClassStyleReport> applyClassStyleAsync(
  EpubEditSession session,
  String name,
  Map<String, String> values, {
  bool unifyConflicts = false,
  double viewportWidth = 360,
  bool Function()? isCancelled,
}) => _dispatch(session, name, values, (
  apply: true,
  unify: unifyConflicts,
  viewportWidth: viewportWidth,
), isCancelled: isCancelled);

typedef _ClassStyleRequest = ({
  String source,
  Map<String, dynamic> draft,
  Map<String, Uint8List> blobs,
  String name,
  Map<String, String> values,
  bool apply,
  bool unify,
  double viewportWidth,
});
typedef _ClassStyleResult = ({
  ClassStyleReport report,
  Map<String, Uint8List?> changes,
  Map<String, dynamic> metadata,
});

Future<ClassStyleReport> _dispatch(
  EpubEditSession session,
  String name,
  Map<String, String> values,
  ({bool apply, bool unify, double viewportWidth}) operation, {
  bool Function()? isCancelled,
}) async {
  final expected = session.revision;
  _checkCurrent(session, expected, isCancelled);
  final request = _snapshot(session, name, values, operation);
  final result = await _runIsolated(request);
  _checkCurrent(session, expected, isCancelled);
  if (operation.apply) {
    session.transaction('修改全书 .$name 样式', (tx) {
      for (final entry in result.changes.entries) {
        final bytes = entry.value;
        if (bytes == null) {
          tx.remove(entry.key);
        } else {
          tx.writeBytes(entry.key, bytes);
        }
      }
      tx.metadata
        ..clear()
        ..addAll(result.metadata);
    }, validate: false); // 同一快照已在 worker 严格校验，避免主线程再扫描 XML。
  }
  return result.report;
}

void _checkCurrent(
  EpubEditSession session,
  int expected,
  bool Function()? cancelled,
) {
  if (session.isClosed || cancelled?.call() == true) {
    throw const EpubEditException('样式任务已取消，未发布结果');
  }
  if (session.revision != expected) {
    throw const EpubEditException('编辑内容已变化，请重新检查或应用样式');
  }
}

_ClassStyleRequest _snapshot(
  EpubEditSession session,
  String name,
  Map<String, String> values,
  ({bool apply, bool unify, double viewportWidth}) operation,
) {
  final blobs = <String, Uint8List>{};
  final draft = session.toDraft(
    storeBlob: (path, bytes) {
      blobs[path] = bytes;
      return path;
    },
  );
  return (
    source: session.baseFile.path,
    draft: draft,
    blobs: blobs,
    name: name,
    values: Map.of(values),
    apply: operation.apply,
    unify: operation.unify,
    viewportWidth: operation.viewportWidth,
  );
}

// 独立函数只捕获纯数据请求，不把主线程会话、归档或取消回调送进 isolate。
Future<_ClassStyleResult> _runIsolated(_ClassStyleRequest request) =>
    Isolate.run(() => _compute(request));

Future<_ClassStyleResult> _compute(_ClassStyleRequest request) async {
  final session = await EpubEditSession.open(
    File(request.source),
    draft: request.draft,
    readBlob: (reference) => request.blobs[reference]!,
  );
  final changed = <String>{};
  final listener = session.changes.listen(
    (event) => changed.addAll(event.changedPaths),
  );
  try {
    final editor = ClassStyleEditor(session);
    final report = request.apply
        ? editor.apply(
            request.name,
            request.values,
            unifyConflicts: request.unify,
            viewportWidth: request.viewportWidth,
          )
        : editor.inspect(
            request.name,
            proposed: request.values,
            viewportWidth: request.viewportWidth,
          );
    return (
      report: report,
      changes: {for (final path in changed) path: session.readBytes(path)},
      metadata: request.apply ? session.metadata : const <String, dynamic>{},
    );
  } finally {
    await listener.cancel();
    session.close();
  }
}
