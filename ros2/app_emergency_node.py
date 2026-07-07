#!/usr/bin/env python3
"""VICA 앱의 비상정지 요청을 모터 E-stop 입력과 Nav2 goal 취소로 연결합니다.

이 노드는 소프트웨어 주행 차단기입니다. 인증된 물리 비상정지 회로를
대체하지 않습니다. 주행 속도 명령은 Nav2가 /cmd_vel로 발행하고,
keyboard_knob만 /cmd_vel을 구독해 CAN 모터 명령으로 변환해야 합니다.
"""

import json
from datetime import datetime, timezone
from typing import Any

import rclpy
from action_msgs.msg import GoalStatus, GoalStatusArray
from action_msgs.srv import CancelGoal
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import Bool, String
from std_srvs.srv import Trigger


class AppEmergencyNode(Node):
    """앱 요청을 받아 E-stop 입력을 만들고 현재 Nav2 목적지를 취소합니다."""

    def __init__(self) -> None:
        super().__init__("app_emergency_node")

        self.declare_parameter("request_topic", "/safety/emergency_stop_request")
        self.declare_parameter("state_topic", "/safety/emergency_stop_state")
        self.declare_parameter("app_emergency_stop_topic", "/app_emergency_stop")
        self.declare_parameter("estop_reset_service", "/estop_reset")
        self.declare_parameter("navigate_action_name", "/navigate_to_pose")
        self.declare_parameter("control_period_sec", 0.05)
        self.declare_parameter("state_period_sec", 1.0)

        request_topic = str(self.get_parameter("request_topic").value)
        state_topic = str(self.get_parameter("state_topic").value)
        app_estop_topic = str(self.get_parameter("app_emergency_stop_topic").value)
        estop_reset_service = str(self.get_parameter("estop_reset_service").value)
        action_name = str(self.get_parameter("navigate_action_name").value)

        self.emergency_active = False
        self.navigation_cancelled = True
        self._cancel_in_flight = False
        self._cancel_response_received = False
        self._cancel_request_sent = False
        self._reset_in_flight = False
        self._estop_reset_done = False
        self._reset_request_id = ""
        self._reset_allowed_after_ns = 0
        self._navigation_status_received = False
        self._has_active_navigation_goal = False
        self._current_active_goal_ids = set()
        self._blocked_goal_ids = set()
        self._last_cancel_attempt_ns = 0
        self._activation_request_id = ""

        self.state_publisher = self.create_publisher(String, state_topic, 10)
        self.goal_event_publisher = self.create_publisher(
            String,
            "/vica_goal_event",
            10,
        )
        self.app_estop_publisher = self.create_publisher(Bool, app_estop_topic, 10)

        self.create_subscription(String, request_topic, self.handle_request, 10)
        self.create_subscription(
            GoalStatusArray,
            f"{action_name.rstrip('/')}/_action/status",
            self.handle_navigation_status,
            10,
        )

        cancel_service = f"{action_name.rstrip('/')}/_action/cancel_goal"
        self.cancel_client = self.create_client(CancelGoal, cancel_service)
        self.estop_reset_client = self.create_client(Trigger, estop_reset_service)

        control_period = float(self.get_parameter("control_period_sec").value)
        state_period = float(self.get_parameter("state_period_sec").value)
        self.create_timer(control_period, self.control_tick)
        self.create_timer(state_period, self.publish_periodic_state)

        self.get_logger().info(
            "app_emergency_node ready: "
            f"app E-stop -> {app_estop_topic}, reset service -> {estop_reset_service}",
        )

    def handle_request(self, msg: String) -> None:
        """앱의 activate/reset/query JSON 요청을 처리합니다."""
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
        elif command in {"reset", "release"}:
            self.reset_emergency_stop(request_id)
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
        if command not in {"activate", "reset", "release", "query"}:
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
        """앱 E-stop 입력을 켜고 Nav2의 모든 활성 goal을 취소합니다."""
        self.emergency_active = True
        self.navigation_cancelled = False
        self._cancel_response_received = False
        self._cancel_request_sent = False
        self._reset_in_flight = False
        self._estop_reset_done = False
        self._reset_request_id = ""
        self._reset_allowed_after_ns = 0
        self._navigation_status_received = False
        self._blocked_goal_ids = set(self._current_active_goal_ids)
        self._activation_request_id = request_id
        self.publish_app_emergency_stop(True)
        self.publish_state(
            state="active",
            request_id=request_id,
            command="activate",
            message="비상정지가 활성화되었습니다. 기존 목적지를 취소하고 있습니다.",
        )
        self.try_cancel_navigation()
        self.get_logger().warn("Emergency stop activated by VICA Supervisor")

    def reset_emergency_stop(self, request_id: str) -> None:
        """앱 E-stop 입력을 내리고 모터 E-stop reset과 Nav2 goal 취소를 수행합니다."""
        self._reset_request_id = request_id
        self._estop_reset_done = False
        self._reset_allowed_after_ns = (
            self.get_clock().now().nanoseconds + 200_000_000
        )
        self.publish_app_emergency_stop(False)
        if not self.navigation_cancelled:
            self.try_cancel_navigation()
        self.publish_state(
            state="active",
            request_id=request_id,
            command="reset",
            message="비상정지 reset을 요청했습니다. 모터 래치 해제와 기존 목적지 취소를 확인하고 있습니다.",
        )
        self.try_reset_estop_latch()
        self.get_logger().info("Emergency stop reset requested by VICA Supervisor")

    def control_tick(self) -> None:
        """비상정지 중에는 Nav2 취소와 모터 E-stop reset을 재시도합니다."""
        if self.emergency_active and not self.navigation_cancelled:
            self.try_cancel_navigation()
        if self._reset_request_id and not self._estop_reset_done:
            self.publish_app_emergency_stop(False)
            self.try_reset_estop_latch()

    def try_cancel_navigation(self) -> None:
        """NavigateToPose CancelGoal 서비스로 모든 활성 goal의 취소를 요청합니다."""
        if self._cancel_in_flight or self.navigation_cancelled:
            return

        now_ns = self.get_clock().now().nanoseconds
        if now_ns - self._last_cancel_attempt_ns < 500_000_000:
            return
        self._last_cancel_attempt_ns = now_ns

        if not self.cancel_client.service_is_ready():
            self.complete_navigation_cancellation(
                "Nav2가 실행되지 않아 취소할 목적지가 없습니다."
            )
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
            and self.navigation_cancelled
        ):
            new_goal_ids = moving_goal_ids - self._blocked_goal_ids
            if new_goal_ids:
                self.publish_state(
                    state="inactive",
                    request_id="",
                    command="status",
                    message="새로운 목적지가 확인되었습니다.",
                )

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

    def complete_navigation_cancellation(
        self,
        reason: str = "비상정지로 기존 목적지 취소",
    ) -> None:
        """취소 승인 또는 활성 goal 없음이 확인되면 해제 가능한 상태로 전환합니다."""
        if self.navigation_cancelled:
            return
        self.navigation_cancelled = True
        self._cancel_request_sent = False
        self.publish_goal_event("goal_canceled", reason)
        if self._reset_request_id and self._estop_reset_done:
            self.complete_emergency_reset()
            return
        self.publish_state(
            state="active",
            request_id=self._activation_request_id,
            command="activate",
            message="비상정지가 활성화되었고 기존 목적지가 취소되었습니다.",
        )
        self.get_logger().warn("All NavigateToPose goals were canceled")

    def try_reset_estop_latch(self) -> None:
        """keyboard_knob의 /estop_reset 서비스를 호출해 모터 E-stop 래치를 해제합니다."""
        if self._reset_in_flight or self._estop_reset_done:
            return
        if self.get_clock().now().nanoseconds < self._reset_allowed_after_ns:
            return
        if not self.estop_reset_client.service_is_ready():
            return

        self._reset_in_flight = True
        future = self.estop_reset_client.call_async(Trigger.Request())
        future.add_done_callback(self.handle_estop_reset_result)

    def handle_estop_reset_result(self, future: Any) -> None:
        self._reset_in_flight = False
        request_id = self._reset_request_id
        try:
            response = future.result()
        except Exception as exc:  # ROS future exceptions vary by distribution.
            self.publish_state(
                state="failed",
                request_id=request_id,
                command="reset",
                message=f"모터 비상정지 reset 서비스 호출 실패: {exc}",
            )
            return

        if response is None or not response.success:
            message = (
                response.message
                if response is not None and response.message
                else "모터 비상정지 reset이 거부되었습니다."
            )
            self.publish_state(
                state="failed",
                request_id=request_id,
                command="reset",
                message=message,
            )
            return

        self._estop_reset_done = True
        if self.navigation_cancelled:
            self.complete_emergency_reset()
        else:
            self.publish_state(
                state="active",
                request_id=request_id,
                command="reset",
                message="모터 비상정지 reset 완료. 기존 목적지 취소를 확인하고 있습니다.",
            )

    def complete_emergency_reset(self) -> None:
        """모터 reset과 Nav2 취소가 모두 끝난 뒤 비활성 상태로 전환합니다."""
        request_id = self._reset_request_id
        self.emergency_active = False
        self._reset_request_id = ""
        self._reset_allowed_after_ns = 0
        self._blocked_goal_ids.update(self._current_active_goal_ids)
        self.publish_app_emergency_stop(False)
        self.publish_state(
            state="inactive",
            request_id=request_id,
            command="reset",
            message="비상정지 reset이 완료되었습니다. 기존 목적지는 취소되었습니다.",
        )
        self.get_logger().info("Emergency stop reset complete")

    def publish_app_emergency_stop(self, active: bool) -> None:
        msg = Bool()
        msg.data = active
        self.app_estop_publisher.publish(msg)

    def publish_periodic_state(self) -> None:
        """앱 재연결 시에도 현재 비상정지 상태를 복구할 수 있게 상태를 반복 발행합니다."""
        self.publish_app_emergency_stop(
            self.emergency_active and not self._reset_request_id
        )
        self.publish_state(
            state="active" if self.emergency_active else "inactive",
            request_id="",
            command="status",
            message=self.current_message(),
        )

    def current_message(self) -> str:
        if not self.emergency_active:
            return "비상정지가 비활성 상태입니다."
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
            "motor_output_blocked": self.emergency_active,
            "motion_hold_active": False,
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
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
