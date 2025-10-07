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
  final TextEditingController _deviceIdController = TextEditingController();
  final TextEditingController _companyIdController = TextEditingController();
  final TextEditingController _tourIdController = TextEditingController();
  String? _savedDeviceId;
  int? _savedCompanyId;
  int? _savedTourId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedDeviceId = prefs.getString('device_id');
      _savedCompanyId = prefs.getInt('company_id_override');
      _savedTourId = prefs.getInt('company_tour_id_override');

      if (_savedDeviceId != null) {
        _deviceIdController.text = _savedDeviceId!;
      }
      if (_savedCompanyId != null) {
        _companyIdController.text = _savedCompanyId.toString();
      }
      if (_savedTourId != null) {
        _tourIdController.text = _savedTourId.toString();
      }
    });
  }

  Future<void> _saveAllSettings() async {
    final deviceId = _deviceIdController.text.trim();
    final companyIdStr = _companyIdController.text.trim();
    final tourIdStr = _tourIdController.text.trim();

    if (deviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('デバイスIDを入力してください')),
      );
      return;
    }

    if (companyIdStr.isEmpty || tourIdStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company IDとTour IDを入力してください')),
      );
      return;
    }

    final companyId = int.tryParse(companyIdStr);
    final tourId = int.tryParse(tourIdStr);

    if (companyId == null || tourId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company IDとTour IDは数値で入力してください')),
      );
      return;
    }

    // ツアーデータ取得と有効期間チェック
    final tourData = await PostgrestService.getTourData(companyId, tourId);

    if (tourData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ツアーが見つかりませんでした'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final validityResult = TourValidityService.checkValidity(tourData);

    if (!validityResult.isValid && mounted) {
      // 有効期間外の場合、エラーダイアログを表示
      _showInvalidTourDialog(validityResult);
      return;
    }

    // 有効なツアーの場合、保存する
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_id', deviceId);
    await prefs.setInt('company_id_override', companyId);
    await prefs.setInt('company_tour_id_override', tourId);

    // ツアー名を保存
    if (tourData['name'] != null) {
      await prefs.setString('tour_name', tourData['name']);
    }

    if (widget.onIdChanged != null) {
      await widget.onIdChanged!();
    }

    setState(() {
      _savedDeviceId = deviceId;
      _savedCompanyId = companyId;
      _savedTourId = tourId;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('設定を保存しました')),
      );
    }
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
              Text(TourValidityService.getValidityPeriodStringFromDates(
                validityResult.validFrom,
                validityResult.validTo,
              )),
            ],
          ],
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
                      Text(TourValidityService.getValidityPeriodStringFromDates(
                        validityResult.validFrom,
                        validityResult.validTo,
                      )),
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
          await prefs.setString('device_id', pCode);
          await prefs.setInt('company_id_override', int.parse(companyId));
          await prefs.setInt('company_tour_id_override', int.parse(tourId));

          // ツアー名を保存
          if (tourData != null && tourData['name'] != null) {
            await prefs.setString('tour_name', tourData['name']);
          }

          // フィールドに反映
          setState(() {
            _deviceIdController.text = pCode;
            _companyIdController.text = companyId;
            _tourIdController.text = tourId;
            _savedDeviceId = pCode;
            _savedCompanyId = int.parse(companyId);
            _savedTourId = int.parse(tourId);
          });

          // 成功ダイアログを表示（ツアー名と開始・終了日時を含む）
          if (mounted) {
            _showTourInfoDialog(
              tourData: tourData,
              pCode: pCode,
              companyId: companyId,
              tourId: tourId,
            );
          }
        } else {
          // company_idとtour_idがない場合は、デバイスIDのみ設定
          setState(() {
            _deviceIdController.text = pCode;
            _savedDeviceId = pCode;
          });

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('device_id', pCode);
        }
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
      body: SingleChildScrollView(
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
                      'ツアー設定',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '各項目を入力するか、QRコードで読み取ってください',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _deviceIdController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'デバイスID',
                        hintText: '例: ID001',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _companyIdController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Company ID',
                        hintText: '例: 2',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _tourIdController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Tour ID',
                        hintText: '例: 1',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveAllSettings,
                            child: const Text('保存'),
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
                    if (_savedDeviceId != null || _savedCompanyId != null || _savedTourId != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  '現在の設定',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_savedDeviceId != null)
                              Text(
                                'デバイスID: $_savedDeviceId',
                                style: const TextStyle(color: Colors.green),
                              ),
                            if (_savedCompanyId != null)
                              Text(
                                'Company ID: $_savedCompanyId',
                                style: const TextStyle(color: Colors.green),
                              ),
                            if (_savedTourId != null)
                              Text(
                                'Tour ID: $_savedTourId',
                                style: const TextStyle(color: Colors.green),
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
