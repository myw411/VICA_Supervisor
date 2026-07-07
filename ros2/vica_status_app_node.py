#!/usr/bin/env python3
"""VICA 앱에 필요한 로봇 상태를 /robot_status JSON topic으로 요약해 publish하는 노드입니다.

연결 흐름:
    VICA/Nav2 기존 topic
        -> /amcl_pose, /odom, /diagnostics
        -> VicaStatusAppNode
        -> /robot_status
        -> rosbridge
        -> Flutter 앱

    vica_goto_goal
        -> /vica_goal_event
        -> VicaStatusAppNode
        -> /robot_status.current_goal/status
        -> Flutter 앱

앱이 /odom, /amcl_pose, /diagnostics 등 여러 ROS2 topic을 직접 구독하지 않도록,
이 노드가 앱 화면에 필요한 값만 하나의 JSON 메시지로 요약합니다.
"""

import json
import math
from datetime import datetime
from pathlib import Path
from typing import Any

import rclpy
from diagnostic_msgs.msg import DiagnosticArray
from geometry_msgs.msg import PoseWithCovarianceStamped
from nav_msgs.msg import Odometry
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import String


class VicaStatusAppNode(Node):
    """VICA 내부 ROS2 상태를 앱 화면에서 쓰기 쉬운 단일 JSON 메시지로 변환합니다.

    구독 topic:
        /amcl_pose: map frame 기준 현재 위치와 방향
        /odom: 선속도/각속도 기반 moving 보조 판단
        /diagnostics: Nav2 오류/대기 사유 후보
        /vica_goal_event: vica_goto_goal의 목적지 이벤트

    발행 topic:
        /robot_status: 앱 대시보드, 현재 위치, 로봇 관리 화면이 사용하는 상태 JSON
    """

    def __init__(self) -> None:
        super().__init__("vica_status_app_node")

        # 앱 표시값과 장소 판정 기준은 파라미터로 바꿀 수 있게 둡니다.
        # map_id는 Nav2에 넘긴 map yaml 파일명에서만 계산합니다.
        self.declare_parameter("robot_id", "vica_01")
        self.declare_parameter("robot_name", "VICA-01")
        self.declare_parameter("map_yaml", "")
        self.declare_parameter("location_match_radius", 0.5)
        self.declare_parameter("publish_period_sec", 1.0)
        self.declare_parameter("nav2_data_timeout_sec", 3.0)
        self.declare_parameter("moving_linear_threshold", 0.03)
        self.declare_parameter("moving_angular_threshold", 0.05)

        self.storage_root = Path.home() / "ros2_ws" / "location"

        # /odom은 odom frame pose도 갖고 있지만, 앱 지도 위 위치는 /amcl_pose를 우선합니다.
        # 여기서는 주로 twist 속도를 읽어 실제 움직임 여부를 보조 판단합니다.
        self.latest_odom: Odometry | None = None

        # /amcl_pose는 map frame 기준이므로 앱 지도 마커 위치와 가장 잘 맞습니다.
        self.latest_amcl_pose: PoseWithCovarianceStamped | None = None

        # diagnostics는 오류/대기 사유 문자열을 만들 때만 사용합니다.
        self.latest_diagnostics: DiagnosticArray | None = None
        self.last_odom_time: datetime | None = None
        self.last_amcl_pose_time: datetime | None = None

        # vica_goto_goal이 목표를 보내면 /vica_goal_event로 목적지 이름이 들어옵니다.
        self.current_goal = ""
        self.missing_map_yaml_warned = False

        # goal_sent/goal_accepted 이후에는 속도가 잠깐 0이어도 앱에 moving으로 유지합니다.
        self.navigation_active = False

        # 앱은 /robot_status 하나만 구독하면 되도록 이 노드가 내부 topic을 요약합니다.
        self.publisher = self.create_publisher(String, "/robot_status", 10)

        # 주행 속도와 fallback 위치를 받습니다.
        self.create_subscription(Odometry, "/odom", self.handle_odom, 10)

        # 지도 기준 현재 위치와 yaw를 받습니다.
        self.create_subscription(
            PoseWithCovarianceStamped,
            "/amcl_pose",
            self.handle_amcl_pose,
            10,
        )

        # Nav2 lifecycle/diagnostic 상태에서 오류 문구 후보를 받습니다.
        self.create_subscription(
            DiagnosticArray,
            "/diagnostics",
            self.handle_diagnostics,
            10,
        )

        # 저장 좌표 주행 노드가 발행하는 goal 이벤트를 받아 current_goal/status에 반영합니다.
        self.create_subscription(String, "/vica_goal_event", self.handle_goal_event, 10)

        # 주기적으로 최신 상태를 JSON으로 만들어 /robot_status에 보냅니다.
        period = float(self.get_parameter("publish_period_sec").value)
        self.timer = self.create_timer(period, self.publish_status)

    def handle_odom(self, msg: Odometry) -> None:
        """encoder_feedback의 /odom을 받아 주행 속도 판단에 사용합니다."""
        self.latest_odom = msg
        self.last_odom_time = datetime.now()

    def handle_amcl_pose(self, msg: PoseWithCovarianceStamped) -> None:
        """AMCL의 map frame 위치를 받아 앱 지도 위 현재 위치 표시에 사용합니다."""
        self.latest_amcl_pose = msg
        self.last_amcl_pose_time = datetime.now()

    def handle_diagnostics(self, msg: DiagnosticArray) -> None:
        """Nav2 diagnostic 메시지를 받아 오류/대기 사유 후보로 사용합니다."""
        self.latest_diagnostics = msg

    def handle_goal_event(self, msg: String) -> None:
        """vica_goto_goal 노드의 목적지 이벤트를 받아 앱의 현재 목적지로 표시합니다.

        event 처리:
            goal_sent/goal_accepted:
                목적지 이름을 current_goal에 저장하고 navigation_active를 True로 만듭니다.
            goal_succeeded/goal_failed/goal_rejected/goal_canceled:
                목적지 표시를 비우고 navigation_active를 False로 만듭니다.

        이 흐름 덕분에 주행 중 속도가 잠깐 0이 되어도 앱 상태가 waiting으로 튀지 않습니다.
        """
        try:
            payload = json.loads(msg.data)
        except json.JSONDecodeError:
            self.get_logger().warn("ignored invalid /vica_goal_event JSON")
            return

        event = str(payload.get("event", ""))
        if event in {"goal_sent", "goal_accepted"}:
            self.current_goal = str(
                payload.get("name") or payload.get("destination") or "",
            )
            self.navigation_active = True
        elif event in {
            "goal_succeeded",
            "goal_failed",
            "goal_rejected",
            "goal_canceled",
            "emergency_stopped",
        }:
            self.current_goal = ""
            self.navigation_active = False

    def publish_status(self) -> None:
        """현재까지 수신한 정보를 앱용 /robot_status JSON으로 publish합니다.

        이 함수는 timer로 주기 실행됩니다. callback들이 최신 값을 멤버 변수에 저장하고,
        이 함수가 그 값들을 조합해 앱이 바로 표시할 수 있는 JSON을 만듭니다.
        """
        map_id = self._current_map_id()
        x, y, yaw, linear_x, angular_z = self._read_odom_values()
        nav2_pose_available = self._nav2_pose_available()
        error_reason = self._diagnostic_reason(min_level=2)
        waiting_reason = self._waiting_reason(
            linear_x,
            angular_z,
            error_reason,
            nav2_pose_available,
        )
        status = self._status(
            linear_x,
            angular_z,
            error_reason,
            nav2_pose_available,
        )

        payload: dict[str, Any] = {
            "robot_id": str(self.get_parameter("robot_id").value),
            "robot_name": str(self.get_parameter("robot_name").value),
            "status": status,
            "x": round(x, 3),
            "y": round(y, 3),
            "yaw": round(yaw, 2),
            "current_location": self._nearest_location_name(map_id, x, y),
            "current_goal": self.current_goal,
            "error_reason": error_reason,
            "waiting_reason": waiting_reason,
            "map_id": map_id,
            "timestamp": datetime.now().isoformat(timespec="seconds"),
        }

        msg = String()
        msg.data = json.dumps(payload, ensure_ascii=False)
        self.publisher.publish(msg)

    def _current_map_id(self) -> str:
        """Nav2에 넘긴 map yaml 경로에서 앱용 map_id를 정합니다."""
        map_yaml = str(self.get_parameter("map_yaml").value).strip()
        if map_yaml:
            return Path(map_yaml).stem
        if not self.missing_map_yaml_warned:
            self.get_logger().warn(
                "map_yaml parameter is required. "
                "Run with: --ros-args -p map_yaml:=/path/to/map.yaml"
            )
            self.missing_map_yaml_warned = True
        return ""

    def _read_odom_values(self) -> tuple[float, float, float, float, float]:
        """map frame 위치를 우선 사용하고, /odom은 속도와 fallback 위치에 사용합니다.

        반환값:
            (x, y, yaw_degree, linear_x, angular_z)

        우선순위:
            1. /amcl_pose가 있으면 x/y/yaw는 map frame 값을 사용합니다.
            2. /amcl_pose가 아직 없으면 /odom pose를 fallback으로 사용합니다.
            3. 속도는 항상 /odom.twist에서 읽습니다.
        """
        linear_x = 0.0
        angular_z = 0.0
        if self.latest_odom is not None:
            twist = self.latest_odom.twist.twist
            linear_x = float(twist.linear.x)
            angular_z = float(twist.angular.z)

        if self._nav2_pose_available() and self.latest_amcl_pose is not None:
            pose = self.latest_amcl_pose.pose.pose
            yaw = self._quaternion_to_yaw_degrees(
                pose.orientation.x,
                pose.orientation.y,
                pose.orientation.z,
                pose.orientation.w,
            )
            return (
                float(pose.position.x),
                float(pose.position.y),
                yaw,
                linear_x,
                angular_z,
            )

        if self.latest_odom is None:
            return 0.0, 0.0, 0.0, 0.0, 0.0

        pose = self.latest_odom.pose.pose
        yaw = self._quaternion_to_yaw_degrees(
            pose.orientation.x,
            pose.orientation.y,
            pose.orientation.z,
            pose.orientation.w,
        )
        return (
            float(pose.position.x),
            float(pose.position.y),
            yaw,
            linear_x,
            angular_z,
        )

    def _nav2_pose_available(self) -> bool:
        """AMCL pose가 최근에 들어왔는지로 Nav2 위치 추정 활성 상태를 판단합니다."""
        if self.latest_amcl_pose is None or self.last_amcl_pose_time is None:
            return False
        timeout_sec = float(self.get_parameter("nav2_data_timeout_sec").value)
        age = (datetime.now() - self.last_amcl_pose_time).total_seconds()
        return age <= timeout_sec

    def _quaternion_to_yaw_degrees(
        self,
        x: float,
        y: float,
        z: float,
        w: float,
    ) -> float:
        """ROS orientation quaternion을 지도 화면에서 보기 쉬운 degree yaw로 변환합니다.

        /amcl_pose와 /odom orientation은 quaternion입니다. 앱과 저장 좌표는 degree yaw를
        사용하므로 z축 회전(yaw)만 뽑아 0~360도 범위로 정규화합니다.
        """
        siny_cosp = 2.0 * (w * z + x * y)
        cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
        yaw = math.degrees(math.atan2(siny_cosp, cosy_cosp))
        return yaw % 360.0

    def _status(
        self,
        linear_x: float,
        angular_z: float,
        error_reason: str,
        nav2_pose_available: bool,
    ) -> str:
        """오류가 있으면 error, 목표 주행 중이거나 속도가 있으면 moving으로 표시합니다.

        status 우선순위:
            1. diagnostics 오류가 있으면 error
            2. vica_goto_goal 목표가 active이면 moving
            3. /odom 속도가 임계값 이상이면 moving
            4. 그 외에는 waiting
        """
        if error_reason:
            return "error"
        if not nav2_pose_available:
            return "waiting"
        if self.navigation_active:
            return "moving"
        if self._is_moving(linear_x, angular_z):
            return "moving"
        return "waiting"

    def _is_moving(self, linear_x: float, angular_z: float) -> bool:
        """작은 센서 노이즈는 정지로 보도록 임계값을 적용합니다."""
        linear_threshold = float(self.get_parameter("moving_linear_threshold").value)
        angular_threshold = float(self.get_parameter("moving_angular_threshold").value)
        return abs(linear_x) >= linear_threshold or abs(angular_z) >= angular_threshold

    def _diagnostic_reason(self, min_level: int) -> str:
        """diagnostics에서 min_level 이상의 첫 메시지를 앱에 보여줄 문자열로 만듭니다.

        diagnostic level은 OK=0, WARN=1, ERROR=2, STALE=3 형태입니다.
        현재는 ERROR 이상만 error_reason으로 사용하도록 min_level=2로 호출합니다.
        """
        if self.latest_diagnostics is None:
            return ""

        for status in self.latest_diagnostics.status:
            level = self._diagnostic_level(status.level)
            if level >= min_level:
                return status.message or status.name
        return ""

    def _diagnostic_level(self, level: Any) -> int:
        """diagnostic level이 byte/string/int 중 어떤 형태로 와도 숫자로 변환합니다.

        ros2 topic echo에서는 level이 문자열처럼 보일 수 있고, Python 메시지에서는 int 또는
        bytes처럼 들어올 수 있어 방어적으로 변환합니다.
        """
        if isinstance(level, int):
            return level
        if isinstance(level, bytes) and level:
            return level[0]
        if isinstance(level, str) and level:
            return ord(level[0])
        return 0

    def _waiting_reason(
        self,
        linear_x: float,
        angular_z: float,
        error_reason: str,
        nav2_pose_available: bool,
    ) -> str:
        """정지 상태일 때 앱에 표시할 대기 사유를 만듭니다.

        navigation_active이거나 실제 속도가 있으면 대기 사유를 비웁니다.
        /odom이 없으면 위치/속도 데이터 자체가 없으므로 수신 대기로 표시합니다.
        """
        if error_reason:
            return ""
        if not nav2_pose_available:
            return "Nav2/AMCL 미실행"
        if self.latest_odom is None:
            return "위치 데이터 수신 대기"
        if self.navigation_active:
            return ""
        if self._is_moving(linear_x, angular_z):
            return ""
        return "목표 없음"

    def _nearest_location_name(self, map_id: str, x: float, y: float) -> str:
        """저장된 장소 중 현재 위치와 설정 반경 이내인 가장 가까운 장소명을 찾습니다.

        locations.json에 저장된 장소들과 현재 x/y 거리 차이를 계산합니다.
        가까운 장소가 없으면 앱에는 "현재 위치 확인 중"으로 표시합니다.
        """
        radius = float(self.get_parameter("location_match_radius").value)
        locations = self._read_locations(map_id)
        nearest_name = ""
        nearest_distance = radius

        for location in locations:
            try:
                dx = x - float(location.get("x", 0.0))
                dy = y - float(location.get("y", 0.0))
            except (TypeError, ValueError):
                continue

            distance = math.hypot(dx, dy)
            if distance <= nearest_distance:
                nearest_distance = distance
                nearest_name = str(location.get("name") or location.get("location_id") or "")

        return nearest_name or "현재 위치 확인 중"

    def _read_locations(self, map_id: str) -> list[dict[str, Any]]:
        """~/ros2_ws/location/<map_id>/locations.json에서 저장 장소 목록을 읽습니다.

        이 함수는 current_location 이름 판정에만 사용합니다. 장소 파일이 없거나 깨져도
        상태 publish 자체는 계속되어야 하므로 예외를 잡고 빈 목록을 반환합니다.
        """
        path = self.storage_root / map_id / "locations.json"
        if not path.exists():
            return []
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            self.get_logger().warn(f"failed to read locations: {exc}")
            return []
        if isinstance(data, list):
            return [item for item in data if isinstance(item, dict)]
        return []


def main() -> None:
    """ROS2 노드를 초기화하고 상태 topic들을 구독한 채 /robot_status를 계속 publish합니다."""
    rclpy.init()
    node = VicaStatusAppNode()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
