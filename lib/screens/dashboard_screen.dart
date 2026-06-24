// 이 파일은 ROS 연결, 지도 연결, 로봇 요약, 최근 알림을 카드형 대시보드로 보여줍니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/robot_status.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/vica_ui.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const double metricLabelFontSize = 16;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final connected =
        supervisor.connectionState == RosConnectionState.connected;
    final robots = supervisor.robots;
    final moving = robots.where((robot) => robot.status == 'moving').length;
    final errors = robots.where((robot) => robot.hasError).length;
    final waiting = robots.where((robot) => robot.status != 'moving').length;
    final robot = supervisor.primaryRobot ?? _waitingRobot();

    return VicaPage(
      title: '로봇 현황',
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: connected
                    ? supervisor.disconnect
                    : () => supervisor.connect(settings),
                icon: Icon(
                  connected ? Icons.check_circle : Icons.radio_button_unchecked,
                ),
                label: Text(connected ? 'ROS 연결됨' : 'ROS 연결'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: connected
                    ? () => supervisor.requestMapList(settings)
                    : null,
                icon: Icon(
                  supervisor.maps.isEmpty
                      ? Icons.radio_button_unchecked
                      : Icons.check_circle,
                ),
                label: Text(
                  supervisor.maps.isEmpty ? '지도 미연결' : '지도 연결됨',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.7,
          children: [
            VicaMetricCard(
              icon: Icons.smart_toy,
              label: '전체 로봇',
              value: robots.length.toString(),
              color: VicaColors.primaryDark,
              labelFontSize: metricLabelFontSize,
            ),
            VicaMetricCard(
              icon: Icons.navigation,
              label: '운행 중',
              value: moving.toString(),
              color: VicaColors.green,
              labelFontSize: metricLabelFontSize,
            ),
            VicaMetricCard(
              icon: Icons.hourglass_empty,
              label: '대기 중',
              value: waiting.toString(),
              color: Colors.blueAccent,
              labelFontSize: metricLabelFontSize,
            ),
            VicaMetricCard(
              icon: Icons.warning,
              label: '오류/긴급 정지',
              value: errors.toString(),
              color: VicaColors.red,
              labelMaxLines: 2,
              labelFontSize: metricLabelFontSize,
            ),
          ],
        ),
        const VicaSectionTitle('로봇 상태'),
        VicaRobotCard(robot: robot),
        const VicaSectionTitle('최근 알림'),
        if (supervisor.logs.isEmpty)
          const VicaCard(child: Text('최근 알림이 없습니다.'))
        else
          ...supervisor.logs.take(3).map((log) => VicaLogTile(log: log)),
      ],
    );
  }

  RobotStatus _waitingRobot() {
    return RobotStatus(
      robotId: 'robot_status_waiting',
      robotName: '로봇 상태 수신 대기',
      status: 'waiting',
      x: 0,
      y: 0,
      yaw: 0,
      currentLocation: '수신 대기',
      currentGoal: '없음',
      battery: 0,
      errorReason: '',
      waitingReason: '로봇 상태 메시지 수신 대기',
      mapId: '',
      timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
    );
  }
}
