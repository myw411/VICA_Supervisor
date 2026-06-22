// 이 파일은 ROS map 좌표와 Flutter 이미지 픽셀 좌표 사이의 변환을 담당합니다.
import 'dart:ui';

import '../models/vica_map.dart';

class MapCoordinate {
  const MapCoordinate._();

  // ROS map 좌표(x, y)를 지도 이미지 픽셀 좌표로 변환합니다.
  static Offset rosToPixel({
    required VicaMap map,
    required double x,
    required double y,
    required bool flipY,
    required double xOffset,
    required double yOffset,
    required double scale,
  }) {
    final correctedX = (x + xOffset) * scale;
    final correctedY = (y + yOffset) * scale;
    final pixelX = (correctedX - map.originX) / map.resolution;
    final rawPixelY = (correctedY - map.originY) / map.resolution;
    return Offset(pixelX, flipY ? map.height - rawPixelY : rawPixelY);
  }

  // 사용자가 지도 이미지에서 찍은 픽셀 위치를 ROS map 좌표(x, y)로 되돌립니다.
  static Offset pixelToRos({
    required VicaMap map,
    required Offset pixel,
    required bool flipY,
    required double xOffset,
    required double yOffset,
    required double scale,
  }) {
    final rawY = flipY ? map.height - pixel.dy : pixel.dy;
    final x = (pixel.dx * map.resolution + map.originX) / scale - xOffset;
    final y = (rawY * map.resolution + map.originY) / scale - yOffset;
    return Offset(x, y);
  }
}
