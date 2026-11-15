import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'body_measurement_plugin_platform_interface.dart';

/// An implementation of [BodyMeasurementPluginPlatform] that uses method channels.
class MethodChannelBodyMeasurementPlugin extends BodyMeasurementPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('body_measurement_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
