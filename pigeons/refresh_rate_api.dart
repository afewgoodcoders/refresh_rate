import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/generated/refresh_rate_api.g.dart',
  dartOptions: DartOptions(),
  kotlinOut:
      'android/src/main/kotlin/in/qoder/refresh_rate/generated/RefreshRateApi.kt',
  kotlinOptions: KotlinOptions(package: '`in`.qoder.refresh_rate.generated'),
  swiftOut: 'ios/refresh_rate/Sources/refresh_rate/generated/RefreshRateApi.swift',
  swiftOptions: SwiftOptions(),
  cppHeaderOut: 'windows/refresh_rate_api.g.h',
  cppSourceOut: 'windows/refresh_rate_api.g.cpp',
  cppOptions: CppOptions(namespace: 'refresh_rate'),
  gobjectHeaderOut: 'linux/refresh_rate_api.g.h',
  gobjectSourceOut: 'linux/refresh_rate_api.g.cc',
  gobjectOptions: GObjectOptions(module: 'RefreshRate'),
  copyrightHeader: 'pigeons/copyright.txt',
))

// ─── Data Classes ─────────────────────────────────────────────────

class DisplayInfoMessage {
  double? currentRate;
  double? maxRate;
  double? minRate;
  List<double?>? supportedRates;
  bool? isVariableRefreshRate;
  double? engineTargetRate;
  bool? iosProMotionEnabled;
  int? androidApiLevel;
  bool? isLowPowerMode;
  // 0=nominal, 1=fair, 2=serious, 3=critical, null=unknown
  int? thermalStateIndex;
  bool? hasAdaptiveRefreshRate;
  String? displayServer;
  int? monitorCount;
}

// Every native operation uses generated messages. Maps are reserved for
// Dart-side exports, not the platform transport.
enum NativePreferenceKind { system, high, category, content, atLeast }
enum NativeSwitchStrategy { seamlessOnly, allowNonSeamless }
enum NativeRequestStatus { submitted, unsupported, unavailable, failed, superseded }

class PreferenceMessage {
  NativePreferenceKind? kind;
  double? fps;
  int? category;
  NativeSwitchStrategy? strategy;
}

class RequestResultMessage {
  NativeRequestStatus? status;
  String? backend;
  String? scope;
  String? message;
  PreferenceMessage? preference;
  int? observedAtMs;
}

class CapabilitiesMessage {
  bool? query;
  bool? surfaceVoting;
  bool? windowPreferences;
  bool? categoryHints;
  bool? engineControl;
  bool? presentationObservation;
  bool? atLeast;
  bool? contentMatching;
  bool? touchBoost;
  bool? callbackObservation;
}

class DiagnosticsMessage {
  String? source;
  String? displayId;
  String? scope;
  double? currentHz;
  double? maximumHz;
  double? suggestedNormalHz;
  double? suggestedHighHz;
  double? callbackHz;
  double? expectedCallbackHz;
  int? sampleCount;
  int? windowUs;
  bool? activityAttached;
  bool? surfaceAvailable;
  bool? touchBoostEnabled;
  RequestResultMessage? lastNativeRequest;
  int? targetGeneration;
  int? submissionCount;
}

// ─── Host API (platform → Dart calls these) ──────────────────────
// These are what the Dart side calls INTO the platform

@HostApi()
abstract class RefreshRateHostApi {
  DisplayInfoMessage getDisplayInfo();
  CapabilitiesMessage getCapabilities();
  DiagnosticsMessage getDiagnostics();
  RequestResultMessage submitPreference(PreferenceMessage preference);
  RequestResultMessage resetTouchBoost();
  bool startObservation();
  void stopObservation();

  // Control
  void enable();
  void disable();
  void preferMax();
  void preferDefault();
  void matchContent(double fps);
  void boost(int durationMs);
  // 0=none, 1=low, 2=normal, 3=high
  void setCategory(int categoryIndex);
  void setTouchBoost(bool enabled);

  bool isSupported();
}

// ─── Flutter API (Dart → platform listens to these) ──────────────
// These are what the platform calls UP to Dart

@FlutterApi()
abstract class RefreshRateFlutterApi {
  void onDisplayInfoChanged(DisplayInfoMessage info);
}
