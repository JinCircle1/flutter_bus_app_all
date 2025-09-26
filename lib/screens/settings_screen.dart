import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/location_settings_service.dart';
import '../services/location_service.dart';
import '../services/server_config_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _apiService = ApiService();
  final AudioService _audioService = AudioService();
  final LocationSettingsService _locationSettingsService =
      LocationSettingsService();
  final LocationService _locationService = LocationService();
  final ServerConfigService _serverConfigService = ServerConfigService();

  List<Map<String, dynamic>> _languages = [];
  int? _selectedLanguageId;
  bool _isLoading = true;
  String? _error;

  // Location settings
  int _timeInterval = 30;
  int _distanceInterval = 10;
  bool _autoUpdateEnabled = true;

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

    try {
      await _audioService.setSelectedLanguageId(languageId);
      setState(() {
        _selectedLanguageId = languageId;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Language setting saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location Settings Section
            const Text(
              'Location Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('Automatic Location Updates'),
                      subtitle: const Text(
                        'Enable background location tracking',
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
                      title: const Text('Time Interval'),
                      subtitle: Text('Update every $_timeInterval seconds'),
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
                      title: const Text('Distance Interval'),
                      subtitle: Text(
                        'Update when moved $_distanceInterval meters',
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
