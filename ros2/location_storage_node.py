#!/usr/bin/env python3
"""VICA_Supervisor의 장소 저장/삭제 요청을 파일 저장소와 동기화하는 ROS2 노드입니다.

연결 흐름:
    Flutter 앱
        -> /save_location 또는 /delete_location_request 또는 /location_list_request
        -> LocationStorageNode
        -> ~/ros2_ws/location/<map_id>/locations.json 갱신/조회
        -> /location_list
        -> Flutter 앱

이 노드는 Nav2 주행에는 직접 관여하지 않습니다. 앱에서 관리자가 저장한 장소 좌표를
지도별 JSON 파일에 보관하고, 앱이 다시 동기화할 수 있도록 목록을 publish합니다.
"""

import json
from pathlib import Path
from typing import Any

import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class LocationStorageNode(Node):
    """Flutter 앱의 저장/삭제 요청을 지도별 locations.json 파일에 반영합니다.

    구독 topic:
        /save_location: 장소 하나를 저장하거나 같은 location_id를 갱신합니다.
        /location_list_request: 특정 map_id의 장소 목록을 요청합니다.
        /delete_location_request: 특정 location_id를 삭제합니다.

    발행 topic:
        /location_list: 요청 또는 변경 후 최신 장소 목록을 앱에 보냅니다.
    """

    def __init__(self) -> None:
        super().__init__("vica_supervisor_location_storage")

        # 지도별 장소 파일은 ros2_ws 아래 location 폴더에 저장합니다.
        # 예: ~/ros2_ws/location/vica_map_0604/locations.json
        self.storage_root = Path.home() / "ros2_ws" / "location"
        self.storage_root.mkdir(parents=True, exist_ok=True)

        # 앱이 장소 저장 버튼을 누르면 /save_location JSON이 들어옵니다.
        self.create_subscription(String, "/save_location", self.save_location, 10)

        # 앱이 지도 선택/동기화 시 해당 지도에 저장된 장소 목록을 요청합니다.
        self.create_subscription(
            String,
            "/location_list_request",
            self.list_locations,
            10,
        )

        # 앱이 저장 장소 삭제를 요청하면 파일에서도 같은 location_id를 제거합니다.
        self.create_subscription(
            String,
            "/delete_location_request",
            self.delete_location,
            10,
        )

        # 저장/삭제/목록 요청이 처리된 뒤 앱에 최신 목록을 돌려주는 publisher입니다.
        self.location_publisher = self.create_publisher(String, "/location_list", 10)

    def list_locations(self, msg: String) -> None:
        """장소 목록 요청을 받아 해당 map_id의 locations.json 내용을 publish합니다.

        입력 JSON 예:
            {"map_id": "vica_map_0604"}

        처리:
            1. 요청 JSON에서 map_id를 꺼냅니다.
            2. 해당 지도 폴더의 locations.json을 읽습니다.
            3. /location_list로 {"map_id": ..., "locations": [...]}를 보냅니다.
        """
        payload = self._decode(msg)
        map_id = payload.get("map_id", "")
        if not map_id:
            self.get_logger().warn("list_locations ignored: map_id missing")
            return
        self._publish_locations(map_id, self._read_locations(map_id))

    def save_location(self, msg: String) -> None:
        """장소 저장 요청을 받아 map_id 폴더의 locations.json에 upsert합니다.

        upsert 방식:
            같은 location_id가 이미 있으면 기존 항목을 제거한 뒤 새 값으로 다시 추가합니다.
            없으면 새 장소를 목록 끝에 추가합니다.

        입력 JSON에는 map_id, location_id, name, category, x, y, yaw, memo가 들어옵니다.
        저장 후에는 앱 화면이 바로 갱신되도록 최신 /location_list를 다시 publish합니다.
        """
        payload = self._decode(msg)
        map_id = payload.get("map_id", "")
        location_id = payload.get("location_id", "")
        if not map_id or not location_id:
            self.get_logger().warn("save_location ignored: map_id/location_id missing")
            return
        locations = self._read_locations(map_id)

        # 같은 location_id를 가진 기존 장소를 먼저 제거해 중복 저장을 막습니다.
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
        """장소 삭제 요청을 받아 locations.json에서 해당 location_id를 제거합니다.

        입력 JSON 예:
            {"map_id": "vica_map_0604", "location_id": "..."}

        삭제 후에는 앱의 목록/마커가 즉시 동기화되도록 최신 목록을 다시 publish합니다.
        """
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
        """std_msgs/String 안의 JSON 문자열을 Python dict로 변환합니다."""
        return json.loads(msg.data)

    def _file_path(self, map_id: str) -> Path:
        """map_id에 해당하는 locations.json 경로를 만들고 폴더가 없으면 생성합니다."""
        map_dir = self.storage_root / map_id
        map_dir.mkdir(parents=True, exist_ok=True)
        return map_dir / "locations.json"

    def _read_locations(self, map_id: str) -> list[dict[str, Any]]:
        """지도별 locations.json을 읽어 장소 dict 목록으로 반환합니다."""
        path = self._file_path(map_id)
        if not path.exists():
            # 아직 저장된 장소가 없는 지도는 빈 목록으로 취급합니다.
            return []
        return json.loads(path.read_text(encoding="utf-8"))

    def _write_locations(self, map_id: str, locations: list[dict[str, Any]]) -> None:
        """장소 목록을 사람이 읽기 쉬운 JSON 형태로 저장합니다."""
        path = self._file_path(map_id)
        path.write_text(
            json.dumps(locations, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def _publish_locations(self, map_id: str, locations: list[dict[str, Any]]) -> None:
        """앱이 받는 /location_list 메시지를 구성해 publish합니다."""
        msg = String()
        msg.data = json.dumps({"map_id": map_id, "locations": locations}, ensure_ascii=False)
        self.location_publisher.publish(msg)


def main() -> None:
    """ROS2 노드를 초기화하고 Ctrl+C가 올 때까지 callback 처리를 계속합니다."""
    rclpy.init()
    node = LocationStorageNode()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
