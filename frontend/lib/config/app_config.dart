/// Application-wide configuration constants.
///
/// Override [baseUrl] at build time without touching source code:
///   flutter run --dart-define=API_BASE_URL=https://your-api.railway.app
///
/// Platform defaults (when dart-define is not supplied):
///   Android emulator  → http://10.0.2.2:5000   (loopback on the host machine)
///   iOS simulator     → http://localhost:5000
///   Physical device   → set API_BASE_URL to your server's LAN IP or hostname
class AppConfig {
  AppConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );

  static const Duration requestTimeout = Duration(seconds: 30);
}
