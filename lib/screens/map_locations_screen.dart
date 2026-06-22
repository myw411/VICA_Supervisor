// 이 파일은 지도별 장소 보기 화면으로, 지도 선택과 장소 마커 강조를 담당합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/map_canvas.dart';

class MapLocationsScreen extends StatelessWidget {
  const MapLocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final map = supervisor.selectedMap;
    final locations = supervisor.locationsFor(map?.mapId);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: map?.mapId,
                  decoration: const InputDecoration(labelText: '지도 선택'),
                  items: supervisor.maps
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.mapId,
                          child: Text(item.mapName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => supervisor.selectMap(settings, value),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: map == null
                    ? null
                    : () => supervisor.requestLocationList(settings, map.mapId),
                icon: const Icon(Icons.refresh),
                tooltip: '장소 목록 새로고침',
              ),
            ],
          ),
        ),
        Expanded(
          child: map == null
              ? const Center(child: Text('지도 목록을 먼저 불러오세요.'))
              : Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: MapCanvas(
                        map: map,
                        settings: settings,
                        locations: locations,
                        selectedLocationId: supervisor.selectedLocationId,
                        robot: supervisor.primaryRobot,
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: ListView.builder(
                        itemCount: locations.length,
                        itemBuilder: (context, index) {
                          final location = locations[index];
                          final selected = supervisor.selectedLocationId ==
                              location.locationId;
                          return ListTile(
                            selected: selected,
                            title: Text(location.name),
                            subtitle: Text(
                              '${location.category}  x:${location.x.toStringAsFixed(2)} y:${location.y.toStringAsFixed(2)}',
                            ),
                            onTap: () =>
                                supervisor.selectLocation(location.locationId),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
