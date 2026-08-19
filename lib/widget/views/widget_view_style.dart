/// 桌面小组件 headless View 共用色板（不依赖 App Theme / Riverpod）。
library;

import 'package:flutter/material.dart';

/// 金额数字：近黑（隐藏前）。
const Color kWidgetExpense = Color(0xFF111827);

/// 收入强调绿（小号本月收入等）。
const Color kWidgetIncome = Color(0xFF16A34A);

/// 柱图支出蓝（ADR-024 参考图）。
const Color kWidgetChartExpense = Color(0xFF2F6BFF);

/// 柱图收入橙。
const Color kWidgetChartIncome = Color(0xFFFF8A3D);

const kWidgetTabularFeature = FontFeature.tabularFigures();

/// 仿毛玻璃：约 85% 不透明浅白，壁纸可隐约透出（非真实 blur；ADR-025）。
Color widgetCardBackground() => const Color(0xD9FFFFFF);

Color widgetInnerPanel() => const Color(0x66FFFFFF);

Color widgetTextSecondary() => const Color(0xFF6B6B6B);

Color widgetTextTertiary() => const Color(0xFFAFAFAF);

Color widgetDivider() => const Color(0x66EDEDED);
