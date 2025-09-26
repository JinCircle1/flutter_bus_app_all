import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class LocationSettingsService {
  static final LocationSettingsService _instance =
      LocationSettingsService._internal();
  factory LocationSettingsService() => _instance;
  LocationSettingsService._internal();

  // Default settings
  static const int _defaultTimeInterval = 30; // seconds
  static const int _defaultDistanceInterval = 10; // meters
  static const bool _defaultAutoUpdate = true;

  // Keys for SharedPreferences
  static const String _keyTimeInterval = 'location_time_interval';
  static const String _keyDistanceInterval = 'location_distance_interval';
  static const String _keyAutoUpdate = 'location_auto_update';

  // Get time interval in seconds
  Future<int> getTimeInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyTimeInterval) ?? _defaultTimeInterval;
  }

  // Set time interval in seconds
  Future<void> setTimeInterval(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTimeInterval, seconds);
  }

  // Get distance interval in meters
  Future<int> getDistanceInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDistanceInterval) ?? _defaultDistanceInterval;
  }

  // Set distance interval in meters
  Future<void> setDistanceInterval(int meters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDistanceInterval, meters);
  }

  // Get auto update enabled state
  Future<bool> getAutoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoUpdate) ?? _defaultAutoUpdate;
  }

  // Set auto update enabled state
  Future<void> setAutoUpdateEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoUpdate, enabled);
  }

  // Get all settings at once
  Future<LocationUpdateSettings> getSettings() async {
    final timeInterval = await getTimeInterval();
    final distanceInterval = await getDistanceInterval();
    final autoUpdateEnabled = await getAutoUpdateEnabled();

    return LocationUpdateSettings(
      timeInterval: timeInterval,
      distanceInterval: distanceInterval,
      autoUpdateEnabled: autoUpdateEnabled,
    );
  }

  // Save all settings at once
  Future<void> saveSettings(LocationUpdateSettings settings) async {
    await Future.wait([
      setTimeInterval(settings.timeInterval),
      setDistanceInterval(settings.distanceInterval),
      setAutoUpdateEnabled(settings.autoUpdateEnabled),
    ]);
  }
}

class LocationUpdateSettings {
  final int timeInterval; // seconds
  final int distanceInterval; // meters
  final bool autoUpdateEnabled;

  LocationUpdateSettings({
    required this.timeInterval,
    required this.distanceInterval,
    required this.autoUpdateEnabled,
  });

  LocationUpdateSettings copyWith({
    int? timeInterval,
    int? distanceInterval,
    bool? autoUpdateEnabled,
  }) {
    return LocationUpdateSettings(
      timeInterval: timeInterval ?? this.timeInterval,
      distanceInterval: distanceInterval ?? this.distanceInterval,
      autoUpdateEnabled: autoUpdateEnabled ?? this.autoUpdateEnabled,
    );
  }

  @override
  String toString() {
    return 'LocationUpdateSettings(timeInterval: ${timeInterval}s, distanceInterval: ${distanceInterval}m, autoUpdate: $autoUpdateEnabled)';
  }
}
