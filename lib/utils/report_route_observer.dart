import 'package:flutter/material.dart';

/// 报表页路由观察：构成卡选中态在 push 下一页时清零（ADR-033）。
final reportRouteObserver = RouteObserver<ModalRoute<void>>();
