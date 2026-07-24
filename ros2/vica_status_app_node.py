#!/usr/bin/env python3
"""VICA 앱에 필요한 로봇 상태를 /robot_status JSON topic으로 요약해 publish하는 노드입니다.

연결 흐름:
    VICA/Nav2 기존 topic/TF
        -> TF map->base_footprint, /odom, /diagnostics
        -> VicaStatusAppNode
        -> /robot_status
        -> rosbridge
        -> Flutter 앱

    vica_goto_goal
        -> /vica_goal_event
        -> VicaStatusAppNode
        -> /robot_status.current_goal
        -> Flutter 앱

앱이 /odom, TF, /diagnostics 등을 직접 구독하지 않도록, 이 노드가 앱 화면에
필요한 값만 하나의 JSON 메시지로 요약합니다.

현재 위치 표시:
    로봇 위치는 map frame 기준 TF(map -> base_footprint)를 주기적으로 조회해 얻습니다.
    /amcl_pose와 달리 TF는 AMCL 보정 사이를 odom으로 연속 보간하므로, 원하는 주기로
    매끄럽게 위치를 읽을 수 있어 앱 마커가 실시간으로 부드럽게 움직입니다.

지도 자동 감지:
    Nav2가 실행되면 map_server 노드가 map yaml 경로를 yaml_filename 파라미터로 갖습니다.
    이 노드는 그 파라미터를 조회해 map_id(파일명 stem)를 자동으로 정하므로, 실행 시
    지도 경로를 따로 넘길 필요가 없습니다. map_yaml 파라미터를 명시하면 그 값이 우선합니다.
"""

import json
import math
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import rclpy
import yaml
from diagnostic_msgs.msg import DiagnosticArray
from nav_msgs.msg import Odometry
from rcl_interfaces.msg import ParameterType
from rcl_interfaces.srv import GetParameters
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.time import Time
from std_msgs.msg import String
from tf2_ros import Buffer, TransformException, TransformListener


class VicaStatusAppNode(Node):
    """VICA 내부 ROS2 상태를 앱 화면에서 쓰기 쉬운 단일 JSON 메시지로 변환합니다."""

    def __init__(self) -> None:
        super().__init__("vica_status_app_node")

        # 앱 표시값과 장소 판정 기준은 파라미터로 바꿀 수 있게 둡니다.
        self.declare_parameter("robot_id", "vica_01")
        self.declare_parameter("robot_name", "VICA-01")
        # map_yaml: 수동 오버라이드. 비워두면 map_server에서 자동 감지합니다.
        self.declare_parameter("map_yaml", "")
        self.declare_parameter("location_match_radius", 0.5)
        self.declare_parameter(
            "destination_storage_root",
            str(Path.home() / "vica_data" / "destinations"),
        )
        # 위치를 매끄럽게 보여주기 위해 기본 10Hz로 발행합니다.
        self.declare_parameter("publish_period_sec", 0.1)
        self.declare_parameter("nav2_data_timeout_sec", 3.0)
        self.declare_parameter("moving_linear_threshold", 0.03)
        self.declare_parameter("moving_angular_threshold", 0.05)
        # TF 프레임. vica_nav2 설정 기준: global=map, base=base_footprint.
        self.declare_parameter("map_frame", "map")
        self.declare_parameter("base_frame", "base_footprint")
        # map yaml 자동 감지에 쓰는 map_server 노드 이름과 조회 주기.
        self.declare_parameter("map_server_node", "/map_server")
        self.declare_parameter("map_poll_period_sec", 2.0)

        self.storage_root = Path(
            str(self.get_parameter("destination_storage_root").value)
        ).expanduser()
        self.map_frame = str(self.get_parameter("map_frame").value)
        self.base_frame = str(self.get_parameter("base_frame").value)

        # /odom은 주로 twist 속도(실제 움직임 여부)와 TF 미확보 시 fallback pose에 씁니다.
        self.latest_odom: Odometry | None = None

        # TF에서 읽은 map frame 기준 현재 pose (x, y, yaw_deg).
        self.tf_pose: tuple[float, float, float] | None = None
        self.last_tf_time: datetime | None = None

        # diagnostics는 오류/대기 사유 문자열을 만들 때만 사용합니다.
        self.latest_diagnostics: DiagnosticArray | None = None

        # vica_goto_goal이 목표를 보내면 /vica_goal_event로 목적지 이름이 들어옵니다.
        self.current_goal = ""
        self.navigation_active = False
        self.missing_map_yaml_warned = False

        # map_server yaml_filename 자동 감지 상태.
        self.detected_map_yaml = ""
        self._map_param_in_flight = False

        # destinations.yaml 캐시 (10Hz 발행마다 파일을 읽지 않도록).
        self._loc_cache: list[dict[str, Any]] = []
        self._loc_cache_map_id = ""
        self._loc_cache_time = 0.0

        # TF 조회 준비.
        self.tf_buffer = Buffer()
        self.tf_listener = TransformListener(self.tf_buffer, self)

        # map_server 파라미터 조회 클라이언트.
        map_server_node = str(self.get_parameter("map_server_node").value).rstrip("/")
        self.map_param_client = self.create_client(
            GetParameters, f"{map_server_node}/get_parameters"
        )

        # 앱은 /robot_status 하나만 구독하면 되도록 이 노드가 내부 상태를 요약합니다.
        self.publisher = self.create_publisher(String, "/robot_status", 10)

        # 주행 속도와 fallback 위치용 /odom.
        self.create_subscription(Odometry, "/odom", self.handle_odom, 10)
        # Nav2 lifecycle/diagnostic 상태에서 오류 문구 후보.
        self.create_subscription(
            DiagnosticArray, "/diagnostics", self.handle_diagnostics, 10
        )
        # 저장 좌표 주행 노드가 발행하는 goal 이벤트.
        self.create_subscription(
            String, "/vica_goal_event", self.handle_goal_event, 10
        )

        period = float(self.get_parameter("publish_period_sec").value)
        self.timer = self.create_timer(period, self.publish_status)

        # 지도 자동 감지: 수동 map_yaml이 없을 때만 map_server 파라미터를 조회합니다.
        # status 노드가 Nav2보다 먼저 떠 있을 수 있어 "받을 때까지" 재시도하고,
        # 첫 감지에 성공하면 타이머를 멈춥니다(계속 조회할 필요 없음).
        if str(self.get_parameter("map_yaml").value).strip():
            self.map_poll_timer = None
        else:
            poll_period = float(self.get_parameter("map_poll_period_sec").value)
            self.map_poll_timer = self.create_timer(poll_period, self._poll_map_yaml)

        self.get_logger().info(
            f"vica_status_app_node ready: TF {self.map_frame}->{self.base_frame}, "
            f"publish {1.0 / period:.0f}Hz, map auto-detect via {map_server_node}"
        )

    # ------------------------------------------------------------------
    # 구독 콜백
    # ------------------------------------------------------------------
    def handle_odom(self, msg: Odometry) -> None:
        self.latest_odom = msg

    def handle_diagnostics(self, msg: DiagnosticArray) -> None:
        self.latest_diagnostics = msg

    def handle_goal_event(self, msg: String) -> None:
        """vica_goto_goal의 목적지 이벤트를 받아 앱의 현재 목적지로 표시합니다.

        goal_sent/goal_accepted 이면 목적지명을 저장하고 navigation_active=True,
        종료/취소 이벤트면 목적지를 비우고 navigation_active=False로 둡니다. 덕분에
        주행 중 속도가 잠깐 0이 되어도 앱 상태가 waiting으로 튀지 않습니다.
        """
        try:
            payload = json.loads(msg.data)
        except json.JSONDecodeError:
            self.get_logger().warn("ignored invalid /vica_goal_event JSON")
            return

        event = str(payload.get("event", ""))
        if event in {"goal_sent", "goal_accepted"}:
            self.current_goal = str(
                payload.get("name") or payload.get("destination") or ""
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

    # ------------------------------------------------------------------
    # map yaml 자동 감지
    # ------------------------------------------------------------------
    def _poll_map_yaml(self) -> None:
        """map_server의 yaml_filename 파라미터를 주기적으로 조회합니다.

        수동 map_yaml 파라미터가 지정돼 있으면 자동 감지는 건너뜁니다.
        map_server가 없으면(=Nav2 미실행) 조용히 넘어갑니다.
        """
        if str(self.get_parameter("map_yaml").value).strip():
            return
        if self._map_param_in_flight or not self.map_param_client.service_is_ready():
            return
        request = GetParameters.Request()
        request.names = ["yaml_filename"]
        self._map_param_in_flight = True
        future = self.map_param_client.call_async(request)
        future.add_done_callback(self._on_map_yaml_result)

    def _on_map_yaml_result(self, future: Any) -> None:
        self._map_param_in_flight = False
        try:
            response = future.result()
        except Exception as exc:  # ROS future 예외는 배포판마다 다릅니다.
            self.get_logger().warn(f"map yaml 조회 실패: {exc}")
            return
        if not response or not response.values:
            return
        value = response.values[0]
        # 비어 있지 않은 yaml_filename을 받으면 확정하고 조회를 멈춥니다.
        # (map_server 구성 직후 잠깐 빈 문자열이 올 수 있어 non-empty일 때만 확정)
        if value.type == ParameterType.PARAMETER_STRING and value.string_value:
            self.detected_map_yaml = value.string_value
            self.get_logger().info(f"map yaml 자동 감지: {self.detected_map_yaml}")
            if self.map_poll_timer is not None:
                self.map_poll_timer.cancel()
                self.map_poll_timer = None

    # ------------------------------------------------------------------
    # TF 위치 조회
    # ------------------------------------------------------------------
    def _update_tf_pose(self) -> None:
        """map->base_frame TF를 조회해 현재 pose를 갱신합니다.

        조회에 실패하면(TF 미확보) 이전 값을 유지하고, 만료 여부는 last_tf_time
        나이로 판단합니다.
        """
        try:
            transform = self.tf_buffer.lookup_transform(
                self.map_frame, self.base_frame, Time()
            )
        except TransformException:
            return
        translation = transform.transform.translation
        rotation = transform.transform.rotation
        yaw = self._quaternion_to_yaw_degrees(
            rotation.x, rotation.y, rotation.z, rotation.w
        )
        self.tf_pose = (float(translation.x), float(translation.y), yaw)
        self.last_tf_time = datetime.now()

    # ------------------------------------------------------------------
    # 상태 발행
    # ------------------------------------------------------------------
    def publish_status(self) -> None:
        """최신 정보를 앱용 /robot_status JSON으로 발행합니다(타이머 주기 실행)."""
        self._update_tf_pose()

        map_id = self._current_map_id()
        x, y, yaw, linear_x, angular_z = self._read_pose_values()
        nav2_pose_available = self._nav2_pose_available()
        error_reason = self._diagnostic_reason(min_level=2)
        waiting_reason = self._waiting_reason(
            linear_x, angular_z, error_reason, nav2_pose_available
        )
        status = self._status(linear_x, angular_z, error_reason, nav2_pose_available)

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
        """수동 map_yaml이 있으면 그 값을, 없으면 자동 감지한 yaml을 map_id로 씁니다."""
        manual = str(self.get_parameter("map_yaml").value).strip()
        yaml_path = manual or self.detected_map_yaml
        if yaml_path:
            return Path(yaml_path).stem
        if not self.missing_map_yaml_warned:
            self.get_logger().warn(
                "map yaml을 아직 확인하지 못했습니다. Nav2(map_server) 실행 여부를 "
                "확인하거나 -p map_yaml:=/path/to/map.yaml 로 직접 지정하세요."
            )
            self.missing_map_yaml_warned = True
        return ""

    def _read_pose_values(self) -> tuple[float, float, float, float, float]:
        """(x, y, yaw_degree, linear_x, angular_z)를 돌려줍니다.

        위치는 TF(map frame)를 우선하고, 아직 없으면 /odom pose를 fallback으로 씁니다.
        속도는 항상 /odom.twist에서 읽습니다.
        """
        linear_x = 0.0
        angular_z = 0.0
        if self.latest_odom is not None:
            twist = self.latest_odom.twist.twist
            linear_x = float(twist.linear.x)
            angular_z = float(twist.angular.z)

        if self._nav2_pose_available() and self.tf_pose is not None:
            x, y, yaw = self.tf_pose
            return x, y, yaw, linear_x, angular_z

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
        """map->base TF가 최근에 확보됐는지로 Nav2 위치 추정 활성 여부를 판단합니다."""
        if self.tf_pose is None or self.last_tf_time is None:
            return False
        timeout_sec = float(self.get_parameter("nav2_data_timeout_sec").value)
        age = (datetime.now() - self.last_tf_time).total_seconds()
        return age <= timeout_sec

    def _quaternion_to_yaw_degrees(
        self, x: float, y: float, z: float, w: float
    ) -> float:
        """orientation quaternion에서 z축 회전(yaw)만 뽑아 0~360도로 정규화합니다."""
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
        """오류>위치미확보>목표주행>속도>대기 순으로 상태를 정합니다."""
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
        """diagnostics에서 min_level(ERROR=2) 이상의 첫 메시지를 오류 문자열로 만듭니다."""
        if self.latest_diagnostics is None:
            return ""
        for status in self.latest_diagnostics.status:
            level = self._diagnostic_level(status.level)
            if level >= min_level:
                return status.message or status.name
        return ""

    def _diagnostic_level(self, level: Any) -> int:
        """diagnostic level이 int/bytes/str 중 어떤 형태로 와도 숫자로 변환합니다."""
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
        """정지 상태일 때 앱에 표시할 대기 사유를 만듭니다."""
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
        """저장된 장소 중 설정 반경 이내에서 가장 가까운 장소명을 찾습니다."""
        radius = float(self.get_parameter("location_match_radius").value)
        locations = self._read_locations(map_id)
        nearest_name = ""
        nearest_distance = radius

        for location in locations:
            try:
                pose = location.get("pose") or {}
                dx = x - float(pose.get("x", 0.0))
                dy = y - float(pose.get("y", 0.0))
            except (TypeError, ValueError):
                continue
            distance = math.hypot(dx, dy)
            if distance <= nearest_distance:
                nearest_distance = distance
                nearest_name = str(
                    location.get("name") or location.get("id") or ""
                )
        return nearest_name or "현재 위치 확인 중"

    def _read_locations(self, map_id: str) -> list[dict[str, Any]]:
        """지도별 destinations.yaml을 읽습니다(2초 캐시).

        발행 주기가 높으므로(10Hz) 매번 파일을 읽지 않도록 map_id별로 잠시 캐시합니다.
        파일이 없거나 깨져도 상태 발행은 계속되어야 하므로 예외 시 빈 목록을 씁니다.
        """
        now = time.monotonic()
        if (
            map_id == self._loc_cache_map_id
            and (now - self._loc_cache_time) < 2.0
        ):
            return self._loc_cache

        result: list[dict[str, Any]] = []
        path = self.storage_root / map_id / "destinations.yaml"
        if map_id and path.exists():
            try:
                data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
                destinations = data.get("destinations", [])
                if isinstance(destinations, list):
                    result = [
                        item for item in destinations if isinstance(item, dict)
                    ]
            except (yaml.YAMLError, OSError) as exc:
                self.get_logger().warn(f"failed to read destinations: {exc}")

        self._loc_cache = result
        self._loc_cache_map_id = map_id
        self._loc_cache_time = now
        return result


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
