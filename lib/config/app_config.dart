import 'package:shared_preferences/shared_preferences.dart';

/// アプリケーション全体の設定を管理するクラス
class AppConfig {
  // WebSocket設定 - カスタムトランスポートが代替ポートを試行
  static const String janusWebSocketUrl = 'wss://circleone.biz:443/janus-ws';

  // 代替接続用の設定
  static const String janusHttpPort = '8188'; // Janus標準HTTPポート
  static const String janusHttpsPort = '8989'; // Janus標準HTTPSポート

  // PostgREST設定 (Supabaseから移行)
  static const String postgrestUrl = 'https://circleone.biz/api';

  // WebRTC設定 - 専用STUN/TURNサーバーを優先使用
  static const String stunServerUrl = 'stun:210.149.70.103:3478';

  // TURNサーバー設定
  static const String turnServerUrl = 'turn:210.149.70.103:3478';
  static const String turnServerUrlTcp = 'turn:210.149.70.103:3478?transport=tcp';
  static const String turnsServerUrl = 'turns:210.149.70.103:5349?transport=tcp';

  // TURN認証情報
  static const String turnUsername = 'c1janus';  // TURNサーバーのユーザー名
  static const String turnCredential = 'c1j-661648'; // TURNサーバーのパスワード

  // TextRoom設定
  static const int textRoomId = 2001;

  // ツアー設定（デフォルト値）
  static const int _defaultCompanyId = 1;
  static const int _defaultCompanyTourId = 1;

  static const String _companyIdKey = 'company_id_override';
  static const String _companyTourIdKey = 'company_tour_id_override';

  /// 設定値を取得（SharedPreferencesの値を優先、なければデフォルト値）
  static Future<int> getCompanyId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_companyIdKey) ?? _defaultCompanyId;
    } catch (e) {
      return _defaultCompanyId;
    }
  }

  /// 設定値を取得（SharedPreferencesの値を優先、なければデフォルト値）
  static Future<int> getCompanyTourId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_companyTourIdKey) ?? _defaultCompanyTourId;
    } catch (e) {
      return _defaultCompanyTourId;
    }
  }

  /// 同期的アクセス用（後方互換性のため）
  static int get companyId => _defaultCompanyId;
  static int get companyTourId => _defaultCompanyTourId;

  // 開発環境と本番環境の切り替え
  static const bool isProduction = false;

  // 環境に応じたURLを取得
  static String get effectivePostgrestUrl {
    return isProduction
        ? 'https://circleone.biz/api'
        : postgrestUrl;
  }
}

// サーバーマップ（元のconfigとの互換性）
final Map<String, String> servermap = {
  'janus_ws': AppConfig.janusWebSocketUrl,
  'postgrest': AppConfig.effectivePostgrestUrl,
};