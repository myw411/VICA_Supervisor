# VICA_Supervisor

VICA 로봇 관리자용 Flutter 앱이다.

## 핵심 연결

- ROS 연결: rosbridge WebSocket
- 지도 이미지: 지도 HTTP 서버 주소 + `/map_list`의 `image_url`
- 목적지 관리: `/save_location`, `/delete_location_request`,
  `/location_list_request`, `/location_list`
- 목적지 정본: `~/vica_data/destinations/<map_id>/destinations.yaml`
- 원격 안내 요청: `/vica/mission/request_destination`
- 비상정지: `/app_estop_activate`, `/app_estop_reset`

앱은 저장 경로나 Nav2 action을 직접 소유하지 않는다. 저장 경로는
`vica_destination_manager`의 ROS 파라미터이고, Nav2 Goal은 Mission Manager만 생성한다.

## 실행

```bash
flutter pub get
flutter run
```

ROS 쪽에서는 다음 구성요소를 별도로 실행한다.

```bash
ros2 launch vica_destination_manager destination_manager.launch.py
ros2 launch vica_mission_manager mission_manager.launch.py \
  map_id:=vica_map_0630 \
  map_yaml:=/path/to/vica_map_0630.yaml
```

`ros2/location_storage_node.py`는 기존 JSON 저장 노드의 보호용 진입점이며 더 이상
사용하지 않는다. 기존 JSON 장소는 새 YAML로 자동 이관하지 않는다.
