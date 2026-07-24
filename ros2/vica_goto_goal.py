#!/usr/bin/env python3
"""Mission Manager 공개 서비스로 목적지 UUID를 요청하는 CLI 도구.

이 도구는 destinations.yaml을 읽거나 NavigateToPose를 직접 호출하지 않는다.
목적지 존재·지도 일치·Safety·Nav2 준비 검증과 Goal 생성은 Mission Manager가 맡는다.
"""
from __future__ import annotations

import argparse
import sys
from uuid import UUID, uuid4

import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from vica_interfaces.srv import RequestDestination


class VicaGotoGoal(Node):
    """`/vica/mission/request_destination` 서비스의 테스트·유지보수용 client."""

    def __init__(self) -> None:
        super().__init__("vica_goto_goal")
        self.client = self.create_client(
            RequestDestination,
            "/vica/mission/request_destination",
        )

    def request_destination(
        self,
        map_id: str,
        destination_id: str,
        timeout_sec: float,
    ) -> tuple[bool, str]:
        if not self.client.wait_for_service(timeout_sec=timeout_sec):
            return False, "Mission Manager 목적지 요청 service가 없습니다."

        request = RequestDestination.Request()
        request.request_id = str(uuid4())
        request.map_id = map_id
        request.destination_id = destination_id
        future = self.client.call_async(request)
        rclpy.spin_until_future_complete(self, future, timeout_sec=timeout_sec)
        if not future.done():
            return False, "Mission Manager 응답 시간이 초과되었습니다."
        try:
            response = future.result()
        except Exception as exc:
            return False, f"Mission Manager 서비스 호출 실패: {exc}"
        if response is None:
            return False, "Mission Manager 응답이 없습니다."
        return bool(response.accepted), str(response.message)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Mission Manager를 통해 저장 목적지 UUID로 주행을 요청합니다.",
    )
    parser.add_argument("map_id", help="현재 Nav2 지도 ID")
    parser.add_argument("destination_id", help="destinations.yaml의 UUID v4")
    parser.add_argument("--timeout", type=float, default=5.0, help="서비스 제한시간(초)")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        parsed = UUID(args.destination_id)
    except ValueError:
        print("destination_id는 UUID여야 합니다.", file=sys.stderr)
        return 2
    if parsed.version != 4 or str(parsed) != args.destination_id.lower():
        print("destination_id는 canonical UUID v4여야 합니다.", file=sys.stderr)
        return 2

    rclpy.init()
    node = VicaGotoGoal()
    try:
        accepted, message = node.request_destination(
            args.map_id,
            str(parsed),
            args.timeout,
        )
        if accepted:
            node.get_logger().info(message)
            return 0
        node.get_logger().error(message)
        return 1
    except (KeyboardInterrupt, ExternalShutdownException):
        return 130
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
