// 이 파일은 지도별 장소 보기 화면으로, 지도 선택과 장소 마커 강조를 담당합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/map_canvas.dart';
import '../widgets/vica_ui.dart';

class MapLocationsScreen extends StatelessWidget {
  const MapLocationsScreen({super.key});

  static const _compactDropdownDecoration = InputDecoration(
    labelText: '지도 선택',
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  );

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final map = supervisor.selectedMap;
    final locations = supervisor.locationsFor(map?.mapId);

    return VicaPage(
      title: '지도별 장소 보기',
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: map?.mapId,
                decoration: _compactDropdownDecoration,
                isExpanded: true,
                itemHeight: null,
                items: supervisor.maps
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.mapId,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(item.mapName),
                        ),
                      ),
                    )
                    .toList(),
                selectedItemBuilder: (context) => supervisor.maps
                    .map(
                      (item) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.mapName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => supervisor.selectMap(settings, value),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: OutlinedButton.icon(
                onPressed: map == null
                    ? null
                    : () => supervisor.requestLocationList(settings, map.mapId),
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('동기화', maxLines: 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (map == null)
          const VicaCard(child: Text('지도 목록을 먼저 불러오세요.'))
        else ...[
          ResponsiveMapFrame(
            map: map,
            child: MapCanvas(
              map: map,
              settings: settings,
              locations: locations,
              selectedLocationId: supervisor.selectedLocationId,
              robot: supervisor.primaryRobot,
              onSelectLocation: (location) =>
                  supervisor.selectLocation(location.locationId),
            ),
          ),
          const SizedBox(height: 20),
          VicaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '저장 장소 목록',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    OutlinedButton(
                      onPressed: null,
                      child: Text('${locations.length}개'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: locations.map((location) {
                    final selected =
                        supervisor.selectedLocationId == location.locationId;
                    return ChoiceChip(
                      selected: selected,
                      avatar: Icon(
                        selected ? Icons.check_circle : Icons.location_on,
                        color:
                            selected ? VicaColors.text : VicaColors.primaryDark,
                        size: 18,
                      ),
                      label: Text(location.name),
                      onSelected: (_) =>
                          supervisor.selectLocation(location.locationId),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
