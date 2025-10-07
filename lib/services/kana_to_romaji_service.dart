/// ひらがな・カタカナをローマ字に変換するサービス
class KanaToRomajiService {
  static final KanaToRomajiService _instance = KanaToRomajiService._internal();
  factory KanaToRomajiService() => _instance;
  KanaToRomajiService._internal();

  // ひらがな→ローマ字マッピング
  static const Map<String, String> _hiraganaMap = {
    // 清音
    'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
    'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
    'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
    'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
    'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
    'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
    'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
    'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
    'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
    'わ': 'wa', 'を': 'wo', 'ん': 'n',

    // 濁音
    'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
    'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
    'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
    'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',

    // 半濁音
    'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',

    // 拗音
    'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
    'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho',
    'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho',
    'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
    'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
    'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
    'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
    'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
    'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
    'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
    'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',

    // 小文字
    'ぁ': 'a', 'ぃ': 'i', 'ぅ': 'u', 'ぇ': 'e', 'ぉ': 'o',
    'ゃ': 'ya', 'ゅ': 'yu', 'ょ': 'yo',
    'ゎ': 'wa',
  };

  // カタカナ→ローマ字マッピング
  static const Map<String, String> _katakanaMap = {
    // 清音
    'ア': 'a', 'イ': 'i', 'ウ': 'u', 'エ': 'e', 'オ': 'o',
    'カ': 'ka', 'キ': 'ki', 'ク': 'ku', 'ケ': 'ke', 'コ': 'ko',
    'サ': 'sa', 'シ': 'shi', 'ス': 'su', 'セ': 'se', 'ソ': 'so',
    'タ': 'ta', 'チ': 'chi', 'ツ': 'tsu', 'テ': 'te', 'ト': 'to',
    'ナ': 'na', 'ニ': 'ni', 'ヌ': 'nu', 'ネ': 'ne', 'ノ': 'no',
    'ハ': 'ha', 'ヒ': 'hi', 'フ': 'fu', 'ヘ': 'he', 'ホ': 'ho',
    'マ': 'ma', 'ミ': 'mi', 'ム': 'mu', 'メ': 'me', 'モ': 'mo',
    'ヤ': 'ya', 'ユ': 'yu', 'ヨ': 'yo',
    'ラ': 'ra', 'リ': 'ri', 'ル': 'ru', 'レ': 're', 'ロ': 'ro',
    'ワ': 'wa', 'ヲ': 'wo', 'ン': 'n',

    // 濁音
    'ガ': 'ga', 'ギ': 'gi', 'グ': 'gu', 'ゲ': 'ge', 'ゴ': 'go',
    'ザ': 'za', 'ジ': 'ji', 'ズ': 'zu', 'ゼ': 'ze', 'ゾ': 'zo',
    'ダ': 'da', 'ヂ': 'ji', 'ヅ': 'zu', 'デ': 'de', 'ド': 'do',
    'バ': 'ba', 'ビ': 'bi', 'ブ': 'bu', 'ベ': 'be', 'ボ': 'bo',

    // 半濁音
    'パ': 'pa', 'ピ': 'pi', 'プ': 'pu', 'ペ': 'pe', 'ポ': 'po',

    // 拗音
    'キャ': 'kya', 'キュ': 'kyu', 'キョ': 'kyo',
    'シャ': 'sha', 'シュ': 'shu', 'ショ': 'sho',
    'チャ': 'cha', 'チュ': 'chu', 'チョ': 'cho',
    'ニャ': 'nya', 'ニュ': 'nyu', 'ニョ': 'nyo',
    'ヒャ': 'hya', 'ヒュ': 'hyu', 'ヒョ': 'hyo',
    'ミャ': 'mya', 'ミュ': 'myu', 'ミョ': 'myo',
    'リャ': 'rya', 'リュ': 'ryu', 'リョ': 'ryo',
    'ギャ': 'gya', 'ギュ': 'gyu', 'ギョ': 'gyo',
    'ジャ': 'ja', 'ジュ': 'ju', 'ジョ': 'jo',
    'ビャ': 'bya', 'ビュ': 'byu', 'ビョ': 'byo',
    'ピャ': 'pya', 'ピュ': 'pyu', 'ピョ': 'pyo',

    // 外来語用
    'ヴァ': 'va', 'ヴィ': 'vi', 'ヴ': 'vu', 'ヴェ': 've', 'ヴォ': 'vo',
    'ファ': 'fa', 'フィ': 'fi', 'フェ': 'fe', 'フォ': 'fo',
    'ウィ': 'wi', 'ウェ': 'we', 'ウォ': 'wo',
    'ティ': 'ti', 'ディ': 'di', 'デュ': 'du',
    'トゥ': 'tu', 'ドゥ': 'du',
    'シェ': 'she', 'ジェ': 'je', 'チェ': 'che',

    // 小文字
    'ァ': 'a', 'ィ': 'i', 'ゥ': 'u', 'ェ': 'e', 'ォ': 'o',
    'ャ': 'ya', 'ュ': 'yu', 'ョ': 'yo',
    'ヮ': 'wa',
    'ッ': '',  // 促音は次の子音を重ねる
  };

  /// ひらがな・カタカナをローマ字に変換
  String convert(String kana) {
    if (kana.isEmpty) return '';

    final buffer = StringBuffer();
    int i = 0;

    while (i < kana.length) {
      // 拗音（2文字）を先にチェック
      if (i + 1 < kana.length) {
        final twoChar = kana.substring(i, i + 2);

        // ひらがな拗音
        if (_hiraganaMap.containsKey(twoChar)) {
          buffer.write(_hiraganaMap[twoChar]);
          i += 2;
          continue;
        }

        // カタカナ拗音
        if (_katakanaMap.containsKey(twoChar)) {
          buffer.write(_katakanaMap[twoChar]);
          i += 2;
          continue;
        }
      }

      // 単一文字
      final char = kana[i];

      // 促音（っ、ッ）の処理
      if (char == 'っ' || char == 'ッ') {
        // 次の文字の子音を重ねる
        if (i + 1 < kana.length) {
          final nextChar = kana[i + 1];
          final romaji = _hiraganaMap[nextChar] ?? _katakanaMap[nextChar];
          if (romaji != null && romaji.isNotEmpty) {
            buffer.write(romaji[0]); // 最初の子音を追加
          }
        }
        i++;
        continue;
      }

      // 長音（ー）の処理
      if (char == 'ー') {
        // 前の母音を延長（同じ母音を追加）
        if (buffer.isNotEmpty) {
          final lastChar = buffer.toString()[buffer.length - 1];
          if ('aiueo'.contains(lastChar)) {
            buffer.write(lastChar);
          }
        }
        i++;
        continue;
      }

      // ひらがな
      if (_hiraganaMap.containsKey(char)) {
        buffer.write(_hiraganaMap[char]);
        i++;
        continue;
      }

      // カタカナ
      if (_katakanaMap.containsKey(char)) {
        buffer.write(_katakanaMap[char]);
        i++;
        continue;
      }

      // その他の文字（スペース、記号など）はそのまま
      buffer.write(char);
      i++;
    }

    // 先頭を大文字に
    final result = buffer.toString();
    if (result.isEmpty) return '';

    return result[0].toUpperCase() + result.substring(1);
  }

  /// ローマ字文字列を単語ごとに先頭大文字に変換
  String toTitleCase(String text) {
    if (text.isEmpty) return '';

    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
