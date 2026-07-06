#!/usr/bin/env python3
"""저장된 VICA 장소 이름을 찾아 Nav2 NavigateToPose goal로 전송하는 노드입니다.

연결 흐름:
    터미널 또는 alias
        -> vica_goto <map_id> <destination>
        -> VicaGotoGoal
        -> ~/ros2_ws/location/<map_id>/locations.json에서 목적지 검색
        -> /vica_destination_request, /vica_goal_event 발행
        -> /navigate_to_pose action goal 전송
        -> Nav2가 VICA를 해당 좌표로 주행

이 노드는 앱에서 직접 Nav2 action에 연결하지 않도록 ROS2 쪽에서 목적지 실행을 담당합니다.
향후 음성/LLM 노드가 목적지 이름을 결정하면 이 노드의 검색/goal 전송 함수를 재사용할 수 있습니다.
"""

import argparse
import json
import math
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import rclpy
from action_msgs.msg import GoalStatus
from geometry_msgs.msg import PoseStamped
from nav2_msgs.action import NavigateToPose
from rclpy.action import ActionClient
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import String


@dataclass(frozen=True)
class SavedLocation:
    """locations.json에서 읽어온 목적지 좌표를 Nav2 goal로 넘기기 쉽게 담습니다.

    location_storage_node.py가 저장한 JSON dict를 typed object로 바꾼 형태입니다.
    Nav2로 보낼 때 필요한 핵심 값은 map_id, x, y, yaw입니다.
    """

    location_id: str
    map_id: str
    name: str
    category: str
    x: float
    y: float
    yaw: float
    memo: str


class VicaGotoGoal(Node):
    """저장 장소 검색, 목적지 요청 기록, Nav2 goal 전송을 담당합니다.

    발행 topic:
        /vica_destination_request: 사용자가 어떤 목적지를 요청했는지 기록합니다.
        /vica_goal_event: goal_sent/accepted/succeeded/failed 같은 진행 상태를 알립니다.

    사용 action:
        /navigate_to_pose: Nav2 NavigateToPose action server에 실제 주행 goal을 보냅니다.
    """

    def __init__(self) -> None:
        super().__init__("vica_goto_goal")

        # 장소 좌표는 지도별 locations.json에 저장되어 있습니다.
        self.storage_root = Path.home() / "ros2_ws" / "location"

        # Nav2 bt_navigator가 제공하는 NavigateToPose action server에 연결합니다.
        self.goal_client = ActionClient(self, NavigateToPose, "/navigate_to_pose")

        # 목적지 요청/처리 결과를 다른 노드와 앱 로그가 볼 수 있게 JSON topic으로 내보냅니다.
        self.request_publisher = self.create_publisher(
            String,
            "/vica_destination_request",
            10,
        )
        self.event_publisher = self.create_publisher(String, "/vica_goal_event", 10)

    def publish_destination_request(
        self,
        map_id: str,
        destination: str,
    ) -> None:
        """터미널로 받은 목적지 요청을 topic으로 기록합니다.

        이 이벤트는 "사용자가 어떤 목적지를 요청했는가"에 대한 로그 성격입니다.
        실제 Nav2 goal 전송 성공/실패 여부는 /vica_goal_event에서 따로 알립니다.
        """
        self._publish_json(
            self.request_publisher,
            {
                "event": "destination_requested",
                "map_id": map_id,
                "destination": destination,
                "timestamp": self._timestamp(),
            },
        )

    def find_location(self, map_id: str, destination: str) -> SavedLocation:
        """map_id의 locations.json에서 name 또는 location_id가 일치하는 장소를 찾습니다.

        검색 기준:
            - location["name"]
            - location["location_id"]

        대소문자와 앞뒤 공백은 무시합니다. 목적지를 찾지 못하면 사용자가 볼 수 있게
        해당 지도에 있는 목적지 이름 목록을 포함한 ValueError를 발생시킵니다.
        """
        locations = self._read_locations(map_id)
        normalized_destination = self._normalize(destination)

        for location in locations:
            name = str(location.get("name", ""))
            location_id = str(location.get("location_id", ""))
            if normalized_destination in {
                self._normalize(name),
                self._normalize(location_id),
            }:
                return self._to_saved_location(map_id, location)

        available = ", ".join(
            str(item.get("name") or item.get("location_id") or "-")
            for item in locations
        )
        raise ValueError(
            f"'{destination}' 목적지를 찾을 수 없습니다. "
            f"map_id={map_id}, available=[{available}]",
        )

    def send_nav2_goal(self, location: SavedLocation) -> bool:
        """저장 좌표를 NavigateToPose action goal로 변환해 Nav2에 전송합니다.

        처리 흐름:
            1. /navigate_to_pose action server가 준비될 때까지 최대 5초 대기합니다.
            2. SavedLocation의 x/y/yaw를 PoseStamped로 변환합니다.
            3. goal_sent 이벤트를 publish합니다.
            4. Nav2 action goal을 비동기로 전송합니다.
            5. accepted/rejected 및 최종 result에 따라 /vica_goal_event를 publish합니다.
        """
        if not self.goal_client.wait_for_server(timeout_sec=5.0):
            self.publish_goal_event("goal_failed", location, "Nav2 action server 대기 시간 초과")
            self.get_logger().error("/navigate_to_pose action server is not available")
            return False

        goal_msg = NavigateToPose.Goal()
        goal_msg.pose = self._to_pose_stamped(location)

        # vica_status_app_node는 이 이벤트를 받아 current_goal과 moving 상태를 갱신합니다.
        self.publish_goal_event("goal_sent", location)
        self.get_logger().info(
            f"Sending goal: map_id={location.map_id}, "
            f"name={location.name}, x={location.x:.3f}, y={location.y:.3f}, yaw={location.yaw:.2f}",
        )

        send_future = self.goal_client.send_goal_async(goal_msg)
        rclpy.spin_until_future_complete(self, send_future)
        goal_handle = send_future.result()

        if goal_handle is None or not goal_handle.accepted:
            self.publish_goal_event("goal_rejected", location, "Nav2 goal rejected")
            self.get_logger().warn("Nav2 goal was rejected")
            return False

        self.publish_goal_event("goal_accepted", location)

        # 여기서 result를 기다리므로 이 명령은 주행이 끝나거나 실패할 때까지 반환되지 않습니다.
        result_future = goal_handle.get_result_async()
        rclpy.spin_until_future_complete(self, result_future)
        result = result_future.result()

        if result is None:
            self.publish_goal_event("goal_failed", location, "Nav2 result missing")
            return False

        status = int(result.status)
        if status == GoalStatus.STATUS_SUCCEEDED:
            self.publish_goal_event("goal_succeeded", location)
            self.get_logger().info(f"Goal succeeded: {location.name}")
            return True

        if status == GoalStatus.STATUS_CANCELED:
            self.publish_goal_event(
                "goal_canceled",
                location,
                "비상정지 또는 외부 요청으로 목적지가 취소되었습니다.",
            )
            self.get_logger().warn(f"Goal canceled: {location.name}")
            return False

        self.publish_goal_event("goal_failed", location, f"Nav2 result status={status}")
        self.get_logger().warn(f"Goal finished with status={status}: {location.name}")
        return False

    def publish_goal_event(
        self,
        event: str,
        location: SavedLocation,
        reason: str = "",
    ) -> None:
        """주행 요청 처리 상태를 /vica_goal_event에 publish합니다.

        주요 event 값:
            goal_sent: Nav2에 goal을 보내기 직전
            goal_accepted: Nav2 action server가 goal을 수락
            goal_rejected: Nav2가 goal을 거절
            goal_succeeded: 목적지 도착 성공
            goal_canceled: 비상정지 또는 외부 요청으로 목적지 취소
            goal_failed: 주행 실패 또는 action server 없음
            goal_dry_run: --dry-run으로 검색만 확인

        vica_status_app_node는 이 topic을 구독해 앱의 현재 목적지와 주행 상태를 보강합니다.
        """
        self._publish_json(
            self.event_publisher,
            {
                "event": event,
                "map_id": location.map_id,
                "location_id": location.location_id,
                "name": location.name,
                "category": location.category,
                "x": location.x,
                "y": location.y,
                "yaw": location.yaw,
                "reason": reason,
                "timestamp": self._timestamp(),
            },
        )

    def publish_error_event(
        self,
        event: str,
        map_id: str,
        destination: str,
        reason: str,
    ) -> None:
        """목적지를 찾기 전 단계에서 발생한 실패도 /vica_goal_event로 알립니다.

        예를 들어 locations.json 파일이 없거나 destination 이름을 찾지 못한 경우에는
        SavedLocation 객체가 없으므로 별도 error payload를 구성해 publish합니다.
        """
        self._publish_json(
            self.event_publisher,
            {
                "event": event,
                "map_id": map_id,
                "destination": destination,
                "name": destination,
                "reason": reason,
                "timestamp": self._timestamp(),
            },
        )

    def _read_locations(self, map_id: str) -> list[dict[str, Any]]:
        """~/ros2_ws/location/<map_id>/locations.json 파일을 읽습니다.

        location_storage_node.py가 관리하는 파일을 그대로 사용합니다.
        파일이 없으면 아직 해당 지도에 목적지가 저장되지 않은 것이므로 FileNotFoundError를 냅니다.
        """
        path = self.storage_root / map_id / "locations.json"
        if not path.exists():
            raise FileNotFoundError(f"location file not found: {path}")
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise ValueError(f"location file must contain a JSON list: {path}")
        return [item for item in data if isinstance(item, dict)]

    def _to_saved_location(
        self,
        fallback_map_id: str,
        location: dict[str, Any],
    ) -> SavedLocation:
        """JSON dict를 SavedLocation으로 변환하고 필수 좌표값을 검증합니다.

        x/y는 Nav2 goal에 반드시 필요하므로 float 변환 중 오류가 나면 상위 예외 처리로 이동합니다.
        yaw가 없으면 기본 0도, 즉 map +x 방향을 바라보는 goal로 취급합니다.
        """
        return SavedLocation(
            location_id=str(location.get("location_id", "")),
            map_id=str(location.get("map_id") or fallback_map_id),
            name=str(location.get("name", "")),
            category=str(location.get("category", "")),
            x=float(location["x"]),
            y=float(location["y"]),
            yaw=float(location.get("yaw", 0.0)),
            memo=str(location.get("memo", "")),
        )

    def _to_pose_stamped(self, location: SavedLocation) -> PoseStamped:
        """저장 좌표와 yaw degree를 Nav2가 사용하는 map frame PoseStamped로 변환합니다.

        Nav2 NavigateToPose goal은 PoseStamped를 요구합니다.
        frame_id는 저장 좌표가 map 기준이라는 전제에 따라 "map"으로 고정합니다.
        """
        pose = PoseStamped()
        pose.header.frame_id = "map"
        pose.header.stamp = self.get_clock().now().to_msg()
        pose.pose.position.x = location.x
        pose.pose.position.y = location.y
        pose.pose.position.z = 0.0
        pose.pose.orientation.z, pose.pose.orientation.w = self._yaw_to_quaternion(
            location.yaw,
        )
        return pose

    def _yaw_to_quaternion(self, yaw_degrees: float) -> tuple[float, float]:
        """2D yaw degree를 z/w quaternion 값으로 변환합니다.

        2D 주행에서는 roll/pitch가 0이므로 orientation의 z와 w만 계산하면 됩니다.
        x/y quaternion 값은 PoseStamped 기본값 0을 그대로 사용합니다.
        """
        yaw_radians = math.radians(yaw_degrees)
        return math.sin(yaw_radians / 2.0), math.cos(yaw_radians / 2.0)

    def _publish_json(self, publisher: Any, payload: dict[str, Any]) -> None:
        """dict payload를 std_msgs/String JSON으로 변환해 publish합니다."""
        msg = String()
        msg.data = json.dumps(payload, ensure_ascii=False)
        publisher.publish(msg)

        # 단발성 CLI 노드라 publish 직후 종료될 수 있으므로, 짧게 spin해 전송 기회를 줍니다.
        rclpy.spin_once(self, timeout_sec=0.05)

    def _normalize(self, value: str) -> str:
        """목적지 비교 시 대소문자와 앞뒤 공백 차이를 무시합니다."""
        return value.strip().casefold()

    def _timestamp(self) -> str:
        """앱 로그와 상태 표시에서 바로 읽을 수 있는 ISO timestamp를 만듭니다."""
        return datetime.now().isoformat(timespec="seconds")


def parse_args(argv: list[str]) -> argparse.Namespace:
    """CLI 인자를 해석합니다.

    기본 사용:
        python3 vica_goto_goal.py <map_id> <destination>

    dry-run:
        python3 vica_goto_goal.py <map_id> <destination> --dry-run
    """
    parser = argparse.ArgumentParser(
        description="저장된 VICA 장소 이름을 Nav2 목적지로 전송합니다.",
    )
    parser.add_argument("map_id", help="장소 폴더 이름 예: vica_map_0604")
    parser.add_argument("destination", help="locations.json의 name 또는 location_id")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="목적지 검색과 이벤트 발행만 확인하고 Nav2 goal은 전송하지 않습니다.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """CLI 진입점입니다.

    처리 순서:
        1. 인자 파싱
        2. ROS2 초기화 및 노드 생성
        3. 목적지 요청 이벤트 publish
        4. 저장 장소 검색
        5. --dry-run이면 여기서 종료
        6. 실제 Nav2 goal 전송
        7. 성공/실패에 맞는 process exit code 반환
    """
    args = parse_args(sys.argv[1:] if argv is None else argv)

    rclpy.init()
    node = VicaGotoGoal()
    try:
        node.publish_destination_request(args.map_id, args.destination)
        location = node.find_location(args.map_id, args.destination)
        if args.dry_run:
            node.publish_goal_event("goal_dry_run", location)
            node.get_logger().info(
                f"Dry run goal: map_id={location.map_id}, "
                f"name={location.name}, x={location.x:.3f}, y={location.y:.3f}, yaw={location.yaw:.2f}",
            )
            return 0
        success = node.send_nav2_goal(location)
        return 0 if success else 1
    except (KeyboardInterrupt, ExternalShutdownException):
        return 130
    except Exception as exc:
        node.publish_error_event(
            "goal_failed",
            args.map_id,
            args.destination,
            str(exc),
        )
        node.get_logger().error(str(exc))
        return 1
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
