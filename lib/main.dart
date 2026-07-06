// 이 파일은 VICA_Supervisor 앱의 진입점이며 provider들을 앱 전체에 등록합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/settings_provider.dart';
import 'providers/supervisor_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settingsProvider = SettingsProvider();
  await settingsProvider.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(create: (_) => SupervisorProvider()),
      ],
      child: const VicaSupervisorApp(),
    ),
  );
} 
