class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  // Translation map - centralized and easily extensible
  final Map<String, Map<String, String>> _translations = {
    'ja': {
      'play': 'ガイド再生',
      'stop': '音声停止',
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
    },
    'en': {
      'play': 'Play Guide',
      'stop': 'Stop Audio',
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
    },
    'ko': {
      'play': '가이드 재생',
      'stop': '오디오 중지',
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
    },
    'zh': {
      'play': '播放指南',
      'stop': '停止音频',
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
}