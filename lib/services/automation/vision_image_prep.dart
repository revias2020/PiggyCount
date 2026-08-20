import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// 后台直存 Vision 上传前图片预处理阈值。
const visionUploadMaxBytes = 1024 * 1024;
const visionUploadMaxEdge = 2048;
const visionUploadJpegQuality = 85;

/// 超阈值时压到 JPEG、长边 ≤ [visionUploadMaxEdge]；否则原样返回。
Future<({Uint8List bytes, String mimeType})> prepareVisionImageForUpload(
  Uint8List raw, {
  String mimeType = 'image/jpeg',
}) async {
  var needsCompress = raw.length > visionUploadMaxBytes;
  if (!needsCompress) {
    final size = await _decodeImageSize(raw);
    if (size != null) {
      needsCompress =
          size.$1 > visionUploadMaxEdge || size.$2 > visionUploadMaxEdge;
    }
  }
  if (!needsCompress) {
    return (bytes: raw, mimeType: mimeType);
  }

  final compressed = await FlutterImageCompress.compressWithList(
    raw,
    minWidth: visionUploadMaxEdge,
    minHeight: visionUploadMaxEdge,
    quality: visionUploadJpegQuality,
    format: CompressFormat.jpeg,
  );
  if (compressed.isEmpty) {
    return (bytes: raw, mimeType: mimeType);
  }
  return (bytes: Uint8List.fromList(compressed), mimeType: 'image/jpeg');
}

Future<(int width, int height)?> _decodeImageSize(Uint8List raw) async {
  try {
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = (image.width, image.height);
    image.dispose();
    return size;
  } catch (_) {
    return null;
  }
}
