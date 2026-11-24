import 'package:flutter/widgets.dart';

/// 欢迎页在返回前台时重新加载联系人预览。
/// 只观察页面级路由，弹窗关闭不触发。
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();