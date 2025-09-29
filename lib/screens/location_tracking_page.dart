import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/postgrest_service.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:math';
import 'package:collection/collection.dart';
import '../config/app_config.dart';

class LocationTrackingPage extends StatefulWidget {
  const LocationTrackingPage({super.key});

  @override
  State<LocationTrackingPage> createState() => _LocationTrackingPageState();
}

class _LocationTrackingPageState extends State<LocationTrackingPage> {
  String name = '';
  double? latitude;
  double? longitude;
  String message = '';
  String nearestName = '';
  double nearestDistance = 0;
  int interval = 10; // 秒（初期値）
  int distanceFilter = 10; // メートル（初期値）

  bool _isPostgrestInitialized = false;
  bool _isInitializing = true;
  bool _hasError = false;
  
  // カリフォルニア側の基準点（City Run の最初あたり）
  final double sourceLat = 37.330248;
  final double sourceLon = -122.02724276;

  // 日本側の基準点（大分あたり）
  final double targetLat = 33.32804474487834;
  final double targetLon = 131.47903040889947;

  @override
  void initState() {
    super.initState();
    debugPrint('LocationTrackingPage: initState() called');
    _initializePostgrest();
  }

  Future<void> _initializePostgrest() async {
    debugPrint('LocationTrackingPage: _initializePostgrest() started');
    try {
      setState(() {
        _isInitializing = true;
        _hasError = false;
      });

      // Initialize PostgREST service
      debugPrint('LocationTrackingPage: Initializing PostgREST...');
      await PostgrestService.initialize();
      
      // Test connection
      final isConnected = await PostgrestService.testConnection();
      if (!isConnected) {
        throw Exception('Failed to connect to PostgREST server');
      }
      
      setState(() {
        _isPostgrestInitialized = true;
      });
      debugPrint('LocationTrackingPage: PostgREST initialized successfully');
      
      debugPrint('LocationTrackingPage: Starting initializeData()...');
      await initializeData();
      debugPrint('LocationTrackingPage: initializeData() completed');
      
      debugPrint('LocationTrackingPage: Starting updateLocationTracking()...');
      await _setupLocationTracking(); // 適切にawaitする
      debugPrint('LocationTrackingPage: updateLocationTracking() completed');
      
      setState(() {
        _isInitializing = false;
      });
      
    } catch (e) {
      debugPrint('LocationTrackingPage: PostgREST initialization error: $e');
      setState(() {
        _isInitializing = false;
        _hasError = true;
        message = 'Initialization error: $e';
      });
    }
  }

  double haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000; // 地球の半径[m]
    final dLat = (lat2 - lat1) * (3.1415926535 / 180);
    final dLon = (lon2 - lon1) * (3.1415926535 / 180);
    final a = 
      (sin(dLat / 2) * sin(dLat / 2)) +
      cos(lat1 * (3.1415926535 / 180)) *
      cos(lat2 * (3.1415926535 / 180)) *
      sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  Future<void> initializeData() async {
    debugPrint('LocationTrackingPage: initializeData() method started');
    try {
      // 端末名を取得
      debugPrint('LocationTrackingPage: Getting device info...');
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        name = androidInfo.model;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        name = iosInfo.utsname.machine;
      } else {
        name = '未対応デバイス';
      }

      debugPrint('LocationTrackingPage: 端末名: $name');

      // 位置情報を取得
      debugPrint('LocationTrackingPage: Getting location...');
      final location = Location();

      // パーミッション確認
      debugPrint('LocationTrackingPage: Checking location permission...');
      var hasPermission = await location.hasPermission();
      debugPrint('LocationTrackingPage: Location permission status: $hasPermission');
      
      if (hasPermission == PermissionStatus.denied) {
        debugPrint('LocationTrackingPage: Requesting location permission...');
        hasPermission = await location.requestPermission();
        debugPrint('LocationTrackingPage: Permission request result: $hasPermission');
        if (hasPermission != PermissionStatus.granted) {
          debugPrint('LocationTrackingPage: Location permission denied');
          setState(() {
            message = '位置情報の許可が得られませんでした';
          });
          return;
        }
      }

      debugPrint('LocationTrackingPage: Getting current location...');
      
      // 位置情報サービスが有効かチェック
      bool serviceEnabled = await location.serviceEnabled();
      debugPrint('LocationTrackingPage: Location service enabled: $serviceEnabled');
      
      if (!serviceEnabled) {
        debugPrint('LocationTrackingPage: Requesting to enable location service...');
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          debugPrint('LocationTrackingPage: Location service not enabled');
          setState(() {
            message = '位置情報サービスが無効です';
          });
          return;
        }
      }
      
      // タイムアウト付きで位置情報取得
      final locData = await location.getLocation().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('LocationTrackingPage: Location timeout');
          throw Exception('位置情報取得がタイムアウトしました');
        },
      );
      
      final rawLat = locData.latitude ?? 0;
      final rawLon = locData.longitude ?? 0;
      debugPrint('LocationTrackingPage: Raw location - lat: $rawLat, lon: $rawLon');

      final corrected = correctToJapan(rawLat, rawLon);
      debugPrint('LocationTrackingPage: Corrected location - lat: ${corrected['latitude']}, lon: ${corrected['longitude']}');

      setState(() {
        latitude = corrected['latitude'];
        longitude = corrected['longitude'];
        message = '補正済み：緯度: ${latitude!.toStringAsFixed(6)}, 経度: ${longitude!.toStringAsFixed(6)}';
      });

      debugPrint('LocationTrackingPage: 取得した緯度: $latitude, 経度: $longitude');
    } catch (e) {
      debugPrint('LocationTrackingPage: データ初期化エラー: $e');
      setState(() {
        message = 'データ初期化エラー: $e';
      });
    }
  }

  /// City Run の位置を日本に補正する
  Map<String, double> correctToJapan(double rawLat, double rawLon) {
    final latOffset = rawLat - sourceLat;
    final lonOffset = rawLon - sourceLon;

    final correctedLat = targetLat + latOffset;
    final correctedLon = targetLon + lonOffset;

    return {
      'latitude': correctedLat,
      'longitude': correctedLon,
    };
  }

  Future<void> findMatchedPlace(double currentLat, double currentLon) async {
    try {
      final amenityId = 0; // 適宜変更
      final religionId = 0; // 適宜変更

      final url = Uri.parse('${AppConfig.postgrestUrl}/rpc/find_nearest_place');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_lat': currentLat,
          'user_lon': currentLon,
          'amenity': amenityId,
          'religion': religionId,
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        if (result is List && result.isNotEmpty) {
          final data = result[0];
          setState(() {
            nearestName = data['nam'] ?? '名称不明';
            nearestDistance = data['distance'] ?? 0;
          });
        } else {
          setState(() {
            nearestName = '該当なし';
            nearestDistance = 0;
          });
        }
      } else {
        debugPrint('HTTPエラー: ${response.statusCode} ${response.reasonPhrase}');
        setState(() {
          nearestName = '検索失敗';
          nearestDistance = 0;
        });
      }
    } catch (e) {
      debugPrint('RPC呼び出しエラー: $e');
      setState(() {
        nearestName = 'RPC呼び出しエラー';
        nearestDistance = 0;
      });
    }
  }

  Future<void> _setupLocationTracking() async {
    debugPrint('LocationTrackingPage: _setupLocationTracking() method started');
    final location = Location();

    await location.changeSettings(
      interval: interval * 1000,
      distanceFilter: distanceFilter.toDouble(),
    );
    debugPrint('LocationTrackingPage: Location settings updated');

    location.onLocationChanged.listen((locData) async {
      debugPrint('LocationTrackingPage: Location changed event received');
      final rawLat = locData.latitude ?? 0;
      final rawLon = locData.longitude ?? 0;
      final corrected = correctToJapan(rawLat, rawLon);

      setState(() {
        latitude = corrected['latitude'];
        longitude = corrected['longitude'];
        message = '補正済み：緯度: ${latitude!.toStringAsFixed(6)}, 経度: ${longitude!.toStringAsFixed(6)}';
      });

      await findMatchedPlace(latitude!, longitude!);
    });
    debugPrint('LocationTrackingPage: Location tracking listener setup completed');
  }

  void updateLocationTracking() async {
    // 後方互換性のため、元のメソッド名も残す
    await _setupLocationTracking();
  }

  Future<void> saveData() async {
    if (latitude == null || longitude == null) {
      setState(() {
        message = '位置情報が取得されていません';
      });
      return;
    }
    
    try {
      await initializeDateFormatting('ja_JP');
      final deviceId = await getUniqueDeviceId();
      final now = DateTime.now();
      final nowUtc = now.toUtc();
      final formatted = DateFormat('yyyy/MM/dd (E) HH:mm:ss', 'ja_JP').format(now);
      debugPrint('表示用日時: $formatted');
      
      final url = Uri.parse('${AppConfig.postgrestUrl}/test_tbl?on_conflict=token');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates',
        },
        body: jsonEncode({
          'nam': name,
          'ido': latitude,
          'keido': longitude,
          'token': deviceId,
          'created_at': nowUtc.toIso8601String(),
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          message = '保存成功';
        });
      } else {
        setState(() {
          message = '''保存失敗:
ステータス: ${response.statusCode}
理由: ${response.reasonPhrase}
本文: ${response.body.isNotEmpty ? response.body : '(本文なし)'}''';
        });
      }
    } catch (e) {
      setState(() {
        message = '保存失敗: $e';
      });
    }
  }

  Future<String> getUniqueDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown_ios';
    } else {
      return 'unsupported_platform';
    }
  }

  Future<void> updateLocation() async {
    final location = Location();
    await location.changeSettings(
      interval: 10000,
      distanceFilter: 0,
    );

    final locData = await location.getLocation();
    final double lat = locData.latitude ?? 0;
    final double lon = locData.longitude ?? 0;

    final corrected = correctToJapan(lat, lon);

    setState(() {
      latitude = corrected['latitude'];
      longitude = corrected['longitude'];
      message = '補正済み：緯度: ${latitude!.toStringAsFixed(6)}, 経度: ${longitude!.toStringAsFixed(6)}';
    });

    await findMatchedPlace(corrected['latitude']!, corrected['longitude']!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('位置情報追跡'),
        actions: [
          if (!_isInitializing)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LocationSettingsPage(
                      initialInterval: interval,
                      initialDistance: distanceFilter,
                      onSettingsChanged: (newInterval, newDistance) {
                        setState(() {
                          interval = newInterval;
                          distanceFilter = newDistance;
                        });
                        updateLocationTracking();
                      },
                    ),
                  ),
                );
              },
            )
        ],
      ),
      body: _isInitializing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('初期化中...'),
                  SizedBox(height: 8),
                  Text('位置情報とPostgRESTを設定しています'),
                ],
              ),
            )
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text('初期化エラー'),
                      const SizedBox(height: 8),
                      Text(message),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          _initializePostgrest();
                        },
                        child: const Text('再試行'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text('名前: $name'),
                      Text('緯度: ${latitude?.toStringAsFixed(6) ?? "取得中..."}'),
                      Text('経度: ${longitude?.toStringAsFixed(6) ?? "取得中..."}'),
                      const SizedBox(height: 10),
                      Text('最寄りの場所: $nearestName'),
                      Text('距離: ${nearestDistance.toStringAsFixed(1)} m'),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: latitude != null && longitude != null ? saveData : null,
                        child: const Text('PostgRESTに保存'),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: updateLocation,
                        child: const Text('位置情報を再取得'),
                      ),
                      const SizedBox(height: 20),
                      Text(message),
                    ],
                  ),
                ),
    );
  }
}

class LocationSettingsPage extends StatefulWidget {
  final int initialInterval;
  final int initialDistance;
  final Function(int, int) onSettingsChanged;

  const LocationSettingsPage({
    super.key,
    required this.initialInterval,
    required this.initialDistance,
    required this.onSettingsChanged,
  });

  @override
  State<LocationSettingsPage> createState() => _LocationSettingsPageState();
}

class _LocationSettingsPageState extends State<LocationSettingsPage> {
  late int interval;
  late int distance;

  @override
  void initState() {
    super.initState();
    interval = widget.initialInterval;
    distance = widget.initialDistance;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('位置情報設定')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('検索間隔（秒）: $interval'),
            Slider(
              value: interval.toDouble(),
              min: 1,
              max: 60,
              divisions: 59,
              label: '$interval秒',
              onChanged: (value) => setState(() {
                interval = value.toInt();
              }),
            ),
            const SizedBox(height: 20),
            Text('移動距離（メートル）: $distance'),
            Slider(
              value: distance.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              label: '$distance m',
              onChanged: (value) => setState(() {
                distance = value.toInt();
              }),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                widget.onSettingsChanged(interval, distance);
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LanguageSettingPage()),
                );
              },
              child: const Text('言語設定'),
            )
          ],
        ),
      ),
    );
  }
}

class Lang {
  final int id;
  final String nam1;

  Lang({required this.id, required this.nam1});

  factory Lang.fromMap(Map<String, dynamic> map) {
    return Lang(
      id: map['id'],
      nam1: map['nam1'],
    );
  }
}

class LanguageSettingPage extends StatefulWidget {
  const LanguageSettingPage({super.key});

  @override
  State<LanguageSettingPage> createState() => _LanguageSettingPageState();
}

class _LanguageSettingPageState extends State<LanguageSettingPage> {
  List<Lang> langList = [];
  Lang? selectedLang;
  String message = '';

  @override
  void initState() {
    super.initState();
    fetchLanguages();
  }

  Future<void> fetchLanguages() async {
    try {
      final url = Uri.parse('${AppConfig.postgrestUrl}/lang_tbl?select=id,nam1');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final langs = data.map((e) => Lang.fromMap(e)).toList();

        setState(() {
          langList = langs;
          selectedLang = langs.firstWhereOrNull((lang) => lang.id == 0)
              ?? (langs.isNotEmpty ? langs.first : null);
        });
      } else {
        debugPrint('HTTPエラー: ${response.statusCode} ${response.body}');
        setState(() {
          message = '取得失敗: ${response.statusCode}';
        });
      }
    } catch (e, stackTrace) {
      debugPrint('言語取得例外: $e');
      debugPrint('スタックトレース: $stackTrace');
      setState(() {
        message = '取得例外: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('言語設定')),
      body: langList.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: DropdownButton<Lang>(
                isExpanded: true,
                value: selectedLang,
                items: langList.map((lang) {
                  return DropdownMenuItem<Lang>(
                    value: lang,
                    child: Text(lang.nam1),
                  );
                }).toList(),
                onChanged: (Lang? newLang) {
                  setState(() {
                    selectedLang = newLang;
                  });
                },
              ),
            ),
    );
  }
}