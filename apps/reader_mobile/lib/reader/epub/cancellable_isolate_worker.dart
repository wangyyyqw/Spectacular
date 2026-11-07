import 'dart:async';
import 'dart:isolate';

import 'package:reader_ui/reader_session.dart';

import 'chapter_preparation_job.dart';

/// 同书纯数据准备共用一个 isolate 槽位，退出后才启动下一项。
class CancellableIsolateWorker {
  final _scheduler = ChapterPreparationScheduler();
  final _activity = _WorkerActivity();

  /// 包含正在启动的 isolate，取消结算后仍等待实际退出。
  int get activeIsolates => _activity.active;
  int get openPortCount => _activity.ports;
  Future<void> get idle => _scheduler.idle;

  /// [input] 在取得槽位后读取；仅 [compute] 和纯数据输入跨 isolate。
  ChapterPreparationHandle<T> schedule<I, T>(
    String key,
    I Function() input,
    T Function(I) compute, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) => _scheduler.schedule<T>(key, (task) async {
    task.check();
    final data = input();
    task.check();
    return _IsolateInvocation(task, data, compute, _activity).run();
  }, priority: priority);

  Future<void> close() {
    _scheduler.close();
    return idle;
  }
}

class _WorkerActivity {
  int active = 0;
  int ports = 0;
}

class _IsolateInvocation<I, T> {
  _IsolateInvocation(this.task, this.input, this.compute, this.activity) {
    unawaited(
      _result.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  final PreparationTask task;
  final I input;
  final T Function(I) compute;
  final _WorkerActivity activity;
  final _result = Completer<T>();
  final _exited = Completer<void>();
  late final ReceivePort _events;
  late final StreamSubscription<dynamic> _subscription;
  Isolate? _isolate;
  bool _acceptCancellation = true;
  bool _starting = false;

  Future<T> run() async {
    task.check();
    _events = ReceivePort();
    activity.ports += 1;
    _subscription = _events.listen(_receive);
    unawaited(task.cancelSignal.then((_) => _cancel()));
    try {
      task.check();
      activity.active += 1;
      _starting = true;
      _isolate = await Isolate.spawn(
        _runPreparation<I, T>,
        _IsolateRequest(input, compute, _events.sendPort),
        onExit: _events.sendPort,
        onError: _events.sendPort,
        errorsAreFatal: true,
      );
      if (!task.isActive) _cancel();
      return await _result.future;
    } finally {
      await _dispose();
    }
  }

  void _receive(dynamic message) {
    if (message == null) {
      if (!_exited.isCompleted) _exited.complete();
      if (!_result.isCompleted) {
        _result.completeError(
          task.isActive
              ? StateError('准备 isolate 未返回结果')
              : const ChapterLoadCancelled(),
          StackTrace.current,
        );
      }
      return;
    }
    if (_result.isCompleted || message is! List) return;
    if (message.length == 2 && message[0] == true) {
      _result.complete(message[1] as T);
    } else if (message.length == 3 && message[0] == false) {
      _result.completeError(
        message[1] as Object,
        StackTrace.fromString(message[2] as String),
      );
    } else if (message.length == 2) {
      _result.completeError(RemoteError('${message[0]}', '${message[1]}'));
    }
  }

  void _cancel() {
    if (!_acceptCancellation) return;
    if (!_result.isCompleted) {
      _result.completeError(const ChapterLoadCancelled(), StackTrace.current);
    }
    _isolate?.kill(priority: Isolate.immediate);
  }

  Future<void> _dispose() async {
    if (_isolate != null) {
      if (!_exited.isCompleted) _isolate!.kill(priority: Isolate.immediate);
      await _exited.future;
    }
    _acceptCancellation = false;
    _isolate = null;
    await _subscription.cancel();
    _events.close();
    activity.ports -= 1;
    if (_starting) activity.active -= 1;
  }
}

class _IsolateRequest<I, T> {
  const _IsolateRequest(this.input, this.compute, this.reply);
  final I input;
  final T Function(I) compute;
  final SendPort reply;
}

void _runPreparation<I, T>(_IsolateRequest<I, T> request) {
  try {
    final value = request.compute(request.input);
    Isolate.exit(request.reply, [true, value]);
  } catch (error, stack) {
    Isolate.exit(request.reply, [false, error, stack.toString()]);
  }
}
