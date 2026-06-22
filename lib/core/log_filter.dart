// 이 파일은 알림 및 로그 화면에서 사용하는 필터 종류를 정의합니다.
enum LogFilter {
  all('전체'),
  emergencyStop('긴급 정지'),
  coordinateTransfer('좌표 전송'),
  connection('연결 상태');

  const LogFilter(this.label);

  final String label;
}
