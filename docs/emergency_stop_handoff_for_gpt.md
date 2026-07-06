# VICA Supervisor 비상정지 기능 GPT 인계 문서

## 1. 문서 목적

이 문서는 VICA Supervisor 앱의 비상정지 기능을 설계하고 구현한 대화 흐름,
결정 이유, 현재 코드 상태, 실제 VICA 연결 시 확인할 내용을 다른 GPT에게
전달하기 위한 인계 문서다.

프로젝트 경로:

```text
C:\Users\myw\Desktop\VICA_APP\VICA_Supervisor
```

현재 변경사항은 작업 트리에 있으며 아직 실제 VICA의 `ros2_ws`에 배포하거나
실제 모터와 통합 시험하지 않았다.

---

## 2. 비상정지 기능을 만든 이유

기존 앱에는 `/robot_status`에서 받은 오류를 긴급 정지 로그와 상태 카드로
표시하는 기능만 있었다. 앱에서 로봇에 실제 정지 요청을 보내거나 현재 Nav2
목적지를 취소하는 통신 경로는 없었다.

이번 기능의 목표는 다음과 같다.

1. 모든 앱 화면에서 비상정지를 즉시 요청한다.
2. 앱의 정지 요청을 ROS2 노드가 받아 모터 속도 명령을 차단한다.
3. 현재 Nav2 목적지를 취소한다.
4. 정지를 해제해도 이전 목적지가 자동으로 재개되지 않게 한다.
5. ROS 연결이나 정지 노드가 응답하지 않을 때 재시도와 취소가 가능해야 한다.
6. 앱이 정지 상태를 명확하게 표시하고, 실제 활성 상태를 임의로 숨기지 않게 한다.

이 기능은 소프트웨어 기반 원격 정지다. 인증된 물리 비상정지 회로를
대체하지 않는다.

---

## 3. 노드 이름 결정

초기에는 `safety_node`, `vica_safety_node` 같은 이름을 검토했다.

최종 노드 이름:

```text
app_emergency_node
```

결정 이유:

- VICA에 존재하거나 앞으로 생성될 다른 safety 노드와 혼동하지 않기 위함
- 앱에서 요청하는 비상정지 전용 노드라는 역할을 드러내기 위함
- `safty`, `satfy` 같은 오타를 없애고 코드 전체에서 `emergency` 명칭을 통일

현재 구현 파일:

```text
ros2/app_emergency_node.py
```

---

## 4. 전체 제어 구조

```text
Nav2 및 다른 주행 명령 발행자
             |
             v
       /cmd_vel_raw
             |
             v
   app_emergency_node
      - 속도 명령 검사
      - 비상정지 차단
      - HOLD 차단
      - command timeout 처리
             |
             v
         /cmd_vel
             |
             v
       모터 드라이버
```

중요한 전제:

- Nav2 출력은 `/cmd_vel_raw`로 remap해야 한다.
- 모터 드라이버는 `app_emergency_node`의 `/cmd_vel`만 구독해야 한다.
- 다른 노드가 모터 드라이버에 직접 명령을 보내는 우회 경로가 없어야 한다.

---

## 5. 앱과 노드의 통신 계약

요청 topic:

```text
/safety/emergency_stop_request
```

상태 및 응답 topic:

```text
/safety/emergency_stop_state
```

메시지 타입:

```text
std_msgs/String JSON
```

요청 예시:

```json
{
  "request_id": "uuid",
  "command": "activate",
  "source": "vica_supervisor",
  "timestamp": "2026-07-06T12:00:00+09:00"
}
```

허용 command:

```text
activate
release
query
```

상태 응답 예시:

```json
{
  "node": "app_emergency_node",
  "request_id": "uuid",
  "command": "activate",
  "state": "active",
  "active": true,
  "motor_output_blocked": true,
  "motion_hold_active": true,
  "navigation_cancelled": true,
  "message": "비상정지가 활성화되었고 기존 목적지가 취소되었습니다.",
  "timestamp": "2026-07-06T03:00:00+00:00"
}
```

노드는 앱 재연결 시 상태를 복구할 수 있도록 상태 메시지를 주기적으로 발행한다.

---

## 6. 현재 상태 흐름

```text
NORMAL
  |
  | activate
  v
EMERGENCY_STOP
  |
  | Nav2 goal 취소 확인
  | release
  v
HOLD
  |
  | 해제 이후 생성된 새로운 Nav2 goal ID 확인
  v
NORMAL
```

### 6.1 비상정지 활성화

앱에서 `activate` 요청을 보내면 노드는 다음 순서로 처리한다.

1. `emergency_active = true`
2. `hold_active = true`
3. `navigation_cancelled = false`
4. `/cmd_vel`에 즉시 0 `Twist` 발행
5. 비상정지 중 제어 주기마다 0 `Twist` 반복 발행
6. `/navigate_to_pose/_action/cancel_goal`로 Nav2 goal 취소 요청
7. `/navigate_to_pose/_action/status`로 goal 상태 확인
8. 앱에 활성화 및 목적지 취소 상태 응답

### 6.2 비상정지 중 새 goal

비상정지 중 새로운 Nav2 goal ID가 들어오면 해당 ID를 차단 목록에 추가하고
다시 취소 요청한다. 비상정지 중 요청된 목적지가 해제 후 재개 조건으로
사용되지 않도록 하기 위함이다.

### 6.3 비상정지 해제

Nav2 목적지 취소가 확인되기 전에는 해제를 거부한다.

해제가 승인되면:

```text
emergency_active = false
hold_active = true
```

앱의 비상정지 팝업은 닫히지만 노드는 계속 `/cmd_vel_raw`를 차단하고
`/cmd_vel`에 0을 발행한다.

### 6.4 HOLD 해제

비상정지 해제 이후 생성된 새로운 Nav2 goal ID가 Action 상태에서 확인돼야
`hold_active = false`가 된다.

이전 goal과 비상정지 중 들어온 goal ID는 차단 목록에 들어 있으므로 HOLD
해제 조건으로 인정되지 않는다.

별도의 앱 `arm` 버튼은 만들지 않았다. 새로운 목적지를 지정하는 행동 자체가
자동으로 다시 주행을 허용하는 역할을 한다.

---

## 7. 취소 상태 최신성 보강

초기 구현에서는 비상정지 전에 받은 “활성 goal 없음” 상태가 취소 성공으로
잘못 재사용될 가능성이 있었다.

현재 구현은 다음과 같이 변경됐다.

1. 실제 `CancelGoal` 요청을 보내기 직전에 상태 수신 기록을 초기화한다.
2. 취소 요청 이후 수신한 Action 상태만 최신 상태로 인정한다.
3. 취소 서비스가 취소를 승인하거나, 취소 요청 이후 상태에서 활성 goal이
   없다고 확인돼야 `navigation_cancelled = true`가 된다.
4. 오래된 상태로 목적지 취소를 성공 처리하지 않는다.

관련 필드:

```text
_cancel_request_sent
_navigation_status_received
_cancel_response_received
_has_active_navigation_goal
_current_active_goal_ids
_blocked_goal_ids
```

---

## 8. 요청 payload 형식 검사

잘못된 JSON이나 잘못된 필드로 callback이 종료되는 것을 막기 위해
`validate_request()`를 추가했다.

검사 항목:

- payload가 JSON 객체인지 확인
- `request_id`가 비어 있지 않은 문자열인지 확인
- `request_id`가 128자를 넘지 않는지 확인
- `command`가 비어 있지 않은 문자열인지 확인
- command가 `activate`, `release`, `query` 중 하나인지 확인
- `source`, `timestamp`가 존재하면 문자열인지 확인

잘못된 요청은 노드 상태를 변경하지 않고 다음처럼 응답한다.

```json
{
  "state": "failed",
  "message": "검사 실패 이유"
}
```

추가 필드는 향후 확장을 위해 허용한다.

---

## 9. 속도 명령 검사

`app_emergency_node`는 `geometry_msgs/msg/Twist`를 받아 다음을 검사한다.

- NaN
- 무한대
- 최대 선속도
- 최대 각속도

기본 제한:

```text
max_linear_speed = 1.0
max_angular_speed = 2.0
```

안전하지 않은 명령은 모터로 전달하지 않고 0 속도를 발행한다.

입력 명령이 일정 시간 들어오지 않아도 0 속도를 발행한다.

```text
command_timeout_sec = 0.5
```

---

## 10. app_emergency_node 파라미터

```text
request_topic            /safety/emergency_stop_request
state_topic              /safety/emergency_stop_state
input_cmd_vel_topic      /cmd_vel_raw
output_cmd_vel_topic     /cmd_vel
navigate_action_name     /navigate_to_pose
control_period_sec       0.05
state_period_sec         1.0
command_timeout_sec      0.5
release_guard_sec        0.5
max_linear_speed         1.0
max_angular_speed        2.0
```

---

## 11. Flutter 설정 변경

수정 파일:

```text
lib/core/app_settings.dart
lib/screens/settings_screen.dart
```

추가 설정:

```dart
emergencyStopRequestTopic
emergencyStopStateTopic
emergencyStopTimeoutSeconds
```

기본값:

```text
/safety/emergency_stop_request
/safety/emergency_stop_state
2초
```

생성자, `copyWith()`, `toJson()`, `fromJson()`과 설정 UI에 모두 반영했다.

---

## 12. Flutter Provider 변경

수정 파일:

```text
lib/providers/supervisor_provider.dart
```

추가 상태:

```dart
inactive
activating
active
releasing
activationFailed
releaseFailed
```

주요 메서드:

```dart
activateEmergencyStop()
retryEmergencyStop()
dismissEmergencyStopFailure()
releaseEmergencyStop()
retryEmergencyStopRelease()
```

주요 동작:

- ROS Bridge 미연결 시 활성화 실패 처리
- 요청 후 설정 시간 내 응답이 없으면 timeout 실패
- 재시도 시 ROS Bridge 재연결 시도
- 활성화 실패 팝업에서 취소하고 앱으로 복귀 가능
- 취소 후 늦게 실제 활성화 응답이 오면 안전을 위해 팝업 재표시
- 재연결 후 `query`를 보내 현재 정지 상태 복구
- 비상정지 관련 요청과 실패를 기존 긴급 정지 로그에 기록

---

## 13. 비상정지 UI 변경

수정 파일:

```text
lib/app.dart
```

모든 화면의 AppBar에 비상정지 버튼을 표시한다.

최종 버튼 형태:

- 홈 버튼 왼쪽
- 홈 버튼과 16px 간격
- 빨간 원 크기 34px
- 내부 경고 아이콘 19px
- 아이콘은 `Center`를 사용해 원 중앙 배치

팝업 차단 방식:

```text
ModalBarrier
PopScope
```

비상정지 처리 중에는:

- 현재 화면 버튼 조작 불가
- AppBar 버튼 조작 불가
- 팝업 바깥 터치로 닫기 불가
- Android 뒤로 가기로 닫기 불가

상태별 화면:

```text
비상정지 요청 중
비상정지 활성화
비상정지 해제 중
비상정지 활성화 실패
비상정지 해제 실패
```

활성화 실패 시:

```text
비상정지 다시 시도
취소하고 돌아가기
```

실제 비상정지가 활성화된 경우에는 임의로 팝업을 숨길 수 없고
`비상정지 해제`가 성공해야 닫힌다.

---

## 14. 기존 ROS2 보조 노드 변경

### ros2/vica_goto_goal.py

기존에는 Nav2 결과가 성공이 아니면 모두 `goal_failed`로 처리했다.

현재는 다음 상태를 별도로 처리한다.

```text
GoalStatus.STATUS_CANCELED
```

발행 이벤트:

```text
goal_canceled
```

### ros2/vica_status_app_node.py

다음 이벤트가 들어오면 현재 목적지와 `navigation_active`를 초기화한다.

```text
goal_succeeded
goal_failed
goal_rejected
goal_canceled
emergency_stopped
```

---

## 15. 함께 수정한 일반 UI 문제

### 긴 지도 이름

수정 파일:

```text
lib/screens/save_location_screen.dart
lib/screens/map_locations_screen.dart
```

적용 내용:

- 드롭다운 바에서 선택된 이름은 한 줄로 표시
- 넘치는 이름은 `...` 처리
- 펼친 목록에서는 전체 이름을 여러 줄로 표시
- `isExpanded: true`
- `itemHeight: null`
- `selectedItemBuilder` 사용

### 장소 저장 입력값 초기화

장소를 임시 저장한 뒤 다음 값을 초기화한다.

```text
장소명
카테고리
메모
선택 좌표
방향
```

저장된 장소 요약과 지도 마커는 유지한다.

---

## 16. 실제 VICA ros2_ws 배포 방법

현재 노드 파일은 Flutter 저장소 안의 배포 원본이다.

실제 VICA에서는 예를 들어 다음 Python 패키지에 넣는다.

```text
~/ros2_ws/src/vica_app_nodes/
├── package.xml
├── setup.py
└── vica_app_nodes/
    ├── __init__.py
    └── app_emergency_node.py
```

`setup.py` entry point:

```python
"app_emergency_node = vica_app_nodes.app_emergency_node:main"
```

필요 의존성:

```xml
<exec_depend>rclpy</exec_depend>
<exec_depend>std_msgs</exec_depend>
<exec_depend>geometry_msgs</exec_depend>
<exec_depend>action_msgs</exec_depend>
```

빌드와 실행:

```bash
cd ~/ros2_ws
colcon build --packages-select vica_app_nodes
source install/setup.bash
ros2 run vica_app_nodes app_emergency_node
```

---

## 17. 실제 연결 전 확인

```bash
ros2 node list
ros2 node info /app_emergency_node
ros2 topic info -v /cmd_vel_raw
ros2 topic info -v /cmd_vel
ros2 action info /navigate_to_pose
ros2 topic echo /safety/emergency_stop_state
```

반드시 확인할 내용:

1. `/app_emergency_node`가 한 개만 실행되는지 확인
2. Nav2 출력이 `/cmd_vel_raw`인지 확인
3. 모든 주행 명령이 비상정지 노드를 통과하는지 확인
4. 모터 드라이버가 `/cmd_vel`만 구독하는지 확인
5. 실제 속도 타입이 `geometry_msgs/msg/Twist`인지 확인
6. VICA가 `TwistStamped`를 사용하면 노드 수정
7. `/navigate_to_pose/_action/status`와 cancel 서비스 확인
8. 앱과 VICA의 ROS Domain ID 확인
9. rosbridge가 요청 및 상태 topic을 전달하는지 확인
10. 앱과 VICA의 네트워크 연결 확인

---

## 18. 실제 시험 순서

최초 시험은 바퀴를 띄우거나 모터 동력을 분리한 상태에서 진행한다.

1. rosbridge와 `app_emergency_node` 실행
2. 앱에서 ROS 연결
3. 정지 상태에서 비상정지 버튼 클릭
4. `active: true` 확인
5. 비상정지 중 `/cmd_vel_raw`에 속도 발행
6. `/cmd_vel`이 계속 0인지 확인
7. Nav2 주행 중 비상정지 실행
8. 기존 goal이 canceled 되는지 확인
9. 비상정지 해제
10. `active: false`, `motion_hold_active: true` 확인
11. 기존 목적지가 다시 시작되지 않는지 확인
12. HOLD 중 `/cmd_vel`이 계속 0인지 확인
13. 새로운 목적지 발행
14. 새 goal ID 확인 후 `motion_hold_active: false` 확인
15. 새 목적지로 정상 주행하는지 확인
16. 노드를 종료하고 앱 실패 및 재시도 팝업 확인
17. rosbridge를 끊고 실패, 재연결, 취소 흐름 확인
18. 배열 payload, 빈 `request_id`, 잘못된 `command` 전송
19. 노드가 종료되지 않고 `state: failed`를 발행하는지 확인

---

## 19. 의도적으로 보류한 항목

### stop_id

아직 구현하지 않았다.

추가가 필요한 상황:

- 여러 앱이나 운영자가 정지와 해제를 요청할 때
- 재연결 및 재시도가 자주 발생할 때
- 이전 release 메시지가 늦게 도착할 가능성이 있을 때

목적:

```text
이전 release 요청이 새로운 비상정지를 잘못 해제하는 문제 방지
```

구현한다면 활성화 시 `stop_id`를 생성하고 같은 `stop_id`를 포함한 release만
허용해야 한다.

### 모터 드라이버 watchdog/deadman

아직 구현하지 않았다. 이것은 앱 노드가 아니라 모터 드라이버 또는 더 낮은
제어 계층에 구현해야 한다.

목적:

```text
app_emergency_node가 종료되거나 ROS 통신이 끊겨도
모터가 마지막 속도 명령을 계속 실행하지 않게 함
```

실제 사람이나 장비 주변에서 동력 시험하기 전에 추가하는 것을 강하게 권장한다.

### 기타 성능 및 안정성 후보

아직 적용하지 않았다.

- 제어 callback에서 반복 조회하는 파라미터 캐시
- 정지용 `Twist()` 메시지 재사용
- 안전하지 않은 명령 오류 로그 주기 제한
- watchdog 시간에 steady/monotonic clock 사용
- 입력 topic과 출력 topic이 같으면 실행 거부
- Action 상태용 QoS 명시
- 상태 publisher에 적절한 QoS 적용

현재 노드의 연산량은 작아서 성능 병목보다 실제 안전 동작 검증이 우선이다.

---

## 20. 검증 상태

완료:

```text
flutter analyze --no-pub
→ No issues found

Dart format
→ 완료

Python 문법 compile 검사
→ Python syntax OK

git diff --check
→ 공백 오류 없음
```

아직 하지 않은 것:

```text
실제 VICA ros2_ws 설치
실제 rosbridge 연결
실제 Nav2 goal 취소 시험
실제 모터 정지 시험
Twist 또는 TwistStamped 현장 확인
```

---

## 21. 관련 파일

```text
docs/emergency_stop_handoff_for_gpt.md
docs/ros2_topic_contract.md
docs/app_emergency_node_setup.md
ros2/app_emergency_node.py
ros2/vica_goto_goal.py
ros2/vica_status_app_node.py
lib/app.dart
lib/core/app_settings.dart
lib/providers/supervisor_provider.dart
lib/screens/settings_screen.dart
lib/screens/save_location_screen.dart
lib/screens/map_locations_screen.dart
```
