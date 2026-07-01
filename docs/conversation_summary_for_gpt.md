# VICA Supervisor 개발 대화 정리본

이 문서는 VICA Supervisor Flutter 앱과 ROS2/Nav2 연동 작업을 진행하며 나눈 대화를, 이후 다른 GPT에게 전달해 전체 프로젝트 정리본을 만들 수 있도록 흐름 중심으로 재구성한 것이다.

중복되는 질문과 답변은 합쳐서 정리했고, 사용자가 질문한 순서와 실제 구현 흐름을 최대한 반영했다.

---

## 1. 초기 요청: VICA 관리자용 Flutter 앱 개발

### 사용자 요청

사용자는 기존 코드베이스 없이 새 Flutter 프로젝트 기준으로 `VICA_Supervisor` 앱을 만들고 싶다고 했다.

목표는 Jetson에서 ROS2/Nav2가 실행 중인 VICA 로봇을 같은 네트워크의 Android 기기에서 관리하는 앱이었다.

핵심 요구사항은 다음과 같았다.

- 앱 이름: `VICA_Supervisor`
- 기존 VICA ROS2 코드나 변수명은 임의로 수정하지 않기
- Flutter 프로젝트는 `ros2_ws`와 분리
- Android 에뮬레이터 관련 설명은 넣지 않기
- 앱은 ROS graph 전체를 탐색하지 않고 필요한 topic/service만 최소한 사용
- nav2 내부 action 전체를 앱에서 직접 연결하지 않기
- `/tf` 전체를 앱에서 구독하지 않기
- 지도 확인, 장소 저장, 현재 위치 확인, 로봇 상태 확인 기능 제공
- 앱 아이콘 설정을 위해 `flutter_launcher_icons` 구성 포함

처음 제안된 기능은 다음과 같았다.

- 대시보드
- 지도별 장소 보기
- 장소 저장
- 현재 위치
- 로봇 관리
- 알림 및 로그
- 설정

ROS2 topic 후보는 다음과 같았다.

```text
/map_list_request
/map_list
/location_list_request
/location_list
/save_location
/delete_location_request
/robot_status
```

`/robot_status`는 `std_msgs/String` JSON 형식을 우선 사용하기로 했다.

---

## 2. Git 작업 및 Flutter 프로젝트 생성 방향

### 사용자 요청

초기에는 현재 VICA 변경사항을 `main`이 아닌 `dev`에 올려달라는 요청이 있었다. 이후 별도의 Flutter 프로젝트 `VICA_Supervisor`를 GitHub 저장소 `myw411/VICA_Supervisor`에 올리는 흐름으로 진행했다.

### 결정 및 답변

Flutter 프로젝트는 `~/VICA_Supervisor`에 생성하고, ROS2 작업공간 `~/ros2_ws`와 분리했다.

위치 저장은 다음 구조를 사용하기로 했다.

```text
~/ros2_ws/location/<map_id>/locations.json
```

지도 이미지는 다음 위치에서 제공하기로 했다.

```text
~/ros2_ws/maps/<지도 이미지 이름>.png
```

GitHub remote는 다음 저장소로 설정했다.

```text
git@github.com:myw411/VICA_Supervisor.git
```

주요 커밋:

```text
앱UI변경_2
vica_status 노드, vica_goto_goal 노드 생성
세부사항 수정1
```

---

## 3. Flutter/Dart 설치 및 실행 환경 확인

### 사용자 질문

Flutter/Dart 명령이 설치되어 있지 않아 `flutter pub get`, `flutter analyze`, 앱 실행 검증을 하지 못한다는 메시지를 보고, Flutter를 어떻게 설치해야 하는지 질문했다.

Android SDK command-line tools를 왜 설치해야 하는지도 물었다.

### 답변 요지

Flutter CLI는 앱 의존성 설치, 분석, 빌드, 실행에 필요하다.

Android SDK command-line tools는 Android APK 빌드와 라이선스 수락, build-tools/platform-tools 설치에 필요하다고 설명했다.

다만 사용자는 당장 APK 빌드가 목적이 아니었으므로 `flutter build apk --debug`는 APK 생성 명령이며, 지금 당장 필요하지 않다고 설명했다.

---

## 4. Jetson에서 Flutter/Android 도구 문제 분석

### 사용자 상황

Jetson에서 `flutter doctor -v`를 실행한 결과:

- Flutter 자체는 설치됨
- Android SDK 버전 문제 발생
- `adb` 실행 중 `Syntax error: "(" unexpected`
- Chrome 없음
- connected device check crash

### 답변 요지

Jetson은 ARM64 환경이므로 Android SDK의 일부 platform-tools 또는 adb 바이너리 호환 문제가 발생할 수 있다고 설명했다.

실제 Android APK 빌드는 x86-64 PC에서 하는 것이 안정적이라고 설명했다.

권장 흐름:

```text
Jetson에서 코드 작성
→ GitHub에 push
→ x86-64 PC에서 clone
→ APK build
→ Android 폰에 설치
→ Jetson ROS2/rosbridge와 연결
```

Jetson에서 adb만 살릴 수도 있지만 Android build/test 전체 환경으로 쓰기에는 제약이 많고, 나중에 build-tools, platform-tools, Gradle, native binary 호환 문제로 계속 막힐 가능성이 있다고 설명했다.

---

## 5. UI 디버깅: Chrome, Firefox, Linux Desktop

### 사용자 질문

Chromium이 제대로 동작하지 않는 것 같고, Firefox로 Flutter 앱을 띄울 수 있는지 질문했다.

### 답변 요지

Flutter web은 공식적으로 Chrome 중심이지만, 다음 방식으로 web-server를 띄운 뒤 Firefox에서 접속해 UI를 확인할 수 있다고 설명했다.

```bash
cd ~/VICA_Supervisor
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
firefox http://127.0.0.1:8080
```

단, 이 방식은 브라우저 환경이라 WebSocket/HTTP/CORS/네트워크 처리 차이로 실제 Android 앱과 완전히 같지는 않을 수 있다고 설명했다.

이후 사용자는 Firefox 우회보다 Linux desktop 실행으로 방향을 바꿨다.

```bash
cd ~/VICA_Supervisor
flutter create --platforms=linux .
flutter pub get
flutter run -d linux
```

Linux desktop 앱 실행 시 한글이 깨지는 문제도 있었고, 이 경우 폰트/locale/Flutter Linux 환경의 영향을 받을 수 있다고 설명했다.

결국 UI 확인은 Linux desktop으로 진행하고, 실제 Android 동작은 APK 설치로 확인하는 방향이 되었다.

---

## 6. APK 생성 및 실제 Android 기기 테스트

### 사용자 질문

Jetson에서 APK 생성이 어렵다면 다른 PC에서 APK를 만들고 Android 폰에서 설치 후 VICA와 연결하는 것이 맞는지 질문했다.

### 답변 요지

맞다고 설명했다.

흐름:

```text
1. Jetson에서 코드 작성
2. GitHub에 push
3. x86-64 PC에서 clone
4. flutter pub get
5. flutter build apk --debug 또는 --release
6. APK를 Android 폰에 설치
7. 앱 설정에서 Jetson IP로 rosbridge/map server 주소 설정
```

Android 앱 설정 예시:

```text
ROS Bridge 주소: ws://<Jetson_IP>:9090
지도 이미지 URL: http://<Jetson_IP>:8000
```

Android에서 HTTP/ws를 사용하기 위해 `AndroidManifest.xml`에 다음 설정도 반영했다.

```xml
android.permission.INTERNET
android:usesCleartextTraffic="true"
```

---

## 7. 네트워크 연결 문제와 해결

### 사용자 상황

폰 브라우저에서 Jetson의 HTTP 지도 서버 주소에 접속되지 않았지만, Jetson 브라우저에서는 접속되었다.

`ufw`는 설치되어 있지 않았다.

### 답변 및 해결

방화벽보다 공유기에서 기기간 통신을 막는 AP isolation/client isolation 가능성이 크다고 설명했다.

사용자는 공유기 기기간 통신 차단 문제임을 확인하고, 핫스팟으로 연결하자 ROS 연결, 지도, 장소 동기화가 모두 정상 동작한다고 밝혔다.

확인된 Jetson IP 예:

```text
192.168.123.110
192.168.123.90
```

앱 설정은 실제 실행 시 Jetson IP에 맞게 변경해야 한다.

---

## 8. 앱 실행에 필요한 보조 서버 및 alias

### 사용자 질문

앱 실행 시 지도 이미지 서버, rosbridge, 지도 목록 노드, 위치 저장 노드를 매번 4개 터미널에서 실행하는 것이 번거롭다며 alias 설정 가능 여부를 물었다.

### 답변 및 구현

가능하다고 설명했고, `.bashrc`에 다음 alias를 추가했다.

```bash
alias app_mapserver='cd ~/ros2_ws && python3 -m http.server 8000 --bind 0.0.0.0'
alias app_rosbridge='source /opt/ros/humble/setup.bash && export ROS_DOMAIN_ID=7 && export ROS_LOCALHOST_ONLY=0 && export RMW_IMPLEMENTATION=rmw_fastrtps_cpp && ros2 launch rosbridge_server rosbridge_websocket_launch.xml address:=0.0.0.0 port:=9090'
alias app_maplist='source /opt/ros/humble/setup.bash && export ROS_DOMAIN_ID=7 && export ROS_LOCALHOST_ONLY=0 && export RMW_IMPLEMENTATION=rmw_fastrtps_cpp && python3 ~/VICA_Supervisor/ros2/map_list_node.py'
alias app_location='source /opt/ros/humble/setup.bash && export ROS_DOMAIN_ID=7 && export ROS_LOCALHOST_ONLY=0 && export RMW_IMPLEMENTATION=rmw_fastrtps_cpp && python3 ~/VICA_Supervisor/ros2/location_storage_node.py'
alias app_vica_status='source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && export ROS_DOMAIN_ID=7 && export ROS_LOCALHOST_ONLY=0 && export RMW_IMPLEMENTATION=rmw_fastrtps_cpp && python3 ~/VICA_Supervisor/ros2/vica_status_app_node.py'
```

사용자가 요청한 대로 기존 `.bashrc`의 다른 코드는 건드리지 않고 주석 블록으로 구분했다.

이후 저장 좌표 주행용 alias도 별도 섹션으로 추가했다.

```bash
alias vica_goto='source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && export ROS_DOMAIN_ID=7 && export ROS_LOCALHOST_ONLY=0 && export RMW_IMPLEMENTATION=rmw_fastrtps_cpp && python3 ~/VICA_Supervisor/ros2/vica_goto_goal.py'
```

사용 예:

```bash
vica_goto vica_map_0604 room1
vica_goto vica_map_0604 입구
```

---

## 9. 초기 Flutter 앱 및 ROS2 보조 노드 구성

### 생성된 주요 ROS2 보조 노드

#### map_list_node.py

파일:

```text
~/VICA_Supervisor/ros2/map_list_node.py
```

역할:

```text
~/ros2_ws/maps/*.png 지도 목록을 읽어 앱에 제공
같은 이름의 .yaml에서 resolution/origin 읽기
```

토픽:

```text
구독: /map_list_request
발행: /map_list
```

#### location_storage_node.py

파일:

```text
~/VICA_Supervisor/ros2/location_storage_node.py
```

역할:

```text
앱에서 저장/삭제한 장소 좌표를 ~/ros2_ws/location/<map_id>/locations.json에 저장
지도별 장소 목록을 앱에 제공
```

토픽:

```text
구독: /save_location
구독: /location_list_request
구독: /delete_location_request
발행: /location_list
```

장소 저장 방식은 지도 하나당 `locations.json` 파일 하나에 여러 장소를 저장하는 방식이다.

사용자는 각 장소마다 파일을 나누는 방식과 비교했을 때 어떤 방식이 더 나은지 질문했다.

답변:

- 지금처럼 지도 하나당 하나의 JSON 파일이 더 단순하고 효율적
- 장소 수가 아주 많지 않으면 관리가 쉽고 동기화도 간단함
- 장소별 파일 분리는 파일 수가 많아지고 삭제/동기화가 복잡해짐

사용자는 현재 방식을 유지하기로 결정했다.

---

## 10. UI 전체 재구성 및 기능 수정

### 사용자 요청

사용자는 여러 장의 참고 스크린샷을 보여주며 앱 UI를 새롭게 구성해달라고 요청했다.

주요 수정 사항:

- 대시보드 카드형 UI
- 지도별 장소 보기 화면
- 장소 저장 화면
- 로봇 관리 화면
- 알림 및 로그 화면
- 설정 화면
- 메뉴 순서 변경
- 상단 오른쪽 아이콘 변경
- 지도 마커/선택 마커/로봇 마커 표시 방식 개선

### 구현 요약

#### 상단 아이콘

기존 종 아이콘 대신 모든 화면 우측 상단에 다음 아이콘을 배치했다.

```text
홈 아이콘 → 대시보드
지도 아이콘 → 지도별 장소 보기
설정 아이콘 → 설정
```

설정 아이콘은 맨 오른쪽에 위치하도록 수정했다.

#### 메뉴 순서

좌측 메뉴에서 `장소 저장`이 `지도별 장소 보기`보다 위로 오도록 변경했다.

#### 장소 저장 화면

초기에는 장소 정보 패널이 화면 아래 카드로 있었으나, 이후 지도 클릭 시 팝업처럼 뜨는 bottom sheet 형태로 변경했다.

장소 정보 패널은 다음 동작을 한다.

```text
지도 클릭
→ 선택 위치에 점 표시
→ 장소 정보 패널 팝업
→ 임시 저장 또는 취소 시 닫힘
→ 임시 저장한 내용은 저장 장소 카드 아래 표시
→ ROS2에 장소 저장 버튼으로 실제 저장
```

카테고리는 직접 입력 가능하면서도 기본 카테고리 선택이 가능하게 했다.

기본 카테고리:

```text
방
화장실
안내소
입출구
엘리베이터
에스컬레이터
```

#### 지도 마커

수정 사항:

- 저장된 장소 점 크기 축소
- 임시 선택 위치 표시
- 선택된 장소는 점이 커지는 대신 작은 물방울 모양 위치 아이콘으로 표시
- 아이콘 위에 장소명 표시
- 지도별 장소 보기, 장소 저장, 현재 위치 등 지도 표시 화면에 동일 적용

#### 로봇 관리

로봇 카드 클릭 시 상세 정보가 bottom sheet 형태로 표시되도록 변경했다.

카드 클릭 시 최신 상태를 한 번 반영하도록 했다.

#### 대시보드

대시보드의 `전체 로봇`, `운행 중`, `대기 중`, `오류/긴급 정지` 카드가 작은 모바일 화면에서 잘리지 않도록 조정했다.

최종 수정:

```text
전체 로봇 → 전체\n로봇
오류/긴급 정지 → 오류\n긴급 정지
```

오류 카드만 별도 작은 글자 크기를 사용했다.

---

## 11. 드롭다운 UI 조정

### 사용자 요청

장소 저장, 지도별 장소 보기, 현재 위치 메뉴의 드롭다운바가 너무 두꺼워서 약 3/5 높이로 줄여달라고 요청했다.

### 구현

각 화면의 `DropdownButtonFormField`에 compact decoration을 적용했다.

적용 화면:

```text
lib/screens/save_location_screen.dart
lib/screens/map_locations_screen.dart
lib/screens/current_location_screen.dart
```

적용 코드 형태:

```dart
isDense: true,
contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 9)
```

---

## 12. 지도 이미지 및 RViz 지도 표시 문제

### 사용자 질문

RViz2에서 지도가 뜨지 않는데 Cartographer도 켜야 하는지 질문했다.

### 확인 결과

`vica_map_0604.yaml`의 image 경로가 실제 존재하지 않는 파일을 가리키고 있었다.

문제 예:

```yaml
image: vica_cartographer_map_20260604_204712.pgm
```

실제 존재 파일:

```text
vica_map_0604.pgm
vica_map_0604.png
vica_map_0604.yaml
```

답변:

저장된 지도로 Nav2 주행/RViz 확인을 할 때는 Cartographer가 필요하지 않다.

필요한 것은 `map_server`가 올바른 YAML/PGM을 읽는 것이다.

Cartographer는 새 지도를 만들거나 SLAM 모드로 동작할 때 필요하다.

RViz 설정:

```text
Fixed Frame: map
Map Topic: /map
Map QoS Durability: Transient Local
```

초기 위치는 RViz2의 `2D Pose Estimate`로 잡을 수 있다.

---

## 13. 현재 위치와 로봇 마커 보정

### 사용자 문제 제기

앱 지도에서 실제 도착 위치와 VICA 현재 위치 표시가 맞지 않았고, 주행 중 화살표가 벽에 붙어 움직이거나 방향이 맞지 않았다.

정지 시 VICA는 map의 +x축, 즉 오른쪽 벽을 바라보고 있는데 앱 화살표는 90도 정도 틀어져 보였다.

### 원인 분석

처음 `vica_status_app_node`는 `/odom` 좌표를 사용해 앱에 현재 위치를 보냈다.

하지만 앱 지도와 Nav2/RViz 기준 위치는 `map` frame 기준이어야 하므로 `/amcl_pose`를 사용해야 했다.

또한 ROS yaw 좌표계와 Flutter 화면 좌표계는 y축 방향이 달라 회전 방향 보정이 필요했다.

### 수정

`vica_status_app_node.py`:

```text
/amcl_pose를 구독
현재 위치 x, y, yaw는 /amcl_pose를 우선 사용
/odom은 속도 판단용으로 유지
```

`map_canvas.dart`:

```dart
yaw: 90 - robot!.yaw + settings.yawOffset
```

이렇게 수정했다.

로봇 마커 크기도 줄였다.

```dart
const markerSize = 9.0;
```

---

## 14. vica_status_app_node 생성 및 상태 처리

### 사용자 질문

로봇 상태를 앱에서 받아오려면 새 노드가 필요한지 질문했다.

### 답변

앱이 `/odom`, `/amcl_pose`, `/diagnostics`, Nav2 상태 등을 직접 모두 구독하는 것보다, ROS2 쪽에서 앱용 상태 요약 노드를 만드는 것이 좋다고 설명했다.

### 생성된 노드

파일:

```text
~/VICA_Supervisor/ros2/vica_status_app_node.py
```

노드명:

```text
vica_status_app_node
```

역할:

```text
VICA 내부 ROS2 상태를 앱이 쓰기 쉬운 /robot_status JSON으로 요약
```

구독 토픽:

```text
/odom
/amcl_pose
/diagnostics
/vica_goal_event
```

발행 토픽:

```text
/robot_status
```

`/robot_status` 예:

```json
{
  "robot_id": "vica_01",
  "robot_name": "VICA-01",
  "status": "moving",
  "x": 2.75,
  "y": 5.14,
  "yaw": 85.32,
  "current_location": "현재 위치 확인 중",
  "current_goal": "toilet",
  "error_reason": "",
  "waiting_reason": "",
  "map_id": "vica_map_0604",
  "timestamp": "2026-06-25T11:40:25"
}
```

### 상태 판단 개선

초기에는 `/odom.twist` 속도만 보고 `moving/waiting`을 판단했다.

문제:

```text
주행 중에도 속도가 잠깐 0에 가까워지면 waiting으로 튐
```

개선:

`vica_goto_goal`에서 발행하는 `/vica_goal_event`를 함께 사용한다.

```text
goal_sent 또는 goal_accepted → navigation_active = True → moving 유지
goal_succeeded, goal_failed, goal_rejected → navigation_active = False
```

사용자는 토픽을 너무 많이 받는 것이 아닌지 질문했다.

답변:

현재 4개 토픽은 모두 저부하이고 역할이 분명하므로 유지해도 무리가 없다고 설명했다.

```text
/amcl_pose        현재 위치
/odom             속도 기반 moving 보조 판단
/vica_goal_event  목적지/주행 이벤트
/diagnostics      오류 사유 후보
```

사용자는 일단 4개를 유지하기로 했다.

---

## 15. 저장 좌표 기반 주행: vica_goto_goal 노드

### 사용자 요구

앱에서 목적지를 지정하는 것이 아니라, Jetson/VICA 쪽에서 이미 저장된 좌표값을 지정해 Nav2로 주행시키고 싶다고 했다.

향후에는 음성 인식과 LLM이 사용자의 의도를 파악하여 미리 DB에 저장된 목적지를 찾아 Nav2로 주행할 계획이라고 설명했다.

지금은 터미널에 목적지 이름을 입력하면 해당 저장 좌표로 주행하도록 만들기로 했다.

### 생성된 노드

파일:

```text
~/VICA_Supervisor/ros2/vica_goto_goal.py
```

노드명:

```text
vica_goto_goal
```

역할:

```text
map_id와 목적지 이름을 받아
~/ros2_ws/location/<map_id>/locations.json에서 장소 검색
찾은 x, y, yaw를 Nav2 /navigate_to_pose action goal로 전송
```

실행:

```bash
vica_goto vica_map_0604 room1
vica_goto vica_map_0604 입구
```

직접 실행:

```bash
python3 ~/VICA_Supervisor/ros2/vica_goto_goal.py vica_map_0604 room1
```

Dry-run:

```bash
python3 ~/VICA_Supervisor/ros2/vica_goto_goal.py vica_map_0604 room1 --dry-run
```

발행 토픽:

```text
/vica_destination_request
/vica_goal_event
```

사용 action:

```text
/navigate_to_pose
nav2_msgs/action/NavigateToPose
```

목적지 검색 함수와 Nav2 goal 전송 함수는 분리해 향후 LLM 연동 시 재사용할 수 있도록 구성했다.

---

## 16. RViz2, 초기 위치, Nav2 주행

### 사용자 질문

Nav2만 실행하고 RViz2를 실행하지 않은 상태에서 `vica_goto_goal`을 실행하니 goal rejected가 발생했다.

```text
Nav2 goal was rejected
```

RViz2에서 초기 위치를 잡지 않아서 그런 것인지 질문했다.

### 답변

가능성이 매우 크다고 설명했다.

RViz2 자체가 필요한 것은 아니지만, AMCL이 map 기준 현재 위치를 알아야 Nav2가 주행할 수 있다.

RViz2의 `2D Pose Estimate`는 `/initialpose`를 발행하여 AMCL 초기 위치를 설정한다.

즉:

```text
RViz2가 없어서 문제가 아니라
초기 위치가 안 잡혀서 문제가 될 수 있음
```

RViz2는 초기 위치만 잡고 꺼도 된다고 설명했다.

조건:

```text
/amcl_pose가 계속 나옴
map -> base_link TF가 정상
Nav2 lifecycle 노드들이 active
```

확인 명령:

```bash
ros2 topic echo /amcl_pose --once
ros2 run tf2_ros tf2_echo map base_link
ros2 lifecycle get /bt_navigator
```

---

## 17. yaw 저장 방식 변경

### 사용자 질문

장소 저장 시 yaw 기본값 `0`은 지도상 오른쪽을 의미하는지 질문했다.

### 답변

ROS/Nav2 기준으로:

```text
yaw = 0도     → +x 방향, 지도 오른쪽
yaw = 90도    → +y 방향, 지도 위쪽
yaw = 180도   → -x 방향, 지도 왼쪽
yaw = 270도   → -y 방향, 지도 아래쪽
```

사용자는 숫자 yaw 입력 대신 직관적인 방향 드롭다운으로 변경하기를 원했다.

### 최종 구현

장소 저장 화면의 yaw 숫자 입력칸을 방향 드롭다운으로 변경했다.

옵션:

```text
앞
뒤
우측
좌측
```

저장 시 변환:

```text
우측 → 0도
앞   → 90도
좌측 → 180도
뒤   → 270도
```

저장 파일에는 기존처럼 숫자 yaw만 저장한다.

```json
{
  "yaw": 180.0
}
```

따라서 `vica_goto_goal.py`와 Nav2 goal 전송 로직은 기존 구조를 그대로 유지한다.

---

## 18. 앱 지도 로딩 문제 분석

### 사용자 질문

앱과 연결했는데 지도를 불러오지 못한다며 `map_list_node`에서 막힌 것인지 질문했다.

### 확인 결과

`map_list_node` 자체는 정상 동작했다.

직접 `/map_list_request`를 보내면 `/map_list`가 응답했다.

HTTP 지도 서버도 정상:

```text
http://127.0.0.1:8000/maps/vica_map_0604.png
```

문제는 앱이 `/map_list_request` publisher로 붙지 않거나 `/map_list` subscriber로 붙지 않는 경우였다.

가능한 원인:

```text
Flutter 앱과 rosbridge 연결 꼬임
앱 저장 설정 주소 문제
rosbridge 재연결 실패
```

권장 조치:

```text
앱 종료 후 재실행
app_rosbridge 재실행
app_maplist 재실행
앱 설정에서 ROS Bridge 주소와 지도 URL 확인
```

Linux 앱 기준:

```text
ROS Bridge 주소: ws://127.0.0.1:9090
지도 이미지 URL: http://127.0.0.1:8000
```

Android 앱 기준:

```text
ROS Bridge 주소: ws://<Jetson_IP>:9090
지도 이미지 URL: http://<Jetson_IP>:8000
```

---

## 19. 현재 노드 및 토픽 최종 정리

### 앱 연동 노드

```text
vica_supervisor_map_list
vica_supervisor_location_storage
vica_status_app_node
vica_goto_goal
```

### 지도 관련

```text
/map_list_request
/map_list
```

### 장소 관련

```text
/location_list_request
/location_list
/save_location
/delete_location_request
```

### 상태 관련

```text
/robot_status
/odom
/amcl_pose
/diagnostics
/vica_goal_event
```

### 주행 관련

```text
/vica_destination_request
/vica_goal_event
/navigate_to_pose
```

---

## 20. 향후 LLM/음성 연동 방향

향후 VICA는 사용자의 음성을 인식하고, LLM이 사용자의 의도를 분석하여 미리 저장된 목적지를 찾아 주행하게 될 예정이다.

예상 구조:

```text
사용자 음성
  ↓
STT
  ↓
LLM 의도 분석
  ↓
목적지 이름 추출
  ↓
저장된 장소 DB 검색
  ↓
vica_goto_goal 구조 재사용
  ↓
Nav2 /navigate_to_pose action
  ↓
VICA 주행
```

현재 `vica_goto_goal.py`는 이 흐름의 핵심이 될 수 있도록 목적지 검색 함수와 Nav2 goal 전송 함수를 분리해 두었다.

나중에는 터미널 인자 대신 LLM 노드가 목적지 요청을 보내는 구조로 확장할 수 있다.

---

## 21. 현재 Git 상태 기록

주요 푸시된 커밋:

```text
앱UI변경_2
vica_status 노드, vica_goto_goal 노드 생성
세부사항 수정1
```

`세부사항 수정1` 커밋 설명:

```text
UI부분, yaw값 저장 부분, vica_status 노드에서 받는 토픽 조정 등
```

현재 저장소:

```text
git@github.com:myw411/VICA_Supervisor.git
```

브랜치:

```text
main
```

---

## 22. 현재 남은 보완 후보

현재 작동은 확인되었지만 추후 보완할 수 있는 항목:

- Nav2 주행 중 비틀거림 개선
- 장애물 인지 문제 보완
- 초기 위치 자동 설정 방식 검토
- RViz 없이 AMCL 초기 pose를 주는 도구 또는 노드 검토
- LLM/음성 노드와 `vica_goto_goal` 연동
- `/diagnostics` 기반 오류 메시지 정교화
- 앱에서 주행 목적지 요청까지 직접 다룰지 여부 결정
- 지도 PNG와 Nav2 PGM/YAML 좌표계가 항상 일치하도록 관리 도구화

