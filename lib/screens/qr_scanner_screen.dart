import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:developer' as developer;

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isProcessing = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Map<String, String>? _parseQRData(String rawData) {
    try {
      developer.log('🔍 [QRScanner] Raw QR data: $rawData');

      // QRコードのフォーマット: "company_id=XXX,tour_id=YYY,p_code=ZZZ"
      final parts = rawData.split(',');
      final Map<String, String> result = {};

      for (final part in parts) {
        final keyValue = part.trim().split('=');
        if (keyValue.length == 2) {
          final key = keyValue[0].trim();
          final value = keyValue[1].trim();
          result[key] = value;
        }
      }

      // 必須フィールドのチェック
      if (result.containsKey('company_id') &&
          result.containsKey('tour_id') &&
          result.containsKey('p_code')) {
        developer.log('✅ [QRScanner] Valid QR data parsed: $result');
        return result;
      } else {
        developer.log('❌ [QRScanner] Missing required fields. Found: ${result.keys}');
        return null;
      }
    } catch (e) {
      developer.log('❌ [QRScanner] Parse error: $e');
      return null;
    }
  }

  void _handleBarcode(BarcodeCapture barcodes) {
    if (_isProcessing) return;

    final barcode = barcodes.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() {
      _isProcessing = true;
    });

    final rawData = barcode!.rawValue!;
    final parsedData = _parseQRData(rawData);

    if (parsedData != null && mounted) {
      // 成功時に振動フィードバック
      Navigator.pop(context, parsedData);
    } else if (mounted) {
      // エラー表示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('無効なQRコード形式です'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );

      // 再スキャン可能にする
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QRコードスキャン'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // カメラビュー
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
          ),
          // スキャンエリアのオーバーレイ
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // 説明テキスト
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black.withValues(alpha: 0.7),
              child: const Text(
                'QRコードを枠内に収めてください',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // フラッシュライトボタン
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _torchOn = !_torchOn;
                    });
                    _controller.toggleTorch();
                  },
                  icon: Icon(
                    _torchOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}