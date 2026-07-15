import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/map_coordinate.dart';
import 'package:vica_supervisor/models/vica_map.dart';

void main() {
  const map = VicaMap(
    mapId: 'test_map',
    mapName: '테스트 지도',
    imageUrl: '/test.png',
    resolution: 0.05,
    originX: -10,
    originY: -5,
    width: 1000,
    height: 800,
  );

  test('화면 표시 크기와 무관한 원본 픽셀 좌표 왕복 변환', () {
    const rosX = 3.125;
    const rosY = -1.75;

    final pixel = MapCoordinate.rosToPixel(
      map: map,
      x: rosX,
      y: rosY,
      flipY: true,
      xOffset: 0.2,
      yOffset: -0.1,
      scale: 1.25,
    );
    final restored = MapCoordinate.pixelToRos(
      map: map,
      pixel: pixel,
      flipY: true,
      xOffset: 0.2,
      yOffset: -0.1,
      scale: 1.25,
    );

    expect(restored.dx, closeTo(rosX, 0.000001));
    expect(restored.dy, closeTo(rosY, 0.000001));
  });

  test('반응형 표시 배율을 적용했다가 제거해도 좌표가 유지된다', () {
    const displayScale = 0.63;
    const rosX = 1.4;
    const rosY = 2.8;

    final originalPixel = MapCoordinate.rosToPixel(
      map: map,
      x: rosX,
      y: rosY,
      flipY: true,
      xOffset: 0,
      yOffset: 0,
      scale: 1,
    );
    final displayedPixel = originalPixel * displayScale;
    final restoredOriginalPixel = displayedPixel / displayScale;
    final restoredRos = MapCoordinate.pixelToRos(
      map: map,
      pixel: restoredOriginalPixel,
      flipY: true,
      xOffset: 0,
      yOffset: 0,
      scale: 1,
    );

    expect(restoredRos.dx, closeTo(rosX, 0.000001));
    expect(restoredRos.dy, closeTo(rosY, 0.000001));
  });
}
