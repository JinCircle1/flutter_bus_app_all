class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  // Translation map - centralized and easily extensible
  final Map<String, Map<String, String>> _translations = {
    'ja': {
      'play': 'ガイド再生',
      'stop': '音声停止',
    },
    'en': {
      'play': 'Play Guide',
      'stop': 'Stop Audio',
    },
    'ko': {
      'play': '가이드 재생',
      'stop': '오디오 중지',
    },
    'zh': {
      'play': '播放指南',
      'stop': '停止音频',
    },
  };

  /// Get translated text for a given language code and key
  String getTranslation(String languageCode, String key) {
    // Get the translation for the current language, fallback to English
    final languageTranslations = _translations[languageCode] ?? _translations['en']!;
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