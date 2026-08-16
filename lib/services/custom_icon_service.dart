import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../styles/tokens.dart';

class CustomIconException implements Exception {
  CustomIconException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 分类自定义图标：相册 → 1:1 裁剪 → 压缩存 `custom_icons/`。
class CustomIconService {
  static const int targetSize = 96;
  static const int quality = 85;
  static const int maxUploadSize = 5 * 1024 * 1024;
  static const int maxDimension = 2048;

  final ImagePicker _picker = ImagePicker();

  Future<Directory> getIconDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'custom_icons'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> resolveIconPath(String relativePath) async {
    final dir = await getIconDirectory();
    return p.join(dir.path, p.basename(relativePath));
  }

  Future<File?> pickFromGallery() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxDimension.toDouble(),
      maxHeight: maxDimension.toDouble(),
    );
    if (image == null) return null;
    return File(image.path);
  }

  /// 强制 1:1 裁剪；取消返回 null。
  Future<File?> cropSquare(File source, {Color? toolbarColor}) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: source.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 100,
      compressFormat: ImageCompressFormat.png,
      maxWidth: 512,
      maxHeight: 512,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪图标',
          toolbarColor: toolbarColor ?? PigTokens.primary,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: '裁剪图标',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );
    if (cropped == null) return null;
    return File(cropped.path);
  }

  Future<void> validateImage(File file) async {
    if (!await file.exists()) {
      throw CustomIconException('图片文件不存在');
    }
    final fileSize = await file.length();
    if (fileSize > maxUploadSize) {
      throw CustomIconException('图片过大，最大支持 5MB');
    }
    final ext = p.extension(file.path).toLowerCase();
    const valid = ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'];
    if (!valid.contains(ext)) {
      throw CustomIconException('不支持的图片格式');
    }
  }

  /// 压缩保存；返回相对路径 `custom_icons/{categoryId}_{ts}.png`。
  Future<String> saveCustomIcon(File sourceFile, int categoryId) async {
    await validateImage(sourceFile);
    final dir = await getIconDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${categoryId}_$timestamp.png';
    final destPath = p.join(dir.path, fileName);

    final result = await FlutterImageCompress.compressAndGetFile(
      sourceFile.path,
      destPath,
      minWidth: targetSize,
      minHeight: targetSize,
      quality: quality,
      format: CompressFormat.png,
    );
    if (result == null) {
      throw CustomIconException('图片压缩失败');
    }

    if (sourceFile.path.contains('cache') || sourceFile.path.contains('tmp')) {
      try {
        await sourceFile.delete();
      } catch (_) {}
    }
    return 'custom_icons/$fileName';
  }

  /// 从导入包字节写入图标；返回相对路径。
  Future<String> importIconBytes(List<int> bytes, {String? preferredName}) async {
    final dir = await getIconDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final base = preferredName == null
        ? 'imported_$stamp.png'
        : 'imported_${stamp}_${p.basename(preferredName)}';
    final fileName = base.toLowerCase().endsWith('.png') ? base : '$base.png';
    final dest = File(p.join(dir.path, fileName));
    await dest.writeAsBytes(bytes, flush: true);
    return 'custom_icons/$fileName';
  }

  Future<void> deleteCustomIcon(String? relativeOrAbsolute) async {
    if (relativeOrAbsolute == null || relativeOrAbsolute.isEmpty) return;
    final abs = relativeOrAbsolute.contains(p.separator) &&
            !relativeOrAbsolute.startsWith('custom_icons')
        ? relativeOrAbsolute
        : await resolveIconPath(relativeOrAbsolute);
    final file = File(abs);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
