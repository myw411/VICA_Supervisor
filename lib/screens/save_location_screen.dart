// 이 파일은 지도 위 좌표 선택, 장소 정보 입력, 임시 저장, ROS2 저장 요청을 처리합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/location_point.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/map_canvas.dart';

class SaveLocationScreen extends StatefulWidget {
  const SaveLocationScreen({super.key});

  @override
  State<SaveLocationScreen> createState() => _SaveLocationScreenState();
}

class _SaveLocationScreenState extends State<SaveLocationScreen> {
  final _uuid = const Uuid();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController(text: 'default');
  final _yawController = TextEditingController(text: '0');
  final _memoController = TextEditingController();
  Offset? _pickedRos;

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _yawController.dispose();
    _memoController.dispose();
    super.dispose();
  }

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
          child: DropdownButtonFormField<String>(
            initialValue: map?.mapId,
            decoration: const InputDecoration(labelText: '저장할 지도'),
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
                        draftLocation: supervisor.draftLocation,
                        onTapMap: (ros) => setState(() => _pickedRos = ros),
                      ),
                    ),
                    SizedBox(
                      width: 320,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Text(
                            _pickedRos == null
                                ? '지도에서 위치를 선택하세요.'
                                : '선택 좌표 x:${_pickedRos!.dx.toStringAsFixed(3)} y:${_pickedRos!.dy.toStringAsFixed(3)}',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(labelText: '장소명'),
                          ),
                          TextField(
                            controller: _categoryController,
                            decoration: const InputDecoration(labelText: '카테고리'),
                          ),
                          TextField(
                            controller: _yawController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'yaw'),
                          ),
                          TextField(
                            controller: _memoController,
                            maxLines: 3,
                            decoration: const InputDecoration(labelText: '메모'),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _pickedRos == null
                                ? null
                                : () {
                                    final draft = LocationPoint(
                                      locationId: _uuid.v4(),
                                      mapId: map.mapId,
                                      name: _nameController.text.trim(),
                                      category: _categoryController.text.trim(),
                                      x: _pickedRos!.dx,
                                      y: _pickedRos!.dy,
                                      yaw: double.tryParse(
                                            _yawController.text.trim(),
                                          ) ??
                                          0,
                                      memo: _memoController.text.trim(),
                                    );
                                    supervisor.setDraftLocation(draft);
                                  },
                            icon: const Icon(Icons.add_location_alt),
                            label: const Text('장소 임시 저장'),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: supervisor.draftLocation == null
                                ? null
                                : () => supervisor.saveDraftLocation(settings),
                            icon: const Icon(Icons.cloud_upload),
                            label: const Text('ROS2에 장소 저장'),
                          ),
                          const SizedBox(height: 16),
                          ExpansionTile(
                            initiallyExpanded: true,
                            title: Text('저장된 장소 ${locations.length}개'),
                            children: locations.map((location) {
                              return ListTile(
                                title: Text(location.name),
                                subtitle: Text(location.memo),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete),
                                  tooltip: 'ROS2 저장 데이터에서도 삭제',
                                  onPressed: () => supervisor.deleteLocation(
                                    settings,
                                    location,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
