// 이 파일은 ROS2 연결, 지도/장소/로봇 상태, 알림 로그를 앱 전체 상태로 관리합니다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/app_settings.dart';
import '../core/log_filter.dart';
import '../models/location_point.dart';
import '../models/robot_status.dart';
import '../models/supervisor_log.dart';
import '../models/vica_map.dart';
import '../ros/ros_bridge_client.dart';

enum EmergencyStopState {
  inactive,
  activating,
  active,
  releasing,
  activationFailed,
  releaseFailed,
}

class SupervisorProvider extends ChangeNotifier {
  SupervisorProvider();

  final _uuid = const Uuid();
  RosBridgeClient? _client;
  RosConnectionState _connectionState = RosConnectionState.disconnected;
  String _connectionDetail = '';
  List<VicaMap> _maps = const [];
  final Map<String, List<LocationPoint>> _locationsByMap = {};
  final Map<String, RobotStatus> _robotsById = {};
  final List<SupervisorLog> _logs = [];
  String? _selectedMapId;
  String? _selectedLocationId;
  LocationPoint? _draftLocation;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _emergencyStopTimeoutTimer;
  EmergencyStopState _emergencyStopState = EmergencyStopState.inactive;
  String _emergencyStopMessage = '';
  String? _pendingEmergencyRequestId;
  int _emergencyRetryGeneration = 0;

  RosConnectionState get connectionState => _connectionState;
  String get connectionDetail => _connectionDetail;
  EmergencyStopState get emergencyStopState => _emergencyStopState;
  String get emergencyStopMessage => _emergencyStopMessage;
  bool get emergencyOverlayVisible =>
      _emergencyStopState != EmergencyStopState.inactive;
  List<VicaMap> get maps => _maps;
  String? get selectedMapId => _selectedMapId;
  String? get selectedLocationId => _selectedLocationId;
  LocationPoint? get draftLocation => _draftLocation;
  List<SupervisorLog> get logs => List.unmodifiable(_logs);
  List<RobotStatus> get robots => _robotsById.values.toList(growable: false);
  RobotStatus? get primaryRobot =>
      _robotsById.isEmpty ? null : _robotsById.values.first;

  VicaMap? get selectedMap {
    for (final map in _maps) {
      if (map.mapId == _selectedMapId) {
        return map;
      }
    }
    return _maps.isEmpty ? null : _maps.first;
  }

  List<LocationPoint> locationsFor(String? mapId) {
    if (mapId == null) {
      return const [];
    }
    return List.unmodifiable(_locationsByMap[mapId] ?? const []);
  }

  // rosbridge 연결을 하나만 유지하고 필요한 topic만 구독합니다.
  Future<void> connect(AppSettings settings) async {
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    final oldClient = _client;
    _client = null;
    await oldClient?.close();
    _client = RosBridgeClient(onState: (state, detail) {
      _setConnectionState(state, detail);
      if (state == RosConnectionState.disconnected ||
          state == RosConnectionState.failed) {
        _scheduleReconnect(settings);
      }
    });
    await _client!.connect(settings.rosBridgeUrl);
    if (_connectionState == RosConnectionState.connected) {
      _subscribeRequiredTopics(settings);
      if (settings.autoRequestMapList) {
        requestMapList(settings);
      }
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    final client = _client;
    _client = null;
    await client?.close();
  }

  // 무한 재시도를 피하기 위해 설정된 횟수까지만 재연결합니다.
  void _scheduleReconnect(AppSettings settings) {
    if (_client == null ||
        _reconnectAttempts >= settings.maxReconnectAttempts) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectAttempts += 1;
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      await _client?.connect(settings.rosBridgeUrl);
      if (_connectionState == RosConnectionState.connected) {
        _subscribeRequiredTopics(settings);
        if (settings.autoRequestMapList) {
          requestMapList(settings);
        }
      }
    });
  }

  void _subscribeRequiredTopics(AppSettings settings) {
    _client
      ?..subscribe(topic: settings.mapListTopic, handler: _handleMapList)
      ..subscribe(
        topic: settings.locationListTopic,
        handler: _handleLocationList,
      )
      ..subscribe(
        topic: settings.robotStatusTopic,
        handler: _handleRobotStatus,
      )
      ..subscribe(
        topic: settings.emergencyStopStateTopic,
        handler: _handleEmergencyStopState,
      );
    _requestEmergencyStopState(settings);
  }

  void activateEmergencyStop(AppSettings settings) {
    if (_connectionState != RosConnectionState.connected) {
      _setEmergencyStopState(
        EmergencyStopState.activationFailed,
        'ROS Bridge에 연결되지 않아 비상정지를 활성화하지 못했습니다.',
      );
      _addLog(LogFilter.emergencyStop, '비상정지 요청 실패: ROS 연결 안 됨');
      return;
    }
    _sendEmergencyCommand(
      settings: settings,
      command: 'activate',
      pendingState: EmergencyStopState.activating,
      timeoutState: EmergencyStopState.activationFailed,
      pendingMessage: 'VICA에 비상정지를 요청하고 있습니다.',
      timeoutMessage: 'app_emergency_node의 비상정지 응답이 없습니다.',
    );
  }

  Future<void> retryEmergencyStop(AppSettings settings) async {
    final generation = ++_emergencyRetryGeneration;
    if (_connectionState != RosConnectionState.connected) {
      await connect(settings);
    }
    if (generation != _emergencyRetryGeneration ||
        _emergencyStopState != EmergencyStopState.activationFailed) {
      return;
    }
    activateEmergencyStop(settings);
  }

  void dismissEmergencyStopFailure() {
    if (_emergencyStopState != EmergencyStopState.activationFailed) {
      return;
    }
    _emergencyRetryGeneration += 1;
    _clearEmergencyStopPending();
    _setEmergencyStopState(EmergencyStopState.inactive, '');
    _addLog(LogFilter.emergencyStop, '비상정지 실패 알림 닫음');
  }

  void releaseEmergencyStop(AppSettings settings) {
    if (_connectionState != RosConnectionState.connected) {
      _setEmergencyStopState(
        EmergencyStopState.releaseFailed,
        'ROS Bridge에 연결되지 않아 비상정지를 해제하지 못했습니다.',
      );
      _addLog(LogFilter.emergencyStop, '비상정지 해제 실패: ROS 연결 안 됨');
      return;
    }
    _sendEmergencyCommand(
      settings: settings,
      command: 'release',
      pendingState: EmergencyStopState.releasing,
      timeoutState: EmergencyStopState.releaseFailed,
      pendingMessage: 'VICA에 비상정지 해제를 요청하고 있습니다.',
      timeoutMessage: 'app_emergency_node의 비상정지 해제 응답이 없습니다.',
    );
  }

  Future<void> retryEmergencyStopRelease(AppSettings settings) async {
    if (_connectionState != RosConnectionState.connected) {
      await connect(settings);
    }
    releaseEmergencyStop(settings);
  }

  void _sendEmergencyCommand({
    required AppSettings settings,
    required String command,
    required EmergencyStopState pendingState,
    required EmergencyStopState timeoutState,
    required String pendingMessage,
    required String timeoutMessage,
  }) {
    final requestId = _uuid.v4();
    _pendingEmergencyRequestId = requestId;
    _setEmergencyStopState(pendingState, pendingMessage);
    _client?.publishJsonString(
      topic: settings.emergencyStopRequestTopic,
      payload: {
        'request_id': requestId,
        'command': command,
        'source': 'vica_supervisor',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _addLog(
      LogFilter.emergencyStop,
      command == 'activate' ? '비상정지 요청 전송' : '비상정지 해제 요청 전송',
    );
    _emergencyStopTimeoutTimer?.cancel();
    _emergencyStopTimeoutTimer = Timer(
      Duration(seconds: settings.emergencyStopTimeoutSeconds),
      () {
        if (_pendingEmergencyRequestId != requestId) {
          return;
        }
        _pendingEmergencyRequestId = null;
        _setEmergencyStopState(timeoutState, timeoutMessage);
        _addLog(LogFilter.emergencyStop, timeoutMessage);
      },
    );
  }

  void _requestEmergencyStopState(AppSettings settings) {
    _client?.publishJsonString(
      topic: settings.emergencyStopRequestTopic,
      payload: {
        'request_id': _uuid.v4(),
        'command': 'query',
        'source': 'vica_supervisor',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  void requestMapList(AppSettings settings) {
    _client?.publishJsonString(
      topic: settings.mapListRequestTopic,
      payload: {
        'request_id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _addLog(LogFilter.connection, '지도 목록 요청 전송');
  }

  void requestLocationList(AppSettings settings, String mapId) {
    _client?.publishJsonString(
      topic: settings.locationListRequestTopic,
      payload: {
        'request_id': _uuid.v4(),
        'map_id': mapId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _addLog(LogFilter.coordinateTransfer, '$mapId 장소 목록 요청 전송');
  }

  void selectMap(AppSettings settings, String? mapId) {
    if (_selectedMapId == mapId) {
      return;
    }
    _selectedMapId = mapId;
    _selectedLocationId = null;
    notifyListeners();
    if (mapId != null && settings.autoRequestLocationList) {
      requestLocationList(settings, mapId);
    }
  }

  void selectLocation(String? locationId) {
    if (_selectedLocationId == locationId) {
      return;
    }
    _selectedLocationId = locationId;
    notifyListeners();
  }

  void setDraftLocation(LocationPoint? next) {
    if (jsonEncode(_draftLocation?.toJson()) == jsonEncode(next?.toJson())) {
      return;
    }
    _draftLocation = next;
    notifyListeners();
  }

  // 임시 저장된 좌표를 ROS2 저장 topic으로 전송합니다.
  void saveDraftLocation(AppSettings settings) {
    final draft = _draftLocation;
    if (draft == null) {
      return;
    }
    final payload = {
      'request_id': _uuid.v4(),
      ...draft.toJson(),
      'storage_root': settings.locationStorageRoot,
      'timestamp': DateTime.now().toIso8601String(),
    };
    _client?.publishJsonString(
      topic: settings.saveLocationTopic,
      payload: payload,
    );
    _addLog(LogFilter.coordinateTransfer, '${draft.name} 장소 저장 요청 전송');
    _draftLocation = null;
    notifyListeners();
  }

  // 삭제 요청도 ROS2 저장 노드가 같은 storage_root에서 처리하도록 보냅니다.
  void deleteLocation(AppSettings settings, LocationPoint location) {
    _client?.publishJsonString(
      topic: settings.deleteLocationRequestTopic,
      payload: {
        'request_id': _uuid.v4(),
        'map_id': location.mapId,
        'location_id': location.locationId,
        'storage_root': settings.locationStorageRoot,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _addLog(LogFilter.coordinateTransfer, '${location.name} 장소 삭제 요청 전송');
  }

  void clearLogs(LogFilter filter) {
    if (filter == LogFilter.all) {
      _logs.clear();
    } else {
      _logs.removeWhere((log) => log.filter == filter);
    }
    notifyListeners();
  }

  void _handleMapList(Map<String, Object?> message) {
    final rawMaps = message['maps'];
    if (rawMaps is! List) {
      return;
    }
    final nextMaps = rawMaps
        .whereType<Map<String, Object?>>()
        .map(VicaMap.fromJson)
        .where((map) => map.mapId.isNotEmpty)
        .toList(growable: false);
    if (listEquals(_maps.map((e) => jsonEncode(e.toJson())).toList(),
        nextMaps.map((e) => jsonEncode(e.toJson())).toList())) {
      return;
    }
    _maps = nextMaps;
    _selectedMapId ??= _maps.isEmpty ? null : _maps.first.mapId;
    _addLog(LogFilter.connection, '지도 목록 ${_maps.length}개 수신');
    notifyListeners();
  }

  void _handleLocationList(Map<String, Object?> message) {
    final mapId = message['map_id'] as String?;
    final rawLocations = message['locations'];
    if (mapId == null || rawLocations is! List) {
      return;
    }
    final nextLocations = rawLocations
        .whereType<Map<String, Object?>>()
        .map((json) => LocationPoint.fromJson(json, mapId))
        .where((location) => location.locationId.isNotEmpty)
        .toList(growable: false);
    final before = jsonEncode(
      (_locationsByMap[mapId] ?? const []).map((e) => e.toJson()).toList(),
    );
    final after = jsonEncode(nextLocations.map((e) => e.toJson()).toList());
    if (before == after) {
      return;
    }
    _locationsByMap[mapId] = nextLocations;
    _addLog(
        LogFilter.coordinateTransfer, '$mapId 장소 ${nextLocations.length}개 수신');
    notifyListeners();
  }

  void _handleRobotStatus(Map<String, Object?> message) {
    final next = RobotStatus.fromJson(message);
    final before = _robotsById[next.robotId];
    if (before != null &&
        jsonEncode(before.toJson()) == jsonEncode(next.toJson())) {
      return;
    }
    _robotsById[next.robotId] = next;
    if (next.hasError) {
      _addLog(
          LogFilter.emergencyStop, '${next.robotName}: ${next.errorReason}');
    }
    notifyListeners();
  }

  void _handleEmergencyStopState(Map<String, Object?> message) {
    final state = message['state'] as String? ?? '';
    final requestId = message['request_id'] as String? ?? '';
    final command = message['command'] as String? ?? '';
    final responseMessage = message['message'] as String? ?? '';
    final matchesPending =
        requestId.isNotEmpty && requestId == _pendingEmergencyRequestId;

    if (state == 'active') {
      if (_emergencyStopState == EmergencyStopState.releaseFailed &&
          command == 'status' &&
          !matchesPending) {
        return;
      }
      _clearEmergencyStopPending();
      _setEmergencyStopState(
        EmergencyStopState.active,
        responseMessage.isEmpty
            ? '비상정지가 활성화되었습니다. 기존 목적지는 취소되었습니다.'
            : responseMessage,
      );
      if (matchesPending || command == 'activate') {
        _addLog(LogFilter.emergencyStop, '비상정지 활성화 완료');
      }
      return;
    }

    if (state == 'inactive' || state == 'released') {
      if (_emergencyStopState == EmergencyStopState.activating) {
        return;
      }
      if (_emergencyStopState == EmergencyStopState.activationFailed &&
          command != 'release') {
        return;
      }
      if (_emergencyStopState == EmergencyStopState.releasing &&
          !matchesPending &&
          command != 'release') {
        return;
      }
      _clearEmergencyStopPending();
      _setEmergencyStopState(EmergencyStopState.inactive, '');
      if (matchesPending || command == 'release') {
        _addLog(LogFilter.emergencyStop, '비상정지 해제 완료');
      }
      return;
    }

    if (state == 'failed') {
      if (_pendingEmergencyRequestId != null && !matchesPending) {
        return;
      }
      final failedState = command == 'release' ||
              _emergencyStopState == EmergencyStopState.releasing
          ? EmergencyStopState.releaseFailed
          : EmergencyStopState.activationFailed;
      _clearEmergencyStopPending();
      _setEmergencyStopState(
        failedState,
        responseMessage.isEmpty
            ? 'app_emergency_node가 요청을 처리하지 못했습니다.'
            : responseMessage,
      );
      _addLog(LogFilter.emergencyStop, _emergencyStopMessage);
    }
  }

  void _clearEmergencyStopPending() {
    _emergencyStopTimeoutTimer?.cancel();
    _emergencyStopTimeoutTimer = null;
    _pendingEmergencyRequestId = null;
  }

  void _setEmergencyStopState(
    EmergencyStopState next,
    String message,
  ) {
    if (_emergencyStopState == next && _emergencyStopMessage == message) {
      return;
    }
    _emergencyStopState = next;
    _emergencyStopMessage = message;
    notifyListeners();
  }

  void _setConnectionState(RosConnectionState next, String detail) {
    if (_connectionState == next && _connectionDetail == detail) {
      return;
    }
    _connectionState = next;
    _connectionDetail = detail;
    _addLog(LogFilter.connection, detail);
    notifyListeners();
  }

  void _addLog(LogFilter filter, String message) {
    if (message.trim().isEmpty) {
      return;
    }
    _logs.insert(
      0,
      SupervisorLog(
        id: _uuid.v4(),
        filter: filter,
        message: message,
        createdAt: DateTime.now(),
      ),
    );
    if (_logs.length > 200) {
      _logs.removeRange(200, _logs.length);
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _emergencyStopTimeoutTimer?.cancel();
    unawaited(_client?.close());
    super.dispose();
  }
}
