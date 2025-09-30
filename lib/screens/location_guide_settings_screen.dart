import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/location_settings_service.dart';
import '../services/location_service.dart';
import '../services/server_config_service.dart';
import '../services/translation_service.dart';

class LocationGuideSettingsScreen extends StatefulWidget {
  const LocationGuideSettingsScreen({super.key});

  @override
  State<LocationGuideSettingsScreen> createState() => _LocationGuideSettingsScreenState();
}

class _LocationGuideSettingsScreenState extends State<LocationGuideSettingsScreen> {
  final ApiService _apiService = ApiService();
  final AudioService _audioService = AudioService();
  final LocationSettingsService _locationSettingsService =
      LocationSettingsService();
  final LocationService _locationService = LocationService();
  final ServerConfigService _serverConfigService = ServerConfigService();
  final TranslationService _translationService = TranslationService();

  List<Map<String, dynamic>> _languages = [];
  int? _selectedLanguageId;
  bool _isLoading = true;
  String? _error;

  // Location settings
  int _timeInterval = 30;
  int _distanceInterval = 10;
  bool _autoUpdateEnabled = true;
  bool _showStatusPanel = false; // デフォルトは非表示

  // Server settings
  String _serverHost = 'circleone.biz';
  int _serverPort = 3000;
  String _serverProtocol = 'https';
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLanguages();
    _loadLocationSettings();
    _loadServerSettings();
    _loadStatusPanelSetting();
  }

  Future<void> _loadLanguages() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final languages = await _apiService.getLanguages();
      final selectedId = await _audioService.getSelectedLanguageId();

      setState(() {
        _languages = languages;
        _selectedLanguageId = selectedId;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load languages: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLocationSettings() async {
    try {
      final settings = await _locationSettingsService.getSettings();
      setState(() {
        _timeInterval = settings.timeInterval;
        _distanceInterval = settings.distanceInterval;
        _autoUpdateEnabled = settings.autoUpdateEnabled;
      });
    } catch (e) {
      // Use default values if loading fails
    }
  }

  Future<void> _onLanguageChanged(int? languageId) async {
    if (languageId == null) return;

    print('🔄 Language change requested: $languageId');

    try {
      await _audioService.setSelectedLanguageId(languageId);
      print('✅ Language saved to AudioService');

      setState(() {
        _selectedLanguageId = languageId;
        print('✅ setState called with languageId: $languageId');
      });

      print('🔍 Available languages: $_languages');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Language setting saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error in _onLanguageChanged: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save language setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadServerSettings() async {
    try {
      final config = await _serverConfigService.getCurrentConfig();
      setState(() {
        _serverHost = config['host'];
        _serverPort = config['port'];
        _serverProtocol = config['protocol'];
        _hostController.text = _serverHost;
        _portController.text = _serverPort.toString();
      });
    } catch (e) {
      print('Failed to load server settings: $e');
    }
  }

  Future<void> _loadStatusPanelSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _showStatusPanel = prefs.getBool('show_status_panel') ?? false; // デフォルトは非表示
      });
    } catch (e) {
      print('Failed to load status panel setting: $e');
    }
  }

  Future<void> _saveStatusPanelSetting(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_status_panel', value);
      setState(() {
        _showStatusPanel = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status panel setting saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save status panel setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveLocationSettings() async {
    try {
      final settings = LocationUpdateSettings(
        timeInterval: _timeInterval,
        distanceInterval: _distanceInterval,
        autoUpdateEnabled: _autoUpdateEnabled,
      );

      await _locationSettingsService.saveSettings(settings);
      await _locationService.updateTrackingSettings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location settings saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save location settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getLanguageCode(int? languageId) {
    print('🌍 _getLanguageCode called with languageId: $languageId');
    if (languageId == null) {
      print('   ⚠️  languageId is null, returning default: en');
      return 'en';
    }

    // データベースから言語コードを取得
    try {
      final language = _languages.firstWhere(
        (lang) => lang['id'] == languageId,
        orElse: () => <String, dynamic>{},
      );

      print('   🔍 Found language data: $language');

      // 'code' または 'language_code' フィールドがあれば使用
      if (language.containsKey('code')) {
        final code = language['code'] as String;
        print('   ✅ Using code field: $code');
        return code;
      } else if (language.containsKey('language_code')) {
        final code = language['language_code'] as String;
        print('   ✅ Using language_code field: $code');
        return code;
      }

      // フィールドがない場合は、name_localから推測
      final nameLocal = language['name_local'] as String? ?? '';
      print('   🔍 Trying to infer from name_local: $nameLocal');
      if (nameLocal.contains('日本') || nameLocal == '日本語') {
        print('   ✅ Inferred: ja');
        return 'ja';
      }
      if (nameLocal.contains('English') || nameLocal == 'English') {
        print('   ✅ Inferred: en');
        return 'en';
      }
      if (nameLocal.contains('한국') || nameLocal == '한국어') {
        print('   ✅ Inferred: ko');
        return 'ko';
      }
      if (nameLocal.contains('中文') || nameLocal.contains('简')) {
        print('   ✅ Inferred: zh');
        return 'zh';
      }

    } catch (e) {
      // エラーの場合はデフォルト値を使用
      print('   ❌ Error in _getLanguageCode: $e');
    }

    // フォールバック: IDベースのマッピング
    String fallbackCode;
    switch (languageId) {
      case 1: fallbackCode = 'ja'; break;
      case 2: fallbackCode = 'en'; break;
      case 3: fallbackCode = 'ko'; break;
      case 4: fallbackCode = 'zh'; break;
      default: fallbackCode = 'en'; break;
    }
    print('   ⚠️  Using ID-based fallback: $fallbackCode');
    return fallbackCode;
  }

  @override
  Widget build(BuildContext context) {
    print('🎨 build() called with _selectedLanguageId: $_selectedLanguageId');
    final languageCode = _getLanguageCode(_selectedLanguageId);
    print('🎨 Using languageCode: $languageCode');
    final title = _translationService.getTranslation(languageCode, 'location_settings');
    print('🎨 Title translation: $title');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location Settings Section
            Text(
              _translationService.getTranslation(languageCode, 'location_settings'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: Text(_translationService.getTranslation(languageCode, 'automatic_location_updates')),
                      subtitle: Text(
                        _translationService.getTranslation(languageCode, 'enable_automatic_updates'),
                      ),
                      value: _autoUpdateEnabled,
                      onChanged: (value) async {
                        setState(() {
                          _autoUpdateEnabled = value;
                        });
                        await _saveLocationSettings();

                        // Start or stop tracking immediately based on setting
                        if (value) {
                          await _locationService.startAutoLocationTracking();
                          print('Auto tracking started from settings');
                        } else {
                          await _locationService.stopAutoLocationTracking();
                          print('Auto tracking stopped from settings');
                        }
                      },
                    ),

                    const Divider(),

                    ListTile(
                      title: Text(_translationService.getTranslation(languageCode, 'time_interval')),
                      subtitle: Text('$_timeInterval ${_translationService.getTranslation(languageCode, 'seconds')}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _timeInterval > 10
                                ? () {
                                    setState(() {
                                      _timeInterval = (_timeInterval - 10)
                                          .clamp(10, 300);
                                    });
                                    _saveLocationSettings();
                                  }
                                : null,
                            icon: const Icon(Icons.remove),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text(
                              '${_timeInterval}s',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _timeInterval < 300
                                ? () {
                                    setState(() {
                                      _timeInterval = (_timeInterval + 10)
                                          .clamp(10, 300);
                                    });
                                    _saveLocationSettings();
                                  }
                                : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),

                    ListTile(
                      title: Text(_translationService.getTranslation(languageCode, 'distance_interval')),
                      subtitle: Text(
                        '$_distanceInterval ${_translationService.getTranslation(languageCode, 'meters')}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _distanceInterval > 5
                                ? () {
                                    setState(() {
                                      _distanceInterval =
                                          (_distanceInterval - 5).clamp(5, 100);
                                    });
                                    _saveLocationSettings();
                                  }
                                : null,
                            icon: const Icon(Icons.remove),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text(
                              '${_distanceInterval}m',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _distanceInterval < 100
                                ? () {
                                    setState(() {
                                      _distanceInterval =
                                          (_distanceInterval + 5).clamp(5, 100);
                                    });
                                    _saveLocationSettings();
                                  }
                                : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _locationService.isAutoTrackingActive
                              ? Icons.gps_fixed
                              : Icons.gps_off,
                          color: _locationService.isAutoTrackingActive
                              ? Colors.green
                              : Colors.grey,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _locationService.isAutoTrackingActive
                              ? 'Tracking active'
                              : 'Tracking inactive',
                          style: TextStyle(
                            color: _locationService.isAutoTrackingActive
                                ? Colors.green
                                : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Display Settings Section
            Text(
              _translationService.getTranslation(languageCode, 'display_settings'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: Text(_translationService.getTranslation(languageCode, 'show_status_panel')),
                      subtitle: Text(
                        _translationService.getTranslation(languageCode, 'show_status_panel_description'),
                      ),
                      value: _showStatusPanel,
                      onChanged: (value) async {
                        await _saveStatusPanelSetting(value);
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Language Selection Section
            const Text(
              'Language Selection',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadLanguages,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                child: Column(
                  children: _languages.map((language) {
                    final languageId = language['id'] as int;
                    final nameJa = language['name_ja'] as String;
                    final nameLocal = language['name_local'] as String;

                    return RadioListTile<int>(
                      title: Text(nameJa),
                      subtitle: Text(nameLocal),
                      value: languageId,
                      groupValue: _selectedLanguageId,
                      onChanged: _onLanguageChanged,
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
