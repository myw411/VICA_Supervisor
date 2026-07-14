# VICA_Supervisor 작업 인계 정리

이 문서는 사용자가 말한 "화요일 오전 10시 53분에 `VICA_Supervisor에서 수정한 부분 git에 올려줘`라고 한 부분"까지의 대화와 작업 내용을 다른 GPT에게 전달하기 위한 정리본이다.

기준 커밋:

```text
393a22d refine nav2 status and yaw alignment
```

이 문서의 범위는 위 커밋까지다. 이후 `ros2_ws_test2`에서 물리 비상정지, `emergency_stop_node`, CAN F1 비트, 하드웨어 배선 문제를 다시 디버깅한 내용은 이 문서의 주요 범위가 아니다.

---

## 1. 전체 작업 배경

사용자는 `VICA_Supervisor` Flutter 앱을 VICA 로봇의 ROS2/Nav2 시스템과 연동해 사용하고 있다.

주요 목표는 다음과 같았다.

- 앱에서 지도별 장소 저장/삭제/조회
- 현재 위치와 로봇 상태 표시
- 앱에서 목적지 주행 요청
- 앱 비상정지 버튼 추가
- 물리 비상정지와 앱 비상정지를 모터 쪽 비상정지 흐름과 맞추기
- Nav2 도착 후 yaw 정렬 오차 줄이기
- Nav2가 꺼져 있을 때 앱 알림이 과도하게 반복되는 문제 완화

작업 대상은 크게 두 영역이었다.

```text
/home/ji_w/VICA_Supervisor
/home/ji_w/ros2_ws_test2
```

단, 이 문서는 `VICA_Supervisor` 저장소에 반영해 git에 올린 내용까지를 중심으로 정리한다.

---

## 2. 앱 비상정지 구조 변경

초기에는 앱 비상정지 노드가 `/cmd_vel`을 직접 막거나 0 속도를 반복 발행하는 구조를 검토했다.

그러나 실제 주행 중 떨림과 속도 저하가 발생했다. 원인은 `/cmd_vel` 경로에 여러 노드가 끼어들면서 Nav2 주행 명령과 앱 비상정지 노드의 0 속도 명령이 섞일 가능성이 커졌기 때문으로 판단했다.

최종 추천 방향은 다음 구조였다.

```text
Nav2
  -> /cmd_vel
  -> keyboard_knob
  -> CAN
  -> motor

앱
  -> app_emergency_node
  -> /app_emergency_stop
  -> emergency_stop_node
  -> /emergency_stop
  -> keyboard_knob latch

앱 reset
  -> app_emergency_node
  -> /app_emergency_stop=false
  -> /estop_reset 호출
  -> Nav2 goal cancel
```

핵심 결정:

- `app_emergency_node`는 `/cmd_vel`을 구독하지 않는다.
- `app_emergency_node`는 `/cmd_vel`을 발행하지 않는다.
- 앱 비상정지는 `/app_emergency_stop`으로만 모터 쪽에 전달한다.
- 실제 모터 정지는 `keyboard_knob`의 `/emergency_stop` 래치와 CAN 정지/브레이크 계층에서 처리한다.
- Nav2 목적지 취소는 앱 reset 흐름에서 함께 처리한다.

이 변경 후 사용자가 실제 주행 테스트를 했고, 기존의 떨림과 속도 저하가 사라졌다고 확인했다.

---

## 3. 앱 reset 명칭과 흐름

앱 UI에서는 기존의 "비상정지 해제" 표현이 혼동될 수 있다고 보고 `reset`으로 통일하는 방향을 잡았다.

reset 의미:

- 앱 비상정지 요청을 false로 되돌림
- 모터 비상정지 래치 해제를 위해 `/estop_reset` 호출
- 진행 중인 Nav2 goal cancel
- reset 완료 상태를 앱에 알림

중요한 판단:

- reset은 단순히 "다시 주행 시작"이 아니다.
- reset 후 이전 목적지가 자동 재개되면 안 된다.
- reset 후 로봇은 정지 상태를 유지해야 한다.
- 사용자가 새 목적지를 다시 보내야 한다.

---

## 4. 관련 문서 정리

비상정지 흐름은 다음 문서에도 반영했다.

```text
docs/app_emergency_node_setup.md
docs/ros2_topic_contract.md
```

`docs/ros2_topic_contract.md` 기준의 주요 topic/service는 다음과 같다.

```text
/safety/emergency_stop_request  std_msgs/String JSON
/safety/emergency_stop_state    std_msgs/String JSON
/app_emergency_stop             std_msgs/Bool
/estop_reset                    std_srvs/srv/Trigger
```

문서에는 앱 비상정지가 `/cmd_vel`을 직접 막지 않고 `/app_emergency_stop`을 통해 모터 비상정지 계층으로 전달된다는 점을 명시했다.

---

## 5. 실행 구조

당시 앱 비상정지 연동 확인을 위한 실행 흐름은 다음과 같이 정리했다.

### 5.1 motor / keyboard_knob

```bash
cd /home/ji_w/ros2_ws_test2
source /opt/ros/humble/setup.bash
colcon build --packages-select mdrobot_can_control
source install/setup.bash

ros2 run mdrobot_can_control keyboard_knob --ros-args -p estop_bit_pressed_value:=0
```

### 5.2 app_emergency_node

```bash
cd /home/ji_w/VICA_Supervisor
source /opt/ros/humble/setup.bash
source /home/ji_w/ros2_ws_test2/install/setup.bash

python3 ros2/app_emergency_node.py
```

당시 설명:

- `app_emergency_node.py`는 Python 스크립트라 APK 재빌드가 필요 없다.
- 앱 UI 자체가 바뀐 경우에만 APK를 다시 만들어야 한다.
- ROS Python 노드만 수정한 경우에는 노드를 재실행하면 된다.

---

## 6. UI 수정: 하단 네비게이션바

사용자는 하단 네비게이션바에 바로가기 아이콘이 너무 많아 메뉴 제목이 다 보이지 않는다고 했다.

수정 방향:

- 지도 모양 아이콘인 "지도별 장소보기" 바로가기 제거
- 빈자리만큼 다른 아이콘 배치 조정
- 네비게이션바 메뉴 이름 글자 크기를 약 2/3 정도로 축소

관련 파일:

```text
lib/widgets/vica_ui.dart
```

이 변경은 앱 UI 변경이므로 실제 Android 앱에서 확인하려면 APK 재빌드가 필요하다.

---

## 7. 장소 저장 yaw 보정 시도

처음에는 Nav2가 목적지 도착 후 yaw 정렬을 할 때 항상 5~10도 정도 덜 도는 것처럼 보였다.

사용자는 CAN 통신 지연이나 각속도 제어 지연 때문에 현재 상황에서는 완벽히 맞추기 어렵다고 판단했고, 장소 저장 시 yaw 값에 자동으로 10도를 더하는 방식을 제안했다.

수정 방향:

- 장소 저장 시 사용자가 입력한 yaw에 내부 설정값으로 10도 보정
- 설정 화면에는 노출하지 않음
- 앱 설정값으로만 유지

관련 파일:

```text
lib/core/app_settings.dart
lib/providers/supervisor_provider.dart
```

이 방식은 이후 "고정 10도 보정은 맞을 때도 있고 아닐 때도 있다"는 이유로 근본 해결책이 아니라고 판단했다.

---

## 8. Nav2 도착 후 yaw 재정렬 방식

고정 10도 보정 대신, Nav2 goal 성공 이후 실제 yaw 오차를 확인하고 필요할 때만 추가 회전하는 방식으로 바꾸기로 했다.

최종 설계:

- Nav2 goal 성공 이후 `vica_goto_goal.py`가 현재 yaw와 목표 yaw의 오차를 확인
- yaw 오차가 기준 이상이면 `cmd_vel`에 `angular.z`만 발행
- `linear.x`는 항상 0
- 정렬이 끝나면 반드시 0 `cmd_vel`을 발행하고 종료
- 재정렬 횟수는 최대 2회
- 기준은 처음에 5도였고, 이후 테스트 결과 3도 이상으로 줄이면 더 잘 맞는다고 판단

기준 커밋 시점의 핵심 변경:

```text
ros2/vica_goto_goal.py
```

주요 파라미터:

```text
yaw_align_enabled
yaw_align_tolerance_deg
yaw_align_max_attempts
yaw_align_max_duration_sec
yaw_align_angular_speed
yaw_align_min_angular_speed
yaw_align_slowdown_deg
yaw_align_cmd_vel_topic
```

당시 커밋 `393a22d`에는 yaw 정렬 보완 로직이 들어갔다. 이후 사용자는 `yaw_align_tolerance_deg`를 5도에서 3도로 다시 낮춰 테스트했고, 2번 정도 수정해서 거의 완벽하게 정렬된다고 말했다. 이 3도 변경은 기준 커밋 이후 작업 트리에 남아 있을 수 있다.

---

## 9. map_id와 현재위치 인식 문제

새로 만든 `0630` 지도에서 장소 저장/송수신은 되지만 삭제가 안 되고, "현재위치" 메뉴가 이전 `0604` 지도만 인식하는 문제가 있었다.

원인으로 본 것:

- 사용하지 않는 `map` 이름의 폴더가 장소 루트에 남아 있어 앱 또는 ROS 노드가 잘못된 지도 폴더를 볼 가능성
- status 노드가 `map_id`를 직접 파라미터로 받는 방식 때문에 Nav2에서 실제 실행 중인 map과 어긋날 가능성

사용자는 불필요한 폴더를 수동 삭제했다.

최종 방향:

- `map_id`를 사용자가 직접 입력하는 방식은 제거
- status 노드는 map yaml 경로에서 Nav2 map과 같은 `map_id`를 추출해 앱에 전달
- launch/alias에서도 Nav2 map과 status map이 항상 같도록 구성
- 다양한 장소에서 주행해도 "현재위치"가 현재 실행 중인 지도를 기준으로 표시되게 함

관련 파일:

```text
ros2/vica_status_app_node.py
```

중요한 결정:

- `map_id` 직접 파라미터 입력은 헷갈리므로 제거하는 쪽으로 정리
- status 노드를 따로 실행하는 방식은 유지 가능
- 단, 실행 시 map yaml 경로는 필요

실행 예:

```bash
app_vica_status /home/ji_w/ros2_ws/maps/vica_map_0630.yaml
```

인자 없이 실행하면 사용법만 출력하고 종료된다.

```text
Usage: app_vica_status /home/ji_w/ros2_ws/maps/<map_id>.yaml
```

이는 정상 동작이다.

---

## 10. Nav2 미실행 상태 알림 문제

사용자가 앱에 필요한 서버, rosbridge, status, maplist, location 노드는 켜져 있고 Nav2만 꺼져 있는 상태에서 앱에 `no events recorded`가 너무 자주 뜬다고 했다.

검토 결과:

- Nav2/AMCL이 꺼져 있으면 `/amcl_pose`가 들어오지 않는다.
- status 노드는 현재 위치와 주행 이벤트를 정상적으로 만들 수 없다.
- 기존 앱 알림은 이 상태를 충분히 구분하지 못하고 이벤트 없음 메시지를 반복 표시할 수 있었다.

수정 방향:

- `/amcl_pose`가 최근 일정 시간 안에 들어오는지 보고 Nav2/AMCL 활성 여부 판단
- Nav2/AMCL이 꺼져 있으면 `waiting_reason`을 정확히 `Nav2/AMCL 미실행`으로 보냄
- 앱에서는 연결당 한 번만 다음 문구 표시

```text
Nav2가 실행되지 않아 현재 위치와 주행 이벤트를 받을 수 없습니다.
```

- 이후 Nav2/AMCL이 활성화되면 한 번만 다음 문구 표시

```text
Nav2가 실행되었습니다.
```

관련 파일:

```text
ros2/vica_status_app_node.py
lib/providers/supervisor_provider.dart
```

이때 사용자는 알림 UI 글씨가 너무 크고 굵다고 했고, 알림창의 글씨 크기와 굵기를 줄이는 UI 수정도 함께 요청했다.

관련 UI 파일:

```text
lib/widgets/vica_ui.dart
```

---

## 11. app_emergency_node의 Nav2 cancel 보완

Nav2가 꺼져 있을 때 앱 비상정지 reset 또는 취소 흐름에서 Nav2 cancel service가 없으면 노드가 불필요하게 멈출 수 있었다.

수정 방향:

- Nav2 cancel service가 없으면 "취소할 목적지가 없음"으로 처리
- 이 경우에도 앱 비상정지 reset 흐름이 완전히 막히지 않게 함
- 앱에는 Nav2 미실행 상태를 명확히 알림

관련 파일:

```text
ros2/app_emergency_node.py
```

---

## 12. 기준 커밋에 포함된 파일

화요일 오전 10:53에 사용자가 요청한 `VICA_Supervisor` git 업로드 시점의 커밋은 다음이다.

```text
393a22d refine nav2 status and yaw alignment
```

이 커밋에 포함된 파일:

```text
lib/core/app_settings.dart
lib/providers/supervisor_provider.dart
lib/widgets/vica_ui.dart
ros2/app_emergency_node.py
ros2/vica_goto_goal.py
ros2/vica_status_app_node.py
```

커밋 요약:

- Nav2/AMCL 미실행 상태 판단 보완
- 앱 알림 중복 억제 및 문구 정리
- 알림 UI 크기/굵기 조정
- app emergency reset/cancel 흐름 보완
- Nav2 goal 성공 후 yaw 재정렬 로직 추가
- map yaml 기반 status map_id 처리 보완

---

## 13. 기준 시점 이후와 혼동하지 말아야 할 것

기준 커밋 이후 사용자는 `ros2_ws_test2`에서 앱 비상정지와 물리 비상정지를 더 많이 디버깅했다.

이후에 나온 내용:

- `emergency_stop_node`를 앱 입력만 처리하도록 할지 여부
- `keyboard_knob`가 물리 F1 입력을 직접 받을지 여부
- `/estop_reset`과 `/safety_reset` 차이
- F1 data의 `08`, `28`, `48`, `68` 값 해석
- 물리 비상정지 버튼 배선 문제
- `ros2_ws_test`와 `ros2_ws_test2`의 safety 통합/분리 구조 비교
- 최종적으로 "앱 비상정지 코드를 끊고 다시 만들자"는 요청

이 내용들은 기준 커밋 `393a22d` 이후의 실험/디버깅이며, 이 문서의 기준 시점에는 포함하지 않는다.

다른 GPT가 보고서를 작성할 때는 `VICA_Supervisor` git 커밋 기준 작업과 이후 `ros2_ws_test2`의 실험적 변경을 분리해서 다루는 것이 좋다.

---

## 14. 인계받는 GPT가 확인하면 좋은 것

보고서 작성 또는 후속 작업 시 다음을 먼저 확인하면 된다.

```bash
cd /home/ji_w/VICA_Supervisor
git log --oneline -5
git show --stat 393a22d
```

그리고 기준 커밋의 핵심 파일을 확인한다.

```bash
sed -n '1,220p' ros2/vica_goto_goal.py
sed -n '1,220p' ros2/vica_status_app_node.py
sed -n '1,260p' ros2/app_emergency_node.py
sed -n '1,220p' lib/providers/supervisor_provider.dart
```

실제 앱에서 UI 변경까지 확인하려면 APK 재빌드가 필요하다.

ROS Python 노드만 확인하려면 APK 재빌드 없이 노드 재실행으로 충분하다.

