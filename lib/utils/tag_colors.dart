import 'package:flutter/material.dart';

import '../styles/tokens.dart';

/// 标签预设色板与解析（对齐 BeeCount TagSeedService 色表）。
abstract final class TagColors {
  static const List<String> palette = [
    '#FF5722',
    '#E91E63',
    '#9C27B0',
    '#673AB7',
    '#3F51B5',
    '#2196F3',
    '#03A9F4',
    '#00BCD4',
    '#009688',
    '#4CAF50',
    '#8BC34A',
    '#CDDC39',
    '#FFC107',
    '#FF9800',
    '#795548',
    '#607D8B',
    '#F44336',
    '#00E676',
    '#FF4081',
    '#536DFE',
  ];

  /// 新建标签默认色（按当前时间在色板内取一格）。
  static String random() {
    final index = DateTime.now().millisecondsSinceEpoch % palette.length;
    return palette[index];
  }

  /// 按序号轮询（迁移补色 / 批量种子）。
  static String at(int index) => palette[index % palette.length];

  static Color parse(String? hex, {Color fallback = PigTokens.primary}) {
    if (hex == null || hex.isEmpty) return fallback;
    try {
      var h = hex;
      if (h.startsWith('#')) h = h.substring(1);
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  static bool isLight(Color color) => color.computeLuminance() > 0.5;
}
