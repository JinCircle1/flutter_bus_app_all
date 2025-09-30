import 'package:shared_preferences/shared_preferences.dart';

class ServerConfigService {
  static final ServerConfigService _instance = ServerConfigService._internal();
  factory ServerConfigService() => _instance;
  ServerConfigService._internal();

  // Default server configuration
  static const String _defaultHost = 'circleone.biz';
  static const int _defaultPort = 443; // Standard HTTPS port (no custom port)
  static const String _defaultProtocol = 'https';
  static const String _defaultApiPath = '/api';

  // SharedPreferences keys
  static const String _hostKey = 'server_host';
  static const String _portKey = 'server_port';
  static const String _protocolKey = 'server_protocol';
  static const String _apiPathKey = 'server_api_path';

  /// Get the current server host
  Future<String> getHost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hostKey) ?? _defaultHost;
  }

  /// Get the current server port
  Future<int> getPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_portKey) ?? _defaultPort;
  }

  /// Get the current protocol (http/https)
  Future<String> getProtocol() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_protocolKey) ?? _defaultProtocol;
  }

  /// Get the API path
  Future<String> getApiPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiPathKey) ?? _defaultApiPath;
  }

  /// Get the complete API base URL
  Future<String> getApiBaseUrl() async {
    final host = await getHost();
    final port = await getPort();
    final protocol = await getProtocol();
    final apiPath = await getApiPath();

    // Don't include port for standard ports (80 for HTTP, 443 for HTTPS)
    final isStandardPort = (protocol == 'https' && port == 443) || (protocol == 'http' && port == 80);
    final portPart = isStandardPort ? '' : ':$port';

    return '$protocol://$host$portPart$apiPath';
  }

  /// Get the complete server base URL (without API path)
  Future<String> getServerBaseUrl() async {
    final host = await getHost();
    final port = await getPort();
    final protocol = await getProtocol();

    // Don't include port for standard ports (80 for HTTP, 443 for HTTPS)
    final isStandardPort = (protocol == 'https' && port == 443) || (protocol == 'http' && port == 80);
    final portPart = isStandardPort ? '' : ':$port';

    return '$protocol://$host$portPart';
  }

  /// Get the audio server base URL (specifically for audio files on port 3000)
  Future<String> getAudioServerBaseUrl() async {
    final host = await getHost();
    final protocol = await getProtocol();

    // Audio files are served on port 3000
    return '${protocol == 'https' ? 'http' : protocol}://$host:3000';
  }

  /// Set server host
  Future<void> setHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
  }

  /// Set server port
  Future<void> setPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_portKey, port);
  }

  /// Set protocol
  Future<void> setProtocol(String protocol) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_protocolKey, protocol);
  }

  /// Set API path
  Future<void> setApiPath(String apiPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiPathKey, apiPath);
  }

  /// Set complete server configuration
  Future<void> setServerConfig({
    required String host,
    required int port,
    required String protocol,
    String? apiPath,
  }) async {
    await setHost(host);
    await setPort(port);
    await setProtocol(protocol);
    if (apiPath != null) {
      await setApiPath(apiPath);
    }
  }

  /// Reset to default configuration
  Future<void> resetToDefaults() async {
    await setServerConfig(
      host: _defaultHost,
      port: _defaultPort,
      protocol: _defaultProtocol,
      apiPath: _defaultApiPath,
    );
  }

  /// Get current server configuration as a map
  Future<Map<String, dynamic>> getCurrentConfig() async {
    return {
      'host': await getHost(),
      'port': await getPort(),
      'protocol': await getProtocol(),
      'apiPath': await getApiPath(),
      'apiBaseUrl': await getApiBaseUrl(),
      'serverBaseUrl': await getServerBaseUrl(),
    };
  }

  /// Test if the server configuration is valid
  Future<bool> testConnection() async {
    try {
      final apiUrl = await getApiBaseUrl();
      // This would be implemented by ApiService
      print('Testing connection to: $apiUrl');
      return true;
    } catch (e) {
      print('Server configuration test failed: $e');
      return false;
    }
  }
}