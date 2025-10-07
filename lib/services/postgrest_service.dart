import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

class PostgrestService {
  static final Logger _logger = Logger('PostgrestService');

  // 設定値
  static const String _baseUrl = 'https://circleone.biz/api';
  static const String _email = 'admin@example.com';
  static const String _password = 'admin123';

  static String? _authToken;

  /// Basic認証トークンを取得
  static Future<String?> _getAuthToken() async {
    final credentials = base64Encode(utf8.encode('$_email:$_password'));
    _authToken = credentials;
    _logger.info('Using Basic authentication');
    return _authToken;
  }

  /// 汎用的なGETリクエスト
  static Future<dynamic> _get(String endpoint) async {
    final token = await _getAuthToken();

    Uri uri = Uri.parse('$_baseUrl$endpoint');
    _logger.info('GET request to: $uri');
    print('🔍 [PostgrestService._get] Full URL: $uri');
    print('🔍 [PostgrestService._get] Endpoint: $endpoint');

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Basic $token';
    }

    print('🔍 [PostgrestService._get] Headers: $headers');

    final response = await http.get(uri, headers: headers);
    _logger.info('Response status: ${response.statusCode}');
    print('🔍 [PostgrestService._get] Response status: ${response.statusCode}');
    print('🔍 [PostgrestService._get] Response body length: ${response.body.length}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      _logger.warning('Authentication required or failed');
      print('❌ [PostgrestService._get] Authentication failed');
      throw Exception('Authentication failed: ${response.statusCode}');
    } else {
      print('❌ [PostgrestService._get] Error response body: ${response.body}');
      throw Exception('GET request failed: ${response.statusCode} - ${response.body}');
    }
  }

  /// 初期化処理
  static Future<void> initialize() async {
    try {
      _logger.info('Initializing PostgREST client...');
      _logger.info('Using URL: $_baseUrl');

      final token = await _getAuthToken();
      if (token != null) {
        _logger.info('PostgREST client initialized successfully');
      } else {
        _logger.warning('PostgREST initialized without authentication');
      }
    } catch (e) {
      _logger.severe('Failed to initialize PostgREST client: $e');
      // 初期化エラーでもアプリを停止させない
    }
  }

  /// 接続テスト
  static Future<bool> testConnection() async {
    try {
      _logger.info('Testing PostgREST connection...');

      // 実際のテーブルにアクセスして接続をテスト
      try {
        await _get('/tours?limit=1');
        _logger.info('Connection successful');
        return true;
      } catch (e) {
        _logger.warning('tours table not accessible, trying another approach: $e');
        // 別のテーブルでテスト
        try {
          await _get('/manager_rooms?limit=1');
          _logger.info('Connection successful via manager_rooms');
          return true;
        } catch (e2) {
          _logger.severe('Connection test failed: $e2');
          return false;
        }
      }
    } catch (e) {
      _logger.severe('Connection test failed: $e');
      return false;
    }
  }

  /// テーブルデータを取得
  static Future<List<Map<String, dynamic>>> fetchTableData(String tableName) async {
    try {
      _logger.info('Fetching data from table: $tableName');

      final response = await _get('/$tableName?limit=1000');

      if (response is List) {
        _logger.info('Fetched ${response.length} records from $tableName');
        return List<Map<String, dynamic>>.from(response);
      } else {
        _logger.warning('Unexpected response format from $tableName');
        return [];
      }
    } catch (e) {
      _logger.severe('Failed to fetch data from $tableName: $e');
      rethrow;
    }
  }

  /// companyId と companyTourId から tour_id と driver_language_id を取得
  /// valid_from, valid_to, name, start_time, end_time も取得
  static Future<Map<String, dynamic>?> getTourData(int companyId, int companyTourId) async {
    const maxRetries = 3;
    const baseDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _logger.info('Getting tour data for companyId: $companyId, companyTourId: $companyTourId (attempt $attempt/$maxRetries)');

        // PostgRESTのクエリ形式（external_tour_idを使用、必要なフィールドをすべて取得）
        final queryUrl = '/tours?company_id=eq.$companyId&external_tour_id=eq.$companyTourId&select=id,company_id,external_tour_id,driver_language_id,start_time,end_time,name&limit=1';
        print('🔍 [PostgrestService] Query URL: $queryUrl');

        final response = await _get(queryUrl).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Request timeout after 10 seconds');
          },
        );

        print('✅ [PostgrestService] getTourData: Successfully received response');
        print('🔍 [PostgrestService] Response: $response');
        print('🔍 [PostgrestService] Response is List: ${response is List}');
        print('🔍 [PostgrestService] Response length: ${response is List ? response.length : 'N/A'}');

        if (response is List && response.isNotEmpty) {
          // サーバー側でフィルタリングが機能していない場合、クライアント側でフィルタリング
          final filteredRecords = response.where((record) {
            return record['company_id'] == companyId &&
                   record['external_tour_id'] == companyTourId;
          }).toList();

          print('🔍 [PostgrestService] Filtered records count: ${filteredRecords.length}');

          if (filteredRecords.isNotEmpty) {
            _logger.info('Tour data retrieved: ${filteredRecords[0]}');
            print('🔍 [PostgrestService] Selected record: ${filteredRecords[0]}');
            return filteredRecords[0];
          } else {
            _logger.warning('No tour data found after filtering');
            print('⚠️ [PostgrestService] No matching tour found for company_id=$companyId, external_tour_id=$companyTourId');
            return null;
          }
        } else {
          _logger.warning('No tour data found');
          print('⚠️ [PostgrestService] Empty response or not a list');
          return null;
        }
      } catch (e) {
        _logger.warning('Attempt $attempt failed to get tour data: $e');

        if (attempt == maxRetries) {
          _logger.severe('Failed to get tour data after $maxRetries attempts: $e');
          return null;
        }

        final delay = baseDelay * attempt;
        _logger.info('Retrying in ${delay.inSeconds} seconds...');
        await Future.delayed(delay);
      }
    }

    return null;
  }

  /// tour_id から manager_rooms の text_room_id を取得
  static Future<int?> getTextRoomId(int tourId) async {
    const maxRetries = 3;
    const baseDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _logger.info('Getting textroom ID for tour_id: $tourId (attempt $attempt/$maxRetries)');

        final response = await _get(
          '/manager_rooms?tour_id=eq.$tourId&select=text_room_id&limit=1',
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Request timeout after 10 seconds');
          },
        );

        if (response is List && response.isNotEmpty) {
          _logger.info('Raw manager_rooms response: ${response[0]}');

          final roomIdValue = response[0]['text_room_id'];
          final roomId = roomIdValue is int ? roomIdValue : int.parse(roomIdValue.toString());
          _logger.info('TextRoom ID retrieved: $roomId');
          return roomId;
        } else {
          _logger.warning('No textroom data found');
          return null;
        }
      } catch (e) {
        _logger.warning('Attempt $attempt failed to get textroom ID: $e');

        if (attempt == maxRetries) {
          _logger.severe('Failed to get textroom ID after $maxRetries attempts: $e');
          return null;
        }

        final delay = baseDelay * attempt;
        _logger.info('Retrying in ${delay.inSeconds} seconds...');
        await Future.delayed(delay);
      }
    }

    return null;
  }

  /// tour_id から manager_rooms の audio_room_id を取得
  static Future<int?> getAudioRoomIdFromTextRoom(int tourId) async {
    const maxRetries = 3;
    const baseDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _logger.info('Getting audio room ID from manager_rooms for tour_id: $tourId (attempt $attempt/$maxRetries)');

        final response = await _get(
          '/manager_rooms?tour_id=eq.$tourId&select=audio_room_id&limit=1',
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Request timeout after 10 seconds');
          },
        );

        if (response is List && response.isNotEmpty) {
          _logger.info('Raw manager_rooms audio response: ${response[0]}');

          final audioRoomIdValue = response[0]['audio_room_id'];
          final audioRoomId = audioRoomIdValue is int ? audioRoomIdValue : int.parse(audioRoomIdValue.toString());
          _logger.info('Audio Room ID retrieved from manager_rooms: $audioRoomId');
          return audioRoomId;
        } else {
          _logger.warning('No audio room data found');
          return null;
        }
      } catch (e) {
        _logger.warning('Attempt $attempt failed to get audio room ID from manager_rooms: $e');

        if (attempt == maxRetries) {
          _logger.severe('Failed to get audio room ID from manager_rooms after $maxRetries attempts: $e');
          return null;
        }

        final delay = baseDelay * attempt;
        _logger.info('Retrying in ${delay.inSeconds} seconds...');
        await Future.delayed(delay);
      }
    }

    return null;
  }

  /// tour_id と language_id から audiobridge_rooms の room_number を取得
  static Future<int?> getAudioRoomId(int tourId, int languageId) async {
    const maxRetries = 3;
    const baseDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _logger.info('🔍 [AUDIO-ROOM] Getting audioroom ID for tour_id: $tourId, language_id: $languageId (attempt $attempt/$maxRetries)');

        final url = '/audiobridge_rooms?tour_id=eq.$tourId&language_id=eq.$languageId&select=room_number&limit=1';
        _logger.info('🔍 [AUDIO-ROOM] Request URL: $_baseUrl$url');

        final response = await _get(url).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Request timeout after 10 seconds');
          },
        );

        _logger.info('🔍 [AUDIO-ROOM] Full response: $response');
        _logger.info('🔍 [AUDIO-ROOM] Response type: ${response.runtimeType}');
        _logger.info('🔍 [AUDIO-ROOM] Response is List: ${response is List}');

        if (response is List) {
          _logger.info('🔍 [AUDIO-ROOM] Response list length: ${response.length}');
          if (response.isNotEmpty) {
            _logger.info('✅ [AUDIO-ROOM] Raw audioroom response: ${response[0]}');

            final roomNumberValue = response[0]['room_number'];
            _logger.info('🔍 [AUDIO-ROOM] room_number value: $roomNumberValue (type: ${roomNumberValue.runtimeType})');

            final roomNumber = roomNumberValue is int ? roomNumberValue : int.parse(roomNumberValue.toString());
            _logger.info('✅ [AUDIO-ROOM] AudioRoom ID retrieved: $roomNumber');
            return roomNumber;
          } else {
            _logger.warning('⚠️ [AUDIO-ROOM] Empty response list - no audioroom data found');
          }
        } else {
          _logger.warning('⚠️ [AUDIO-ROOM] Response is not a List: ${response.runtimeType}');
        }

        // データが見つからない場合、利用可能なaudiobridge_roomsテーブル全体を確認
        _logger.info('🔍 [AUDIO-ROOM] Checking all audiobridge_rooms for debugging...');
        try {
          final allRooms = await _get('/audiobridge_rooms?limit=10');
          _logger.info('🔍 [AUDIO-ROOM] All available rooms: $allRooms');
        } catch (e) {
          _logger.warning('⚠️ [AUDIO-ROOM] Failed to get all rooms: $e');
        }

        return null;
      } catch (e) {
        _logger.warning('❌ [AUDIO-ROOM] Attempt $attempt failed to get audioroom ID: $e');
        _logger.warning('❌ [AUDIO-ROOM] Error type: ${e.runtimeType}');

        if (attempt == maxRetries) {
          _logger.severe('❌ [AUDIO-ROOM] Failed to get audioroom ID after $maxRetries attempts: $e');
          return null;
        }

        final delay = baseDelay * attempt;
        _logger.info('🔄 [AUDIO-ROOM] Retrying in ${delay.inSeconds} seconds...');
        await Future.delayed(delay);
      }
    }

    return null;
  }

  /// テーブル一覧を取得
  static Future<List<String>> listTables() async {
    try {
      _logger.info('Listing available tables...');

      // PostgRESTで利用可能なテーブル名のリスト
      final commonTables = [
        'audiobridge_rooms',
        'manager_rooms',
        'tours',
        'languages',
        'passengers',
        'users',
        'profiles',
      ];

      // 各テーブルの存在を確認
      List<String> existingTables = [];
      for (String tableName in commonTables) {
        try {
          await _get('/$tableName?limit=1');
          existingTables.add(tableName);
          _logger.info('Table exists: $tableName');
        } catch (e) {
          // テーブルが存在しない場合はスキップ
          if (!e.toString().contains('401')) {
            _logger.fine('Table does not exist or not accessible: $tableName');
          }
        }
      }

      // アルファベット順にソート
      existingTables.sort();

      _logger.info('Found ${existingTables.length} accessible tables');
      return existingTables;
    } catch (e) {
      _logger.severe('Failed to list tables: $e');
      return [];
    }
  }
}