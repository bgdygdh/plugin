import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'body_measurement_plugin_method_channel.dart';

abstract class BodyMeasurementPluginPlatform extends PlatformInterface {
  /// Constructs a BodyMeasurementPluginPlatform.
  BodyMeasurementPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static BodyMeasurementPluginPlatform _instance = MethodChannelBodyMeasurementPlugin();

  /// The default instance of [BodyMeasurementPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelBodyMeasurementPlugin].
  static BodyMeasurementPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [BodyMeasurementPluginPlatform] when
  /// they register themselves.
  static set instance(BodyMeasurementPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
