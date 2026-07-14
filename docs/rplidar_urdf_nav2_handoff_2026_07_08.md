# VICA RPLIDAR / URDF / Nav2 디버깅 인계 보고서

이 문서는 VICA ROS2 워크스페이스에서 YDLIDAR G2를 임시로 RPLIDAR A2M8-R4로 대체하며 진행한 대화와 디버깅 내용을, 다른 GPT가 이어서 정리하거나 다음 작업을 계획할 수 있도록 흐름 중심으로 정리한 보고서다.

기준 시점:

```text
2026-07-08
작업 공간: /home/ji_w/ros2_ws, /home/ji_w/ros2_ws_test2
관련 앱 저장소: /home/ji_w/VICA_Supervisor
```

---

## 1. 작업 배경

기존 VICA 로봇은 YDLIDAR G2를 기준으로 구성되어 있었다.

그러나 사용자는 YDLIDAR를 A/S 수리 보낼 예정이었고, 그 동안 SLAMTEC RPLIDAR A2M8-R4를 임시 대체 LiDAR로 사용하려고 했다.

중요한 전제:

- RPLIDAR는 임시 대체 방안이다.
- 최종적으로는 다시 YDLIDAR를 사용할 예정이다.
- RPLIDAR도 기존 YDLIDAR가 하던 역할을 모두 수행해야 한다.
- RPLIDAR 사용 중에는 `scan_rear_filter`를 사용하지 않기로 했다.
- 외부 ROS2 드라이버는 VICA repo에 직접 포함하지 않고 `vica.repos`로 관리한다.

---

## 2. RPLIDAR SDK 단독 테스트

사용자는 먼저 공식 SDK를 받아 독립적으로 장치 통신을 확인했다.

공식 참고 링크:

```text
https://github.com/Slamtec/rplidar_sdk
https://github.com/Slamtec/rplidar_ros
https://www.slamtec.com/ko/lidar/a2
```

초기 실행:

```bash
./output/Linux/Release/ultra_simple /dev/ttyUSB0
```

SDK 2.1.0에서는 위 형식이 아니라 아래 형식이 필요했다.

```bash
./output/Linux/Release/ultra_simple --channel --serial /dev/ttyUSB0 115200
```

A2M8 계열 baudrate는 SDK 출력 기준 `115200`이었다.

SDK 단독 테스트 결과:

- LiDAR 모터 정상 회전
- 데이터 정상 수신
- 하드웨어, USB 포트, baudrate 기본 확인 완료

---

## 3. 독립 ROS2 워크스페이스 테스트

VICA 워크스페이스를 건드리기 전에 독립 워크스페이스를 만들었다.

```bash
mkdir -p ~/rplidar_test_ws/src
cd ~/rplidar_test_ws/src
git clone -b ros2 https://github.com/Slamtec/rplidar_ros.git
```

빌드:

```bash
cd ~/rplidar_test_ws
source /opt/ros/humble/setup.bash
colcon build --symlink-install
source install/setup.bash
```

udev rule 적용 후 `/dev/rplidar`가 생성되었다.

확인 결과:

```text
/dev/rplidar -> ttyUSB0
/dev/ttyUSB0 권한 rwx
```

RPLIDAR 단독 실행:

```bash
ros2 launch rplidar_ros rplidar_a2m8_launch.py \
  serial_port:=/dev/rplidar \
  serial_baudrate:=115200
```

RViz2에서 `/scan` 표시도 확인했다.

초기 RViz2 이슈:

- `Fixed Frame`을 `laser_frame`으로 두었는데 `/scan`의 `frame_id`가 `laser`라서 Message Filter queue full 경고가 발생했다.
- 해결은 `Fixed Frame=laser`로 맞추거나, 실행 시 `frame_id:=laser_frame`을 지정하는 방식이었다.

VICA 통합 기준으로는 `frame_id:=laser_frame`을 사용하기로 했다.

---

## 4. VICA 워크스페이스에 rplidar_ros 추가

RPLIDAR 드라이버는 VICA 규칙에 따라 `vica.repos`에 추가했다.

추가한 항목:

```yaml
  src/rplidar_ros:
    type: git
    url: https://github.com/Slamtec/rplidar_ros.git
    version: ros2
```

중간에 실수로 아래 명령을 실행해 `src/src/rplidar_ros`가 생겼다.

```bash
vcs import src < vica.repos
```

이 repo의 `vica.repos`에는 이미 경로가 `src/...`로 들어 있으므로 올바른 명령은 다음이었다.

```bash
cd ~/ros2_ws
vcs import < vica.repos
```

잘못 생긴 중첩 폴더는 제거하고, 최종적으로 정상 위치는 다음이 되었다.

```text
~/ros2_ws/src/rplidar_ros
```

확인:

```text
remote: https://github.com/Slamtec/rplidar_ros.git
branch: ros2
latest local commit: 24cc9b6 fixed "error: unknown type name 'nullptr_t'" (#145)
package version: 2.1.4
embedded SDK: 2.1.0
```

---

## 5. A2M8-R4 드라이버 / SDK 적합성 확인

공식 A2 문서와 로컬 드라이버를 대조했다.

RPLIDAR A2M8 datasheet 핵심:

- A2M8은 12m 범위 2D 360도 LiDAR
- typical scan frequency 10Hz
- 5-15Hz 조정 가능
- A2 원시 데이터 좌표계는 left-handed coordinate system
- sensor dead zone ahead가 x축
- 회전 각도는 clockwise로 증가

로컬 `rplidar_ros` 확인:

```text
launch/rplidar_a2m8_launch.py
serial_baudrate default = 115200
scan_mode default = Sensitivity
```

그러나 실제 A2M8-R4 장치는 `Sensitivity`를 지원하지 않았다.

실행 결과:

```text
scan mode `Sensitivity' is not supported by lidar
supported modes:
  Standard
  Express
  Boost
```

따라서 실제 운용에서는 `scan_mode:=Express`를 사용했다.

정상 실행 로그:

```text
current scan mode: Express
sample rate: 4 Khz
max_distance: 12.0 m
scan frequency: 10.0 Hz
```

---

## 6. VICA 워크스페이스에서 /scan 확인

VICA 워크스페이스에서 RPLIDAR를 실행하고 `/scan`을 확인했다.

실행 예:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash

ros2 launch rplidar_ros rplidar_a2m8_launch.py \
  serial_port:=/dev/rplidar \
  serial_baudrate:=115200 \
  frame_id:=laser_frame
```

또는 이후 테스트용으로 직접 노드를 실행했다.

```bash
ros2 run rplidar_ros rplidar_node --ros-args \
  -p channel_type:=serial \
  -p serial_port:=/dev/rplidar \
  -p serial_baudrate:=115200 \
  -p frame_id:=laser_frame \
  -p angle_compensate:=true \
  -p inverted:=false \
  -p flip_x_axis:=true \
  -p scan_mode:=Express
```

확인 결과:

```text
/scan publisher count: 1
frame_id: laser_frame
rate: 약 11.7 Hz
range_min: 0.15 m
range_max: 12.0 m
```

RPLIDAR를 사용하니 기존 YDLIDAR에서 보이던 왼쪽 반원 형태 오인식이 사라지고 스캔이 깔끔하게 보였다.

---

## 7. scan_rear_filter와 Nav2 costmap topic

기존 구조:

```text
YDLIDAR -> /scan
/scan -> scan_rear_filter -> /scan_nav2
Nav2 costmap -> /scan_nav2
AMCL -> /scan
Cartographer -> /scan
```

RPLIDAR 운용 조건:

- `scan_rear_filter`는 사용하지 않음
- Nav2 costmap도 `/scan`을 직접 보도록 변경

사용자가 직접 `nav2_params.yaml`을 수정했고, 확인 결과 다음 상태였다.

```yaml
amcl:
  scan_topic: "/scan"

local_costmap:
  voxel_layer:
    scan:
      topic: /scan

global_costmap:
  obstacle_layer:
    scan:
      topic: /scan
```

즉 `/scan_nav2`는 현재 `nav2_params.yaml`에서 더 이상 사용되지 않았다.

---

## 8. RPLIDAR scan 방향 / frame 해석

스캔 방향이 실제 로봇 방향 및 지도 방향과 맞지 않는 문제가 있었다.

초기에는 `base_link -> laser_frame` yaw를 직접 바꾸는 방식, RViz 화면 회전, `inverted`, `flip_x_axis` 등이 혼동되었다.

중요하게 정리된 내용:

- 지도 방향을 바꾸는 문제는 아니다.
- 실제로 조절해야 하는 것은 `/scan` 데이터가 `laser_frame` 안에서 어떤 방향을 0도로 사용하는지, 또는 `laser_frame`이 `base_link`에 어떻게 붙어 있는지다.
- RPLIDAR datasheet에는 원시 좌표계가 ROS 일반 LaserScan 해석과 다르다는 내용이 있다.
- `rplidar_ros/src/rplidar_node.cpp`에는 `inverted`, `flip_x_axis` 파라미터가 존재한다.

테스트한 조합 중 실제 스캔/오도메트리 방향이 가장 잘 맞았던 명령:

```bash
ros2 run rplidar_ros rplidar_node --ros-args \
  -p channel_type:=serial \
  -p serial_port:=/dev/rplidar \
  -p serial_baudrate:=115200 \
  -p frame_id:=laser_frame \
  -p angle_compensate:=true \
  -p inverted:=false \
  -p flip_x_axis:=true \
  -p scan_mode:=Express
```

별도로 사용자가 static TF yaw도 테스트했다.

```bash
ros2 run tf2_ros static_transform_publisher \
  --x 0.0 \
  --y 0.0 \
  --z 0.30 \
  --yaw -2.770796 \
  --pitch 0.0 \
  --roll 0.0 \
  --frame-id base_link \
  --child-frame-id laser_frame
```

이 값은 실제 RPLIDAR 장착 방향과 `base_link` x축을 맞추는 후보로 보였다.

하지만 최종적으로는 바로 `VICA.xacro`를 수정하지 않고, 기존 URDF를 그대로 띄운 상태에서 전체 흐름을 먼저 확인하기로 했다.

---

## 9. URDF / robot_state_publisher / RobotModel 검토

사용자는 `vica_description`의 URDF를 RViz2에서 사용하면 별도 static TF가 필요 없다는 이야기를 들었고, 이를 확인했다.

공식 `robot_state_publisher` 문서/README 기준:

- URDF의 kinematic tree를 읽어 TF를 발행한다.
- fixed joint는 `/tf_static`으로 발행한다.
- movable joint는 `/joint_states`를 받아 `/tf`로 발행한다.

로컬 URDF에는 이미 다음 fixed joint가 있었다.

```xml
<joint name="laser_joint" type="fixed">
  <origin xyz="0.185 0.0 0.236" rpy="0 0 0"/>
  <parent link="base_link"/>
  <child link="laser_frame"/>
</joint>
```

따라서 `robot_state_publisher`를 사용하면 `base_link -> laser_frame`은 URDF에서 발행할 수 있다.

주의점:

- `tf_vica`와 `robot_state_publisher`를 동시에 사용하면 `base_link -> laser_frame` 중복 발행이 된다.
- RPLIDAR 임시 값으로는 `rpy="0 0 -2.770796"` 후보가 있었지만, 원본 `VICA.xacro`는 당장 수정하지 않기로 했다.
- RPLIDAR 임시 운용이 안정화되면 나중에 `laser_joint`만 변경하거나 RPLIDAR용 별도 xacro를 만드는 방향이 좋다.

---

## 10. vica_description 빌드 / display.launch.py 문제

처음에는 `vica_description` 패키지가 설치되어 있지 않았다.

```text
Package 'vica_description' not found
```

해결:

```bash
cd ~/ros2_ws
source /opt/ros/humble/setup.bash
colcon build --symlink-install --packages-select vica_description
source install/setup.bash
```

이후 `display.launch.py` 실행 시 `robot_description` 파라미터 YAML 파싱 에러가 있었다.

```text
Unable to parse the value of parameter robot_description as yaml.
If the parameter is meant to be a string, try wrapping it in
launch_ros.parameter_descriptions.ParameterValue(value, value_type=str)
```

해결 방향:

```python
from launch_ros.parameter_descriptions import ParameterValue

robot_description = {
    "robot_description": ParameterValue(
        Command([
            FindExecutable(name="xacro"),
            " ",
            model,
        ]),
        value_type=str,
    )
}
```

이후 `joint_state_publisher_gui` 미설치 오류도 있었다.

```text
package 'joint_state_publisher_gui' not found
```

해결:

```bash
sudo apt install -y ros-humble-joint-state-publisher-gui
```

그 뒤 `display.launch.py`는 실행되었고, `robot_state_publisher`가 다음 세그먼트들을 인식했다.

```text
base_link
laser_frame
camera_link
left_wheel_1
right_wheel_1
front caster links
```

RViz2 RobotModel도 정상 표시되었다.

---

## 11. ROS_DOMAIN_ID / 실행 환경 문제

중간에 노드들이 서로 보이지 않는 문제가 반복되었다.

VICA alias들은 보통 다음 환경을 포함한다.

```bash
export ROS_DOMAIN_ID=7
export ROS_LOCALHOST_ONLY=0
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
```

그러나 직접 실행한 터미널에서는 `source`만 하고 위 export가 빠진 경우가 있었다.

그 결과:

- 어떤 터미널에서는 `base_link`가 보이지만 다른 터미널에서는 보이지 않음
- `map`이 RViz2 Fixed Frame에 안 보임
- `imu_base_link_adapter`가 `base_link`를 못 찾음
- RPLIDAR, URDF, Nav2가 서로 다른 domain에 떠 있을 가능성이 생김

이후 모든 터미널에서 다음 환경을 통일하라고 정리했다.

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=7
export ROS_LOCALHOST_ONLY=0
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
```

---

## 12. encoder_feedback / odom 문제

Nav2와 AMCL이 `map -> odom`을 만들지 못하는 문제가 있었다.

대표 로그:

```text
Timed out waiting for transform from base_link to odom
Invalid frame ID "odom"
```

확인 결과 `encoder_feedback` 노드는 떴지만 `/odom`이 안 나오거나 `odom -> base_link` TF가 없었다.

`encoder_feedback` 기본값:

```python
request_position_feedback = False
publish_tf = False
```

`encoder_restart` alias로 실행하면 로그가 다음과 같았다.

```text
position feedback mode: read-only
```

이 상태에서는 모터 드라이버가 위치 피드백을 자발적으로 반환해야 `/odom`을 낼 수 있다. 이후 다른 모터 노드가 동작하면서 position feedback이 들어와 `Initial position set` 로그가 보이기도 했다.

디버깅용으로 권장한 실행:

```bash
ros2 run encoder_feedback encoder_feedback --ros-args \
  -p request_position_feedback:=true \
  -p publish_tf:=true
```

확인 명령:

```bash
ros2 topic hz /odom
ros2 topic echo /odom --once
ros2 run tf2_ros tf2_echo odom base_link
```

주의:

- `request_position_feedback:=true`는 CAN 위치 피드백 요청 프레임을 보낸다.
- 주행 명령은 아니지만 실제 모터 드라이버와 CAN 통신하므로 위험도는 중간으로 안내했다.
- Nav2 goal을 주면 실제 바퀴가 움직일 수 있으므로 비상정지 준비가 필요하다.

---

## 13. AMCL / map / RViz2 문제

문제 상황:

- `/map`이 안 뜨거나 RViz2 Fixed Frame 목록에 `map`이 보이지 않음
- `2D Pose Estimate`가 제대로 안 됨
- AMCL이 아래 경고를 출력

```text
AMCL cannot publish a pose or update the transform.
Please set the initial pose...
```

정리한 원인:

- `map` 프레임은 map_server가 단독으로 만드는 것이 아니라, AMCL이 `map -> odom`을 발행해야 TF tree에 나타난다.
- AMCL이 `map -> odom`을 내려면 먼저 `odom -> base_link -> laser_frame` 체인이 있어야 한다.
- `odom`이 없으면 `/scan`이 들어와도 AMCL message filter가 queue full로 버린다.

대표 로그:

```text
Message Filter dropping message: frame 'laser_frame'
Timed out waiting for transform from base_link to odom
```

최종적으로 사용자는 이전에 저장해둔 다른 RViz2 설정 파일로 들어갔고, 그 설정에서는 `map` 디스플레이/topic 연결이 되어 있어서 지도가 뜨고 위치도 잘 잡혔다.

사용자 최종 확인:

```text
RViz2 map topic 문제는 다른 저장된 RViz2 설정 파일에서 해결됨.
지도 표시와 위치 추정이 정상 동작함.
일단 연결은 모두 정상.
```

즉, 마지막 상태에서는 RPLIDAR, URDF RobotModel, map 표시, localization 흐름이 동작하는 상태로 판단했다.

---

## 14. tf_tree 스크립트 문제와 수정

TF tree 그림을 보려고 `tf_tree` alias를 사용했다.

alias:

```bash
tf_tree
```

내부 실행:

```bash
/home/ji_w/ros2_ws/scripts/run_tf_tree.sh
```

문제:

스크립트가 기존 `frames*.pdf/gv/yaml`을 지우고 새로 만들었다.

기존 코드:

```bash
rm -f "$OUT_DIR"/frames*.pdf "$OUT_DIR"/frames*.gv "$OUT_DIR"/frames*.yaml
```

사용자는 직전 TF 그림이 삭제되었다고 문제를 제기했다.

수정:

```bash
echo "[6] Keep old frames files..."
echo "[TF TREE - HOST] Existing frames*.pdf/gv/yaml files will not be removed."
```

즉, 삭제 로직을 제거했다. 앞으로 `tf_tree`를 실행해도 기존 TF 그림 파일은 삭제하지 않는다.

---

## 15. .bashrc alias 관련

RPLIDAR 실행 alias도 추가했었다.

alias 이름:

```bash
rplidar
```

초기 alias는 launch 파일 기반이었다.

```bash
ros2 launch rplidar_ros rplidar_a2m8_launch.py \
  serial_port:=/dev/rplidar \
  serial_baudrate:=115200 \
  frame_id:=laser_frame
```

이후 실제 A2M8-R4에서는 `Express` 모드 및 `flip_x_axis:=true` 테스트가 중요해졌다.

따라서 alias를 실제 운용 기준으로 다시 정리하려면 다음 형태가 더 명확하다.

```bash
ros2 run rplidar_ros rplidar_node --ros-args \
  -p channel_type:=serial \
  -p serial_port:=/dev/rplidar \
  -p serial_baudrate:=115200 \
  -p frame_id:=laser_frame \
  -p angle_compensate:=true \
  -p inverted:=false \
  -p flip_x_axis:=true \
  -p scan_mode:=Express
```

단, 이 문서 작성 시점에 alias가 위 형태로 최종 정리되었는지는 별도 확인이 필요하다.

---

## 16. 현재 권장 실행 순서

최종적으로 안정적인 최소 실행 흐름은 다음과 같이 정리했다.

모든 터미널 공통:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=7
export ROS_LOCALHOST_ONLY=0
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
```

### 16.1 URDF / RobotModel

```bash
ros2 launch vica_description display.launch.py
```

주의:

- `tf_vica`는 켜지 않는다.
- `robot_state_publisher`가 URDF fixed joint로 `base_link -> laser_frame`을 발행한다.

### 16.2 RPLIDAR

```bash
ros2 run rplidar_ros rplidar_node --ros-args \
  -p channel_type:=serial \
  -p serial_port:=/dev/rplidar \
  -p serial_baudrate:=115200 \
  -p frame_id:=laser_frame \
  -p angle_compensate:=true \
  -p inverted:=false \
  -p flip_x_axis:=true \
  -p scan_mode:=Express
```

확인:

```bash
ros2 topic hz /scan
ros2 topic echo /scan --once
```

### 16.3 odom

```bash
ros2 run encoder_feedback encoder_feedback --ros-args \
  -p request_position_feedback:=true \
  -p publish_tf:=true
```

또는 실제 통합 주행에서는 기존 모터 노드와 encoder read-only 조합이 사용될 수 있으므로, `/odom`과 `odom -> base_link`가 실제로 나오는지만 확인한다.

```bash
ros2 topic hz /odom
ros2 run tf2_ros tf2_echo odom base_link
```

### 16.4 Nav2

```bash
ros2 launch vica_nav2 nav2_map_test.launch.py \
  map:=/home/ji_w/ros2_ws/maps/vica_map_0630.yaml
```

### 16.5 RViz2

최종적으로는 사용자가 이전에 저장해둔 다른 RViz2 설정 파일을 사용했을 때 map topic이 정상 연결되고 위치도 잘 잡혔다.

확인해야 할 Display:

```text
Fixed Frame: map
Map: /map
LaserScan: /scan
TF
RobotModel
Odometry
Polygon
Path
```

초기 위치:

```text
2D Pose Estimate
```

확인:

```bash
ros2 run tf2_ros tf2_echo map odom
ros2 topic echo /amcl_pose --once
```

---

## 17. 남은 정리 / TODO

다음 GPT가 이어받을 때 확인하면 좋은 항목:

1. `~/.bashrc`의 `rplidar` alias가 실제 운용 명령과 일치하는지 확인
2. RPLIDAR 운용에서 `flip_x_axis:=true`를 계속 쓸지, URDF `laser_joint` rpy를 실제 장착값으로 바꿀지 결정
3. `VICA.xacro` 원본은 현재 바로 수정하지 않는 방향이었다.
4. RPLIDAR가 임시 장비이므로 YDLIDAR 복귀 시 되돌릴 수 있게 문서화 필요
5. `display.launch.py`의 `robot_description` ParameterValue 수정이 현재 워크스페이스에 반영되어 있는지 확인
6. `tf_vica`와 `robot_state_publisher`를 동시에 켜지 않도록 launch/alias 정리 필요
7. `encoder_feedback`의 `publish_tf` / `request_position_feedback` 기본 운용 방식을 실제 주행 구조와 맞춰 재검토
8. RViz2 설정 파일 중 map이 정상 표시되는 파일을 표준 설정으로 저장할지 결정
9. RPLIDAR 운용 시 `scan_rear_filter` 미사용 정책 유지
10. Nav2 costmap이 `/scan`을 보고 있는지 계속 확인

---

## 18. 안전 관련 메모

이 작업은 실제 바퀴가 움직일 수 있는 AMR에서 진행되었다.

단계별 위험도:

```text
RPLIDAR 단독 실행:
  바퀴 움직임 없음. LiDAR 모터만 회전.

URDF / RViz2 / robot_state_publisher:
  바퀴 움직임 없음.

encoder_feedback / CAN:
  직접 주행 명령은 아니지만 CAN/모터 드라이버와 통신하므로 위험도 중간.

Nav2 실행:
  goal을 주면 실제 바퀴가 움직일 수 있음.

mdrobot_can_keyboard_knob_node:
  실제 모터 명령 경로와 연결되므로 비상정지 준비 필요.
```

작업 중 계속 강조한 원칙:

- `/cmd_vel`을 직접 모터 CAN 명령으로 우회 연결하지 않는다.
- Nav2 goal 테스트 전 비상정지를 준비한다.
- TF 중복 발행을 피한다.
- `map -> odom`, `odom -> base_link`, `base_link -> laser_frame` 체인을 항상 확인한다.

---

## 19. 최종 상태 요약

사용자는 마지막에 다음을 확인했다.

```text
일단 연결 모두 정상.
전에 저장해둔 다른 RViz2 설정 파일로 들어가니 map topic이 있고,
거기서 연결하니 지도도 뜨고 위치도 잘 잡힘.
```

따라서 현재 대화의 결론은 다음과 같다.

```text
RPLIDAR A2M8-R4 임시 대체 운용 가능성 확인
SDK / ROS2 드라이버 / udev / /scan 확인 완료
RPLIDAR scan 방향은 flip_x_axis:=true + Express 모드가 유력
URDF RobotModel / robot_state_publisher 사용 흐름 확인
Nav2 costmap은 /scan으로 수정 완료
RViz2 map 표시 문제는 저장된 다른 RViz2 설정 파일 사용으로 해결
AMCL localization도 정상 확인
```

