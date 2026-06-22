# ROS2 Topic Contract

이 문서는 VICA_Supervisor가 사용하는 최소 ROS2 topic 계약입니다. 앱은 nav2 action, `/tf`, ROS graph 전체 탐색에 직접 연결하지 않습니다.

## 지도 저장 경로

- 지도 이미지 원본 위치: `~/ros2_ws/maps/<지도 이미지 이름>.png`
- 장소 저장 루트: `~/ros2_ws/location`
- 지도별 장소 파일: `~/ros2_ws/location/<map_id>/locations.json`

## Topic

| 목적 | Topic | Type |
| --- | --- | --- |
| 지도 목록 요청 | `/map_list_request` | `std_msgs/String` JSON |
| 지도 목록 수신 | `/map_list` | `std_msgs/String` JSON |
| 장소 목록 요청 | `/location_list_request` | `std_msgs/String` JSON |
| 장소 목록 수신 | `/location_list` | `std_msgs/String` JSON |
| 장소 저장 요청 | `/save_location` | `std_msgs/String` JSON |
| 장소 삭제 요청 | `/delete_location_request` | `std_msgs/String` JSON |
| 로봇 상태 수신 | `/robot_status` | `std_msgs/String` JSON |

## 지도 목록 예시

```json
{
  "maps": [
    {
      "map_id": "vica_map_0604",
      "map_name": "vica_map_0604",
      "image_url": "/maps/vica_map_0604.png",
      "resolution": 0.05,
      "origin_x": -10.0,
      "origin_y": -10.0,
      "width": 1024,
      "height": 1024
    }
  ],
  "timestamp": "2026-06-22T10:00:00"
}
```

## 장소 저장 요청 예시

```json
{
  "request_id": "uuid",
  "map_id": "vica_map_0604",
  "location_id": "uuid",
  "name": "안내소",
  "category": "guide",
  "x": 1.23,
  "y": 2.34,
  "yaw": 90.0,
  "memo": "입구 근처 안내소",
  "storage_root": "~/ros2_ws/location",
  "timestamp": "2026-06-22T10:00:00"
}
```

## 장소 삭제 요청 예시

```json
{
  "request_id": "uuid",
  "map_id": "vica_map_0604",
  "location_id": "uuid",
  "storage_root": "~/ros2_ws/location",
  "timestamp": "2026-06-22T10:00:00"
}
```
