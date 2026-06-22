// 이 파일은 원격 제어 없이 로봇의 현재 위치와 주행 상태를 지도 위에 표시합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vica_map.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/map_canvas.dart';

class CurrentLocationScreen extends StatelessWidget {
  const CurrentLocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final robot = supervisor.primaryRobot;
    final map = robot == null
        ? supervisor.selectedMap
        : _findMapById(supervisor.maps, robot.mapId);
    final locations = supervisor.locationsFor(map?.mapId);
    return robot == null
        ? const Center(child: Text('로봇 상태를 아직 수신하지 않았습니다.'))
        : Row(
            children: [
              Expanded(
                flex: 2,
                child: map == null
                    ? const Center(child: Text('현재 map_id와 일치하는 지도가 없습니다.'))
                    : MapCanvas(
                        map: map,
                        settings: settings,
                        locations: locations,
                        robot: robot,
                      ),
              ),
              SizedBox(
                width: 320,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(robot.robotName,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _Info(label: 'x', value: robot.x.toStringAsFixed(3)),
                    _Info(label: 'y', value: robot.y.toStringAsFixed(3)),
                    _Info(label: 'yaw', value: robot.yaw.toStringAsFixed(2)),
                    _Info(label: 'map_id', value: robot.mapId),
                    _Info(label: '현재 위치명', value: robot.currentLocation),
                    _Info(label: '목적지', value: robot.currentGoal),
                    _Info(label: '주행 상태', value: robot.status),
                    _Info(label: '오류 사유', value: robot.errorReason),
                    _Info(label: '대기 사유', value: robot.waitingReason),
                    _Info(label: '마지막 수신', value: robot.timestamp.toLocal().toString()),
                  ],
                ),
              ),
            ],
          );
  }

  VicaMap? _findMapById(List<VicaMap> maps, String mapId) {
    for (final map in maps) {
      if (map.mapId == mapId) {
        return map;
      }
    }
    return null;
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}
