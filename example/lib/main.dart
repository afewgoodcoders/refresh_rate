import 'package:flutter/widgets.dart';
import 'package:refresh_rate/refresh_rate.dart';

import 'src/example_app.dart';
export 'src/example_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RefreshRateExampleApp());
  // The engine may register plugins before attaching its rendering surface.
  // Start the app first, then inspect the supported backend after its first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final result = await RefreshRate.enable();
    debugPrint('Refresh preference: ${result.status.name} (${result.backend})');
    // An unavailable Android surface is reapplied by native attachment callbacks.
    // Apple/desktop/web control support is reported separately from display Hz.
  });
}
