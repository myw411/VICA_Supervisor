#!/usr/bin/env python3
"""VICA_Supervisor의 장소 저장/삭제 topic을 받아 ~/ros2_ws/location을 갱신하는 ROS2 예시 노드입니다."""

import json
from pathlib import Path
from typing import Any

import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class LocationStorageNode(Node):
    """Flutter 앱의 저장/삭제 요청을 지도별 locations.json 파일에 반영합니다."""

    def __init__(self) -> None:
        super().__init__("vica_supervisor_location_storage")
        self.storage_root = Path.home() / "ros2_ws" / "location"
        self.storage_root.mkdir(parents=True, exist_ok=True)
        self.create_subscription(String, "/save_location", self.save_location, 10)
        self.create_subscription(
            String,
            "/location_list_request",
            self.list_locations,
            10,
        )
        self.create_subscription(
            String,
            "/delete_location_request",
            self.delete_location,
            10,
        )
        self.location_publisher = self.create_publisher(String, "/location_list", 10)

    def list_locations(self, msg: String) -> None:
        """장소 목록 요청을 받아 해당 map_id의 locations.json 내용을 publish합니다."""
        payload = self._decode(msg)
        map_id = payload.get("map_id", "")
        if not map_id:
            self.get_logger().warn("list_locations ignored: map_id missing")
            return
        self._publish_locations(map_id, self._read_locations(map_id))

    def save_location(self, msg: String) -> None:
        """장소 저장 요청을 받아 map_id 폴더의 locations.json에 upsert합니다."""
        payload = self._decode(msg)
        map_id = payload.get("map_id", "")
        location_id = payload.get("location_id", "")
        if not map_id or not location_id:
            self.get_logger().warn("save_location ignored: map_id/location_id missing")
            return
        locations = self._read_locations(map_id)
        locations = [item for item in locations if item.get("location_id") != location_id]
        locations.append(
            {
                "location_id": location_id,
                "map_id": map_id,
                "name": payload.get("name", ""),
                "category": payload.get("category", ""),
                "x": float(payload.get("x", 0.0)),
                "y": float(payload.get("y", 0.0)),
                "yaw": float(payload.get("yaw", 0.0)),
                "memo": payload.get("memo", ""),
            }
        )
        self._write_locations(map_id, locations)
        self._publish_locations(map_id, locations)

    def delete_location(self, msg: String) -> None:
        """장소 삭제 요청을 받아 locations.json에서 해당 location_id를 제거합니다."""
        payload = self._decode(msg)
        map_id = payload.get("map_id", "")
        location_id = payload.get("location_id", "")
        if not map_id or not location_id:
            self.get_logger().warn("delete_location ignored: map_id/location_id missing")
            return
        locations = [
            item
            for item in self._read_locations(map_id)
            if item.get("location_id") != location_id
        ]
        self._write_locations(map_id, locations)
        self._publish_locations(map_id, locations)

    def _decode(self, msg: String) -> dict[str, Any]:
        return json.loads(msg.data)

    def _file_path(self, map_id: str) -> Path:
        map_dir = self.storage_root / map_id
        map_dir.mkdir(parents=True, exist_ok=True)
        return map_dir / "locations.json"

    def _read_locations(self, map_id: str) -> list[dict[str, Any]]:
        path = self._file_path(map_id)
        if not path.exists():
            return []
        return json.loads(path.read_text(encoding="utf-8"))

    def _write_locations(self, map_id: str, locations: list[dict[str, Any]]) -> None:
        path = self._file_path(map_id)
        path.write_text(
            json.dumps(locations, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def _publish_locations(self, map_id: str, locations: list[dict[str, Any]]) -> None:
        msg = String()
        msg.data = json.dumps({"map_id": map_id, "locations": locations}, ensure_ascii=False)
        self.location_publisher.publish(msg)


def main() -> None:
    rclpy.init()
    node = LocationStorageNode()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
