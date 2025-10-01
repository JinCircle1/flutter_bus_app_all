import 'package:flutter/material.dart';
import 'unified_map_screen.dart';
import 'qr_scanner_screen.dart';
import '../services/startup_tour_check_service.dart';

/// 起動時にツアーの有効期間をチェックして適切な画面に遷移する
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
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
      final result = await Navigator.pushReplacement<Map<String, String>?, void>(
        context,
        MaterialPageRoute(builder: (context) => const QRScannerScreen()),
      );

      // QRスキャン後、結果がある場合は案内地図画面へ遷移
      if (result != null && mounted) {
        // QRスキャンが成功した場合、案内地図画面に遷移
        // (device_id_screen.dartでデータ保存処理が完了している前提)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const UnifiedMapScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
