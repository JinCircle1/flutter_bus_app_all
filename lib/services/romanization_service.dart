import 'dart:convert';
import 'package:http/http.dart' as http;

class RomanizationService {
  static final RomanizationService _instance = RomanizationService._internal();
  factory RomanizationService() => _instance;
  RomanizationService._internal();

  // Cache for romanized names to avoid repeated API calls
  final Map<String, String> _cache = {};

  /// Convert Japanese text to romanized text
  Future<String?> romanize(String japaneseText) async {
    if (japaneseText.isEmpty) return null;

    // Check cache first
    if (_cache.containsKey(japaneseText)) {
      print('DEBUG: Found cached romanization for "$japaneseText": ${_cache[japaneseText]}');
      return _cache[japaneseText];
    }

    // Try local conversion first (for common patterns)
    final localResult = _localRomanization(japaneseText);
    if (localResult != null) {
      _cache[japaneseText] = localResult;
      print('DEBUG: Local romanization for "$japaneseText": $localResult');
      return localResult;
    }

    // Try online translation API as fallback
    final apiResult = await _translateToEnglish(japaneseText);
    if (apiResult != null) {
      _cache[japaneseText] = apiResult;
      print('DEBUG: API translation for "$japaneseText": $apiResult');
      return apiResult;
    }

    print('DEBUG: No romanization found for "$japaneseText"');
    return null;
  }

  /// Local romanization using common Japanese landmark patterns
  String? _localRomanization(String japaneseText) {
    // Common Japanese place name suffixes and their romanizations
    final Map<String, String> commonSuffixes = {
      '駅': 'Station',
      '神社': 'Shrine',
      '寺': 'Temple',
      '城': 'Castle',
      '公園': 'Park',
      '橋': 'Bridge',
      '山': 'Mountain',
      '川': 'River',
      '湖': 'Lake',
      '島': 'Island',
      '港': 'Port',
      '空港': 'Airport',
      '美術館': 'Art Museum',
      '博物館': 'Museum',
      '大学': 'University',
      '病院': 'Hospital',
      '市役所': 'City Hall',
      '図書館': 'Library',
      '学校': 'School',
      '高校': 'High School',
      '中学校': 'Middle School',
      '小学校': 'Elementary School',
      'タワー': 'Tower',
      'ビル': 'Building',
      'センター': 'Center',
      'ホテル': 'Hotel',
      'デパート': 'Department Store',
      'ショッピングモール': 'Shopping Mall',
    };

    // Famous Japanese landmarks dictionary
    final Map<String, String> famousLandmarks = {
      '東京駅': 'Tokyo Station',
      '新宿駅': 'Shinjuku Station',
      '渋谷駅': 'Shibuya Station',
      '池袋駅': 'Ikebukuro Station',
      '品川駅': 'Shinagawa Station',
      '上野駅': 'Ueno Station',
      '東京タワー': 'Tokyo Tower',
      'スカイツリー': 'Tokyo Skytree',
      '浅草寺': 'Sensoji Temple',
      '明治神宮': 'Meiji Shrine',
      '皇居': 'Imperial Palace',
      '上野公園': 'Ueno Park',
      '新宿御苑': 'Shinjuku Gyoen',
      '銀座': 'Ginza',
      '原宿': 'Harajuku',
      '秋葉原': 'Akihabara',
      '築地市場': 'Tsukiji Market',
      '両国国技館': 'Ryogoku Kokugikan',
      '東京ドーム': 'Tokyo Dome',
      '羽田空港': 'Haneda Airport',
      '成田空港': 'Narita Airport',
      '大阪城': 'Osaka Castle',
      '京都駅': 'Kyoto Station',
      '清水寺': 'Kiyomizu Temple',
      '金閣寺': 'Kinkaku-ji Temple',
      '銀閣寺': 'Ginkaku-ji Temple',
      '伏見稲荷大社': 'Fushimi Inari Shrine',
      '奈良公園': 'Nara Park',
      '東大寺': 'Todai-ji Temple',
      '富士山': 'Mount Fuji',
      '箱根': 'Hakone',
      '鎌倉': 'Kamakura',
      '江ノ島': 'Enoshima',
      '横浜': 'Yokohama',
      'みなとみらい': 'Minato Mirai',
      '札幌': 'Sapporo',
      '函館': 'Hakodate',
      '広島': 'Hiroshima',
      '厳島神社': 'Itsukushima Shrine',
      '長崎': 'Nagasaki',
      '熊本城': 'Kumamoto Castle',
    };

    // Check for exact famous landmark matches first
    if (famousLandmarks.containsKey(japaneseText)) {
      return famousLandmarks[japaneseText];
    }

    // Check for common suffix patterns
    for (final entry in commonSuffixes.entries) {
      if (japaneseText.endsWith(entry.key)) {
        final baseName = japaneseText.substring(0, japaneseText.length - entry.key.length);
        // Try to find the base name in famous landmarks
        for (final landmark in famousLandmarks.entries) {
          if (landmark.key.startsWith(baseName)) {
            final romanBase = landmark.value.split(' ').first;
            return '$romanBase ${entry.value}';
          }
        }
        // If no match found, just add the suffix
        return '$baseName ${entry.value}';
      }
    }

    return null;
  }

  /// Translate Japanese text to English using a translation API
  Future<String?> _translateToEnglish(String japaneseText) async {
    try {
      // Using Google Translate API (free tier)
      // Note: In production, you should use your own API key
      final encodedText = Uri.encodeComponent(japaneseText);
      final url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=ja&tl=en&dt=t&q=$encodedText';

      print('DEBUG: Attempting translation API call for: $japaneseText');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; Flutter app)',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty && data[0] is List && data[0].isNotEmpty) {
          final translatedText = data[0][0][0] as String?;
          if (translatedText != null && translatedText.isNotEmpty) {
            print('DEBUG: Translation API success: "$japaneseText" -> "$translatedText"');
            return translatedText;
          }
        }
      }

      print('DEBUG: Translation API failed for: $japaneseText (Status: ${response.statusCode})');
    } catch (e) {
      print('DEBUG: Translation API error for "$japaneseText": $e');
    }

    return null;
  }

  /// Clear the romanization cache
  void clearCache() {
    _cache.clear();
    print('DEBUG: Romanization cache cleared');
  }

  /// Get cache size
  int get cacheSize => _cache.length;

  /// Add custom romanization to cache
  void addCustomRomanization(String japanese, String roman) {
    _cache[japanese] = roman;
    print('DEBUG: Added custom romanization: "$japanese" -> "$roman"');
  }
}