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
| 비상정지 요청 | `/safety/emergency_stop_request` | `std_msgs/String` JSON |
| 비상정지 상태/응답 | `/safety/emergency_stop_state` | `std_msgs/String` JSON |

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

## app_emergency_node

- 실제 ROS2 node 이름: `app_emergency_node`
- 앱 요청 topic: `/safety/emergency_stop_request`
- 앱 상태/응답 topic: `/safety/emergency_stop_state`
- Nav2 입력: `/cmd_vel_raw`
- 모터 드라이버 출력: `/cmd_vel`
- 취소 대상 action: `/navigate_to_pose`

Nav2와 다른 주행 명령 발행자는 `/cmd_vel_raw`로 remap해야 합니다. 모터
드라이버는 `app_emergency_node`가 발행하는 `/cmd_vel`만 구독해야 하며,
다른 노드가 모터 드라이버에 직접 속도 명령을 보내는 우회 경로가 없어야 합니다.

### 비상정지 요청

```json
{
  "request_id": "uuid",
  "command": "activate",
  "source": "vica_supervisor",
  "timestamp": "2026-07-04T12:00:00+09:00"
}
```

`command`는 `activate`, `release`, `query` 중 하나입니다.
`request_id`와 `command`는 비어 있지 않은 문자열인 필수 필드입니다.
`source`와 `timestamp`는 선택 필드이지만, 전달할 경우 문자열이어야 합니다.
payload가 JSON 객체가 아니거나 필드 형식이 잘못되면 노드는 동작을 변경하지
않고 `state: failed` 응답을 발행합니다.

### 비상정지 상태/응답

```json
{
  "node": "app_emergency_node",
  "request_id": "uuid",
  "command": "activate",
  "state": "active",
  "active": true,
  "motor_output_blocked": true,
  "motion_hold_active": false,
  "navigation_cancelled": true,
  "message": "비상정지가 활성화되었고 기존 목적지가 취소되었습니다.",
  "timestamp": "2026-07-04T03:00:00+00:00"
}
```

앱은 요청 후 설정된 제한시간 안에 같은 `request_id`의 응답이 없으면 실패
팝업을 표시합니다. 노드는 앱 재접속 복구를 위해 현재 상태를 주기적으로
발행합니다. 비상정지 해제는 Nav2 목적지 취소가 확인된 뒤에만 허용합니다.
해제 후에도 `motion_hold_active`는 `true`로 유지되며, 해제 이후 생성된 새
Nav2 goal ID가 확인되어야 속도 명령을 다시 전달합니다.

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
