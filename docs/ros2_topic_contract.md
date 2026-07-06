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
| 앱 비상정지 입력 | `/app_emergency_stop` | `std_msgs/Bool` |

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
- 모터 E-stop 입력 topic: `/app_emergency_stop`
- 모터 E-stop reset 서비스: `/estop_reset`
- 취소 대상 action: `/navigate_to_pose`

Nav2 주행 명령은 `/cmd_vel`로 발행하고, `keyboard_knob`만 `/cmd_vel`을
구독해 CAN 모터 명령으로 변환합니다. `app_emergency_node`는 `/cmd_vel`을
구독하거나 발행하지 않으며, 앱 비상정지는 `/app_emergency_stop`으로
`emergency_stop_node`에 전달됩니다.

### 비상정지 요청

```json
{
  "request_id": "uuid",
  "command": "activate",
  "source": "vica_supervisor",
  "timestamp": "2026-07-04T12:00:00+09:00"
}
```

`command`는 `activate`, `reset`, `query` 중 하나입니다.
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
발행합니다. reset은 `/app_emergency_stop=false`, `/estop_reset` 호출,
Nav2 목적지 취소가 모두 확인된 뒤 완료됩니다. 주행 정지는 `/cmd_vel`에
0을 섞는 방식이 아니라 `keyboard_knob`의 `/emergency_stop` 래치와 CAN
0rpm/brake 송신으로 처리합니다.

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
