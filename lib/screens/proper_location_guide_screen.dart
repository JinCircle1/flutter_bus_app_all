import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../services/landmark_service.dart';
import '../services/audio_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../services/romanization_service.dart';
import 'settings_screen.dart';
import 'debug_screen.dart';

class ProperLocationGuideScreen extends StatefulWidget {
  const ProperLocationGuideScreen({super.key});

  @override
  State<ProperLocationGuideScreen> createState() => _ProperLocationGuideScreenState();
}

class _ProperLocationGuideScreenState extends State<ProperLocationGuideScreen> {
  final LandmarkService _landmarkService = LandmarkService();
  final AudioService _audioService = AudioService();
  final LocationService _locationService = LocationService();
  final ApiService _apiService = ApiService();
  final TranslationService _translationService = TranslationService();
  final RomanizationService _romanizationService = RomanizationService();

  Map<String, dynamic>? _currentLandmark;
  bool _isPlaying = false;
  bool _isLoading = true;
  String _status = 'Getting location...';

  Position? _currentPosition;
  List<Map<String, dynamic>> _landmarks = [];
  List<Map<String, dynamic>> _languages = [];
  int _selectedLanguageId = 1; // Default to Japanese
  LatLng _mapCenter = const LatLng(33.3, 131.5);
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _locationSubscription;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Reset server configuration to correct defaults
      await _apiService.resetServerConfig();

      // Get current position, landmarks, and languages
      print('DEBUG: Starting app initialization...');

      final apiBaseUrl = await _apiService.getBaseUrl();
      print('DEBUG: API Base URL: $apiBaseUrl');

      final position = await _locationService.getCurrentPosition();
      print('DEBUG: Position obtained: $position');

      try {
        print('DEBUG: Attempting to get landmarks...');
        final landmarks = await _apiService.getLandmarks();
        print('DEBUG: Landmarks obtained: ${landmarks.length} landmarks');

        print('DEBUG: Attempting to get languages...');
        final languages = await _apiService.getLanguages();
        print('DEBUG: Languages obtained: ${languages.length} languages');
        print('DEBUG: Languages data: $languages');

        setState(() {
          _landmarks = landmarks;
          _languages = languages;
        });
      } catch (e) {
        print('DEBUG: API call failed: $e');
        print('DEBUG: Error details: ${e.toString()}');
        setState(() {
          _landmarks = [];
          _languages = [];
        });
      }

      final selectedLanguageId = await _audioService.getSelectedLanguageId();
      print('DEBUG: Selected language ID: $selectedLanguageId');

      setState(() {
        _currentPosition = position;
        _selectedLanguageId = selectedLanguageId;
        if (position != null) {
          _mapCenter = LatLng(position.latitude, position.longitude);
        }
        _isLoading = false;
      });

      // Check for nearby landmarks
      await _checkLandmarkProximity();

      // Don't move map or start tracking until map is ready
      // This will be handled in _onMapReady callback
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _getMockLandmarks() {
    return [
      {
        'id': 1,
        'name': '別府タワー',
        'name_en': 'Beppu Tower',
        'latitude': 33.2382,
        'longitude': 131.6126,
        'radius_meters': 100,
      },
      {
        'id': 2,
        'name': '別府駅',
        'name_en': 'Beppu Station',
        'latitude': 33.2840,
        'longitude': 131.4896,
        'radius_meters': 150,
      },
    ];
  }

  List<Map<String, dynamic>> _getMockLanguages() {
    return [
      {'id': 1, 'code': 'ja_JP', 'name_ja': '日本語', 'name_local': '日本語'},
      {'id': 2, 'code': 'en_US', 'name_ja': '英語', 'name_local': 'English'},
    ];
  }

  Future<void> _checkLandmarkProximity() async {
    if (_currentPosition == null) {
      _status = 'Location not available';
      if (!_isPlaying) {
        setState(() {});
      }
      return;
    }

    try {
      // Use LandmarkService to get nearby landmarks
      final nearbyLandmarks = await _landmarkService.getNearbyLandmarks(
        _currentPosition!,
      );

      // Update state variables but only call setState if audio is not playing
      _currentLandmark = nearbyLandmarks.isNotEmpty
          ? nearbyLandmarks.first
          : null;

      _status = nearbyLandmarks.isNotEmpty
          ? 'Near: ${nearbyLandmarks.first['name']} (within ${nearbyLandmarks.first['radius_meters']}m radius)'
          : 'No landmarks nearby';

      if (!_isPlaying) {
        setState(() {});
      }
    } catch (e) {
      _status = 'Location error: $e';
      if (!_isPlaying) {
        setState(() {});
      }
    }
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final position = await _locationService.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        if (position != null) {
          _mapCenter = LatLng(position.latitude, position.longitude);
          // Only move map if audio is not playing
          if (!_isPlaying && _mapReady) {
            _mapController.move(_mapCenter, 15.0);
          }
        }
        _isLoading = false;
      });
      await _checkLandmarkProximity();

      // Restart auto tracking if it was active
      if (_locationService.isAutoTrackingActive) {
        await _startAutoLocationTracking();
      }
    } catch (e) {
      setState(() {
        _status = 'Error refreshing location: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _playAudio() async {
    if (_currentLandmark == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No landmark nearby to play audio'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isPlaying = true;
    });

    try {
      final landmarkId = _currentLandmark!['id'] as int;

      print('=== LOCATION GUIDE AUDIO PLAYBACK ===');
      print('Current landmark: ${_currentLandmark!['name']} (ID: $landmarkId)');
      print('Selected language ID: $_selectedLanguageId');
      print('Calling playLandmarkAudio...');

      // Try to play landmark-specific audio
      final success = await _audioService.playLandmarkAudio(landmarkId);

      print('Audio playback result: ${success ? "SUCCESS (server audio)" : "FALLBACK (default audio)"}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Playing audio for ${_currentLandmark!['name']}'
                : 'Playing default audio - no specific audio available'),
            backgroundColor: success ? Colors.green : Colors.orange,
          ),
        );
      }

      // Monitor audio completion
      _monitorAudioCompletion();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _isPlaying = false;
      });
    }
  }

  void _monitorAudioCompletion() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_audioService.isPlaying) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
        }
      }
    });
  }

  Future<void> _stopAudio() async {
    await _audioService.stopAudio();
    setState(() {
      _isPlaying = false;
    });
  }

  String _getPlayButtonText() {
    final languageCode = _languages
        .firstWhere((lang) => lang['id'] == _selectedLanguageId,
            orElse: () => {'code': 'en_US'})['code']
        .toString();

    return _translationService.getPlayButtonText(
      _translationService.extractLanguageCode(languageCode),
      _isPlaying,
    );
  }

  void _navigateToSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );

    // Refresh language settings after returning from settings
    final selectedLanguageId = await _audioService.getSelectedLanguageId();
    if (mounted && _selectedLanguageId != selectedLanguageId) {
      setState(() {
        _selectedLanguageId = selectedLanguageId;
      });
    }
  }

  void _navigateToDebug() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DebugScreen()),
    );
  }

  void _onMapReady() {
    setState(() {
      _mapReady = true;
    });

    // Move map to current location if available
    if (_currentPosition != null) {
      _mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        15.0,
      );
    }

    // Start automatic location tracking now that map is ready
    _startAutoLocationTracking();
  }

  Future<void> _startAutoLocationTracking() async {
    try {
      print('Starting auto location tracking...');
      await _locationService.startAutoLocationTracking();

      // Listen to automatic location updates
      final locationStream = _locationService.autoLocationStream;
      if (locationStream != null) {
        print('Location stream is available, starting to listen...');
        _locationSubscription = locationStream.listen(
          (Position position) {
            print('New position received: ${position.latitude}, ${position.longitude}');

            // Update position data but avoid setState during audio playback to prevent map redraw
            _currentPosition = position;
            _mapCenter = LatLng(position.latitude, position.longitude);

            if (!_isPlaying) {
              // Only trigger setState and map updates when audio is not playing
              setState(() {});

              // Update map to new location (smooth transition) only if map is ready
              if (_mapReady) {
                try {
                  final currentZoom = _mapController.camera.zoom;
                  _mapController.move(_mapCenter, currentZoom);
                  print('Map moved to new position');
                } catch (e) {
                  // Fallback if camera not ready yet
                  _mapController.move(_mapCenter, 15.0);
                  print('Map moved with default zoom due to error: $e');
                }
              }
            } else {
              print('Skipping map update and setState - audio is playing');
            }

            // Check for nearby landmarks with new position
            _checkLandmarkProximity();
          },
          onError: (error) {
            print('Auto location tracking error: $error');
          },
        );
      } else {
        print('Location stream is null - tracking may not be enabled');
      }
    } catch (e) {
      print('Failed to start auto location tracking: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Guide'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _navigateToDebug,
            icon: const Icon(Icons.bug_report),
            tooltip: 'Debug',
          ),
          IconButton(
            onPressed: _navigateToSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
          IconButton(
            onPressed: _refreshLocation,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Status bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: _currentLandmark != null
                        ? Colors.green[50]
                        : Colors.grey[50],
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _status,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_currentPosition != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Map
                Expanded(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _mapCenter,
                      initialZoom: 15.0,
                      minZoom: 10.0,
                      maxZoom: 18.0,
                      onMapReady: _onMapReady,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.flutter_busappall',
                      ),
                      MarkerLayer(markers: _buildMarkers()),
                    ],
                  ),
                ),

                // Control panel
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_currentLandmark != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Text(
                                _currentLandmark!['name'],
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_currentLandmark!['name_en'] != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _currentLandmark!['name_en'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _currentLandmark != null
                                  ? (_isPlaying ? _stopAudio : _playAudio)
                                  : null,
                              icon: Icon(
                                _isPlaying ? Icons.stop : Icons.play_arrow,
                              ),
                              label: Text(_getPlayButtonText()),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: _currentLandmark != null
                                    ? null
                                    : Colors.grey[300],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _refreshLocation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[100],
                              padding: const EdgeInsets.all(12),
                            ),
                            child: const Icon(Icons.my_location),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Add current position marker
    if (_currentPosition != null) {
      markers.add(
        Marker(
          width: 30.0,
          height: 30.0,
          point: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
        ),
      );
    }

    // Add landmark markers
    for (final landmark in _landmarks) {
      final isNearby = _currentLandmark != null &&
          _currentLandmark!['id'] == landmark['id'];

      markers.add(
        Marker(
          width: 40.0,
          height: 40.0,
          point: LatLng(landmark['latitude'], landmark['longitude']),
          child: Icon(
            Icons.place,
            color: isNearby ? Colors.green : Colors.red,
            size: 40,
          ),
        ),
      );
    }

    return markers;
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _locationService.stopAutoLocationTracking();
    _audioService.dispose();
    super.dispose();
  }
}