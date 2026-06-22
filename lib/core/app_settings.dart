// 이 파일은 앱 설정값과 ROS topic 이름, 지도 서버 주소 같은 기본 구성을 보관합니다.
import 'package:flutter/foundation.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.rosBridgeUrl = 'ws://192.168.0.10:9090',
    this.mapHttpBaseUrl = 'http://192.168.0.10:8000',
    this.locationStorageRoot = '~/ros2_ws/location',
    this.mapListRequestTopic = '/map_list_request',
    this.mapListTopic = '/map_list',
    this.locationListRequestTopic = '/location_list_request',
    this.locationListTopic = '/location_list',
    this.saveLocationTopic = '/save_location',
    this.deleteLocationRequestTopic = '/delete_location_request',
    this.robotStatusTopic = '/robot_status',
    this.maxLogs = 200,
    this.maxReconnectAttempts = 5,
    this.autoRequestMapList = true,
    this.autoRequestLocationList = true,
    this.xOffset = 0,
    this.yOffset = 0,
    this.yawOffset = 0,
    this.mapScale = 1,
    this.flipMapY = true,
  });

  final String rosBridgeUrl;
  final String mapHttpBaseUrl;
  final String locationStorageRoot;
  final String mapListRequestTopic;
  final String mapListTopic;
  final String locationListRequestTopic;
  final String locationListTopic;
  final String saveLocationTopic;
  final String deleteLocationRequestTopic;
  final String robotStatusTopic;
  final int maxLogs;
  final int maxReconnectAttempts;
  final bool autoRequestMapList;
  final bool autoRequestLocationList;
  final double xOffset;
  final double yOffset;
  final double yawOffset;
  final double mapScale;
  final bool flipMapY;

  AppSettings copyWith({
    String? rosBridgeUrl,
    String? mapHttpBaseUrl,
    String? locationStorageRoot,
    String? mapListRequestTopic,
    String? mapListTopic,
    String? locationListRequestTopic,
    String? locationListTopic,
    String? saveLocationTopic,
    String? deleteLocationRequestTopic,
    String? robotStatusTopic,
    int? maxLogs,
    int? maxReconnectAttempts,
    bool? autoRequestMapList,
    bool? autoRequestLocationList,
    double? xOffset,
    double? yOffset,
    double? yawOffset,
    double? mapScale,
    bool? flipMapY,
  }) {
    return AppSettings(
      rosBridgeUrl: rosBridgeUrl ?? this.rosBridgeUrl,
      mapHttpBaseUrl: mapHttpBaseUrl ?? this.mapHttpBaseUrl,
      locationStorageRoot: locationStorageRoot ?? this.locationStorageRoot,
      mapListRequestTopic: mapListRequestTopic ?? this.mapListRequestTopic,
      mapListTopic: mapListTopic ?? this.mapListTopic,
      locationListRequestTopic:
          locationListRequestTopic ?? this.locationListRequestTopic,
      locationListTopic: locationListTopic ?? this.locationListTopic,
      saveLocationTopic: saveLocationTopic ?? this.saveLocationTopic,
      deleteLocationRequestTopic:
          deleteLocationRequestTopic ?? this.deleteLocationRequestTopic,
      robotStatusTopic: robotStatusTopic ?? this.robotStatusTopic,
      maxLogs: maxLogs ?? this.maxLogs,
      maxReconnectAttempts:
          maxReconnectAttempts ?? this.maxReconnectAttempts,
      autoRequestMapList: autoRequestMapList ?? this.autoRequestMapList,
      autoRequestLocationList:
          autoRequestLocationList ?? this.autoRequestLocationList,
      xOffset: xOffset ?? this.xOffset,
      yOffset: yOffset ?? this.yOffset,
      yawOffset: yawOffset ?? this.yawOffset,
      mapScale: mapScale ?? this.mapScale,
      flipMapY: flipMapY ?? this.flipMapY,
    );
  }

  Map<String, Object> toJson() {
    return {
      'rosBridgeUrl': rosBridgeUrl,
      'mapHttpBaseUrl': mapHttpBaseUrl,
      'locationStorageRoot': locationStorageRoot,
      'mapListRequestTopic': mapListRequestTopic,
      'mapListTopic': mapListTopic,
      'locationListRequestTopic': locationListRequestTopic,
      'locationListTopic': locationListTopic,
      'saveLocationTopic': saveLocationTopic,
      'deleteLocationRequestTopic': deleteLocationRequestTopic,
      'robotStatusTopic': robotStatusTopic,
      'maxLogs': maxLogs,
      'maxReconnectAttempts': maxReconnectAttempts,
      'autoRequestMapList': autoRequestMapList,
      'autoRequestLocationList': autoRequestLocationList,
      'xOffset': xOffset,
      'yOffset': yOffset,
      'yawOffset': yawOffset,
      'mapScale': mapScale,
      'flipMapY': flipMapY,
    };
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    const defaults = AppSettings();
    return AppSettings(
      rosBridgeUrl: json['rosBridgeUrl'] as String? ?? defaults.rosBridgeUrl,
      mapHttpBaseUrl:
          json['mapHttpBaseUrl'] as String? ?? defaults.mapHttpBaseUrl,
      locationStorageRoot:
          json['locationStorageRoot'] as String? ?? defaults.locationStorageRoot,
      mapListRequestTopic:
          json['mapListRequestTopic'] as String? ?? defaults.mapListRequestTopic,
      mapListTopic: json['mapListTopic'] as String? ?? defaults.mapListTopic,
      locationListRequestTopic: json['locationListRequestTopic'] as String? ??
          defaults.locationListRequestTopic,
      locationListTopic:
          json['locationListTopic'] as String? ?? defaults.locationListTopic,
      saveLocationTopic:
          json['saveLocationTopic'] as String? ?? defaults.saveLocationTopic,
      deleteLocationRequestTopic:
          json['deleteLocationRequestTopic'] as String? ??
              defaults.deleteLocationRequestTopic,
      robotStatusTopic:
          json['robotStatusTopic'] as String? ?? defaults.robotStatusTopic,
      maxLogs: json['maxLogs'] as int? ?? defaults.maxLogs,
      maxReconnectAttempts:
          json['maxReconnectAttempts'] as int? ?? defaults.maxReconnectAttempts,
      autoRequestMapList:
          json['autoRequestMapList'] as bool? ?? defaults.autoRequestMapList,
      autoRequestLocationList: json['autoRequestLocationList'] as bool? ??
          defaults.autoRequestLocationList,
      xOffset: (json['xOffset'] as num?)?.toDouble() ?? defaults.xOffset,
      yOffset: (json['yOffset'] as num?)?.toDouble() ?? defaults.yOffset,
      yawOffset: (json['yawOffset'] as num?)?.toDouble() ?? defaults.yawOffset,
      mapScale: (json['mapScale'] as num?)?.toDouble() ?? defaults.mapScale,
      flipMapY: json['flipMapY'] as bool? ?? defaults.flipMapY,
    );
  }
}
