import 'dart:async';
import 'dart:isolate';

import 'txt_models.dart';

typedef TxtWorkerRequest = ({Object input, SendPort output});

/// 可中断同步正则的独立任务；超时检查在调用 isolate 中执行。
Future<T> runTxtWorker<T>(
  void Function(TxtWorkerRequest) worker,
  Object input, {
  void Function(double)? onProgress,
  bool Function()? isCancelled,
}) async {
  final port = ReceivePort();
  final exitPort = ReceivePort();
  final exited = exitPort.first;
  final completed = Completer<T>();
  var lastProgress = DateTime.now();
  var watching = false;
  final subscription = port.listen((dynamic event) {
    final message = event as (String, Object?);
    lastProgress = DateTime.now();
    switch (message.$1) {
      case 'progress':
        onProgress?.call(message.$2 as double);
      case 'watch':
        watching = message.$2 as bool;
      case 'result':
        if (!completed.isCompleted) completed.complete(message.$2 as T);
      case 'error':
        if (!completed.isCompleted) completed.completeError(message.$2!);
    }
  });
  final isolate = await Isolate.spawn(worker, (
    input: input,
    output: port.sendPort,
  ), onExit: exitPort.sendPort);
  final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
    if (completed.isCompleted) return;
    if (isCancelled?.call() == true) {
      completed.completeError(
        const TxtConversionException('E_CANCELLED', '已取消'),
      );
    } else if (watching &&
        DateTime.now().difference(lastProgress).inSeconds >= 2) {
      completed.completeError(
        const TxtConversionException(
          'E_TXT_REGEX_TIMEOUT',
          '章节正则处理超时，请简化表达式后重试',
        ),
      );
    }
  });
  try {
    return await completed.future;
  } finally {
    timer.cancel();
    isolate.kill(priority: Isolate.immediate);
    await exited;
    exitPort.close();
    await subscription.cancel();
    port.close();
  }
}
