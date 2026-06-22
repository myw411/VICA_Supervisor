// 이 파일은 ROS 연결, 지도 연결, 로봇 요약, 최근 알림을 보여주는 대시보드 화면입니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/status_badge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final robot = supervisor.primaryRobot;
    final connected =
        supervisor.connectionState == RosConnectionState.connected;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            StatusBadge(
              label: connected ? 'ROS 연결됨' : 'ROS 미연결',
              color: connected ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            StatusBadge(
              label: supervisor.maps.isEmpty ? '지도 미수신' : '지도 ${supervisor.maps.length}개',
              color: supervisor.maps.isEmpty ? Colors.orange : Colors.blue,
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: connected
                  ? supervisor.disconnect
                  : () => supervisor.connect(settings),
              icon: Icon(connected ? Icons.link_off : Icons.link),
              label: Text(connected ? '연결 해제' : 'ROS 연결'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          supervisor.connectionDetail,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _Section(
          title: '로봇 상태 요약',
          child: robot == null
              ? const Text('수신된 로봇 상태가 없습니다.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${robot.robotName} / ${robot.status}'),
                    Text('배터리 ${robot.battery}%'),
                    Text('현재 위치: ${robot.currentLocation}'),
                    Text('목적지: ${robot.currentGoal}'),
                    if (robot.errorReason.isNotEmpty)
                      Text('오류: ${robot.errorReason}'),
                    if (robot.waitingReason.isNotEmpty)
                      Text('대기: ${robot.waitingReason}'),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '최근 알림',
          child: supervisor.logs.isEmpty
              ? const Text('최근 알림이 없습니다.')
              : Column(
                  children: supervisor.logs.take(5).map((log) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(log.message),
                      subtitle: Text(log.createdAt.toLocal().toString()),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: connected ? () => supervisor.requestMapList(settings) : null,
          icon: const Icon(Icons.map),
          label: const Text('지도 목록 새로고침'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
