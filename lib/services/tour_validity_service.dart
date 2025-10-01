import 'dart:developer' as developer;

class TourValidityService {
  /// ツアーの有効期間をチェック
  /// valid_from と valid_to を確認して、現在日時が期間内かチェック
  static TourValidityResult checkValidity(Map<String, dynamic>? tourData) {
    if (tourData == null) {
      return TourValidityResult(
        isValid: false,
        errorType: ValidityErrorType.notFound,
        message: 'ツアーデータが見つかりません',
      );
    }

    try {
      // valid_from/valid_to または start_time/end_time を使用
      final validFrom = tourData['valid_from'] ?? tourData['start_time'];
      final validTo = tourData['valid_to'] ?? tourData['end_time'];

      developer.log('🔍 [TourValidity] Checking validity with:');
      developer.log('   - validFrom (or start_time): $validFrom');
      developer.log('   - validTo (or end_time): $validTo');

      // valid_from/start_time と valid_to/end_time が存在しない場合は有効とみなす
      if (validFrom == null && validTo == null) {
        developer.log('✅ [TourValidity] No validity period set, tour is valid');
        return TourValidityResult(
          isValid: true,
          errorType: null,
          message: null,
        );
      }

      final now = DateTime.now();
      developer.log('   - Current time: $now');

      // valid_from チェック（開始日時前）
      if (validFrom != null) {
        // UTCとしてパースしてJST（UTC+9）に変換
        final validFromDate = DateTime.parse(validFrom).toUtc().add(const Duration(hours: 9));
        developer.log('   - Parsed validFromDate (JST): $validFromDate');

        if (now.isBefore(validFromDate)) {
          developer.log('❌ [TourValidity] Tour not started yet. Start: $validFromDate, Now: $now');
          return TourValidityResult(
            isValid: false,
            errorType: ValidityErrorType.notStarted,
            message: 'このツアーはまだ開始されていません\n開始日時: ${_formatDateTime(validFromDate)}',
            validFrom: validFromDate,
            validTo: validTo != null ? DateTime.parse(validTo).toUtc().add(const Duration(hours: 9)) : null,
          );
        }
      }

      // valid_to チェック（終了日時後）
      if (validTo != null) {
        // UTCとしてパースしてJST（UTC+9）に変換
        final validToDate = DateTime.parse(validTo).toUtc().add(const Duration(hours: 9));
        developer.log('   - Parsed validToDate (JST): $validToDate');

        if (now.isAfter(validToDate)) {
          developer.log('❌ [TourValidity] Tour expired. End: $validToDate, Now: $now');
          return TourValidityResult(
            isValid: false,
            errorType: ValidityErrorType.expired,
            message: 'このツアーの有効期限が切れています\n終了日時: ${_formatDateTime(validToDate)}',
            validFrom: validFrom != null ? DateTime.parse(validFrom).toUtc().add(const Duration(hours: 9)) : null,
            validTo: validToDate,
          );
        }
      }

      // 有効期間内
      developer.log('✅ [TourValidity] Tour is valid');
      return TourValidityResult(
        isValid: true,
        errorType: null,
        message: null,
        validFrom: validFrom != null ? DateTime.parse(validFrom).toUtc().add(const Duration(hours: 9)) : null,
        validTo: validTo != null ? DateTime.parse(validTo).toUtc().add(const Duration(hours: 9)) : null,
      );
    } catch (e) {
      developer.log('❌ [TourValidity] Error checking validity: $e');
      return TourValidityResult(
        isValid: false,
        errorType: ValidityErrorType.error,
        message: '有効期間のチェック中にエラーが発生しました: $e',
      );
    }
  }

  /// 日時を日本語形式でフォーマット
  static String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}年${dateTime.month}月${dateTime.day}日 '
           '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// 有効期間の残り日数を取得（有効な場合のみ）
  static int? getRemainingDays(Map<String, dynamic>? tourData) {
    if (tourData == null) return null;

    try {
      final validTo = tourData['valid_to'] ?? tourData['end_time'];
      if (validTo == null) return null;

      // UTCとしてパースしてJST（UTC+9）に変換
      final validToDate = DateTime.parse(validTo).toUtc().add(const Duration(hours: 9));
      final now = DateTime.now();

      if (now.isAfter(validToDate)) return null;

      final difference = validToDate.difference(now);
      return difference.inDays;
    } catch (e) {
      developer.log('❌ [TourValidity] Error getting remaining days: $e');
      return null;
    }
  }

  /// 有効期間を取得（表示用）
  static String? getValidityPeriodString(Map<String, dynamic>? tourData) {
    if (tourData == null) return null;

    try {
      final validFrom = tourData['valid_from'] ?? tourData['start_time'];
      final validTo = tourData['valid_to'] ?? tourData['end_time'];

      if (validFrom == null && validTo == null) {
        return '期限なし';
      }

      final fromStr = validFrom != null
          ? _formatDateTime(DateTime.parse(validFrom).toUtc().add(const Duration(hours: 9)))
          : '開始日なし';
      final toStr = validTo != null
          ? _formatDateTime(DateTime.parse(validTo).toUtc().add(const Duration(hours: 9)))
          : '終了日なし';

      return '$fromStr ～ $toStr';
    } catch (e) {
      developer.log('❌ [TourValidity] Error formatting validity period: $e');
      return null;
    }
  }
}

/// ツアー有効性チェックの結果
class TourValidityResult {
  final bool isValid;
  final ValidityErrorType? errorType;
  final String? message;
  final DateTime? validFrom;
  final DateTime? validTo;

  TourValidityResult({
    required this.isValid,
    required this.errorType,
    required this.message,
    this.validFrom,
    this.validTo,
  });
}

/// 有効性エラーの種類
enum ValidityErrorType {
  notFound,    // ツアーが見つからない
  notStarted,  // まだ開始されていない
  expired,     // 期限切れ
  error,       // その他のエラー
}