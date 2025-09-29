import '../config/app_config.dart';
import 'postgrest_service.dart';

class RoomConfig {
  final Map<int, String> languages;  // language_id -> language_name
  final int defaultLanguageId;
  final int textRoom;
  final Map<int, int> languageToRoomNumber;  // language_id -> room_number

  RoomConfig({
    required this.languages,
    required this.defaultLanguageId,
    required this.textRoom,
    required this.languageToRoomNumber,
  });

}

class RoomConfigService {
  static RoomConfig? _config;
  static final Map<String, int> _roomNumberToLanguageId = {};

  static Future<RoomConfig> getConfig() async {
    if (_config != null) {
      return _config!;
    }

    // DBから設定を読み込み
    _config = await _loadConfigFromDatabase();
    return _config!;
  }

  /// DBからRoomConfigを読み込み
  static Future<RoomConfig> _loadConfigFromDatabase() async {
    try {
      print('Starting database config load...');

      // PostgrestServiceを初期化
      print('Initializing PostgrestService service...');
      await PostgrestService.initialize();
      print('PostgrestService service initialized.');

      // 1. まずtoursテーブルの内容を確認
      print('Checking tours table data...');
      final allTours = await PostgrestService.fetchTableData('tours');
      print('All tours in database:');
      for (var tour in allTours) {
        print('  Tour: id=${tour['id']}, company_id=${tour['company_id']}, company_tour_id=${tour['company_tour_id']}, driver_language_id=${tour['driver_language_id']}');
      }

      // 1. 設定値を取得
      final companyId = await AppConfig.getCompanyId();
      final companyTourId = await AppConfig.getCompanyTourId();

      // 1. ツアーIDを取得
      print('Getting tour data for companyId: $companyId, companyTourId: $companyTourId');
      final tourData = await PostgrestService.getTourData(
        companyId,
        companyTourId
      );

      if (tourData == null) {
        throw Exception('Tour data not found');
      }

      final tourId = tourData['id'] as int;
      final driverLanguageId = tourData['driver_language_id'] as int;
      print('Tour data retrieved: tourId=$tourId, driverLanguageId=$driverLanguageId');

      // 2. TextRoom IDを取得
      print('Getting textroom ID for tourId: $tourId');
      final textRoomId = await PostgrestService.getTextRoomId(tourId);
      if (textRoomId == null) {
        throw Exception('TextRoom ID not found');
      }
      print('TextRoom ID retrieved: $textRoomId');

      // 3. AudioBridge roomsを取得
      final audioBridgeRooms = await PostgrestService.fetchTableData('audiobridge_rooms');
      final tourAudioRooms = audioBridgeRooms
          .where((room) => room['tour_id'] == tourId)
          .toList();

      if (tourAudioRooms.isEmpty) {
        throw Exception('AudioBridge rooms not found for tour');
      }

      // 4. Language情報を取得
      final languagesData = await PostgrestService.fetchTableData('languages');
      final languageMap = <int, String>{};
      final languageToRoomMap = <int, int>{};

      // AudioBridge roomsをIDでソートして最小IDを特定
      tourAudioRooms.sort((a, b) => (a['language_id'] as int).compareTo(b['language_id'] as int));
      final defaultLanguageId = tourAudioRooms.first['language_id'] as int;

      for (final audioRoom in tourAudioRooms) {
        final languageId = audioRoom['language_id'] as int;
        final roomNumber = audioRoom['room_number'] as int;

        // Language名を取得
        final language = languagesData.firstWhere(
          (lang) => lang['id'] == languageId,
          orElse: () => {'name_local': 'Unknown'}
        );

        languageMap[languageId] = language['name_local'] as String;
        languageToRoomMap[languageId] = roomNumber;

        // Room number to language ID mapping for later lookup (backward compatibility)
        _roomNumberToLanguageId[roomNumber.toString()] = languageId;
      }

      final config = RoomConfig(
        languages: languageMap,
        defaultLanguageId: defaultLanguageId,
        textRoom: textRoomId,
        languageToRoomNumber: languageToRoomMap,
      );

      // RoomConfig の値をログ出力
      print('=== RoomConfig loaded from database ===');
      print('TextRoom ID: ${config.textRoom}');
      print('Default Language ID: ${config.defaultLanguageId}');
      print('Languages: ${config.languages}');
      print('Language to Room mapping: ${config.languageToRoomNumber}');
      print('======================================');

      return config;

    } catch (e) {
      print('Failed to load config from database: $e');
      rethrow;
    }
  }

  static String getLanguageName(int languageId) {
    return _config?.languages[languageId] ?? '不明';
  }

  static int getDefaultLanguageId() {
    return _config?.defaultLanguageId ?? 1;
  }

  static int getTextRoom() {
    return _config?.textRoom ?? 2001;
  }

  static Map<int, String> getLanguages() {
    return _config?.languages ?? {};
  }

  /// Language IDから対応するroom numberを取得
  static int? getRoomNumberFromLanguageId(int languageId) {
    return _config?.languageToRoomNumber[languageId];
  }

  /// Room numberから対応するlanguage IDを取得 (backward compatibility)
  static int? getLanguageIdFromRoomNumber(String roomNumber) {
    return _roomNumberToLanguageId[roomNumber];
  }

  /// キャッシュをクリアして次回DB読み込みを強制
  static void clearCache() {
    _config = null;
    _roomNumberToLanguageId.clear();
  }
}