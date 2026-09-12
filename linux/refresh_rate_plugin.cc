// Linux implementation of RefreshRatePlugin.
//
// Uses GDK for query support. Implements the pigeon protocol using raw binary
// channel handlers — avoids the GObject/C++ bridge problem with BinaryMessenger.
// Control is not supported on Linux; compositor owns refresh rates.

#include "include/refresh_rate/refresh_rate_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <cstring>
#include <cstdlib>
#include <set>

#define REFRESH_RATE_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), refresh_rate_plugin_get_type(), RefreshRatePlugin))

#define PIGEON_CHANNEL_PREFIX "dev.flutter.pigeon.refresh_rate.RefreshRateHostApi."

struct _RefreshRatePlugin {
  GObject parent_instance;
  FlBinaryMessenger* messenger;
  GWeakRef view;
};

G_DEFINE_TYPE(RefreshRatePlugin, refresh_rate_plugin, g_object_get_type())

// ─── Pigeon binary encoding helpers ─────────────────────────────────

static void pb_byte(GByteArray* b, guint8 v) {
  g_byte_array_append(b, &v, 1);
}

static void pb_varint(GByteArray* b, gsize v) {
  if (v < 254) {
    pb_byte(b, (guint8)v);
  } else if (v < 65536) {
    pb_byte(b, 254);
    guint16 u = (guint16)v;
    g_byte_array_append(b, (const guint8*)&u, 2);
  } else {
    pb_byte(b, 255);
    guint32 u = (guint32)v;
    g_byte_array_append(b, (const guint8*)&u, 4);
  }
}

static void pb_null(GByteArray* b) { pb_byte(b, 0); }
static void pb_bool(GByteArray* b, gboolean v) { pb_byte(b, v ? 1 : 2); }

static void pb_double(GByteArray* b, double v) {
  pb_byte(b, 6);
  while (b->len % 8 != 0) pb_byte(b, 0);
  g_byte_array_append(b, (const guint8*)&v, 8);
}

static void pb_int64(GByteArray* b, gint64 v) {
  pb_byte(b, 4);
  g_byte_array_append(b, (const guint8*)&v, 8);
}

static void pb_string(GByteArray* b, const char* s) {
  pb_byte(b, 7);
  gsize len = strlen(s);
  pb_varint(b, len);
  g_byte_array_append(b, (const guint8*)s, len);
}

// Build pigeon success response: outer list [result]
// For display info: result is custom type 129 (DisplayInfoMessage)
static GBytes* build_display_info_response(
    double current, double max_rate, double min_rate,
    double* rates, int n_rates,
    gboolean is_vrr,
    const char* display_server,
    gint64 monitor_count) {

  GByteArray* b = g_byte_array_new();

  // Outer success wrapper: list([result])
  pb_byte(b, 12); pb_varint(b, 1);

  // Custom type 129 (DisplayInfoMessage)
  pb_byte(b, 129);

  // Inner list of 13 fields
  pb_byte(b, 12); pb_varint(b, 13);

  if (current > 0) pb_double(b, current); else pb_null(b);                // 0: currentRate
  pb_null(b);               // 1: maxRate
  pb_null(b);              // 2: minRate

  // 3: supportedRates list
  pb_byte(b, 12); pb_varint(b, n_rates);
  for (int i = 0; i < n_rates; i++) pb_double(b, rates[i]);

  pb_null(b);                   // 4: isVariableRefreshRate
  pb_null(b);                   // 5: engineTargetRate
  pb_null(b);                           // 6: iosProMotionEnabled
  pb_null(b);                           // 7: androidApiLevel
  pb_null(b);                           // 8: isLowPowerMode
  pb_null(b);                           // 9: thermalStateIndex
  pb_null(b);                   // 10: hasAdaptiveRefreshRate

  if (display_server) pb_string(b, display_server);
  else pb_null(b);                      // 11: displayServer

  pb_int64(b, monitor_count);           // 12: monitorCount

  return g_byte_array_free_to_bytes(b);
}

// Pigeon empty success response: []
static GBytes* build_empty_success() {
  GByteArray* b = g_byte_array_new();
  pb_byte(b, 12); pb_varint(b, 0);
  return g_byte_array_free_to_bytes(b);
}

// Pigeon bool success response: [bool]
static GBytes* build_bool_success(gboolean v) {
  GByteArray* b = g_byte_array_new();
  pb_byte(b, 12); pb_varint(b, 1);
  pb_bool(b, v);
  return g_byte_array_free_to_bytes(b);
}

// ─── GDK display helpers ────────────────────────────────────────────

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

// ─── Pigeon channel handlers ────────────────────────────────────────

static void handle_get_display_info(
    FlBinaryMessenger* messenger,
    const gchar* channel,
    GBytes* message,
    FlBinaryMessengerResponseHandle* response_handle,
    gpointer user_data) {

  auto* plugin = REFRESH_RATE_PLUGIN(user_data);
  const double current = get_window_rate(plugin);
  GdkDisplay* display = gdk_display_get_default();
  const gint64 count = display ? gdk_display_get_n_monitors(display) : 0;
  g_autoptr(GBytes) response = build_display_info_response(
      current, 0, 0, nullptr, 0, FALSE, get_display_server_type(), count);
  fl_binary_messenger_send_response(messenger, response_handle, response, nullptr);
}

static void handle_noop(
    FlBinaryMessenger* messenger,
    const gchar* channel,
    GBytes* message,
    FlBinaryMessengerResponseHandle* response_handle,
    gpointer user_data) {
  g_autoptr(GBytes) response = build_empty_success();
  fl_binary_messenger_send_response(messenger, response_handle, response, nullptr);
}

static void handle_is_supported(
    FlBinaryMessenger* messenger,
    const gchar* channel,
    GBytes* message,
    FlBinaryMessengerResponseHandle* response_handle,
    gpointer user_data) {
  g_autoptr(GBytes) response = build_bool_success(FALSE);
  fl_binary_messenger_send_response(messenger, response_handle, response, nullptr);
}

// ─── Plugin lifecycle ────────────────────────────────────────────────

static void refresh_rate_plugin_dispose(GObject* object) {
  g_weak_ref_set(&REFRESH_RATE_PLUGIN(object)->view, nullptr);
  G_OBJECT_CLASS(refresh_rate_plugin_parent_class)->dispose(object);
}

static void refresh_rate_plugin_finalize(GObject* object) {
  g_weak_ref_clear(&REFRESH_RATE_PLUGIN(object)->view);
  G_OBJECT_CLASS(refresh_rate_plugin_parent_class)->finalize(object);
}

static void refresh_rate_plugin_class_init(RefreshRatePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = refresh_rate_plugin_dispose;
  G_OBJECT_CLASS(klass)->finalize = refresh_rate_plugin_finalize;
}

static void refresh_rate_plugin_init(RefreshRatePlugin* self) { g_weak_ref_init(&self->view, nullptr); }

void refresh_rate_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  RefreshRatePlugin* plugin = REFRESH_RATE_PLUGIN(
      g_object_new(refresh_rate_plugin_get_type(), nullptr));

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  plugin->messenger = messenger;
  g_weak_ref_set(&plugin->view, G_OBJECT(fl_plugin_registrar_get_view(registrar)));

  fl_binary_messenger_set_message_handler_on_channel(
      messenger, PIGEON_CHANNEL_PREFIX "getDisplayInfo",
      handle_get_display_info, g_object_ref(plugin), g_object_unref);

  const char* noop_channels[] = {
      "enable", "disable", "preferMax", "preferDefault",
      "matchContent", "boost", "setCategory", "setTouchBoost", nullptr
  };
  for (int i = 0; noop_channels[i]; i++) {
    gchar* name = g_strconcat(PIGEON_CHANNEL_PREFIX, noop_channels[i], nullptr);
    fl_binary_messenger_set_message_handler_on_channel(
        messenger, name, handle_noop, g_object_ref(plugin), g_object_unref);
    g_free(name);
  }

  fl_binary_messenger_set_message_handler_on_channel(
      messenger, PIGEON_CHANNEL_PREFIX "isSupported",
      handle_is_supported, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
