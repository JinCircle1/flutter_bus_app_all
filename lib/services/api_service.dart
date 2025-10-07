import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'server_config_service.dart';

class ApiService {
  static const String dbName = 'mydb';
  final ServerConfigService _serverConfig = ServerConfigService();
  String? _token;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// Get the current API base URL from server configuration
  Future<String> getBaseUrl() async {
    return await _serverConfig.getApiBaseUrl();
  }

  /// Get the current server base URL (for audio files, etc.)
  Future<String> getServerBaseUrl() async {
    return await _serverConfig.getServerBaseUrl();
  }

  /// Get the audio server base URL (specifically for audio files on port 3000)
  Future<String> getAudioServerBaseUrl() async {
    return await _serverConfig.getAudioServerBaseUrl();
  }

  /// Update server configuration
  Future<void> updateServerConfig({
    required String host,
    required int port,
    required String protocol,
    String? apiPath,
  }) async {
    await _serverConfig.setServerConfig(
      host: host,
      port: port,
      protocol: protocol,
      apiPath: apiPath,
    );
    developer.log('Server configuration updated to: ${await getBaseUrl()}', name: 'ApiService');
  }

  /// Reset server configuration to defaults
  Future<void> resetServerConfig() async {
    await _serverConfig.resetToDefaults();
    developer.log('Server configuration reset to defaults: ${await getBaseUrl()}', name: 'ApiService');
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
    _token = token;
  }

  Future<bool> login(String email, String password) async {
    try {
      final baseUrl = await getBaseUrl();
      final uri = Uri.parse('$baseUrl/rpc/login');
      final body = jsonEncode({'email': email, 'password': password});

      developer.log('Login attempt: $uri', name: 'ApiService');
      developer.log('Login body: $body', name: 'ApiService');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      developer.log(
        'Login response status: ${response.statusCode}',
        name: 'ApiService',
      );
      developer.log(
        'Login response body: ${response.body}',
        name: 'ApiService',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['token'] != null) {
          await _saveToken(data['token']);
          developer.log('Token saved successfully', name: 'ApiService');
          return true;
        } else {
          developer.log('No token in response', name: 'ApiService');
        }
      } else {
        developer.log(
          'Login failed with status: ${response.statusCode}',
          name: 'ApiService',
        );
      }
      return false;
    } catch (e) {
      developer.log('Login error: $e', name: 'ApiService');
      return false;
    }
  }

  Future<List<dynamic>> get(String endpoint) async {
    // Since authentication is not working but data access is available without auth,
    // we'll try without authentication first
    try {
      final baseUrl = await getBaseUrl();
      final uri = Uri.parse('$baseUrl/$endpoint');
      developer.log('API Request: $uri', name: 'ApiService');

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      developer.log(
        'Response status: ${response.statusCode}',
        name: 'ApiService',
      );
      developer.log('Response body: ${response.body}', name: 'ApiService');

      if (response.statusCode == 200) {
        final body = response.body.trim();
        if (body.isEmpty) {
          return [];
        }
        final decoded = jsonDecode(body);
        if (decoded is List) {
          return decoded;
        } else {
          throw Exception(
            'Expected array response, got: ${decoded.runtimeType}',
          );
        }
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed - please login first');
      } else if (response.statusCode == 404) {
        throw Exception('API endpoint not found: $endpoint');
      } else if (response.statusCode >= 500) {
        throw Exception(
          'Server error (${response.statusCode}): ${response.body}',
        );
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('HandshakeException')) {
        throw Exception(
          'Network connection failed - check internet connection',
        );
      } else if (e.toString().contains('TimeoutException')) {
        throw Exception('Request timed out - server may be unavailable');
      } else {
        rethrow;
      }
    }
  }

  Future<List<Map<String, dynamic>>> getLandmarks() async {
    final data = await get('landmarks');
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getLanguages() async {
    final data = await get('languages');
    return data.cast<Map<String, dynamic>>();
  }

  /// Get all UI translations from the database
  Future<List<Map<String, dynamic>>> getUITranslations() async {
    try {
      final data = await get('ui_translations');
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      developer.log('Error fetching UI translations: $e', name: 'ApiService');
      // Return empty list if table doesn't exist yet
      return [];
    }
  }


  /// Generate audio data based on landmarks and languages
  Future<List<Map<String, dynamic>>> _generateAudioFromLandmarks(
    int landmarkId,
    int languageId,
  ) async {
    try {
      // Get landmark data to construct audio URLs
      final landmarks = await getLandmarks();
      final languages = await getLanguages();

      final landmark = landmarks.firstWhere(
        (l) => l['id'] == landmarkId,
        orElse: () => <String, dynamic>{},
      );

      final language = languages.firstWhere(
        (l) => l['id'] == languageId,
        orElse: () => <String, dynamic>{},
      );

      if (landmark.isEmpty || language.isEmpty) {
        print('DEBUG: Landmark or language not found: landmark_id=$landmarkId, language_id=$languageId');
        return [];
      }

      // Generate audio URL based on landmark and language
      // Extract language code from locale format (ja_JP -> ja, en_US -> en, vi_VN -> vi)
      final fullCode = language['code'] as String;
      final languageCode = fullCode.split('_')[0]; // ja_JP -> ja
      final audioUrl = 'audio/landmark_${landmarkId}_$languageCode.mp3';

      final generatedAudio = {
        'id': landmarkId * 10 + languageId, // Generate unique ID
        'landmark_id': landmarkId,
        'language_id': languageId,
        'audio_url': audioUrl,
        'filename': 'landmark_${landmarkId}_$languageCode.mp3',
        'title': '${landmark['name']}の音声ガイド (${language['name_local']})',
      };

      print('DEBUG: Generated audio data: $generatedAudio');
      return [generatedAudio];

    } catch (e) {
      print('ERROR: Failed to generate audio from landmarks: $e');
      return [];
    }
  }

  /// Test landmark_audios table access without filters
  Future<List<Map<String, dynamic>>> getAllLandmarkAudios() async {
    try {
      print('DEBUG: Testing landmark_audios access with all landmarks...');

      // Get all landmarks first
      final landmarks = await getLandmarks();
      final allAudios = <Map<String, dynamic>>[];

      // Fetch audio data for each landmark using the new endpoint
      for (final landmark in landmarks) {
        final landmarkId = landmark['id'] as int;
        try {
          final audioData = await _getAudioForLandmark(landmarkId);
          allAudios.addAll(audioData);
        } catch (e) {
          print('DEBUG: No audio data for landmark $landmarkId: $e');
        }
      }

      print('DEBUG: Retrieved ${allAudios.length} total audio records');
      return allAudios;
    } catch (e) {
      print('ERROR: Failed to access landmark_audios: $e');
      print('WARNING: No audio data available - database connection failed');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getAudioForLandmark(int landmarkId) async {
    try {
      // Use the new API endpoint that requires landmark_id parameter
      final serverConfigService = ServerConfigService();
      final audioServerBaseUrl = await serverConfigService.getAudioServerBaseUrl();
      final url = '$audioServerBaseUrl/api/landmark_audios?landmark_id=$landmarkId';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to get audio for landmark $landmarkId: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getLandmarkAudios(
    int landmarkId,
    int languageId,
  ) async {
    try {
      // First try to get all landmark_audios to see if the table is accessible
      final allAudios = await getAllLandmarkAudios();
      print('DEBUG: landmark_audios table has ${allAudios.length} total records');

      // Then filter locally instead of using database filters
      final filteredAudios = allAudios.where((audio) {
        return audio['landmark_id'] == landmarkId && audio['language_id'] == languageId;
      }).toList();

      print('DEBUG: Found ${filteredAudios.length} audios for landmark_id=$landmarkId, language_id=$languageId');

      for (int i = 0; i < filteredAudios.length; i++) {
        final audio = filteredAudios[i];
        print('DEBUG: Audio $i: $audio');
        if (audio['audio_url'] != null) {
          print('DEBUG: Audio URL $i: ${audio['audio_url']}');
        }
      }

      return filteredAudios;

    } catch (e) {
      print('ERROR: getLandmarkAudios failed: $e');
      print('DEBUG: Attempting to generate audio data from landmarks...');

      // Generate audio data based on landmarks
      final generatedAudios = await _generateAudioFromLandmarks(landmarkId, languageId);
      if (generatedAudios.isNotEmpty) {
        print('DEBUG: Successfully generated ${generatedAudios.length} audio records');
        return generatedAudios;
      }

      // Final fallback: try the old way with filters for debugging
      try {
        final endpoint = 'landmark_audios?landmark_id=eq.$landmarkId&language_id=eq.$languageId';
        print('DEBUG: Final fallback - trying filtered endpoint: $endpoint');
        final data = await get(endpoint);
        return data.cast<Map<String, dynamic>>();
      } catch (e2) {
        print('ERROR: Final fallback also failed: $e2');
        throw Exception('All methods to access landmark_audios failed: $e2');
      }
    }
  }

  // Test database connectivity
  Future<Map<String, dynamic>> testConnection() async {
    final baseUrl = await getBaseUrl();
    final result = <String, dynamic>{
      'baseUrl': baseUrl,
      'hasToken': _token != null,
      'tokenValue': _token != null ? '${_token!.substring(0, 10)}...' : 'null',
      'endpoints': <String, dynamic>{},
    };

    final endpoints = ['landmarks', 'languages', 'landmark_audios'];

    for (final endpoint in endpoints) {
      try {
        final startTime = DateTime.now();

        // First try with current authentication
        final data = await get(endpoint);
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime).inMilliseconds;

        result['endpoints'][endpoint] = {
          'status': 'success',
          'count': data.length,
          'responseTime': '${duration}ms',
          'sample': data.isNotEmpty ? data.first : null,
        };
      } catch (e) {
        // If authenticated request fails, try without authentication
        try {
          final startTime = DateTime.now();
          final response = await http.get(
            Uri.parse('$baseUrl/$endpoint'),
            headers: {'Content-Type': 'application/json'},
          );
          final endTime = DateTime.now();
          final duration = endTime.difference(startTime).inMilliseconds;

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as List;
            result['endpoints'][endpoint] = {
              'status': 'success_no_auth',
              'count': data.length,
              'responseTime': '${duration}ms',
              'sample': data.isNotEmpty ? data.first : null,
              'note': 'Accessed without authentication',
            };
          } else {
            result['endpoints'][endpoint] = {
              'status': 'error',
              'error': 'HTTP ${response.statusCode}: ${response.body}',
            };
          }
        } catch (e2) {
          result['endpoints'][endpoint] = {
            'status': 'error',
            'error': e.toString(),
          };
        }
      }
    }

    return result;
  }
}
