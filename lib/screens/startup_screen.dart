import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'unified_map_screen.dart';
import 'qr_scanner_screen.dart';
import 'device_id_screen.dart';
import '../services/startup_tour_check_service.dart';
import '../services/postgrest_service.dart';
import '../services/tour_validity_service.dart';
import 'dart:io' show Platform, exit;

/// 起動時にツアーの有効期間をチェックして適切な画面に遷移する
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _checkAndNavigate();
  }

  Future<void> _checkAndNavigate() async {
    // 少し待機してスプラッシュ画面のような効果を与える
    await Future.delayed(const Duration(milliseconds: 500));

    // ツアーの有効期間をチェック
    final isValid = await StartupTourCheckService.checkTourValidityOnStartup();

    if (!mounted) return;

    if (isValid) {
      // 有効なツアーがある場合は案内地図画面へ
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const UnifiedMapScreen()),
      );
    } else {
      // 無効またはツアー設定がない場合はQRスキャナー画面へ
      setState(() {
        _isNavigating = true;
      });

      final result = await Navigator.push<Map<String, String>?>(
        context,
        MaterialPageRoute(builder: (context) => const QRScannerScreen()),
      );

      setState(() {
        _isNavigating = false;
      });

      // QRスキャン後、結果がある場合はデータを保存して案内地図画面へ遷移
      if (result != null && mounted) {
        await _processQRData(result);
      } else if (mounted) {
        // QRスキャンがキャンセルされた場合、もう一度QRスキャナーを表示
        // (バックボタンが押された場合など)
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          _checkAndNavigate();
        }
      }
    }
  }

  Future<void> _processQRData(Map<String, String> result) async {
    final pCode = result['p_code'];
    final companyId = result['company_id'];
    final tourId = result['tour_id'];

    if (pCode == null || companyId == null || tourId == null) {
      if (mounted) {
        _showErrorDialog('QRコードのデータが不完全です');
      }
      return;
    }

    // ツアーデータ取得と有効期間チェック
    final tourData = await PostgrestService.getTourData(
      int.parse(companyId),
      int.parse(tourId),
    );

    final validityResult = TourValidityService.checkValidity(tourData);

    if (!mounted) return;

    if (!validityResult.isValid) {
      // 有効期間外の場合、エラーメッセージを表示してアプリを終了
      _showInvalidTourDialog(validityResult);
      return;
    }

    // 有効なツアーの場合、データを保存
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_id', pCode);
    await prefs.setInt('company_id_override', int.parse(companyId));
    await prefs.setInt('company_tour_id_override', int.parse(tourId));

    // ツアー名を保存
    if (tourData != null && tourData['name'] != null) {
      await prefs.setString('tour_name', tourData['name']);
    }

    // 案内地図画面へ遷移
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const UnifiedMapScreen()),
      );
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('エラー'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // QRスキャナーに戻る
              _checkAndNavigate();
            },
            child: const Text('再試行'),
          ),
        ],
      ),
    );
  }

  void _showInvalidTourDialog(TourValidityResult validityResult) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              validityResult.errorType == ValidityErrorType.expired
                  ? Icons.error
                  : Icons.warning,
              color: Colors.red,
            ),
            const SizedBox(width: 8),
            const Text('無効なツアー'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              validityResult.message ?? 'このツアーは現在利用できません',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (validityResult.validFrom != null || validityResult.validTo != null) ...[
              const Divider(),
              const Text(
                '有効期間:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(TourValidityService.getValidityPeriodString(
                {
                  'valid_from': validityResult.validFrom?.toIso8601String(),
                  'valid_to': validityResult.validTo?.toIso8601String()
                },
              ) ?? '不明'),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const Text(
              'アプリを終了します',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // アプリを終了
              if (Platform.isAndroid) {
                SystemNavigator.pop();
              } else if (Platform.isIOS) {
                exit(0);
              }
            },
            child: const Text('終了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ナビゲーション中は透明な画面を表示（背景が見えないように）
    if (_isNavigating) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_bus,
              size: 80,
              color: Colors.blue.shade700,
            ),
            const SizedBox(height: 24),
            const Text(
              'Bus & Location Guide',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              '起動中...',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
