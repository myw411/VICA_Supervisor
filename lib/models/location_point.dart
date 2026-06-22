// 이 파일은 지도 위에 저장하거나 표시할 장소 좌표 데이터를 표현합니다.
class LocationPoint {
  const LocationPoint({
    required this.locationId,
    required this.mapId,
    required this.name,
    required this.category,
    required this.x,
    required this.y,
    required this.yaw,
    required this.memo,
  });

  final String locationId;
  final String mapId;
  final String name;
  final String category;
  final double x;
  final double y;
  final double yaw;
  final String memo;

  factory LocationPoint.fromJson(Map<String, Object?> json, String fallbackMapId) {
    return LocationPoint(
      locationId: json['location_id'] as String? ?? '',
      mapId: json['map_id'] as String? ?? fallbackMapId,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      yaw: (json['yaw'] as num?)?.toDouble() ?? 0,
      memo: json['memo'] as String? ?? '',
    );
  }

  Map<String, Object> toJson() {
    return {
      'location_id': locationId,
      'map_id': mapId,
      'name': name,
      'category': category,
      'x': x,
      'y': y,
      'yaw': yaw,
      'memo': memo,
    };
  }
}
