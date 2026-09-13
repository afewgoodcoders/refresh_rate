import 'package:flutter/widgets.dart';
import '../refresh_rate.dart';
import 'auto_controller.dart';
import 'rate_controller.dart';

class _ScopeDepth extends InheritedWidget {
  const _ScopeDepth({required this.depth, required super.child});
  final int depth;
  @override
  bool updateShouldNotify(_ScopeDepth oldWidget) => depth != oldWidget.depth;
}

/// A preference owned by a visible route/widget. Nested scopes win ties by depth.
/// Set active=false for custom offstage navigation that does not use TickerMode.
class RefreshRateScope extends StatefulWidget {
  /// Creates a [RefreshRateScope] with the supplied configuration.
  const RefreshRateScope(
      {super.key,
      required this.preference,
      required this.child,
      this.active = true,
      this.priority = 50,
      this.onResult});

  /// The preference associated with this owner or submission.
  final RatePreference preference;

  /// Widget subtree governed by this integration.
  final Widget child;

  /// Whether this subtree is eligible to hold a foreground preference.
  final bool active;

  /// Higher priorities win; newer requests break ties.
  final int priority;

  /// Receives the latest submission outcome while this scope is mounted.
  final ValueChanged<RateRequestResult>? onResult;
  @override
  State<RefreshRateScope> createState() => _RefreshRateScopeState();
}

class _RefreshRateScopeState extends State<RefreshRateScope> {
  RefreshRateLease? _lease;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;
  int _depth = 0, _version = 0;
  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      _foreground = state == AppLifecycleState.resumed;
      if (mounted) _sync();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _depth =
        (context.dependOnInheritedWidgetOfExactType<_ScopeDepth>()?.depth ??
                0) +
            1;
    _sync();
  }

  @override
  void didUpdateWidget(RefreshRateScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final visible = widget.active &&
        _foreground &&
        // Retained for the minimum supported Flutter 3.24 SDK.
        // ignore: deprecated_member_use
        TickerMode.of(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (!visible) {
      _version++;
      _lease?.release();
      _lease = null;
      return;
    }
    final priority = widget.priority + _depth;
    if (_lease?.preference == widget.preference &&
        _lease?.priority == priority) {
      return;
    }
    final old = _lease;
    final version = ++_version;
    _lease = RefreshRate.request(widget.preference,
        owner: 'scope', priority: priority);
    old?.release();
    RefreshRate.controller.reconcile(reason: 'scopeChanged').then((result) {
      if (mounted && version == _version) widget.onResult?.call(result);
    });
  }

  @override
  void dispose() {
    _version++;
    _lifecycle?.dispose();
    _lease?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ScopeDepth(depth: _depth, child: widget.child);
}

/// Feeds touch and complete scroll lifetimes (including flings) into a policy.
class RefreshRateInteraction extends StatefulWidget {
  /// Creates a [RefreshRateInteraction] with the supplied configuration.
  const RefreshRateInteraction(
      {super.key, required this.controller, required this.child});

  /// Shared preference arbiter used by this integration.
  final RefreshRateAutoController controller;

  /// Widget subtree governed by this integration.
  final Widget child;
  @override
  State<RefreshRateInteraction> createState() => _RefreshRateInteractionState();
}

class _RefreshRateInteractionState extends State<RefreshRateInteraction> {
  final _pointers = <int, Object>{};
  final _scrolls = <BuildContext?, Object>{};
  void _clear(RefreshRateAutoController controller) {
    for (final token in [..._pointers.values, ..._scrolls.values]) {
      controller.endActivity(token);
    }
    _pointers.clear();
    _scrolls.clear();
  }

  @override
  void didUpdateWidget(RefreshRateInteraction old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) _clear(old.controller);
  }

  @override
  void dispose() {
    _clear(widget.controller);
    super.dispose();
  }

  void _endPointer(int pointer) {
    final token = _pointers.remove(pointer);
    if (token != null) widget.controller.endActivity(token);
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              _scrolls.putIfAbsent(
                  notification.context, widget.controller.beginActivity);
            } else if (notification is ScrollEndNotification) {
              final token = _scrolls.remove(notification.context);
              if (token != null) widget.controller.endActivity(token);
            }
            return false;
          },
          child: Listener(
              onPointerDown: (e) => _pointers.putIfAbsent(
                  e.pointer, widget.controller.beginActivity),
              onPointerUp: (e) => _endPointer(e.pointer),
              onPointerCancel: (e) => _endPointer(e.pointer),
              child: widget.child));
}

/// Explicit playback-state adapter. Supply source FPS and current player state.
/// Backend results describe whether a qualified content surface is available.
class RefreshRateContentController {
  RefreshRateLease? _lease;
  bool _disposed = false;

  /// Reconciles exact content cadence with current playback and visibility.
  Future<RateRequestResult> update(
      {required double sourceFps,
      double playbackSpeed = 1,
      bool playing = true,
      bool buffering = false,
      bool visible = true,
      FrameRateSwitchStrategy strategy =
          FrameRateSwitchStrategy.seamlessOnly}) {
    if (_disposed) throw StateError('Content controller disposed');
    if (!sourceFps.isFinite ||
        sourceFps <= 0 ||
        !playbackSpeed.isFinite ||
        playbackSpeed <= 0) {
      throw ArgumentError('Invalid playback rate');
    }
    final old = _lease;
    if (!playing || buffering || !visible) {
      _lease = null;
      return old?.release() ??
          Future.value(const RateRequestResult(
              status: RequestStatus.superseded,
              preference: RatePreference.system()));
    }
    final preference =
        RatePreference.content(sourceFps * playbackSpeed, strategy: strategy);
    if (old?.preference == preference) {
      return RefreshRate.controller.reconcile(reason: 'playbackUnchanged');
    }
    _lease = RefreshRate.request(preference, owner: 'content', priority: 250);
    old?.release();
    return RefreshRate.controller.reconcile(reason: 'playbackChanged');
  }

  /// Releases owned listeners, timers and requests; repeated calls are safe.
  Future<void> dispose() async {
    _disposed = true;
    await _lease?.release();
    _lease = null;
  }
}
