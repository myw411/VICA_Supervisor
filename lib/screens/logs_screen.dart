// 이 파일은 전체, 긴급 정지, 좌표 전송, 연결 상태 로그 필터와 삭제 기능을 제공합니다.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/log_filter.dart';
import '../providers/supervisor_provider.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  LogFilter _filter = LogFilter.all;
  final _format = DateFormat('HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final logs = _filter == LogFilter.all
        ? supervisor.logs
        : supervisor.logs.where((log) => log.filter == _filter).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SegmentedButton<LogFilter>(
                segments: LogFilter.values
                    .map(
                      (filter) => ButtonSegment(
                        value: filter,
                        label: Text(filter.label),
                      ),
                    )
                    .toList(),
                selected: {_filter},
                onSelectionChanged: (value) =>
                    setState(() => _filter = value.first),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => supervisor.clearLogs(_filter),
                icon: const Icon(Icons.delete_sweep),
                label: Text(_filter == LogFilter.all ? '전체 삭제' : '필터 삭제'),
              ),
            ],
          ),
        ),
        Expanded(
          child: logs.isEmpty
              ? const Center(child: Text('표시할 로그가 없습니다.'))
              : ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return ListTile(
                      leading: const Icon(Icons.event_note),
                      title: Text(log.message),
                      subtitle: Text('${log.filter.label} / ${_format.format(log.createdAt)}'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
