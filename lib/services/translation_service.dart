import 'api_service.dart';

class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  final ApiService _apiService = ApiService();
  bool _initialized = false;

  // Translation map - will be populated from database, with hardcoded fallback
  final Map<String, Map<String, String>> _translations = {
    'ja': {
      'play': 'ガイド再生',
      'stop': '音声停止',
      'settings': '設定',
      'language_selection': '言語選択',
      'location_settings': '位置情報設定',
      'automatic_location_updates': '自動位置情報更新',
      'time_interval': '時間間隔',
      'distance_interval': '距離間隔',
      'seconds': '秒',
      'meters': 'メートル',
      'enable_automatic_updates': '自動更新を有効にする',
      'display_settings': '表示設定',
      'show_status_panel': 'ステータスパネルを表示',
      'show_status_panel_description': 'ステータスパネルの表示/非表示を切り替えます',
      'distance': '距離',
      'unknown': '不明',
      'direction_north': '北',
      'direction_northeast': '北東',
      'direction_east': '東',
      'direction_southeast': '南東',
      'direction_south': '南',
      'direction_southwest': '南西',
      'direction_west': '西',
      'direction_northwest': '北西',
      'direction': '方向',
      'detection_range': '検知範囲',
      'audio_guide': '音声ガイド',
      'audio_available': 'あり',
      'audio_unavailable': 'なし',
      'error': '確認エラー',
      'languages_count': '言語',
      'close': '閉じる',
    },
    'en': {
      'play': 'Play Guide',
      'stop': 'Stop Audio',
      'settings': 'Settings',
      'language_selection': 'Language Selection',
      'location_settings': 'Location Settings',
      'automatic_location_updates': 'Automatic Location Updates',
      'time_interval': 'Time Interval',
      'distance_interval': 'Distance Interval',
      'seconds': 'seconds',
      'meters': 'meters',
      'enable_automatic_updates': 'Enable automatic updates',
      'display_settings': 'Display Settings',
      'show_status_panel': 'Show Status Panel',
      'show_status_panel_description': 'Show or hide the status panel on the map',
      'distance': 'Distance',
      'unknown': 'Unknown',
      'direction_north': 'North',
      'direction_northeast': 'Northeast',
      'direction_east': 'East',
      'direction_southeast': 'Southeast',
      'direction_south': 'South',
      'direction_southwest': 'Southwest',
      'direction_west': 'West',
      'direction_northwest': 'Northwest',
      'direction': 'Direction',
      'detection_range': 'Detection Range',
      'audio_guide': 'Audio Guide',
      'audio_available': 'Available',
      'audio_unavailable': 'Unavailable',
      'error': 'Error',
      'languages_count': 'languages',
      'close': 'Close',
    },
    'ko': {
      'play': '가이드 재생',
      'stop': '오디오 중지',
      'settings': '설정',
      'language_selection': '언어 선택',
      'location_settings': '위치 설정',
      'automatic_location_updates': '자동 위치 업데이트',
      'time_interval': '시간 간격',
      'distance_interval': '거리 간격',
      'seconds': '초',
      'meters': '미터',
      'enable_automatic_updates': '자동 업데이트 활성화',
      'display_settings': '디스플레이 설정',
      'show_status_panel': '상태 패널 표시',
      'show_status_panel_description': '지도에서 상태 패널을 표시하거나 숨깁니다',
      'distance': '거리',
      'unknown': '알 수 없음',
      'direction_north': '북',
      'direction_northeast': '북동',
      'direction_east': '동',
      'direction_southeast': '남동',
      'direction_south': '남',
      'direction_southwest': '남서',
      'direction_west': '서',
      'direction_northwest': '북서',
      'direction': '방향',
      'detection_range': '감지 범위',
      'audio_guide': '오디오 가이드',
      'audio_available': '있음',
      'audio_unavailable': '없음',
      'error': '오류',
      'languages_count': '개 언어',
      'close': '닫기',
    },
    'zh': {
      'play': '播放指南',
      'stop': '停止音频',
      'settings': '设置',
      'language_selection': '语言选择',
      'location_settings': '位置设置',
      'automatic_location_updates': '自动位置更新',
      'time_interval': '时间间隔',
      'distance_interval': '距离间隔',
      'seconds': '秒',
      'meters': '米',
      'enable_automatic_updates': '启用自动更新',
      'display_settings': '显示设置',
      'show_status_panel': '显示状态面板',
      'show_status_panel_description': '在地图上显示或隐藏状态面板',
      'distance': '距离',
      'unknown': '未知',
      'direction_north': '北',
      'direction_northeast': '东北',
      'direction_east': '东',
      'direction_southeast': '东南',
      'direction_south': '南',
      'direction_southwest': '西南',
      'direction_west': '西',
      'direction_northwest': '西北',
      'direction': '方向',
      'detection_range': '检测范围',
      'audio_guide': '语音导览',
      'audio_available': '有',
      'audio_unavailable': '无',
      'error': '错误',
      'languages_count': '种语言',
      'close': '关闭',
    },
    'vi': {
      'play': 'Phát hướng dẫn',
      'stop': 'Dừng âm thanh',
      'settings': 'Cài đặt',
      'language_selection': 'Chọn ngôn ngữ',
      'location_settings': 'Cài đặt vị trí',
      'automatic_location_updates': 'Cập nhật vị trí tự động',
      'time_interval': 'Khoảng thời gian',
      'distance_interval': 'Khoảng cách',
      'seconds': 'giây',
      'meters': 'mét',
      'enable_automatic_updates': 'Bật cập nhật tự động',
      'display_settings': 'Cài đặt hiển thị',
      'show_status_panel': 'Hiển thị bảng trạng thái',
      'show_status_panel_description': 'Hiển thị hoặc ẩn bảng trạng thái trên bản đồ',
      'distance': 'Khoảng cách',
      'unknown': 'Không xác định',
      'direction_north': 'Bắc',
      'direction_northeast': 'Đông Bắc',
      'direction_east': 'Đông',
      'direction_southeast': 'Đông Nam',
      'direction_south': 'Nam',
      'direction_southwest': 'Tây Nam',
      'direction_west': 'Tây',
      'direction_northwest': 'Tây Bắc',
      'direction': 'Hướng',
      'detection_range': 'Phạm vi phát hiện',
      'audio_guide': 'Hướng dẫn âm thanh',
      'audio_available': 'Có',
      'audio_unavailable': 'Không có',
      'error': 'Lỗi',
      'languages_count': 'ngôn ngữ',
      'close': 'Đóng',
    },
  };

  /// Get translated text for a given language code and key
  String getTranslation(String languageCode, String key) {
    // Normalize language code (e.g., 'ja_JP' -> 'ja', 'en_US' -> 'en')
    final normalizedCode = languageCode.split('_')[0].toLowerCase();

    // Get the translation for the current language, fallback to English
    final languageTranslations = _translations[normalizedCode] ?? _translations['en']!;
    return languageTranslations[key] ?? key; // Return key if translation not found
  }

  /// Get play button text based on language and playing state
  String getPlayButtonText(String languageCode, bool isPlaying) {
    return getTranslation(languageCode, isPlaying ? 'stop' : 'play');
  }

  /// Add or update translation for a language
  void addTranslation(String languageCode, String key, String value) {
    _translations.putIfAbsent(languageCode, () => {});
    _translations[languageCode]![key] = value;
  }

  /// Add multiple translations for a language
  void addLanguageTranslations(String languageCode, Map<String, String> translations) {
    _translations[languageCode] = translations;
  }

  /// Get all supported language codes
  List<String> getSupportedLanguages() {
    return _translations.keys.toList();
  }

  /// Check if a language is supported
  bool isLanguageSupported(String languageCode) {
    return _translations.containsKey(languageCode);
  }

  /// Extract language code from locale string (e.g., 'ja' from 'ja_JP')
  String extractLanguageCode(String localeCode) {
    return localeCode.split('_')[0].toLowerCase();
  }

  /// Initialize translations from database
  /// Database table structure: ui_translations (language_code, translation_key, translation_value)
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      print('🌐 [TranslationService] データベースから翻訳を読み込み中...');
      final dbTranslations = await _apiService.getUITranslations();

      if (dbTranslations.isEmpty) {
        print('⚠️ [TranslationService] データベースに翻訳データがありません。ハードコードされた翻訳を使用します。');
        _initialized = true;
        return;
      }

      // Group translations by language code
      for (final translation in dbTranslations) {
        final languageCode = translation['language_code'] as String?;
        final key = translation['translation_key'] as String?;
        final value = translation['translation_value'] as String?;

        if (languageCode != null && key != null && value != null) {
          addTranslation(languageCode, key, value);
        }
      }

      _initialized = true;
      print('✅ [TranslationService] データベースから${dbTranslations.length}件の翻訳を読み込みました');
    } catch (e) {
      print('❌ [TranslationService] 翻訳の読み込みエラー: $e');
      print('⚠️ [TranslationService] ハードコードされた翻訳を使用します');
      _initialized = true;
    }
  }
}