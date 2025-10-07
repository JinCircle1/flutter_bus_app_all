import 'package:shared_preferences/shared_preferences.dart';
import 'postgrest_service.dart';
import 'tour_validity_service.dart';

/// アプリ起動時のツアー有効期間チェックサービス
class StartupTourCheckService {
  /// 起動時にツアーの有効期間をチェック
  ///
  /// 戻り値:
  /// - true: 有効なツアーがある、またはツアー設定がない
  /// - false: 無効なツアー（有効期間外）
  static Future<bool> checkTourValidityOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Company IDとCompany Tour IDを取得
      final companyId = prefs.getInt('company_id_override');
      final companyTourId = prefs.getInt('company_tour_id_override');

      print('🔍 [STARTUP] Company ID: $companyId, Company Tour ID: $companyTourId');

      // どちらかが設定されていない場合は、チェックをスキップ（初回起動など）
      if (companyId == null || companyTourId == null) {
        print('⚠️ [STARTUP] ツアー設定がありません。QRスキャナー画面へ遷移します');
        return false;
      }

      // ツアーデータを取得
      final tourData = await PostgrestService.getTourData(companyId, companyTourId);

      if (tourData == null) {
        print('⚠️ [STARTUP] ツアーデータが見つかりません');
        return false;
      }

      // 有効期間をチェック
      final validityResult = TourValidityService.checkValidity(tourData);

      if (validityResult.isValid) {
        print('✅ [STARTUP] ツアーは有効です');
        return true;
      } else {
        print('❌ [STARTUP] ツアーが無効です: ${validityResult.message}');
        return false;
      }
    } catch (e) {
      print('❌ [STARTUP] ツアーチェックエラー: $e');
      // エラーの場合は安全のため無効として扱う
      return false;
    }
  }

  /// 起動時にツアーの有効期間をチェック（詳細版）
  ///
  /// 戻り値: Map<String, dynamic>
  /// - 'isValid': bool - 有効かどうか
  /// - 'validityResult': TourValidityResult? - 有効期間チェック結果（期間外の場合）
  static Future<Map<String, dynamic>> checkTourValidityOnStartupDetailed() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Company IDとCompany Tour IDを取得
      final companyId = prefs.getInt('company_id_override');
      final companyTourId = prefs.getInt('company_tour_id_override');

      print('🔍 [STARTUP] Company ID: $companyId, Company Tour ID: $companyTourId');

      // どちらかが設定されていない場合は、チェックをスキップ（初回起動など）
      if (companyId == null || companyTourId == null) {
        print('⚠️ [STARTUP] ツアー設定がありません。QRスキャナー画面へ遷移します');
        return {'isValid': false, 'validityResult': null};
      }

      // ツアーデータを取得
      print('📡 [STARTUP] ツアーデータを取得中...');
      final tourData = await PostgrestService.getTourData(companyId, companyTourId);

      if (tourData == null) {
        print('⚠️ [STARTUP] ツアーデータが見つかりません');
        print('📍 [STARTUP] Returning: isValid=false, validityResult=null');
        return {'isValid': false, 'validityResult': null};
      }

      print('✅ [STARTUP] ツアーデータを取得しました: $tourData');

      // 有効期間をチェック
      print('🕐 [STARTUP] 有効期間をチェック中...');
      final validityResult = TourValidityService.checkValidity(tourData);

      if (validityResult.isValid) {
        print('✅ [STARTUP] ツアーは有効です');
        print('📍 [STARTUP] Returning: isValid=true, validityResult=null');
        return {'isValid': true, 'validityResult': null};
      } else {
        print('❌ [STARTUP] ツアーが無効です: ${validityResult.message}');
        print('📍 [STARTUP] Returning: isValid=false, validityResult=${validityResult.errorType}');
        return {'isValid': false, 'validityResult': validityResult};
      }
    } catch (e) {
      print('❌ [STARTUP] ツアーチェックエラー: $e');
      // エラーの場合は安全のため無効として扱う
      return {'isValid': false, 'validityResult': null};
    }
  }
}
