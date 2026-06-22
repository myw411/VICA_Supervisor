// 이 파일은 앱 테마, 상단 구조, 하단 NavigationBar 탭 구성을 담당합니다.
import 'package:flutter/material.dart';

import 'screens/current_location_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/map_locations_screen.dart';
import 'screens/robot_management_screen.dart';
import 'screens/save_location_screen.dart';
import 'screens/settings_screen.dart';

class VicaSupervisorApp extends StatelessWidget {
  const VicaSupervisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VICA_Supervisor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const SupervisorShell(),
    );
  }
}

class SupervisorShell extends StatefulWidget {
  const SupervisorShell({super.key});

  @override
  State<SupervisorShell> createState() => _SupervisorShellState();
}

class _SupervisorShellState extends State<SupervisorShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    MapLocationsScreen(),
    SaveLocationScreen(),
    CurrentLocationScreen(),
    RobotManagementScreen(),
    LogsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VICA_Supervisor'),
      ),
      body: SafeArea(child: _screens[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: '대시보드',
          ),
          NavigationDestination(
            icon: Icon(Icons.map),
            label: '지도',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_location),
            label: '장소 저장',
          ),
          NavigationDestination(
            icon: Icon(Icons.my_location),
            label: '현재 위치',
          ),
          NavigationDestination(
            icon: Icon(Icons.precision_manufacturing),
            label: '로봇',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications),
            label: '로그',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
