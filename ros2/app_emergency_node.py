#!/usr/bin/env python3
"""VICA 앱의 비상정지 요청을 모터 차단과 Nav2 goal 취소로 연결합니다.

이 노드는 소프트웨어 주행 차단기입니다. 인증된 물리 비상정지 회로를
대체하지 않습니다. 모든 주행 속도 명령은 반드시 input_cmd_vel_topic으로
들어와 이 노드의 output_cmd_vel_topic을 거쳐 모터 드라이버로 전달되어야 합니다.
"""

import json
import math
from datetime import datetime, timezone
from typing import Any

import rclpy
from action_msgs.msg import GoalStatus, GoalStatusArray
from action_msgs.srv import CancelGoal
from geometry_msgs.msg import Twist
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import String


class AppEmergencyNode(Node):
    """앱 요청을 받아 모터 명령을 차단하고 현재 Nav2 목적지를 취소합니다."""

    def __init__(self) -> None:
        super().__init__("app_emergency_node")

        self.declare_parameter("request_topic", "/safety/emergency_stop_request")
        self.declare_parameter("state_topic", "/safety/emergency_stop_state")
        self.declare_parameter("input_cmd_vel_topic", "/cmd_vel_raw")
        self.declare_parameter("output_cmd_vel_topic", "/cmd_vel")
        self.declare_parameter("navigate_action_name", "/navigate_to_pose")
        self.declare_parameter("control_period_sec", 0.05)
        self.declare_parameter("state_period_sec", 1.0)
        self.declare_parameter("command_timeout_sec", 0.5)
        self.declare_parameter("release_guard_sec", 0.5)
        self.declare_parameter("max_linear_speed", 1.0)
        self.declare_parameter("max_angular_speed", 2.0)

        request_topic = str(self.get_parameter("request_topic").value)
        state_topic = str(self.get_parameter("state_topic").value)
        input_topic = str(self.get_parameter("input_cmd_vel_topic").value)
        output_topic = str(self.get_parameter("output_cmd_vel_topic").value)
        action_name = str(self.get_parameter("navigate_action_name").value)

        self.emergency_active = False
        self.hold_active = False
        self.navigation_cancelled = True
        self._cancel_in_flight = False
        self._cancel_response_received = False
        self._cancel_request_sent = False
        self._navigation_status_received = False
        self._has_active_navigation_goal = False
        self._current_active_goal_ids = set()
        self._blocked_goal_ids = set()
        self._last_cancel_attempt_ns = 0
        self._last_input_ns = 0
        self._release_guard_until_ns = 0
        self._activation_request_id = ""

        self.state_publisher = self.create_publisher(String, state_topic, 10)
        self.goal_event_publisher = self.create_publisher(
            String,
            "/vica_goal_event",
            10,
        )
        self.cmd_vel_publisher = self.create_publisher(Twist, output_topic, 10)

        self.create_subscription(String, request_topic, self.handle_request, 10)
        self.create_subscription(Twist, input_topic, self.handle_cmd_vel, 10)
        self.create_subscription(
            GoalStatusArray,
            f"{action_name.rstrip('/')}/_action/status",
            self.handle_navigation_status,
            10,
        )

        cancel_service = f"{action_name.rstrip('/')}/_action/cancel_goal"
        self.cancel_client = self.create_client(CancelGoal, cancel_service)

        control_period = float(self.get_parameter("control_period_sec").value)
        state_period = float(self.get_parameter("state_period_sec").value)
        self.create_timer(control_period, self.control_tick)
        self.create_timer(state_period, self.publish_periodic_state)

        self.get_logger().info(
            "app_emergency_node ready: "
            f"{input_topic} -> safety gate -> {output_topic}",
        )

    def handle_request(self, msg: String) -> None:
        """앱의 activate/release/query JSON 요청을 처리합니다."""
        try:
            payload = json.loads(msg.data)
        except (json.JSONDecodeError, TypeError):
            self.publish_state(
                state="failed",
                request_id="",
                command="unknown",
                message="비상정지 요청 JSON 형식이 올바르지 않습니다.",
            )
            return

        request_id, command, validation_error = self.validate_request(payload)
        if validation_error:
            self.publish_state(
                state="failed",
                request_id=request_id,
                command=command or "unknown",
                message=validation_error,
            )
            return

        if command == "activate":
            self.activate_emergency_stop(request_id)
        elif command == "release":
            self.release_emergency_stop(request_id)
        elif command == "query":
            self.publish_state(
                state="active" if self.emergency_active else "inactive",
                request_id=request_id,
                command=command,
                message=self.current_message(),
            )
        else:
            self.publish_state(
                state="failed",
                request_id=request_id,
                command=command or "unknown",
                message=f"지원하지 않는 비상정지 명령입니다: {command}",
            )

    @staticmethod
    def validate_request(payload: Any) -> tuple[str, str, str]:
        """요청 객체와 필수 필드 형식을 검사하고 오류 메시지를 반환합니다."""
        if not isinstance(payload, dict):
            return "", "", "비상정지 요청 payload는 JSON 객체여야 합니다."

        raw_request_id = payload.get("request_id")
        if not isinstance(raw_request_id, str) or not raw_request_id.strip():
            return "", "", "request_id는 비어 있지 않은 문자열이어야 합니다."
        request_id = raw_request_id.strip()
        if len(request_id) > 128:
            return "", "", "request_id는 128자를 넘을 수 없습니다."

        raw_command = payload.get("command")
        if not isinstance(raw_command, str) or not raw_command.strip():
            return request_id, "", "command는 비어 있지 않은 문자열이어야 합니다."
        command = raw_command.strip().lower()
        if command not in {"activate", "release", "query"}:
            return request_id, command, f"지원하지 않는 비상정지 명령입니다: {command}"

        for field_name in ("source", "timestamp"):
            value = payload.get(field_name)
            if value is not None and not isinstance(value, str):
                return (
                    request_id,
                    command,
                    f"{field_name}는 문자열이어야 합니다.",
                )

        return request_id, command, ""

    def activate_emergency_stop(self, request_id: str) -> None:
        """모터 출력을 즉시 0으로 차단하고 Nav2의 모든 활성 goal을 취소합니다."""
        self.emergency_active = True
        self.hold_active = True
        self.navigation_cancelled = False
        self._cancel_response_received = False
        self._cancel_request_sent = False
        self._navigation_status_received = False
        self._blocked_goal_ids = set(self._current_active_goal_ids)
        self._activation_request_id = request_id
        self.publish_zero_velocity()
        self.publish_state(
            state="active",
            request_id=request_id,
            command="activate",
            message="비상정지가 활성화되었습니다. 기존 목적지를 취소하고 있습니다.",
        )
        self.try_cancel_navigation()
        self.get_logger().warn("Emergency stop activated by VICA Supervisor")

    def release_emergency_stop(self, request_id: str) -> None:
        """Nav2 goal 취소가 확인된 경우에만 비상정지 래치를 해제합니다."""
        if self.emergency_active and not self.navigation_cancelled:
            self.publish_state(
                state="failed",
                request_id=request_id,
                command="release",
                message="기존 목적지 취소가 아직 확인되지 않아 해제할 수 없습니다.",
            )
            self.try_cancel_navigation()
            return

        self.emergency_active = False
        self.hold_active = True
        self._blocked_goal_ids.update(self._current_active_goal_ids)
        now_ns = self.get_clock().now().nanoseconds
        guard_sec = float(self.get_parameter("release_guard_sec").value)
        self._release_guard_until_ns = now_ns + int(guard_sec * 1_000_000_000)
        self._last_input_ns = 0
        self.publish_zero_velocity()
        self.publish_state(
            state="inactive",
            request_id=request_id,
            command="release",
            message="비상정지가 해제되었습니다. 새로운 목적지를 기다리는 HOLD 상태입니다.",
        )
        self.get_logger().info(
            "Emergency stop released; HOLD remains until a new Nav2 goal",
        )

    def handle_cmd_vel(self, msg: Twist) -> None:
        """안전 범위의 새 속도 명령만 모터 드라이버 쪽으로 전달합니다."""
        now_ns = self.get_clock().now().nanoseconds
        self._last_input_ns = now_ns

        if (
            self.emergency_active
            or self.hold_active
            or now_ns < self._release_guard_until_ns
        ):
            self.publish_zero_velocity()
            return

        if not self.is_safe_velocity(msg):
            self.get_logger().error("Unsafe cmd_vel rejected; publishing zero velocity")
            self.publish_zero_velocity()
            return

        self.cmd_vel_publisher.publish(msg)

    def is_safe_velocity(self, msg: Twist) -> bool:
        """NaN/무한대와 설정된 최대 선속도·각속도를 넘는 명령을 거부합니다."""
        values = (
            msg.linear.x,
            msg.linear.y,
            msg.linear.z,
            msg.angular.x,
            msg.angular.y,
            msg.angular.z,
        )
        if not all(math.isfinite(value) for value in values):
            return False

        max_linear = float(self.get_parameter("max_linear_speed").value)
        max_angular = float(self.get_parameter("max_angular_speed").value)
        linear_safe = all(abs(value) <= max_linear for value in values[:3])
        angular_safe = all(abs(value) <= max_angular for value in values[3:])
        return linear_safe and angular_safe

    def control_tick(self) -> None:
        """정지 중에는 0 속도를 반복 발행하고 Nav2 취소를 재시도합니다."""
        now_ns = self.get_clock().now().nanoseconds

        if self.emergency_active or self.hold_active:
            self.publish_zero_velocity()
            if self.emergency_active and not self.navigation_cancelled:
                self.try_cancel_navigation()
            return

        if now_ns < self._release_guard_until_ns:
            self.publish_zero_velocity()
            return

        timeout_sec = float(self.get_parameter("command_timeout_sec").value)
        command_expired = (
            self._last_input_ns == 0
            or now_ns - self._last_input_ns > int(timeout_sec * 1_000_000_000)
        )
        if command_expired:
            self.publish_zero_velocity()

    def try_cancel_navigation(self) -> None:
        """NavigateToPose CancelGoal 서비스로 모든 활성 goal의 취소를 요청합니다."""
        if self._cancel_in_flight or self.navigation_cancelled:
            return

        now_ns = self.get_clock().now().nanoseconds
        if now_ns - self._last_cancel_attempt_ns < 500_000_000:
            return
        self._last_cancel_attempt_ns = now_ns

        if not self.cancel_client.service_is_ready():
            return

        self._cancel_in_flight = True
        self._cancel_request_sent = True
        self._navigation_status_received = False
        request = CancelGoal.Request()
        future = self.cancel_client.call_async(request)
        future.add_done_callback(self.handle_cancel_result)

    def handle_navigation_status(self, msg: GoalStatusArray) -> None:
        """Nav2에 취소되지 않은 활성 goal이 남아 있는지 추적합니다."""
        active_states = {
            GoalStatus.STATUS_ACCEPTED,
            GoalStatus.STATUS_EXECUTING,
            GoalStatus.STATUS_CANCELING,
        }
        movable_states = {
            GoalStatus.STATUS_ACCEPTED,
            GoalStatus.STATUS_EXECUTING,
        }
        self._current_active_goal_ids = {
            self.goal_id(status.goal_info)
            for status in msg.status_list
            if status.status in active_states
        }
        moving_goal_ids = {
            self.goal_id(status.goal_info)
            for status in msg.status_list
            if status.status in movable_states
        }
        self._has_active_navigation_goal = bool(self._current_active_goal_ids)

        if self._cancel_request_sent:
            self._navigation_status_received = True

        if self.emergency_active:
            new_goal_ids = moving_goal_ids - self._blocked_goal_ids
            if new_goal_ids:
                self._blocked_goal_ids.update(new_goal_ids)
                self.navigation_cancelled = False
                self._cancel_response_received = False
                self._cancel_request_sent = False
                self.try_cancel_navigation()

        if (
            self.emergency_active
            and self._cancel_response_received
            and self._navigation_status_received
            and not self._has_active_navigation_goal
        ):
            self.complete_navigation_cancellation()
            return

        if (
            not self.emergency_active
            and self.hold_active
            and self.navigation_cancelled
        ):
            new_goal_ids = moving_goal_ids - self._blocked_goal_ids
            if new_goal_ids:
                self.hold_active = False
                self._release_guard_until_ns = 0
                self.publish_state(
                    state="inactive",
                    request_id="",
                    command="status",
                    message="새로운 목적지가 확인되어 HOLD 상태를 해제했습니다.",
                )
                self.get_logger().info("HOLD released by a new Nav2 goal")

    def handle_cancel_result(self, future: Any) -> None:
        """취소 서비스가 응답하면 이전 목적지가 더 이상 재개되지 않도록 확정합니다."""
        self._cancel_in_flight = False
        try:
            response = future.result()
        except Exception as exc:  # ROS future exceptions vary by distribution.
            self._cancel_request_sent = False
            self.get_logger().error(f"Nav2 goal cancellation failed: {exc}")
            return

        if response is None:
            return

        self._cancel_response_received = True
        cancel_accepted = response.return_code == CancelGoal.Response.ERROR_NONE
        if cancel_accepted:
            self._blocked_goal_ids.update(
                self.goal_id(goal_info) for goal_info in response.goals_canceling
            )
        no_active_goal = (
            self._navigation_status_received
            and not self._has_active_navigation_goal
        )
        if not cancel_accepted and not no_active_goal:
            self.get_logger().error(
                "Nav2 rejected goal cancellation; emergency stop remains latched",
            )
            return

        self.complete_navigation_cancellation()

    def complete_navigation_cancellation(self) -> None:
        """취소 승인 또는 활성 goal 없음이 확인되면 해제 가능한 상태로 전환합니다."""
        if self.navigation_cancelled:
            return
        self.navigation_cancelled = True
        self._cancel_request_sent = False
        self.publish_goal_event("goal_canceled", "비상정지로 기존 목적지 취소")
        self.publish_state(
            state="active",
            request_id=self._activation_request_id,
            command="activate",
            message="비상정지가 활성화되었고 기존 목적지가 취소되었습니다.",
        )
        self.get_logger().warn("All NavigateToPose goals were canceled")

    def publish_zero_velocity(self) -> None:
        """모터 드라이버 입력 topic에 완전한 0 Twist를 발행합니다."""
        self.cmd_vel_publisher.publish(Twist())

    def publish_periodic_state(self) -> None:
        """앱 재연결 시에도 현재 비상정지 상태를 복구할 수 있게 상태를 반복 발행합니다."""
        self.publish_state(
            state="active" if self.emergency_active else "inactive",
            request_id="",
            command="status",
            message=self.current_message(),
        )

    def current_message(self) -> str:
        if not self.emergency_active:
            if self.hold_active:
                return "비상정지가 해제되었으며 새로운 목적지를 기다리는 HOLD 상태입니다."
            return "비상정지가 해제된 상태입니다."
        if self.navigation_cancelled:
            return "비상정지가 활성화되었고 기존 목적지가 취소되었습니다."
        return "비상정지는 활성화되었으며 기존 목적지 취소를 확인하고 있습니다."

    def publish_state(
        self,
        *,
        state: str,
        request_id: str,
        command: str,
        message: str,
    ) -> None:
        payload = {
            "node": "app_emergency_node",
            "request_id": request_id,
            "command": command,
            "state": state,
            "active": self.emergency_active,
            "motor_output_blocked": self.emergency_active
            or self.hold_active
            or self.get_clock().now().nanoseconds < self._release_guard_until_ns,
            "motion_hold_active": self.hold_active,
            "navigation_cancelled": self.navigation_cancelled,
            "message": message,
            "timestamp": self.timestamp(),
        }
        self.publish_json(self.state_publisher, payload)

    def publish_goal_event(self, event: str, reason: str) -> None:
        self.publish_json(
            self.goal_event_publisher,
            {
                "event": event,
                "reason": reason,
                "source": "app_emergency_node",
                "timestamp": self.timestamp(),
            },
        )

    @staticmethod
    def publish_json(publisher: Any, payload: dict[str, Any]) -> None:
        msg = String()
        msg.data = json.dumps(payload, ensure_ascii=False)
        publisher.publish(msg)

    @staticmethod
    def timestamp() -> str:
        return datetime.now(timezone.utc).isoformat(timespec="seconds")

    @staticmethod
    def goal_id(goal_info: Any) -> tuple[int, ...]:
        return tuple(int(value) for value in goal_info.goal_id.uuid)


def main() -> None:
    rclpy.init()
    node = AppEmergencyNode()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.publish_zero_velocity()
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
