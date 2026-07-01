#!/usr/bin/env python3
"""~/ros2_ws/maps의 지도 목록을 VICA_Supervisor 앱에 제공하는 ROS2 노드입니다.

연결 흐름:
    Flutter 앱
        -> /map_list_request
        -> MapListNode
        -> ~/ros2_ws/maps/*.png 및 같은 이름의 *.yaml 조회
        -> /map_list
        -> Flutter 앱

앱은 /map_list로 받은 image_url을 지도 HTTP 서버(app_mapserver)의 base URL과
합쳐 실제 PNG 지도를 불러옵니다. 이 노드는 지도 이미지를 직접 전송하지 않고,
지도 ID, 이미지 URL, resolution, origin, 이미지 크기 같은 메타데이터만 전송합니다.
"""

import json
from pathlib import Path
from typing import Any

import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class MapListNode(Node):
    """지도 목록 요청을 받으면 ~/ros2_ws/maps/*.png를 /map_list로 publish합니다.

    구독 topic:
        /map_list_request: 앱의 지도 목록 동기화 요청

    발행 topic:
        /map_list: 앱이 지도 드롭다운과 지도 캔버스에 사용할 지도 메타데이터
    """

    def __init__(self) -> None:
        super().__init__("vica_supervisor_map_list")

        # 앱에서 보여줄 지도 PNG와 Nav2 map yaml이 놓이는 기본 폴더입니다.
        self.maps_root = Path.home() / "ros2_ws" / "maps"

        # 앱이 시작되거나 동기화 버튼을 누르면 이 topic으로 빈 JSON/String 요청을 보냅니다.
        self.create_subscription(String, "/map_list_request", self.publish_maps, 10)

        # 지도 목록 응답은 std_msgs/String JSON으로 보냅니다.
        self.publisher = self.create_publisher(String, "/map_list", 10)

    def publish_maps(self, _: String) -> None:
        """PNG 지도와 같은 이름의 YAML 메타데이터를 읽어 map list JSON을 구성합니다.

        처리:
            1. ~/ros2_ws/maps/*.png를 정렬해 순회합니다.
            2. 같은 stem의 .yaml에서 resolution/origin을 읽습니다.
            3. PNG 헤더에서 width/height를 읽습니다.
            4. 앱이 이해하는 JSON 목록으로 묶어 /map_list에 publish합니다.
        """
        maps = []
        for image_path in sorted(self.maps_root.glob("*.png")):
            metadata = self._read_yaml_like_metadata(image_path.with_suffix(".yaml"))
            width, height = self._png_size(image_path)
            maps.append(
                {
                    "map_id": image_path.stem,
                    "map_name": image_path.stem,
                    "image_url": f"/maps/{image_path.name}",
                    "resolution": float(metadata.get("resolution", 0.05)),
                    "origin_x": float(metadata.get("origin_x", 0.0)),
                    "origin_y": float(metadata.get("origin_y", 0.0)),
                    "width": width,
                    "height": height,
                }
            )
        msg = String()
        msg.data = json.dumps({"maps": maps}, ensure_ascii=False)
        self.publisher.publish(msg)

    def _read_yaml_like_metadata(self, path: Path) -> dict[str, Any]:
        """외부 YAML 패키지 없이 ROS map yaml의 resolution/origin만 단순 파싱합니다.

        ROS map yaml은 보통 image, resolution, origin 등의 값을 가집니다.
        앱 좌표 변환에는 resolution과 origin x/y만 필요하므로 이 두 항목만 읽습니다.
        yaml 패키지 의존성을 추가하지 않기 위해 단순 문자열 파싱을 사용합니다.
        """
        metadata: dict[str, Any] = {}
        if not path.exists():
            # yaml이 없는 PNG도 지도 목록에는 보이게 하고 기본 resolution/origin을 씁니다.
            return metadata
        for line in path.read_text(encoding="utf-8").splitlines():
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            key = key.strip()
            value = value.strip()
            if key == "resolution":
                metadata["resolution"] = value
            elif key == "origin":
                origin = value.strip("[]").split(",")
                if len(origin) >= 2:
                    metadata["origin_x"] = origin[0].strip()
                    metadata["origin_y"] = origin[1].strip()
        return metadata

    def _png_size(self, path: Path) -> tuple[int, int]:
        """PNG IHDR 헤더에서 이미지 크기를 읽어 지도 좌표 변환에 사용합니다.

        Pillow 같은 이미지 라이브러리를 추가하지 않고 PNG 표준 헤더만 읽습니다.
        앱은 이 크기를 기준으로 ROS 좌표와 화면 픽셀 좌표를 변환합니다.
        """
        with path.open("rb") as file:
            signature = file.read(8)
            if signature != b"\x89PNG\r\n\x1a\n":
                return 1024, 1024
            file.read(8)
            width = int.from_bytes(file.read(4), "big")
            height = int.from_bytes(file.read(4), "big")
        return width, height


def main() -> None:
    """ROS2 노드를 초기화하고 지도 목록 요청 callback을 계속 대기합니다."""
    rclpy.init()
    node = MapListNode()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
