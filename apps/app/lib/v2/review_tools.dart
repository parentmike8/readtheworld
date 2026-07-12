import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _reviewEnvironmentChannel = MethodChannel(
  'today.readtheworld.app/review_environment',
);

bool reviewToolsAvailableFor({
  required bool debugBuild,
  required bool isIos,
  required bool isTestFlight,
}) => debugBuild || (isIos && isTestFlight);

class ReviewTools {
  ReviewTools._();

  static Future<bool>? _availability;

  static Future<bool> available() => _availability ??= _resolveAvailability();

  static Future<bool> _resolveAvailability() async {
    if (kDebugMode) return true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      final isTestFlight =
          await _reviewEnvironmentChannel.invokeMethod<bool>('isTestFlight') ??
          false;
      return reviewToolsAvailableFor(
        debugBuild: false,
        isIos: true,
        isTestFlight: isTestFlight,
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
