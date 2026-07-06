# app_emergency_node 배포 및 연동 점검

## VICA ros2_ws에 배치

이 저장소의 `ros2/app_emergency_node.py`를 VICA의 실제 ROS2 Python
패키지에 넣고 실행 파일 이름과 node 이름을 모두 `app_emergency_node`로
사용합니다.

예시 패키지 구조:

```text
~/ros2_ws/src/vica_app_nodes/
├── package.xml
├── setup.py
└── vica_app_nodes/
    ├── __init__.py
    └── app_emergency_node.py
```

`setup.py`의 `console_scripts`에는 다음 entry point를 추가합니다.

```python
"app_emergency_node = vica_app_nodes.app_emergency_node:main"
```

`package.xml`에는 최소한 다음 실행 의존성이 필요합니다.

```xml
<exec_depend>rclpy</exec_depend>
<exec_depend>std_msgs</exec_depend>
<exec_depend>geometry_msgs</exec_depend>
<exec_depend>action_msgs</exec_depend>
```

빌드 및 실행:

```bash
cd ~/ros2_ws
colcon build --packages-select vica_app_nodes
source install/setup.bash
ros2 run vica_app_nodes app_emergency_node
```

## cmd_vel 연결

기본 연결은 다음과 같습니다.

```text
Nav2 /cmd_vel_raw -> app_emergency_node -> /cmd_vel -> motor driver
```

Nav2 controller server의 속도 출력은 `/cmd_vel_raw`로 remap합니다.
모터 드라이버가 기존 `/cmd_vel`을 계속 구독하도록 두면
`app_emergency_node`의 출력만 모터로 전달됩니다.

현장 topic이 다르면 node parameter로 변경합니다.

```bash
ros2 run vica_app_nodes app_emergency_node --ros-args \
  -p input_cmd_vel_topic:=/cmd_vel_raw \
  -p output_cmd_vel_topic:=/cmd_vel \
  -p navigate_action_name:=/navigate_to_pose
```

## 실제 연결 전 확인

```bash
ros2 node list
ros2 node info /app_emergency_node
ros2 topic info -v /cmd_vel_raw
ros2 topic info -v /cmd_vel
ros2 action info /navigate_to_pose
ros2 topic echo /safety/emergency_stop_state
```

반드시 확인할 사항:

1. `/app_emergency_node`가 한 개만 실행 중인지 확인합니다.
2. Nav2와 모든 주행 명령 발행자가 `/cmd_vel_raw`로만 보내는지 확인합니다.
3. 모터 드라이버가 `/cmd_vel`만 구독하고 우회 입력이 없는지 확인합니다.
4. 실제 메시지 형식이 `geometry_msgs/msg/Twist`인지 확인합니다.
5. 앱과 VICA의 ROS Domain ID 및 네트워크 연결이 같은지 확인합니다.
6. rosbridge가 `/safety/emergency_stop_request`와
   `/safety/emergency_stop_state`를 전달하는지 확인합니다.

## 단계별 시험

처음에는 바퀴를 지면에서 띄우거나 모터 전원을 분리한 상태에서 시험합니다.

1. 정지 상태에서 앱 버튼을 눌러 성공 팝업과 `active: true`를 확인합니다.
2. 활성화 중 `/cmd_vel_raw`에 속도 명령을 넣어도 `/cmd_vel`이 계속 0인지 확인합니다.
3. Nav2 주행 중 정지를 눌러 action goal이 canceled 상태가 되는지 확인합니다.
4. 비상정지를 해제한 뒤 기존 목적지가 다시 시작되지 않는지 확인합니다.
5. 해제 후 `/safety/emergency_stop_state`의 `motion_hold_active`가
   `true`이고 `/cmd_vel`이 계속 0인지 확인합니다.
6. 새로운 목적지를 보낸 뒤에만 `motion_hold_active`가 `false`로 바뀌고
   주행이 다시 시작되는지 확인합니다.
7. `app_emergency_node`를 종료한 뒤 앱에서 정지를 눌러 실패 팝업과 재시도를 확인합니다.
8. rosbridge 연결을 끊고 동일한 실패/재연결/재시도 흐름을 확인합니다.
9. 앱을 종료했다 다시 열어도 node가 active이면 정지 팝업이 복구되는지 확인합니다.
10. 해제 요청 중 연결을 끊으면 팝업이 유지되고 해제 재시도가 나타나는지 확인합니다.
11. 배열 payload, 빈 `request_id`, 잘못된 `command`를 보내도 node가
    종료되지 않고 `/safety/emergency_stop_state`에 `state: failed`가
    발행되는지 확인합니다.

소프트웨어 node는 물리 비상정지 회로를 대체하지 않습니다. 실제 사람과
장비가 있는 환경에서는 독립된 하드웨어 비상정지를 함께 사용해야 합니다.
