// Windows implementation of RefreshRatePlugin.
//
// Uses QueryDisplayConfig for accurate refresh rates (rational numbers like 59.94Hz)
// and EnumDisplaySettings for enumerating all supported modes.
// Control is query-only on Windows — rate control requires system-level access.

#include "include/refresh_rate/refresh_rate_plugin_c_api.h"
#include "refresh_rate_api.g.h"

#include <flutter/plugin_registrar_windows.h>
#include <windows.h>
#include <wingdi.h>

#include <algorithm>
#include <cmath>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace refresh_rate {

class RefreshRatePlugin : public flutter::Plugin, public RefreshRateHostApi {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit RefreshRatePlugin(HWND window);
  virtual ~RefreshRatePlugin();

  // RefreshRateHostApi
  ErrorOr<DisplayInfoMessage> GetDisplayInfo() override;
  std::optional<FlutterError> Enable() override { return std::nullopt; }
  std::optional<FlutterError> Disable() override { return std::nullopt; }
  std::optional<FlutterError> PreferMax() override { return std::nullopt; }
  std::optional<FlutterError> PreferDefault() override { return std::nullopt; }
  std::optional<FlutterError> MatchContent(double fps) override { return std::nullopt; }
  std::optional<FlutterError> Boost(int64_t duration_ms) override { return std::nullopt; }
  std::optional<FlutterError> SetCategory(int64_t category_index) override { return std::nullopt; }
  std::optional<FlutterError> SetTouchBoost(bool enabled) override { return std::nullopt; }
  ErrorOr<bool> IsSupported() override { return false; }

 private:
  HWND window_;
  std::wstring DeviceName();
  double GetCurrentRate();
  double GetMaxRate();
  std::vector<double> GetSupportedRates();
  double GetCurrentRateViaQueryDisplayConfig();
  double GetCurrentRateViaEnumDisplaySettings();
};

void RefreshRatePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto* view = registrar->GetView();
  auto plugin = std::make_unique<RefreshRatePlugin>(view ? view->GetNativeWindow() : nullptr);
  RefreshRateHostApi::SetUp(registrar->messenger(), plugin.get());
  registrar->AddPlugin(std::move(plugin));
}

RefreshRatePlugin::RefreshRatePlugin(HWND window) : window_(window) {}
std::wstring RefreshRatePlugin::DeviceName() {
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  const auto monitor = MonitorFromWindow(window_, MONITOR_DEFAULTTONULL);
  if (!monitor || !GetMonitorInfoW(monitor, reinterpret_cast<MONITORINFO*>(&info))) return {};
  return info.szDevice;
}
RefreshRatePlugin::~RefreshRatePlugin() {}

double RefreshRatePlugin::GetCurrentRateViaQueryDisplayConfig() {
  UINT32 pathCount = 0, modeCount = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount) != ERROR_SUCCESS) {
    return 0.0;
  }
  std::vector<DISPLAYCONFIG_PATH_INFO> paths(pathCount);
  std::vector<DISPLAYCONFIG_MODE_INFO> modes(modeCount);
  if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths.data(),
                         &modeCount, modes.data(), nullptr) != ERROR_SUCCESS) {
    return 0.0;
  }
  const auto device = DeviceName();
  if (device.empty()) return 0.0;
  for (UINT32 i = 0; i < pathCount; i++) {
    DISPLAYCONFIG_SOURCE_DEVICE_NAME source{};
    source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
    source.header.size = sizeof(source);
    source.header.adapterId = paths[i].sourceInfo.adapterId;
    source.header.id = paths[i].sourceInfo.id;
    if (DisplayConfigGetDeviceInfo(&source.header) == ERROR_SUCCESS && device == source.viewGdiDeviceName) {
      const auto rate = paths[i].targetInfo.refreshRate;
      if (rate.Denominator > 0) return static_cast<double>(rate.Numerator) / rate.Denominator;
    }
  }
  return 0.0;
}

double RefreshRatePlugin::GetCurrentRateViaEnumDisplaySettings() {
  DEVMODEW dm{};
  const auto device = DeviceName();
  if (device.empty()) return 0.0;
  dm.dmSize = sizeof(dm);
  if (EnumDisplaySettingsW(device.c_str(), ENUM_CURRENT_SETTINGS, &dm)) {
    double rate = static_cast<double>(dm.dmDisplayFrequency);
    if (rate > 1) return rate;
  }
  return 0.0;
}

double RefreshRatePlugin::GetCurrentRate() {
  double rate = GetCurrentRateViaQueryDisplayConfig();
  if (rate > 1.0) return rate;
  return GetCurrentRateViaEnumDisplaySettings();
}

double RefreshRatePlugin::GetMaxRate() {
  auto rates = GetSupportedRates();
  if (rates.empty()) return 0.0;
  return *std::max_element(rates.begin(), rates.end());
}

std::vector<double> RefreshRatePlugin::GetSupportedRates() {
  DEVMODEW dm{}, current{};
  const auto device = DeviceName();
  if (device.empty()) return {};
  dm.dmSize = sizeof(dm);
  current.dmSize = sizeof(current);
  if (!EnumDisplaySettingsW(device.c_str(), ENUM_CURRENT_SETTINGS, &current)) return {};

  std::set<double> rateSet;
  int modeNum = 0;
  while (EnumDisplaySettingsW(device.c_str(), modeNum, &dm)) {
    if (dm.dmPelsWidth == current.dmPelsWidth &&
        dm.dmPelsHeight == current.dmPelsHeight &&
        dm.dmDisplayFrequency > 1) {
      rateSet.insert(static_cast<double>(dm.dmDisplayFrequency));
    }
    modeNum++;
  }
  return std::vector<double>(rateSet.begin(), rateSet.end());
}

ErrorOr<DisplayInfoMessage> RefreshRatePlugin::GetDisplayInfo() {
  double currentRate = GetCurrentRate();
  auto supportedRates = GetSupportedRates();
  double maxRate = supportedRates.empty() ? 0.0
      : *std::max_element(supportedRates.begin(), supportedRates.end());
  double minRate = supportedRates.empty() ? 0.0 : supportedRates.front();


  flutter::EncodableList rates;
  for (double r : supportedRates) {
    rates.push_back(flutter::EncodableValue(r));
  }

  DisplayInfoMessage msg;
  msg.set_current_rate(currentRate);
  msg.set_max_rate(maxRate);
  msg.set_min_rate(minRate);
  msg.set_supported_rates(rates);
  msg.set_monitor_count(static_cast<int64_t>(GetSystemMetrics(SM_CMONITORS)));
  return msg;
}

}  // namespace refresh_rate

void RefreshRatePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  refresh_rate::RefreshRatePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
