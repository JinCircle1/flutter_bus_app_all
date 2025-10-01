import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/postgrest_service.dart';
import '../services/tour_validity_service.dart';
import 'qr_scanner_screen.dart';
import 'dart:io' show Platform, exit;

class DeviceIdScreen extends StatefulWidget {
  final Future<void> Function()? onIdChanged;

  const DeviceIdScreen({super.key, this.onIdChanged});

  @override
  State<DeviceIdScreen> createState() => _DeviceIdScreenState();
}

class _DeviceIdScreenState extends State<DeviceIdScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _savedId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedId = prefs.getString('device_id');
      if (_savedId != null) {
        _controller.text = _savedId!;
      }
    });
  }

  Future<void> _saveDeviceId(String id) async {
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IDを入力してください')),
      );
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final oldId = prefs.getString('device_id');
    await prefs.setString('device_id', id);

    if (oldId != id && widget.onIdChanged != null) {
      await widget.onIdChanged!();
    }

    setState(() {
      _savedId = id;
      _controller.text = id;
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ID「$id」を保存しました')));
    }
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) => const QRScannerScreen(),
      ),
    );

    if (result != null && mounted) {
      final pCode = result['p_code'];
      final companyId = result['company_id'];
      final tourId = result['tour_id'];

      print('🔍 [QR] Scanned QR data:');
      print('   - p_code: $pCode');
      print('   - company_id: $companyId (type: ${companyId.runtimeType})');
      print('   - tour_id: $tourId (type: ${tourId.runtimeType})');

      if (pCode != null) {
        // company_idとtour_idがある場合、有効期間をチェック
        if (companyId != null && tourId != null) {
          // ツアーデータ取得と有効期間チェック
          print('🔍 [QR] Calling getTourData with: company_id=${int.parse(companyId)}, tour_id=${int.parse(tourId)}');
          final tourData = await PostgrestService.getTourData(
            int.parse(companyId),
            int.parse(tourId),
          );

          final validityResult = TourValidityService.checkValidity(tourData);

          if (!validityResult.isValid && mounted) {
            // 有効期間外の場合、エラーメッセージを表示してアプリを終了
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
                        {'valid_from': validityResult.validFrom?.toIso8601String(), 'valid_to': validityResult.validTo?.toIso8601String()}
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
            return;
          }

          // 有効なツアーの場合、保存する
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('company_id_override', int.parse(companyId));
          await prefs.setInt('company_tour_id_override', int.parse(tourId));

          // ツアー名を保存
          if (tourData != null && tourData['name'] != null) {
            await prefs.setString('tour_name', tourData['name']);
          }

          // 成功ダイアログを表示（ツアー名と開始・終了日時を含む）
          if (mounted) {
            _showTourInfoDialog(
              tourData: tourData,
              pCode: pCode,
              companyId: companyId,
              tourId: tourId,
            );
          }
        }

        // p_codeをデバイスIDに設定
        await _saveDeviceId(pCode);
      }
    }
  }

  /// ツアー情報ダイアログを表示
  void _showTourInfoDialog({
    required Map<String, dynamic>? tourData,
    required String pCode,
    required String companyId,
    required String tourId,
  }) {
    // デバッグ: 取得されたデータの全フィールドを確認
    print('🔍 [TourInfo] Retrieved tour data:');
    print('   - Tour ID (internal): ${tourData?['id']}');
    print('   - Company ID: ${tourData?['company_id']}');
    print('   - External Tour ID: ${tourData?['external_tour_id']}');
    print('   - Name: ${tourData?['name']}');
    print('   - start_time: ${tourData?['start_time']}');
    print('   - end_time: ${tourData?['end_time']}');

    final tourName = tourData?['name'] ?? '不明';
    final startTime = tourData?['start_time'];
    final endTime = tourData?['end_time'];

    String formatDateTime(String? dateTimeStr) {
      if (dateTimeStr == null) return '未設定';
      try {
        // UTCとしてパースしてからJST（UTC+9）に変換
        final dt = DateTime.parse(dateTimeStr).toUtc();
        final jst = dt.add(const Duration(hours: 9));
        return '${jst.year}年${jst.month}月${jst.day}日 '
               '${jst.hour.toString().padLeft(2, '0')}:'
               '${jst.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        return dateTimeStr;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 24),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'QRコード読み取り成功',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ツアー情報',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildInfoRow('ツアー名', tourName),
              const Divider(),
              _buildInfoRow('デバイスID', pCode),
              _buildInfoRow('Company ID', companyId),
              _buildInfoRow('Tour ID', tourId),
              const Divider(),
              const Text(
                '開催期間',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildInfoRow('開始日時', formatDateTime(startTime)),
              _buildInfoRow('終了日時', formatDateTime(endTime)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  /// 情報行を構築
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ユーザー設定')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'デバイスID設定',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'この端末に割り当てるIDを入力、またはQRコードで読み取り',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'IDを入力',
                        hintText: '例: ID001',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final id = _controller.text.trim();
                              _saveDeviceId(id);
                            },
                            child: const Text('IDを保存'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _scanQRCode,
                            label: const Text("QR読み取り"),
                          ),
                        ),
                      ],
                    ),
                    if (_savedId != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '現在のID: $_savedId',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
