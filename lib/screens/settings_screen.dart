// 이 파일은 rosbridge 주소, 지도 서버 주소, topic 이름, 동기화와 좌표 보정 설정을 편집합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings = context.watch<SettingsProvider>().settings;
    _syncControllers(_settings);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Field(controller: _c('rosBridgeUrl'), label: 'ROS Bridge WebSocket 주소'),
        _Field(controller: _c('mapHttpBaseUrl'), label: '지도 HTTP 서버 주소'),
        _Field(controller: _c('locationStorageRoot'), label: '좌표 저장 루트'),
        const SizedBox(height: 12),
        Text('Topic 이름', style: Theme.of(context).textTheme.titleMedium),
        _Field(controller: _c('mapListRequestTopic'), label: '지도 목록 요청 topic'),
        _Field(controller: _c('mapListTopic'), label: '지도 목록 topic'),
        _Field(controller: _c('locationListRequestTopic'), label: '장소 목록 요청 topic'),
        _Field(controller: _c('locationListTopic'), label: '장소 목록 topic'),
        _Field(controller: _c('saveLocationTopic'), label: '장소 저장 topic'),
        _Field(controller: _c('deleteLocationRequestTopic'), label: '장소 삭제 요청 topic'),
        _Field(controller: _c('robotStatusTopic'), label: '로봇 상태 topic'),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('지도 목록 자동 요청'),
          value: _settings.autoRequestMapList,
          onChanged: (value) => setState(
            () => _settings = _settings.copyWith(autoRequestMapList: value),
          ),
        ),
        SwitchListTile(
          title: const Text('장소 목록 자동 요청'),
          value: _settings.autoRequestLocationList,
          onChanged: (value) => setState(
            () => _settings = _settings.copyWith(autoRequestLocationList: value),
          ),
        ),
        ExpansionTile(
          title: const Text('고급 설정'),
          children: [
            _Field(controller: _c('xOffset'), label: 'x 보정값', number: true),
            _Field(controller: _c('yOffset'), label: 'y 보정값', number: true),
            _Field(controller: _c('yawOffset'), label: 'yaw 보정값', number: true),
            _Field(controller: _c('mapScale'), label: '지도 스케일 보정값', number: true),
            SwitchListTile(
              title: const Text('지도 Y축 반전'),
              value: _settings.flipMapY,
              onChanged: (value) => setState(
                () => _settings = _settings.copyWith(flipMapY: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('설정 저장'),
        ),
      ],
    );
  }

  TextEditingController _c(String key) => _controllers[key]!;

  void _syncControllers(AppSettings settings) {
    final values = {
      'rosBridgeUrl': settings.rosBridgeUrl,
      'mapHttpBaseUrl': settings.mapHttpBaseUrl,
      'locationStorageRoot': settings.locationStorageRoot,
      'mapListRequestTopic': settings.mapListRequestTopic,
      'mapListTopic': settings.mapListTopic,
      'locationListRequestTopic': settings.locationListRequestTopic,
      'locationListTopic': settings.locationListTopic,
      'saveLocationTopic': settings.saveLocationTopic,
      'deleteLocationRequestTopic': settings.deleteLocationRequestTopic,
      'robotStatusTopic': settings.robotStatusTopic,
      'xOffset': settings.xOffset.toString(),
      'yOffset': settings.yOffset.toString(),
      'yawOffset': settings.yawOffset.toString(),
      'mapScale': settings.mapScale.toString(),
    };
    for (final entry in values.entries) {
      _controllers.putIfAbsent(
        entry.key,
        () => TextEditingController(text: entry.value),
      );
      if (_controllers[entry.key]!.text.isEmpty) {
        _controllers[entry.key]!.text = entry.value;
      }
    }
  }

  // 입력된 문자열을 AppSettings로 변환해 저장합니다.
  Future<void> _save() async {
    final next = _settings.copyWith(
      rosBridgeUrl: _c('rosBridgeUrl').text.trim(),
      mapHttpBaseUrl: _c('mapHttpBaseUrl').text.trim(),
      locationStorageRoot: _c('locationStorageRoot').text.trim(),
      mapListRequestTopic: _c('mapListRequestTopic').text.trim(),
      mapListTopic: _c('mapListTopic').text.trim(),
      locationListRequestTopic: _c('locationListRequestTopic').text.trim(),
      locationListTopic: _c('locationListTopic').text.trim(),
      saveLocationTopic: _c('saveLocationTopic').text.trim(),
      deleteLocationRequestTopic: _c('deleteLocationRequestTopic').text.trim(),
      robotStatusTopic: _c('robotStatusTopic').text.trim(),
      xOffset: double.tryParse(_c('xOffset').text.trim()) ?? 0,
      yOffset: double.tryParse(_c('yOffset').text.trim()) ?? 0,
      yawOffset: double.tryParse(_c('yawOffset').text.trim()) ?? 0,
      mapScale: double.tryParse(_c('mapScale').text.trim()) ?? 1,
    );
    await context.read<SettingsProvider>().update(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장했습니다.')),
      );
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.number = false,
  });

  final TextEditingController controller;
  final String label;
  final bool number;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
