#!/usr/bin/env python3
"""VICA 앱에 필요한 로봇 상태를 /robot_status JSON topic으로 요약해 publish하는 노드입니다."""

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
    """VICA 내부 ROS2 상태를 앱 화면에서 쓰기 쉬운 단일 JSON 메시지로 변환합니다."""

    def __init__(self) -> None:
        super().__init__("vica_status_app_node")

        # 앱 표시값과 장소 판정 기준은 파라미터로 바꿀 수 있게 둡니다.
        self.declare_parameter("robot_id", "vica_01")
        self.declare_parameter("robot_name", "VICA-01")
        self.declare_parameter("map_id", "vica_map_0604")
        self.declare_parameter("location_match_radius", 0.5)
        self.declare_parameter("publish_period_sec", 1.0)
        self.declare_parameter("moving_linear_threshold", 0.03)
        self.declare_parameter("moving_angular_threshold", 0.05)

        self.storage_root = Path.home() / "ros2_ws" / "location"
        self.latest_odom: Odometry | None = None
        self.latest_amcl_pose: PoseWithCovarianceStamped | None = None
        self.latest_diagnostics: DiagnosticArray | None = None
        self.last_odom_time: datetime | None = None
        self.current_goal = ""

        # 앱은 /robot_status 하나만 구독하면 되도록 이 노드가 내부 topic을 요약합니다.
        self.publisher = self.create_publisher(String, "/robot_status", 10)
        self.create_subscription(Odometry, "/odom", self.handle_odom, 10)
        self.create_subscription(
            PoseWithCovarianceStamped,
            "/amcl_pose",
            self.handle_amcl_pose,
            10,
        )
        self.create_subscription(
            DiagnosticArray,
            "/diagnostics",
            self.handle_diagnostics,
            10,
        )
        self.create_subscription(String, "/vica_goal_event", self.handle_goal_event, 10)

        period = float(self.get_parameter("publish_period_sec").value)
        self.timer = self.create_timer(period, self.publish_status)

    def handle_odom(self, msg: Odometry) -> None:
        """encoder_feedback의 /odom을 받아 주행 속도 판단에 사용합니다."""
        self.latest_odom = msg
        self.last_odom_time = datetime.now()

    def handle_amcl_pose(self, msg: PoseWithCovarianceStamped) -> None:
        """AMCL의 map frame 위치를 받아 앱 지도 위 현재 위치 표시에 사용합니다."""
        self.latest_amcl_pose = msg

    def handle_diagnostics(self, msg: DiagnosticArray) -> None:
        """Nav2 diagnostic 메시지를 받아 오류/대기 사유 후보로 사용합니다."""
        self.latest_diagnostics = msg

    def handle_goal_event(self, msg: String) -> None:
        """vica_goto_goal 노드의 목적지 이벤트를 받아 앱의 현재 목적지로 표시합니다."""
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
        elif event in {"goal_succeeded", "goal_failed", "goal_rejected"}:
            self.current_goal = ""

    def publish_status(self) -> None:
        """현재까지 수신한 정보를 앱용 /robot_status JSON으로 publish합니다."""
        map_id = str(self.get_parameter("map_id").value)
        x, y, yaw, linear_x, angular_z = self._read_odom_values()
        error_reason = self._diagnostic_reason(min_level=2)
        waiting_reason = self._waiting_reason(linear_x, angular_z, error_reason)
        status = self._status(linear_x, angular_z, error_reason)

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

    def _read_odom_values(self) -> tuple[float, float, float, float, float]:
        """map frame 위치를 우선 사용하고, /odom은 속도와 fallback 위치에 사용합니다."""
        linear_x = 0.0
        angular_z = 0.0
        if self.latest_odom is not None:
            twist = self.latest_odom.twist.twist
            linear_x = float(twist.linear.x)
            angular_z = float(twist.angular.z)

        if self.latest_amcl_pose is not None:
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

    def _quaternion_to_yaw_degrees(
        self,
        x: float,
        y: float,
        z: float,
        w: float,
    ) -> float:
        """ROS orientation quaternion을 지도 화면에서 보기 쉬운 degree yaw로 변환합니다."""
        siny_cosp = 2.0 * (w * z + x * y)
        cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
        yaw = math.degrees(math.atan2(siny_cosp, cosy_cosp))
        return yaw % 360.0

    def _status(self, linear_x: float, angular_z: float, error_reason: str) -> str:
        """오류가 있으면 error, 속도가 있으면 moving, 아니면 waiting으로 표시합니다."""
        if error_reason:
            return "error"
        if self._is_moving(linear_x, angular_z):
            return "moving"
        return "waiting"

    def _is_moving(self, linear_x: float, angular_z: float) -> bool:
        """작은 센서 노이즈는 정지로 보도록 임계값을 적용합니다."""
        linear_threshold = float(self.get_parameter("moving_linear_threshold").value)
        angular_threshold = float(self.get_parameter("moving_angular_threshold").value)
        return abs(linear_x) >= linear_threshold or abs(angular_z) >= angular_threshold

    def _diagnostic_reason(self, min_level: int) -> str:
        """diagnostics에서 min_level 이상의 첫 메시지를 앱에 보여줄 문자열로 만듭니다."""
        if self.latest_diagnostics is None:
            return ""

        for status in self.latest_diagnostics.status:
            level = self._diagnostic_level(status.level)
            if level >= min_level:
                return status.message or status.name
        return ""

    def _diagnostic_level(self, level: Any) -> int:
        """diagnostic level이 byte/string/int 중 어떤 형태로 와도 숫자로 변환합니다."""
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
    ) -> str:
        """정지 상태일 때 앱에 표시할 대기 사유를 만듭니다."""
        if error_reason:
            return ""
        if self.latest_odom is None:
            return "위치 데이터 수신 대기"
        if self._is_moving(linear_x, angular_z):
            return ""
        return "목표 없음"

    def _nearest_location_name(self, map_id: str, x: float, y: float) -> str:
        """저장된 장소 중 현재 위치와 0.5m 이내인 가장 가까운 장소명을 찾습니다."""
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
        """~/ros2_ws/location/<map_id>/locations.json에서 저장 장소 목록을 읽습니다."""
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
