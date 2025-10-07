import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'location_settings_service.dart' as local;

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final local.LocationSettingsService _settingsService = local.LocationSettingsService();

  Timer? _locationTimer;
  StreamSubscription<Position>? _positionSubscription;
  StreamController<Position>? _locationStreamController;
  Position? _lastKnownPosition;

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<Position?> getCurrentPosition() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return null;

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      return null;
    }
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  bool isWithinRadius(
    Position userPosition,
    double landmarkLat,
    double landmarkLon,
    int radiusMeters,
  ) {
    final distance = calculateDistance(
      userPosition.latitude,
      userPosition.longitude,
      landmarkLat,
      landmarkLon,
    );
    return distance <= radiusMeters;
  }

  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  // Start automatic location tracking
  Future<void> startAutoLocationTracking() async {
    await stopAutoLocationTracking(); // Stop any existing tracking

    final settings = await _settingsService.getSettings();
    print('Location settings: $settings');
    if (!settings.autoUpdateEnabled) {
      print('Auto location tracking is disabled in settings');
      return;
    }

    _locationStreamController = StreamController<Position>.broadcast();

    // Start position stream with configurable distance filter
    print('🔍 [LocationService] Starting Geolocator stream with distanceFilter: ${settings.distanceInterval}m');
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: settings.distanceInterval,
          ),
        ).listen(
          (Position position) {
            print('📍 [LocationService] Geolocator stream received: lat=${position.latitude}, lon=${position.longitude}');
            _lastKnownPosition = position;
            _locationStreamController?.add(position);
          },
          onError: (error) {
            print('❌ [LocationService] Location stream error: $error');
          },
        );
    print('✅ [LocationService] Geolocator stream listener attached');

    // Also start a timer-based update as fallback
    _startTimerBasedUpdates(settings.timeInterval);
  }

  // Stop automatic location tracking
  Future<void> stopAutoLocationTracking() async {
    _locationTimer?.cancel();
    _locationTimer = null;

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    await _locationStreamController?.close();
    _locationStreamController = null;
  }

  // Get the stream for automatic location updates
  Stream<Position>? get autoLocationStream => _locationStreamController?.stream;

  // Check if auto tracking is active
  bool get isAutoTrackingActive =>
      _positionSubscription != null || _locationTimer != null;

  // Update location tracking settings
  Future<void> updateTrackingSettings() async {
    if (isAutoTrackingActive) {
      await startAutoLocationTracking(); // Restart with new settings
    }
  }

  void _startTimerBasedUpdates(int intervalSeconds) {
    _locationTimer?.cancel();
    print('⏰ [LocationService] Starting timer-based updates (every ${intervalSeconds}s)');
    _locationTimer = Timer.periodic(Duration(seconds: intervalSeconds), (
      timer,
    ) async {
      try {
        print('⏰ [LocationService] Timer tick - getting current position...');
        final position = await getCurrentPosition();
        if (position != null) {
          print('⏰ [LocationService] Position: lat=${position.latitude}, lon=${position.longitude}');
          // Only emit if there's a significant distance change or no previous position
          if (_lastKnownPosition == null) {
            print('⏰ [LocationService] No previous position - emitting update');
            _lastKnownPosition = position;
            _locationStreamController?.add(position);
          } else {
            final distance = calculateDistance(
              _lastKnownPosition!.latitude,
              _lastKnownPosition!.longitude,
              position.latitude,
              position.longitude,
            );
            print('⏰ [LocationService] Distance from last position: ${distance.toStringAsFixed(2)}m (threshold: 5m)');
            if (distance > 5.0) {
              print('⏰ [LocationService] Distance > 5m - emitting update');
              _lastKnownPosition = position;
              _locationStreamController?.add(position);
            } else {
              print('⏰ [LocationService] Distance <= 5m - skipping update');
            }
          }
        } else {
          print('⚠️ [LocationService] Timer tick - position is null');
        }
      } catch (e) {
        print('Timer-based location update error: $e');
      }
    });
  }

  // Cleanup resources
  void dispose() {
    stopAutoLocationTracking();
  }
}
