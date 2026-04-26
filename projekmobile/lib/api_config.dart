import 'package:flutter/foundation.dart';

/// Set this from CLI when using a physical device, for example:
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.19:3000
const String _apiBaseUrlFromEnv = String.fromEnvironment('API_BASE_URL');

class ApiConfig {
  static String get baseUrl {
    if (_apiBaseUrlFromEnv.isNotEmpty) {
      return _apiBaseUrlFromEnv;
    }

    if (kIsWeb) {
      return 'http://localhost:3000';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Android emulator maps host machine localhost to 10.0.2.2.
        return 'http://10.0.2.2:3000';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return 'http://localhost:3000';
      case TargetPlatform.fuchsia:
        return 'http://localhost:3000';
    }
  }

  static String endpoint(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$baseUrl$normalizedPath';
  }
}
