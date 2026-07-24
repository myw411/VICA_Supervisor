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

  static const _nav2UnavailableReason = 'Nav2/AMCL 미실행';
  static const _nav2UnavailableMessage =
      'Nav2가 실행되지 않아 현재 위치와 주행 이벤트를 받을 수 없습니다.';
  static const _nav2AvailableMessage = 'Nav2가 실행되었습니다.';
  static const _noEventsRecordedReason = 'no events recorded';

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
  EmergencyStopState _emergencyStopState = EmergencyStopState.inactive;
  String _emergencyStopMessage = '';
  bool _nav2UnavailableNotified = false;
  bool _nav2AvailableNotified = false;
  bool _nav2WasUnavailable = false;
  bool _noEventsRecordedNotified = false;

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
    _resetNav2NotificationState();
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
        topic: settings.emergencyStateTopic,
        handler: _handleEmergencyStopState,
      );
  }

  // 앱 비상정지 버튼: app_emergency_node의 activate 서비스를 호출합니다.
  // 서비스 응답으로 성공/실패를 바로 판정하므로 request_id나 timeout 타이머가 필요없습니다.
  Future<void> activateEmergencyStop(AppSettings settings) async {
    if (_emergencyStopState == EmergencyStopState.activating ||
        _emergencyStopState == EmergencyStopState.releasing) {
      return;
    }
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      _setEmergencyStopState(
        EmergencyStopState.activationFailed,
        'ROS Bridge에 연결되지 않아 비상정지를 활성화하지 못했습니다.',
      );
      _addLog(LogFilter.emergencyStop, '비상정지 요청 실패: ROS 연결 안 됨');
      return;
    }
    _setEmergencyStopState(
      EmergencyStopState.activating,
      'VICA에 비상정지를 요청하고 있습니다.',
    );
    _addLog(LogFilter.emergencyStop, '비상정지 요청 전송');
    try {
      final response = await client.callService(
        service: settings.emergencyActivateService,
        timeout: Duration(seconds: settings.emergencyServiceTimeoutSeconds),
      );
      if (response.result && response.success) {
        _setEmergencyStopState(
          EmergencyStopState.active,
          response.message.isEmpty
              ? '비상정지가 활성화되었습니다. 기존 목적지는 취소되었습니다.'
              : response.message,
        );
        _addLog(LogFilter.emergencyStop, '비상정지 활성화 완료');
      } else {
        _setEmergencyStopState(
          EmergencyStopState.activationFailed,
          response.message.isEmpty ? '비상정지 요청을 처리하지 못했습니다.' : response.message,
        );
        _addLog(LogFilter.emergencyStop, _emergencyStopMessage);
      }
    } catch (error) {
      _setEmergencyStopState(
        EmergencyStopState.activationFailed,
        'app_emergency_node의 비상정지 응답이 없습니다: $error',
      );
      _addLog(LogFilter.emergencyStop, _emergencyStopMessage);
    }
  }

  Future<void> retryEmergencyStop(AppSettings settings) async {
    if (_connectionState != RosConnectionState.connected) {
      await connect(settings);
    }
    if (_emergencyStopState != EmergencyStopState.activationFailed) {
      return;
    }
    await activateEmergencyStop(settings);
  }

  void dismissEmergencyStopFailure() {
    if (_emergencyStopState != EmergencyStopState.activationFailed) {
      return;
    }
    _setEmergencyStopState(EmergencyStopState.inactive, '');
    _addLog(LogFilter.emergencyStop, '비상정지 실패 알림 닫음');
  }

  // 비상정지 해제: app_emergency_node의 reset 서비스를 호출합니다.
  // 노드가 /app_emergency_stop=false 전파 → Nav2 재취소 → /estop_reset 호출까지
  // 마친 뒤 성공/실패를 돌려주므로, 성공이면 이후 정상 주행 명령이 그대로 반영됩니다.
  Future<void> resetEmergencyStop(AppSettings settings) async {
    if (_emergencyStopState == EmergencyStopState.releasing ||
        _emergencyStopState == EmergencyStopState.activating) {
      return;
    }
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      _setEmergencyStopState(
        EmergencyStopState.releaseFailed,
        'ROS Bridge에 연결되지 않아 비상정지를 해제하지 못했습니다.',
      );
      _addLog(LogFilter.emergencyStop, '비상정지 해제 실패: ROS 연결 안 됨');
      return;
    }
    _setEmergencyStopState(
      EmergencyStopState.releasing,
      'VICA에 비상정지 해제를 요청하고 있습니다.',
    );
    _addLog(LogFilter.emergencyStop, '비상정지 해제 요청 전송');
    try {
      final response = await client.callService(
        service: settings.emergencyResetService,
        timeout: Duration(seconds: settings.emergencyServiceTimeoutSeconds),
      );
      if (response.result && response.success) {
        _setEmergencyStopState(EmergencyStopState.inactive, '');
        _addLog(LogFilter.emergencyStop, '비상정지 해제 완료');
      } else {
        _setEmergencyStopState(
          EmergencyStopState.releaseFailed,
          response.message.isEmpty ? '비상정지 해제를 처리하지 못했습니다.' : response.message,
        );
        _addLog(LogFilter.emergencyStop, _emergencyStopMessage);
      }
    } catch (error) {
      _setEmergencyStopState(
        EmergencyStopState.releaseFailed,
        'app_emergency_node의 비상정지 해제 응답이 없습니다: $error',
      );
      _addLog(LogFilter.emergencyStop, _emergencyStopMessage);
    }
  }

  Future<void> retryEmergencyStopRelease(AppSettings settings) async {
    if (_connectionState != RosConnectionState.connected) {
      await connect(settings);
    }
    await resetEmergencyStop(settings);
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

  // 임시 저장된 목적지를 destinations 스키마의 JSON으로 전송합니다.
  void saveDraftLocation(AppSettings settings) {
    final draft = _draftLocation;
    if (draft == null) {
      return;
    }
    final destination = draft.toJson();
    final pose = Map<String, Object>.from(
      destination['pose']! as Map<String, Object>,
    );
    pose['yaw'] = _normalizeYawDegrees(draft.yaw);
    final payload = {
      'request_id': _uuid.v4(),
      'map_id': draft.mapId,
      ...destination,
      'pose': pose,
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

  double _normalizeYawDegrees(double yaw) {
    final normalized = yaw % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
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
      final errorReason = next.errorReason.trim();
      if (_isNoEventsRecorded(errorReason)) {
        if (!_noEventsRecordedNotified) {
          _noEventsRecordedNotified = true;
          _addLog(LogFilter.connection, errorReason);
        }
      } else {
        _addLog(LogFilter.emergencyStop, '${next.robotName}: $errorReason');
      }
    }
    _handleNav2StatusLog(next);
    notifyListeners();
  }

  bool _isNoEventsRecorded(String message) {
    return message.trim().toLowerCase() == _noEventsRecordedReason;
  }

  void _handleNav2StatusLog(RobotStatus robot) {
    final nav2Unavailable = robot.waitingReason == _nav2UnavailableReason;
    if (nav2Unavailable) {
      _nav2WasUnavailable = true;
      if (!_nav2UnavailableNotified) {
        _nav2UnavailableNotified = true;
        _nav2AvailableNotified = false;
        _addLog(LogFilter.connection, _nav2UnavailableMessage);
      }
      return;
    }

    if (_nav2WasUnavailable && !_nav2AvailableNotified) {
      _nav2AvailableNotified = true;
      _addLog(LogFilter.connection, _nav2AvailableMessage);
    }
    _nav2WasUnavailable = false;
  }

  void _resetNav2NotificationState() {
    _nav2UnavailableNotified = false;
    _nav2AvailableNotified = false;
    _nav2WasUnavailable = false;
    _noEventsRecordedNotified = false;
  }

  // /app_estop_state 주기 브로드캐스트로 오버레이 상태를 노드 실제 상태에 맞춥니다.
  // 앱이 비상정지 중에 재접속하면 이 토픽으로 활성 오버레이를 복구합니다.
  void _handleEmergencyStopState(Map<String, Object?> message) {
    final active = message['active'] == true;
    final stateMessage = message['message'] as String? ?? '';

    // 서비스 호출이 진행 중일 때는 그 응답이 상태를 결정하므로 브로드캐스트는 무시합니다.
    if (_emergencyStopState == EmergencyStopState.activating ||
        _emergencyStopState == EmergencyStopState.releasing) {
      return;
    }

    if (active) {
      // 노드가 활성이라고 알리면(정지가 유지되는 안전한 사실) 활성 오버레이로 맞춥니다.
      if (_emergencyStopState != EmergencyStopState.active) {
        _setEmergencyStopState(
          EmergencyStopState.active,
          stateMessage.isEmpty ? '비상정지가 활성화되어 있습니다.' : stateMessage,
        );
      }
      return;
    }

    // 노드가 비활성이라고 알릴 때: 실패 알림은 사용자가 닫기 전까지 유지합니다.
    if (_emergencyStopState == EmergencyStopState.activationFailed ||
        _emergencyStopState == EmergencyStopState.releaseFailed) {
      return;
    }
    if (_emergencyStopState != EmergencyStopState.inactive) {
      _setEmergencyStopState(EmergencyStopState.inactive, '');
    }
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
    unawaited(_client?.close());
    super.dispose();
  }
}
