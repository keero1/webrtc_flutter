//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_screen_capture/flutter_screen_capture_plugin.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>
#include <screen_retriever_linux/screen_retriever_linux_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) flutter_screen_capture_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterScreenCapturePlugin");
  flutter_screen_capture_plugin_register_with_registrar(flutter_screen_capture_registrar);
  g_autoptr(FlPluginRegistrar) flutter_webrtc_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterWebRTCPlugin");
  flutter_web_r_t_c_plugin_register_with_registrar(flutter_webrtc_registrar);
  g_autoptr(FlPluginRegistrar) screen_retriever_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "ScreenRetrieverLinuxPlugin");
  screen_retriever_linux_plugin_register_with_registrar(screen_retriever_linux_registrar);
}
