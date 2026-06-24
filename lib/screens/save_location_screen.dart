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
  static const _defaultCategories = [
    '방',
    '화장실',
    '안내소',
    '입출구',
    '엘리베이터',
    '에스컬레이터',
  ];

  final _uuid = const Uuid();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _yawController = TextEditingController();
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
    final draft = supervisor.draftLocation;
    final previewLocation =
        draft ?? (map == null ? null : _previewLocation(map.mapId));

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
              width: 132,
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
                draftLocation: previewLocation,
                onTapMap: (ros) {
                  supervisor.setDraftLocation(null);
                  setState(() => _pickedRos = ros);
                  _showLocationInfoSheet(context, supervisor, map.mapId);
                },
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
                        '저장 장소',
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
                if (draft != null) ...[
                  const SizedBox(height: 14),
                  _DraftSummary(location: draft),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => supervisor.saveDraftLocation(settings),
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('ROS2에 장소 저장'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showLocationInfoSheet(
    BuildContext context,
    SupervisorProvider supervisor,
    String mapId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            minChildSize: 0.42,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return DecoratedBox(
                decoration: const BoxDecoration(
                  color: VicaColors.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: VicaColors.muted,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '장소 정보 패널',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (_pickedRos != null)
                      Text(
                        '선택 좌표 x:${_pickedRos!.dx.toStringAsFixed(3)} y:${_pickedRos!.dy.toStringAsFixed(3)}',
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '장소명',
                        hintText: '예: room_1',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _categoryController,
                      decoration: InputDecoration(
                        labelText: '카테고리',
                        hintText: '직접 입력 또는 선택',
                        suffixIcon: PopupMenuButton<String>(
                          icon: const Icon(Icons.arrow_drop_down),
                          onSelected: (value) =>
                              _categoryController.text = value,
                          itemBuilder: (context) => _defaultCategories
                              .map(
                                (category) => PopupMenuItem(
                                  value: category,
                                  child: Text(category),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _yawController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'yaw',
                        hintText: '0',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _memoController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '메모',
                        hintText: '장소 설명',
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _pickedRos == null
                          ? null
                          : () {
                              _saveDraft(supervisor, mapId);
                              Navigator.of(sheetContext).pop();
                            },
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('장소 임시 저장'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('취소'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  LocationPoint? _previewLocation(String mapId) {
    final picked = _pickedRos;
    if (picked == null) {
      return null;
    }
    return LocationPoint(
      locationId: 'preview_location',
      mapId: mapId,
      name: '선택 위치',
      category: '',
      x: picked.dx,
      y: picked.dy,
      yaw: 0,
      memo: '',
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
        name: _nameController.text.trim().isEmpty
            ? '새 장소'
            : _nameController.text.trim(),
        category: _categoryController.text.trim().isEmpty
            ? '방'
            : _categoryController.text.trim(),
        x: picked.dx,
        y: picked.dy,
        yaw: double.tryParse(_yawController.text.trim()) ?? 0,
        memo: _memoController.text.trim(),
      ),
    );
  }
}

class _DraftSummary extends StatelessWidget {
  const _DraftSummary({required this.location});

  final LocationPoint location;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VicaColors.softBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('임시 저장된 장소', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('이름: ${location.name}'),
          Text('카테고리: ${location.category}'),
          Text(
            '좌표: x ${location.x.toStringAsFixed(3)}, y ${location.y.toStringAsFixed(3)}, yaw ${location.yaw.toStringAsFixed(2)}',
          ),
          if (location.memo.isNotEmpty) Text('메모: ${location.memo}'),
        ],
      ),
    );
  }
}
