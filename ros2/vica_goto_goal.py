#!/usr/bin/env python3
"""저장된 VICA 장소 이름을 찾아 Nav2 NavigateToPose goal로 전송하는 노드입니다."""

import argparse
import json
import math
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import rclpy
from geometry_msgs.msg import PoseStamped
from nav2_msgs.action import NavigateToPose
from rclpy.action import ActionClient
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import String


@dataclass(frozen=True)
class SavedLocation:
    """locations.json에서 읽어온 목적지 좌표를 Nav2 goal로 넘기기 쉽게 담습니다."""

    location_id: str
    map_id: str
    name: str
    category: str
    x: float
    y: float
    yaw: float
    memo: str


class VicaGotoGoal(Node):
    """저장 장소 검색, 목적지 요청 기록, Nav2 goal 전송을 담당합니다."""

    def __init__(self) -> None:
        super().__init__("vica_goto_goal")
        self.storage_root = Path.home() / "ros2_ws" / "location"
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
        """터미널로 받은 목적지 요청을 topic으로 기록합니다."""
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
        """map_id의 locations.json에서 name 또는 location_id가 일치하는 장소를 찾습니다."""
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
        """저장 좌표를 NavigateToPose action goal로 변환해 Nav2에 전송합니다."""
        if not self.goal_client.wait_for_server(timeout_sec=5.0):
            self.publish_goal_event("goal_failed", location, "Nav2 action server 대기 시간 초과")
            self.get_logger().error("/navigate_to_pose action server is not available")
            return False

        goal_msg = NavigateToPose.Goal()
        goal_msg.pose = self._to_pose_stamped(location)

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
        result_future = goal_handle.get_result_async()
        rclpy.spin_until_future_complete(self, result_future)
        result = result_future.result()

        if result is None:
            self.publish_goal_event("goal_failed", location, "Nav2 result missing")
            return False

        status = int(result.status)
        if status == 4:
            self.publish_goal_event("goal_succeeded", location)
            self.get_logger().info(f"Goal succeeded: {location.name}")
            return True

        self.publish_goal_event("goal_failed", location, f"Nav2 result status={status}")
        self.get_logger().warn(f"Goal finished with status={status}: {location.name}")
        return False

    def publish_goal_event(
        self,
        event: str,
        location: SavedLocation,
        reason: str = "",
    ) -> None:
        """주행 요청 처리 상태를 /vica_goal_event에 publish합니다."""
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
        """목적지를 찾기 전 단계에서 발생한 실패도 /vica_goal_event로 알립니다."""
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
        """~/ros2_ws/location/<map_id>/locations.json 파일을 읽습니다."""
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
        """JSON dict를 SavedLocation으로 변환하고 필수 좌표값을 검증합니다."""
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
        """저장 좌표와 yaw degree를 Nav2가 사용하는 map frame PoseStamped로 변환합니다."""
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
        """2D yaw degree를 z/w quaternion 값으로 변환합니다."""
        yaw_radians = math.radians(yaw_degrees)
        return math.sin(yaw_radians / 2.0), math.cos(yaw_radians / 2.0)

    def _publish_json(self, publisher: Any, payload: dict[str, Any]) -> None:
        msg = String()
        msg.data = json.dumps(payload, ensure_ascii=False)
        publisher.publish(msg)
        rclpy.spin_once(self, timeout_sec=0.05)

    def _normalize(self, value: str) -> str:
        """목적지 비교 시 대소문자와 앞뒤 공백 차이를 무시합니다."""
        return value.strip().casefold()

    def _timestamp(self) -> str:
        return datetime.now().isoformat(timespec="seconds")


def parse_args(argv: list[str]) -> argparse.Namespace:
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
