import 'dart:io';

import 'package:flutter/material.dart';

import '../services/custom_icon_service.dart';
import '../styles/tokens.dart';
import '../utils/category_icons.dart';

/// 统一渲染分类图标：Material 或本地自定义图。
class CategoryIconView extends StatelessWidget {
  const CategoryIconView({
    super.key,
    required this.name,
    this.icon,
    this.iconType = 'material',
    this.customIconPath,
    this.size = 22,
    this.color,
  });

  final String name;
  final String? icon;
  final String iconType;
  final String? customIconPath;
  final double size;
  final Color? color;

  bool get _isCustom =>
      iconType == 'custom' &&
      customIconPath != null &&
      customIconPath!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final fallbackColor = color ?? categoryIconColor(name, icon: icon);
    if (!_isCustom) {
      return Icon(
        categoryIconData(icon),
        color: fallbackColor,
        size: size,
      );
    }
    return FutureBuilder<String>(
      future: CustomIconService().resolveIconPath(customIconPath!),
      builder: (context, snap) {
        final path = snap.data;
        if (path == null) {
          return Icon(
            categoryIconData(icon),
            color: fallbackColor,
            size: size,
          );
        }
        final file = File(path);
        return ClipOval(
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stackTrace) => Icon(
              categoryIconData(icon),
              color: fallbackColor,
              size: size,
            ),
          ),
        );
      },
    );
  }
}

/// 圆形底上的分类图标（管理页 / 账单行常用）。
class CategoryIconCircle extends StatelessWidget {
  const CategoryIconCircle({
    super.key,
    required this.name,
    this.icon,
    this.iconType = 'material',
    this.customIconPath,
    this.diameter = 44,
    this.iconSize = 22,
    this.backgroundColor,
  });

  final String name;
  final String? icon;
  final String iconType;
  final String? customIconPath;
  final double diameter;
  final double iconSize;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final color = categoryIconColor(name, icon: icon);
    final isCustom = iconType == 'custom' &&
        customIconPath != null &&
        customIconPath!.isNotEmpty;

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: backgroundColor ??
            (isCustom
                ? PigTokens.surfaceSecondary
                : color.withValues(alpha: 0.14)),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: isCustom
          ? FutureBuilder<String>(
              future: CustomIconService().resolveIconPath(customIconPath!),
              builder: (context, snap) {
                final path = snap.data;
                if (path == null) {
                  return Icon(
                    categoryIconData(icon),
                    color: color,
                    size: iconSize,
                  );
                }
                return Image.file(
                  File(path),
                  width: diameter,
                  height: diameter,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stackTrace) => Icon(
                    categoryIconData(icon),
                    color: color,
                    size: iconSize,
                  ),
                );
              },
            )
          : Icon(
              categoryIconData(icon),
              color: color,
              size: iconSize,
            ),
    );
  }
}
