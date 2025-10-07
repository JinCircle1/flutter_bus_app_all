import 'dart:math' show cos, sin, atan2, sqrt, pi;
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'location_service.dart';
import 'translation_service.dart';

class LandmarkService {
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();
  final TranslationService _translationService = TranslationService();

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

  /// 2点間の距離を計算（メートル）
  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // 地球の半径（メートル）
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// 方位角を計算（度数法、0-360度）
  double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLon = _toRadians(lon2 - lon1);
    final lat1Rad = _toRadians(lat1);
    final lat2Rad = _toRadians(lat2);

    final y = sin(dLon) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLon);

    final bearingRad = atan2(y, x);
    final bearingDeg = _toDegrees(bearingRad);

    return (bearingDeg + 360) % 360; // 0-360度の範囲に正規化
  }

  /// 方位角から方向を取得（8方位）
  String getDirectionFromBearing(double bearing, [String languageCode = 'ja']) {
    const directionKeys = [
      'direction_north',
      'direction_northeast',
      'direction_east',
      'direction_southeast',
      'direction_south',
      'direction_southwest',
      'direction_west',
      'direction_northwest'
    ];
    final index = ((bearing + 22.5) / 45).floor() % 8;
    return _translationService.getTranslation(languageCode, directionKeys[index]);
  }

  double _toRadians(double degrees) {
    return degrees * pi / 180;
  }

  double _toDegrees(double radians) {
    return radians * 180 / pi;
  }
}
