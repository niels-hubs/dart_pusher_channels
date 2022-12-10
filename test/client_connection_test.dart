import 'dart:async';
import 'dart:convert';
import 'package:dart_pusher_channels/src/client/client.dart';
import 'package:dart_pusher_channels/src/client/controller.dart';
import 'package:dart_pusher_channels/src/connection/connection.dart';
import 'package:dart_pusher_channels/src/utils/event_names.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

class TestConnection implements PusherChannelsConnection {
  bool _isClosed = false;
  StreamController<String>? _messageStreamController;
  StreamSubscription? _streamSubscription;

  TestConnection();

  @visibleForTesting
  void fireConnectionEstablished() {
    _messageStreamController?.add(
      jsonEncode({
        'event': PusherChannelsEventNames.connectionEstablished,
        'data': jsonEncode({
          'socket_id': '123',
        })
      }),
    );
  }

  @visibleForTesting
  void fireException() {
    _messageStreamController?.addError(
      Exception('Some exception'),
    );
  }

  @override
  Future<void> close() async {
    if (_isClosed) {
      throw Exception('closed');
    }
    _isClosed = true;
    await _streamSubscription?.cancel();
    await _messageStreamController?.close();
  }

  @override
  void connect({
    required PusherChannelsConnectionOnDoneCallback onDoneCallback,
    required PusherChannelsConnectionOnErrorCallback onErrorCallback,
    required PusherChannelsConnectionOnEventCallback onEventCallback,
  }) {
    if (_isClosed) {
      throw Exception('closed');
    }
    _streamSubscription =
        (_messageStreamController ??= StreamController()).stream.listen(
              (event) => _onEvent(
                event,
                onEventCallback,
              ),
              onDone: () => _onDone(onDoneCallback),
              onError: (error, trace) => _onError(
                exception: error,
                trace: trace,
                callback: onErrorCallback,
              ),
            );
  }

  @override
  void sendEvent(String eventEncoded) {}

  void _onEvent(
    String event,
    PusherChannelsConnectionOnEventCallback callback,
  ) {
    if (_isClosed) {
      return;
    }
    callback(event);
  }

  void _onDone(PusherChannelsConnectionOnDoneCallback callback) {
    if (_isClosed) {
      return;
    }
    callback();
  }

  void _onError({
    required dynamic exception,
    required StackTrace trace,
    required PusherChannelsConnectionOnErrorCallback callback,
  }) {
    if (_isClosed) {
      return;
    }
    callback(
      exception,
      trace,
    );
  }
}

void main() {
  group(
    'TestConnection methods |',
    () {
      test(
        'Throws an error if using after closing',
        () {
          final connection = TestConnection();
          connection.close();
          expect(connection.close(), throwsException);
          dynamic exception;
          try {
            connection.connect(
              onDoneCallback: () {},
              onErrorCallback: (error, trace) {},
              onEventCallback: (event) {},
            );
          } catch (ex) {
            exception = ex;
          }

          expect(exception is Exception, true);
        },
      );
    },
  );
  group('Testing pusher channels lifecycle |', () {
    test('Connection is pending until connection is established', () async {
      final testConnection = TestConnection();
      final client = PusherChannelsClient.custom(
        connectionDelegate: () => testConnection,
        connectionErrorHandler: (exception, trace, refresh) {},
      );
      final stream = client.lifecycleStream;
      final stopWatch = Stopwatch()..start();
      unawaited(
        expectLater(
          stream,
          emitsInOrder(
            [
              PusherChannelsClientLifeCycleState.pendingConnection,
              PusherChannelsClientLifeCycleState.disposed,
              emitsDone,
            ],
          ),
        ),
      );
      unawaited(
        client.connect().then((_) => stopWatch.stop()),
      );
      await Future.delayed(
        const Duration(seconds: 3),
      );
      client.dispose();

      expect(
        stopWatch.elapsed.inSeconds,
        3,
      );
    });
    test(
      'If PusherChannelsConnectionEstablishedEvent fires - connection is established',
      () async {
        TestConnection? currentTestConnection;
        final client = PusherChannelsClient.custom(
          connectionDelegate: () {
            return currentTestConnection = TestConnection();
          },
          connectionErrorHandler: (exception, trace, refresh) {},
        );
        final stream = client.lifecycleStream;
        unawaited(
          expectLater(
            stream,
            emitsInOrder(
              [
                PusherChannelsClientLifeCycleState.pendingConnection,
                PusherChannelsClientLifeCycleState.establishedConnection,
                PusherChannelsClientLifeCycleState.disposed,
                emitsDone,
              ],
            ),
          ),
        );

        final future = client.connect().then((value) => client.dispose());
        await Future(() => currentTestConnection?.fireConnectionEstablished());
        await future;
      },
    );
  });
}
