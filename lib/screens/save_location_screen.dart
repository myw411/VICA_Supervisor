// 이 파일은 지도 위 좌표 선택, 장소 정보 입력, 임시 저장, ROS2 저장 요청을 처리합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/location_point.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/map_canvas.dart';
import '../widgets/vica_ui.dart';

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
  String? _deleteTargetId;

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
    final deleteTarget = _selectedLocation(locations);

    return VicaPage(
      title: '장소 저장',
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: map?.mapId,
                decoration: const InputDecoration(labelText: '불러올 지도'),
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
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: OutlinedButton.icon(
                onPressed: map == null
                    ? null
                    : () => supervisor.requestLocationList(settings, map.mapId),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('새로고침'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (map == null)
          const VicaCard(child: Text('지도 목록을 먼저 불러오세요.'))
        else ...[
          SizedBox(
            height: 390,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MapCanvas(
                map: map,
                settings: settings,
                locations: locations,
                draftLocation: supervisor.draftLocation,
                onTapMap: (ros) => setState(() => _pickedRos = ros),
              ),
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
                        '저장된 장소',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    OutlinedButton(onPressed: null, child: Text('${locations.length}개')),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: deleteTarget?.locationId,
                  decoration: const InputDecoration(labelText: '장소 선택'),
                  items: locations
                      .map(
                        (location) => DropdownMenuItem(
                          value: location.locationId,
                          child: Text(location.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _deleteTargetId = value),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: deleteTarget == null
                      ? null
                      : () => supervisor.deleteLocation(settings, deleteTarget),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('선택 장소 삭제'),
                ),
              ],
            ),
          ),
          VicaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '장소 정보 패널',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickedRos == null
                          ? null
                          : () => _saveDraft(supervisor, map.mapId),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('수정'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
                TextField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: '카테고리'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _yawController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'yaw'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _memoController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '메모'),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _pickedRos == null
                      ? null
                      : () => _saveDraft(supervisor, map.mapId),
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('장소 임시 저장'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: supervisor.draftLocation == null
                      ? null
                      : () => supervisor.saveDraftLocation(settings),
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('ROS2에 장소 저장'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  LocationPoint? _selectedLocation(List<LocationPoint> locations) {
    if (locations.isEmpty) {
      return null;
    }
    for (final location in locations) {
      if (location.locationId == _deleteTargetId) {
        return location;
      }
    }
    return locations.first;
  }

  void _saveDraft(SupervisorProvider supervisor, String mapId) {
    final picked = _pickedRos;
    if (picked == null) {
      return;
    }
    supervisor.setDraftLocation(
      LocationPoint(
        locationId: _uuid.v4(),
        mapId: mapId,
        name: _nameController.text.trim(),
        category: _categoryController.text.trim(),
        x: picked.dx,
        y: picked.dy,
        yaw: double.tryParse(_yawController.text.trim()) ?? 0,
        memo: _memoController.text.trim(),
      ),
    );
  }
}
