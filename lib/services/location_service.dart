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
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: settings.distanceInterval,
          ),
        ).listen(
          (Position position) {
            _lastKnownPosition = position;
            _locationStreamController?.add(position);
          },
          onError: (error) {
            print('Location stream error: $error');
          },
        );

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
    _locationTimer = Timer.periodic(Duration(seconds: intervalSeconds), (
      timer,
    ) async {
      try {
        final position = await getCurrentPosition();
        if (position != null) {
          // Only emit if there's a significant distance change or no previous position
          if (_lastKnownPosition == null ||
              calculateDistance(
                    _lastKnownPosition!.latitude,
                    _lastKnownPosition!.longitude,
                    position.latitude,
                    position.longitude,
                  ) >
                  5.0) {
            // 5 meter threshold to avoid unnecessary updates
            _lastKnownPosition = position;
            _locationStreamController?.add(position);
          }
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
