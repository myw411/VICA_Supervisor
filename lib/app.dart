// 이 파일은 앱 테마, 상단 구조, 하단 NavigationBar 탭 구성을 담당합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_settings.dart';
import 'providers/settings_provider.dart';
import 'providers/supervisor_provider.dart';
import 'widgets/vica_ui.dart';
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
        fontFamily: 'NanumGothic',
        scaffoldBackgroundColor: VicaColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: VicaColors.primary,
          surface: VicaColors.background,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFBF9FF),
          foregroundColor: VicaColors.text,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: VicaColors.text,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: VicaColors.text,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
          titleMedium: TextStyle(
            color: VicaColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
          bodyMedium: TextStyle(
            color: VicaColors.muted,
            fontSize: 16,
            height: 1.4,
            letterSpacing: 0,
          ),
          bodySmall: TextStyle(
            color: VicaColors.muted,
            fontSize: 13,
            height: 1.3,
            letterSpacing: 0,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Color(0xFFF8FAFD),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: VicaColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: VicaColors.primary, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: VicaColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
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
    SaveLocationScreen(),
    MapLocationsScreen(),
    CurrentLocationScreen(),
    RobotManagementScreen(),
    LogsScreen(),
    SettingsScreen(),
  ];

  static const _titles = [
    '대시보드',
    '장소 저장',
    '지도별 장소 보기',
    '현재 위치',
    '로봇 관리',
    '알림 및 로그',
    '설정',
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();

    return PopScope(
      canPop: !supervisor.emergencyOverlayVisible,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: Text(_titles[_index]),
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Tooltip(
                    message: '비상정지',
                    child: SizedBox.square(
                      dimension: 34,
                      child: Material(
                        color: Colors.red.shade700,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () =>
                              supervisor.activateEmergencyStop(settings),
                          child: const Center(
                            child: Icon(
                              Icons.warning_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _index = 0),
                  icon: const Icon(Icons.home_outlined),
                  tooltip: '대시보드',
                ),
                IconButton(
                  onPressed: () => setState(() => _index = 2),
                  icon: const Icon(Icons.map_outlined),
                  tooltip: '지도별 장소 보기',
                ),
                IconButton(
                  onPressed: () => setState(() => _index = 6),
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: '설정',
                ),
                const SizedBox(width: 10),
              ],
            ),
            drawer: NavigationDrawer(
              selectedIndex: _index,
              onDestinationSelected: (value) {
                Navigator.of(context).pop();
                setState(() => _index = value);
              },
              children: const [
                SizedBox(height: 20),
                Padding(
                  padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
                  child: Text('VICA_Supervisor'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.dashboard),
                  label: Text('대시보드'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.add_location),
                  label: Text('장소 저장'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.map),
                  label: Text('지도별 장소 보기'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.my_location),
                  label: Text('현재 위치'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.precision_manufacturing),
                  label: Text('로봇 관리'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.notifications),
                  label: Text('알림 및 로그'),
                ),
                NavigationDrawerDestination(
                  icon: Icon(Icons.settings),
                  label: Text('설정'),
                ),
              ],
            ),
            body: SafeArea(child: _screens[_index]),
          ),
          if (supervisor.emergencyOverlayVisible)
            Positioned.fill(
              child: _EmergencyStopOverlay(
                settings: settings,
                supervisor: supervisor,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmergencyStopOverlay extends StatelessWidget {
  const _EmergencyStopOverlay({
    required this.settings,
    required this.supervisor,
  });

  final AppSettings settings;
  final SupervisorProvider supervisor;

  @override
  Widget build(BuildContext context) {
    final state = supervisor.emergencyStopState;
    final isBusy = state == EmergencyStopState.activating ||
        state == EmergencyStopState.releasing;
    final isFailure = state == EmergencyStopState.activationFailed ||
        state == EmergencyStopState.releaseFailed;
    final title = switch (state) {
      EmergencyStopState.activating => '비상정지 요청 중',
      EmergencyStopState.active => '비상정지 활성화',
      EmergencyStopState.releasing => '비상정지 해제 중',
      EmergencyStopState.activationFailed => '비상정지 활성화 실패',
      EmergencyStopState.releaseFailed => '비상정지 해제 실패',
      EmergencyStopState.inactive => '',
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        const ModalBarrier(
          dismissible: false,
          color: Colors.black54,
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                elevation: 16,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isFailure
                        ? Colors.orange.shade700
                        : Colors.red.shade700,
                    width: 3,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: isFailure
                            ? Colors.orange.shade700
                            : Colors.red.shade700,
                        child: Icon(
                          isFailure
                              ? Icons.warning_amber_rounded
                              : Icons.warning_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        supervisor.emergencyStopMessage,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (isBusy)
                        const CircularProgressIndicator()
                      else
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => _handleAction(state),
                                style: FilledButton.styleFrom(
                                  backgroundColor: isFailure
                                      ? Colors.orange.shade800
                                      : Colors.red.shade800,
                                ),
                                icon: Icon(
                                  isFailure ? Icons.refresh : Icons.lock_open,
                                ),
                                label: Text(_actionLabel(state)),
                              ),
                            ),
                            if (state ==
                                EmergencyStopState.activationFailed) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      supervisor.dismissEmergencyStopFailure,
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('취소하고 돌아가기'),
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _actionLabel(EmergencyStopState state) {
    return switch (state) {
      EmergencyStopState.active => '비상정지 해제',
      EmergencyStopState.releaseFailed => '해제 다시 시도',
      EmergencyStopState.activationFailed => '비상정지 다시 시도',
      _ => '',
    };
  }

  void _handleAction(EmergencyStopState state) {
    switch (state) {
      case EmergencyStopState.active:
        supervisor.releaseEmergencyStop(settings);
        return;
      case EmergencyStopState.releaseFailed:
        supervisor.retryEmergencyStopRelease(settings);
        return;
      case EmergencyStopState.activationFailed:
        supervisor.retryEmergencyStop(settings);
        return;
      case EmergencyStopState.inactive:
      case EmergencyStopState.activating:
      case EmergencyStopState.releasing:
        return;
    }
  }
}
