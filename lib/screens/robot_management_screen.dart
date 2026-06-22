// 이 파일은 로봇 카드 목록과 선택한 로봇의 상세 상태를 표시합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/robot_status.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/status_badge.dart';

class RobotManagementScreen extends StatefulWidget {
  const RobotManagementScreen({super.key});

  @override
  State<RobotManagementScreen> createState() => _RobotManagementScreenState();
}

class _RobotManagementScreenState extends State<RobotManagementScreen> {
  String? _selectedRobotId;

  @override
  Widget build(BuildContext context) {
    final robots = context.watch<SupervisorProvider>().robots;
    final selected = _selectedRobotId == null
        ? (robots.isEmpty ? null : robots.first)
        : _findRobot(robots, _selectedRobotId!);
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: robots.isEmpty
              ? const Center(child: Text('로봇 상태 수신 대기 중'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: robots.length,
                  itemBuilder: (context, index) {
                    final robot = robots[index];
                    return Card(
                      child: ListTile(
                        selected: selected?.robotId == robot.robotId,
                        title: Text(robot.robotName),
                        subtitle: Text('${robot.status} / 배터리 ${robot.battery}%'),
                        trailing: robot.hasError
                            ? const Icon(Icons.warning, color: Colors.red)
                            : const Icon(Icons.check_circle, color: Colors.green),
                        onTap: () => setState(
                          () => _selectedRobotId = robot.robotId,
                        ),
                      ),
                    );
                  },
                ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const Center(child: Text('로봇을 선택하세요.'))
              : _RobotDetail(robot: selected),
        ),
      ],
    );
  }

  RobotStatus? _findRobot(List<RobotStatus> robots, String robotId) {
    for (final robot in robots) {
      if (robot.robotId == robotId) {
        return robot;
      }
    }
    return null;
  }
}

class _RobotDetail extends StatelessWidget {
  const _RobotDetail({required this.robot});

  final RobotStatus robot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Text(robot.robotName, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(width: 12),
            StatusBadge(
              label: robot.status,
              color: robot.hasError ? Colors.red : Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Info(label: '현재 위치', value: robot.currentLocation),
        _Info(label: '좌표', value: 'x ${robot.x}, y ${robot.y}, yaw ${robot.yaw}'),
        _Info(label: '목적지', value: robot.currentGoal),
        _Info(label: '오류 사유', value: robot.errorReason),
        _Info(label: '대기 사유', value: robot.waitingReason),
        _Info(label: '마지막 통신', value: robot.timestamp.toLocal().toString()),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}
