import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Converts [CameraImage] to NV21 bytes for ML Kit InputImage (Android).
(Uint8List nv21, int width, int height) cameraImageToNv21(CameraImage cameraImage) {
  final image = cameraImageToImage(cameraImage);
  if (image == null) return (Uint8List(0), 0, 0);
  final w = image.width;
  final h = image.height;
  final ySize = w * h;
  final out = Uint8List(ySize + ySize ~/ 2);
  int yIdx = 0;
  int uvIdx = ySize;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();
      out[yIdx++] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }
  }
  for (int y = 0; y < h; y += 2) {
    for (int x = 0; x < w; x += 2) {
      final p = image.getPixel(x, y);
      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();
      final v = (0.877 * (r - (0.299 * r + 0.587 * g + 0.114 * b))).round().clamp(0, 255);
      final u = (0.492 * (b - (0.299 * r + 0.587 * g + 0.114 * b))).round().clamp(0, 255);
      out[uvIdx++] = v;
      out[uvIdx++] = u;
    }
  }
  return (out, w, h);
}

/// Converts [CameraImage] to [img.Image] (RGBA).
img.Image? cameraImageToImage(CameraImage cameraImage) {
  if (cameraImage.format.group == ImageFormatGroup.yuv420) {
    return _yuv420ToImage(cameraImage);
  }
  if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
    return _bgra8888ToImage(cameraImage);
  }
  return null;
}

img.Image _yuv420ToImage(CameraImage cameraImage) {
  final int width = cameraImage.width;
  final int height = cameraImage.height;
  final int uvRowStride = cameraImage.planes[1].bytesPerRow;
  final int uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

  final image = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int uvIndex =
          uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
      final yIndex = y * cameraImage.planes[0].bytesPerRow + x;
      final yValue = cameraImage.planes[0].bytes[yIndex];
      final u = cameraImage.planes[1].bytes[uvIndex] - 128;
      final v = cameraImage.planes[2].bytes[uvIndex] - 128;

      int r = (yValue + (1.370705 * v)).round().clamp(0, 255);
      int g = (yValue - (0.337633 * u) - (0.698001 * v)).round().clamp(0, 255);
      int b = (yValue + (1.732446 * u)).round().clamp(0, 255);

      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

img.Image _bgra8888ToImage(CameraImage cameraImage) {
  final bytes = cameraImage.planes[0].bytes;
  return img.Image.fromBytes(
    width: cameraImage.width,
    height: cameraImage.height,
    bytes: bytes.buffer,
    order: img.ChannelOrder.bgra,
  );
}
