import 'package:flutter/widgets.dart';
import '../models/enums.dart';
import 'refresh_rate_session.dart';

/// Adds route context to an application-owned session. Supply a name mapper
/// when route names contain identifiers that must not enter telemetry.
class RefreshRateNavigatorObserver extends NavigatorObserver {
  /// The session getter may return null when no measurement is active.
  RefreshRateNavigatorObserver({required this.session, this.routeName});

  /// Current application-owned session; navigation does not create sessions.
  final RefreshRateSession? Function() session;

  /// Optional privacy-aware route naming function.
  final String? Function(Route<dynamic>)? routeName;
  void _record(Route<dynamic>? route, String action) {
    final current = session();
    if (current == null ||
        current.state == SessionState.completed ||
        current.state == SessionState.finalizing) {
      return;
    }
    final name = route == null
        ? null
        : (routeName != null ? routeName!(route) : route.settings.name);
    current.setTag('route', name?.substring(0, name.length.clamp(0, 256)));
    current.mark('navigation:$action');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(route, 'push');
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(previousRoute, 'pop');
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record(newRoute, 'replace');
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.isCurrent) _record(previousRoute, 'remove');
  }
}
