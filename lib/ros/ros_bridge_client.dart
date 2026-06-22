// 이 파일은 rosbridge WebSocket 연결, topic 구독, std_msgs/String JSON publish를 담당합니다.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

enum RosConnectionState {
  disconnected,
  connecting,
  connected,
  failed,
}

typedef RosTopicHandler = void Function(Map<String, Object?> message);
typedef RosStateHandler = void Function(RosConnectionState state, String detail);

class RosBridgeClient {
  RosBridgeClient({required this.onState});

  final RosStateHandler onState;
  final Map<String, RosTopicHandler> _handlers = {};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  RosConnectionState _state = RosConnectionState.disconnected;

  RosConnectionState get state => _state;

  // 기존 channel을 확실히 닫고 새 WebSocket 연결을 하나만 생성합니다.
  Future<void> connect(String url) async {
    await close();
    _setState(RosConnectionState.connecting, 'ROS 연결 시도: $url');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _subscription = _channel!.stream.listen(
        _handleRawMessage,
        onDone: () => _setState(RosConnectionState.disconnected, 'ROS 연결 종료'),
        onError: (Object error) =>
            _setState(RosConnectionState.failed, 'ROS 연결 오류: $error'),
      );
      _setState(RosConnectionState.connected, 'ROS 연결 완료');
    } catch (error) {
      _setState(RosConnectionState.failed, 'ROS 연결 실패: $error');
      await close();
    }
  }

  // 화면이나 앱이 연결을 해제할 때 subscription과 channel을 함께 정리합니다.
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (_state != RosConnectionState.disconnected) {
      _setState(RosConnectionState.disconnected, 'ROS 연결 해제');
    }
  }

  // rosbridge subscribe 명령을 보내고 topic별 handler를 등록합니다.
  void subscribe({
    required String topic,
    required RosTopicHandler handler,
    String type = 'std_msgs/String',
  }) {
    _handlers[topic] = handler;
    _send({
      'op': 'subscribe',
      'topic': topic,
      'type': type,
    });
  }

  void unsubscribe(String topic) {
    _handlers.remove(topic);
    _send({
      'op': 'unsubscribe',
      'topic': topic,
    });
  }

  // std_msgs/String의 data 필드에 JSON 문자열을 넣어서 publish합니다.
  void publishJsonString({
    required String topic,
    required Map<String, Object?> payload,
  }) {
    _send({
      'op': 'publish',
      'topic': topic,
      'msg': {
        'data': jsonEncode(payload),
      },
    });
  }

  void _send(Map<String, Object?> command) {
    if (_channel == null) {
      return;
    }
    _channel!.sink.add(jsonEncode(command));
  }

  void _handleRawMessage(dynamic raw) {
    final decoded = jsonDecode(raw as String) as Map<String, Object?>;
    final topic = decoded['topic'] as String?;
    final msg = decoded['msg'];
    final handler = topic == null ? null : _handlers[topic];
    if (handler == null || msg is! Map<String, Object?>) {
      return;
    }

    final data = msg['data'];
    if (data is! String) {
      handler(msg);
      return;
    }

    final payload = jsonDecode(data) as Map<String, Object?>;
    handler(payload);
  }

  void _setState(RosConnectionState next, String detail) {
    if (_state == next && detail.isEmpty) {
      return;
    }
    _state = next;
    onState(next, detail);
  }
}
