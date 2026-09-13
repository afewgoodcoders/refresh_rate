// GDK queries through generated Pigeon GObject bindings.
#include "include/refresh_rate/refresh_rate_plugin.h"
#include "refresh_rate_api.g.h"
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#define REFRESH_RATE_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), refresh_rate_plugin_get_type(), RefreshRatePlugin))
struct _RefreshRatePlugin { GObject parent_instance; GWeakRef view; };
G_DEFINE_TYPE(RefreshRatePlugin, refresh_rate_plugin, g_object_get_type())

static double get_window_rate(RefreshRatePlugin* plugin) {
  GObject* view = static_cast<GObject*>(g_weak_ref_get(&plugin->view));
  if (!view) return 0;
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(view));
  GdkDisplay* display = window ? gdk_window_get_display(window) : nullptr;
  GdkMonitor* monitor = display ? gdk_display_get_monitor_at_window(display, window) : nullptr;
  const int rate = monitor ? gdk_monitor_get_refresh_rate(monitor) : 0;
  g_object_unref(view);
  return rate > 0 ? rate / 1000.0 : 0;
}

static const char* get_display_server_type() {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) return "unknown";
  const gchar* name = G_OBJECT_TYPE_NAME(display);
  if (name) {
    if (g_str_has_prefix(name, "GdkWayland")) return "wayland";
    if (g_str_has_prefix(name, "GdkX11")) return "x11";
  }
  const char* wayland = g_getenv("WAYLAND_DISPLAY");
  if (wayland && wayland[0] != '\0') return "wayland";
  const char* x11 = g_getenv("DISPLAY");
  if (x11 && x11[0] != '\0') return "x11";
  return "unknown";
}

static RefreshRateRefreshRateHostApiGetDisplayInfoResponse* get_display_info(gpointer data) {
  auto* plugin = REFRESH_RATE_PLUGIN(data);
  double rate = get_window_rate(plugin);
  auto* display = gdk_display_get_default();
  int64_t count = display ? gdk_display_get_n_monitors(display) : 0;
  g_autoptr(FlValue) rates = fl_value_new_list();
  g_autoptr(RefreshRateDisplayInfoMessage) result = refresh_rate_display_info_message_new(
      rate > 0 ? &rate : nullptr, nullptr, nullptr, rates, nullptr, nullptr,
      nullptr, nullptr, nullptr, nullptr, nullptr, get_display_server_type(), &count);
  return refresh_rate_refresh_rate_host_api_get_display_info_response_new(result);
}
static RefreshRateRefreshRateHostApiGetCapabilitiesResponse* get_capabilities(gpointer data) {
  gboolean query = TRUE, no = FALSE;
  g_autoptr(RefreshRateCapabilitiesMessage) result = refresh_rate_capabilities_message_new(
      &query, &no, &no, &no, &no, &no, &no, &no, &no, &no);
  return refresh_rate_refresh_rate_host_api_get_capabilities_response_new(result);
}
static RefreshRateRefreshRateHostApiGetDiagnosticsResponse* get_diagnostics(gpointer data) {
  double rate = get_window_rate(REFRESH_RATE_PLUGIN(data));
  g_autoptr(RefreshRateDiagnosticsMessage) result = refresh_rate_diagnostics_message_new(
      "gdkMonitor", nullptr, "applicationMonitor", rate > 0 ? &rate : nullptr,
      nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
      nullptr, nullptr, nullptr, nullptr, nullptr);
  return refresh_rate_refresh_rate_host_api_get_diagnostics_response_new(result);
}
static RefreshRateRefreshRateHostApiSubmitPreferenceResponse* submit_preference(
    RefreshRatePreferenceMessage* preference, gpointer data) {
  auto* kind = refresh_rate_preference_message_get_kind(preference);
  const bool clear = kind && *kind == REFRESH_RATE_NATIVE_PREFERENCE_KIND_SYSTEM;
  auto status = clear ? REFRESH_RATE_NATIVE_REQUEST_STATUS_SUBMITTED : REFRESH_RATE_NATIVE_REQUEST_STATUS_UNSUPPORTED;
  g_autoptr(RefreshRateRequestResultMessage) result = refresh_rate_request_result_message_new(
      &status, clear ? "clearOwnedPreference" : "unavailable", "applicationMonitor",
      "Linux compositor owns refresh scheduling", preference, nullptr);
  return refresh_rate_refresh_rate_host_api_submit_preference_response_new(result);
}
static RefreshRateRefreshRateHostApiResetTouchBoostResponse* reset_touch_boost(gpointer data) {
  auto status = REFRESH_RATE_NATIVE_REQUEST_STATUS_UNSUPPORTED;
  g_autoptr(RefreshRateRequestResultMessage) result = refresh_rate_request_result_message_new(
      &status, "unavailable", "applicationMonitor", nullptr, nullptr, nullptr);
  return refresh_rate_refresh_rate_host_api_reset_touch_boost_response_new(result);
}
static RefreshRateRefreshRateHostApiStartObservationResponse* start_observation(gpointer data) {
  return refresh_rate_refresh_rate_host_api_start_observation_response_new(FALSE);
}
static RefreshRateRefreshRateHostApiIsSupportedResponse* is_supported(gpointer data) {
  return refresh_rate_refresh_rate_host_api_is_supported_response_new(FALSE);
}
static RefreshRateRefreshRateHostApiStopObservationResponse* stop_observation(gpointer data) {
  return refresh_rate_refresh_rate_host_api_stop_observation_response_new();
}
static RefreshRateRefreshRateHostApiEnableResponse* enable(gpointer data) {
  return refresh_rate_refresh_rate_host_api_enable_response_new_error("unsupported", "Linux compositor owns refresh scheduling", nullptr);
}
static RefreshRateRefreshRateHostApiDisableResponse* disable(gpointer data) {
  return refresh_rate_refresh_rate_host_api_disable_response_new();
}
static RefreshRateRefreshRateHostApiPreferMaxResponse* prefer_max(gpointer data) {
  return refresh_rate_refresh_rate_host_api_prefer_max_response_new_error("unsupported", "Linux compositor owns refresh scheduling", nullptr);
}
static RefreshRateRefreshRateHostApiPreferDefaultResponse* prefer_default(gpointer data) {
  return refresh_rate_refresh_rate_host_api_prefer_default_response_new();
}
static RefreshRateRefreshRateHostApiMatchContentResponse* match_content(double fps, gpointer data) {
  return refresh_rate_refresh_rate_host_api_match_content_response_new_error("unsupported", "Linux compositor owns refresh scheduling", nullptr);
}
static RefreshRateRefreshRateHostApiBoostResponse* boost(int64_t duration_ms, gpointer data) {
  return refresh_rate_refresh_rate_host_api_boost_response_new_error("unsupported", "Linux compositor owns refresh scheduling", nullptr);
}
static RefreshRateRefreshRateHostApiSetCategoryResponse* set_category(int64_t category_index, gpointer data) {
  return refresh_rate_refresh_rate_host_api_set_category_response_new_error("unsupported", "Linux compositor owns refresh scheduling", nullptr);
}
static RefreshRateRefreshRateHostApiSetTouchBoostResponse* set_touch_boost(gboolean enabled, gpointer data) {
  return refresh_rate_refresh_rate_host_api_set_touch_boost_response_new_error("unsupported", "Linux compositor owns refresh scheduling", nullptr);
}
static void refresh_rate_plugin_finalize(GObject* object) {
  g_weak_ref_clear(&REFRESH_RATE_PLUGIN(object)->view);
  G_OBJECT_CLASS(refresh_rate_plugin_parent_class)->finalize(object);
}
static void refresh_rate_plugin_class_init(RefreshRatePluginClass* klass) {
  G_OBJECT_CLASS(klass)->finalize = refresh_rate_plugin_finalize;
}
static void refresh_rate_plugin_init(RefreshRatePlugin* self) { g_weak_ref_init(&self->view, nullptr); }
void refresh_rate_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  g_autoptr(RefreshRatePlugin) plugin = REFRESH_RATE_PLUGIN(g_object_new(refresh_rate_plugin_get_type(), nullptr));
  g_weak_ref_set(&plugin->view, G_OBJECT(fl_plugin_registrar_get_view(registrar)));
  static const RefreshRateRefreshRateHostApiVTable vtable = {
    get_display_info, get_capabilities, get_diagnostics, submit_preference,
    reset_touch_boost, start_observation, stop_observation, enable, disable,
    prefer_max, prefer_default, match_content, boost, set_category, set_touch_boost, is_supported
  };
  refresh_rate_refresh_rate_host_api_set_method_handlers(
      fl_plugin_registrar_get_messenger(registrar), nullptr, &vtable, g_object_ref(plugin), g_object_unref);
}
