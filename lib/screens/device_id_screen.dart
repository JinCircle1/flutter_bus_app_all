import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/room_config_service.dart';

class DeviceIdScreen extends StatefulWidget {
  final Future<void> Function()? onIdChanged;
  final Future<void> Function()? onLanguageChanged;

  const DeviceIdScreen({super.key, this.onIdChanged, this.onLanguageChanged});

  @override
  State<DeviceIdScreen> createState() => _DeviceIdScreenState();
}

class _DeviceIdScreenState extends State<DeviceIdScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _savedId;
  int _selectedLanguageId = 1;
  bool _isScanning = false;
  Map<int, String> _languages = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final config = await RoomConfigService.getConfig();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _languages = config.languages;
      _savedId = prefs.getString('device_id');
      _selectedLanguageId = prefs.getInt('selected_language_id') ?? config.defaultLanguageId;
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

  Future<void> _saveLanguage(int languageId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_language_id', languageId);
    setState(() {
      _selectedLanguageId = languageId;
    });

    // 言語変更コールバックを呼び出し
    if (widget.onLanguageChanged != null) {
      await widget.onLanguageChanged!();
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('言語設定を保存しました')));
    }
  }

  void _startScanning() => setState(() => _isScanning = true);
  void _stopScanning() => setState(() => _isScanning = false);

  void _onDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.first;
    final raw = barcode.rawValue ?? '';

    if (raw.startsWith("DEVICE_ID:")) {
      final id = raw.replaceFirst("DEVICE_ID:", "").trim();
      _stopScanning();
      _saveDeviceId(id);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("無効なQRコードです")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ユーザー設定')),
      body:
          _isScanning
              ? Stack(
                children: [
                  MobileScanner(onDetect: _onDetect),
                  Positioned(
                    top: 40,
                    right: 20,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _stopScanning,
                    ),
                  ),
                ],
              )
              : Padding(
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
                                    onPressed: _startScanning,
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
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '言語設定',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '音声ガイドの言語を選択してください',
                              style: TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            if (_languages.isEmpty)
                              const Center(
                                child: CircularProgressIndicator(),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: DropdownButton<int>(
                                  value: _languages.containsKey(_selectedLanguageId) 
                                      ? _selectedLanguageId 
                                      : _languages.keys.first,
                                  isExpanded: true,
                                  underline: Container(),
                                  items: _languages.entries.map((entry) {
                                    return DropdownMenuItem<int>(
                                      value: entry.key,
                                      child: Text(
                                        '${entry.value} (Language ID: ${entry.key})',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (int? newValue) {
                                    if (newValue != null && newValue != _selectedLanguageId) {
                                      _saveLanguage(newValue);
                                    }
                                  },
                                ),
                              ),
                            if (_languages.containsKey(_selectedLanguageId)) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blue),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.language, color: Colors.blue, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      '現在の言語: ${_languages[_selectedLanguageId]}',
                                      style: const TextStyle(
                                        color: Colors.blue,
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
