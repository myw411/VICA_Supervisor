# VICA_Supervisor

VICA 로봇 관리자용 Flutter 앱입니다. ROS2/nav2가 동작 중인 Jetson과 같은 네트워크에 있는 Android 기기에서 실행하는 것을 기준으로 합니다.

## 핵심 연결 방식

- ROS 연결: rosbridge WebSocket
- 지도 이미지: 설정 화면의 지도 HTTP 서버 주소 + ROS2가 내려준 `image_url`
- 좌표 저장: 앱이 `/save_location`, `/delete_location_request`에 JSON 요청을 보내고 ROS2 저장 노드가 `~/ros2_ws/location/<map_id>/locations.json`을 갱신

## 실행

```bash
cd ~/VICA_Supervisor
flutter pub get
dart run flutter_launcher_icons
flutter run
```

## ROS2 연동 테스트 순서

1. Jetson에서 rosbridge WebSocket 서버를 실행합니다.
2. 지도 이미지 HTTP 서버가 `~/ros2_ws/maps`를 제공하도록 실행합니다.
3. 필요하면 `ros2/map_list_node.py`, `ros2/location_storage_node.py`를 ROS2 환경에서 실행합니다.
4. 앱 설정에서 WebSocket 주소와 지도 HTTP 서버 주소를 입력합니다.
5. 대시보드에서 ROS 연결 후 지도 목록 요청을 확인합니다.
6. 지도 화면에서 지도 이미지와 장소 목록이 표시되는지 확인합니다.
7. 장소 저장 화면에서 좌표를 찍고 임시 저장 후 ROS2 저장 요청을 보냅니다.
8. `~/ros2_ws/location/<map_id>/locations.json`에 저장 결과가 반영되는지 확인합니다.
