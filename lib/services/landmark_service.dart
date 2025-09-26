import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'location_service.dart';

class LandmarkService {
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();

  // Cache for landmarks to improve performance
  List<Map<String, dynamic>>? _cachedLandmarks;
  DateTime? _lastFetchTime;
  static const Duration _cacheExpiry = Duration(minutes: 10);

  static final LandmarkService _instance = LandmarkService._internal();
  factory LandmarkService() => _instance;
  LandmarkService._internal();

  Future<List<Map<String, dynamic>>> getNearbyLandmarks(
    Position userPosition,
  ) async {
    try {
      final landmarks = await _getLandmarksWithCache();
      final nearbyLandmarks = <Map<String, dynamic>>[];

      for (final landmark in landmarks) {
        final landmarkLat = landmark['latitude'] as double;
        final landmarkLon = landmark['longitude'] as double;
        final radiusMeters = landmark['radius_meters'] as int;

        if (_locationService.isWithinRadius(
          userPosition,
          landmarkLat,
          landmarkLon,
          radiusMeters,
        )) {
          nearbyLandmarks.add(landmark);
        }
      }

      return nearbyLandmarks;
    } catch (e) {
      throw Exception('Failed to get nearby landmarks: $e');
    }
  }

  /// Get landmarks with caching support
  Future<List<Map<String, dynamic>>> _getLandmarksWithCache() async {
    final now = DateTime.now();

    // Check if cache is valid
    if (_cachedLandmarks != null &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!) < _cacheExpiry) {
      print('DEBUG: Using cached landmarks (${_cachedLandmarks!.length} landmarks)');
      return _cachedLandmarks!;
    }

    // Fetch fresh data
    print('DEBUG: Fetching fresh landmark data...');
    _cachedLandmarks = await _apiService.getLandmarks();
    _lastFetchTime = now;

    print('DEBUG: Cached ${_cachedLandmarks!.length} landmarks');
    return _cachedLandmarks!;
  }

  /// Force refresh landmarks data (clears cache)
  Future<List<Map<String, dynamic>>> refreshLandmarks() async {
    print('DEBUG: Force refreshing landmarks...');
    _cachedLandmarks = null;
    _lastFetchTime = null;
    return await _getLandmarksWithCache();
  }

  /// Clear landmarks cache
  void clearCache() {
    print('DEBUG: Clearing landmarks cache');
    _cachedLandmarks = null;
    _lastFetchTime = null;
  }

  Future<Map<String, dynamic>?> checkLandmarkProximity() async {
    final position = await _locationService.getCurrentPosition();
    if (position == null) {
      throw Exception('Unable to get current location');
    }

    final nearbyLandmarks = await getNearbyLandmarks(position);
    return nearbyLandmarks.isNotEmpty ? nearbyLandmarks.first : null;
  }

  Stream<Map<String, dynamic>?> watchLandmarkProximity() async* {
    await for (final position in _locationService.getPositionStream()) {
      try {
        final nearbyLandmarks = await getNearbyLandmarks(position);
        yield nearbyLandmarks.isNotEmpty ? nearbyLandmarks.first : null;
      } catch (e) {
        yield null;
      }
    }
  }
}
