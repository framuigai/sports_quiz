import 'dart:io';

/// Central place for API configuration.
/// We auto-select the correct loopback for Android emulator:
///   - Android emulator → http://10.0.2.2:8000
///   - Others           → http://127.0.0.1:8000
class ApiConfig {
  static String get baseUrl {
    if (Platform.isAndroid) {
      // Android emulator cannot hit 127.0.0.1 on host, must use 10.0.2.2
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  /// Default network timeout for API calls.
  static const Duration timeout = Duration(seconds: 30);
}
