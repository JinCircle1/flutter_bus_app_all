import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart' as loc;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:janus_client/janus_client.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'bus_guide_main_page.dart';
import 'device_id_screen.dart';
import 'company_tour_config_screen.dart';
import 'location_guide_settings_screen.dart';
import '../config/app_config.dart';
import '../services/room_config_service.dart';
import '../services/text_room_service.dart';
import '../services/postgrest_service.dart';
import '../services/landmark_service.dart';
import '../services/audio_service.dart';
import '../services/location_service.dart';
import '../services/translation_service.dart';
import '../services/api_service.dart';

class UnifiedMapScreen extends StatefulWidget {
  const UnifiedMapScreen({super.key});

  @override
  State<UnifiedMapScreen> createState() => _UnifiedMapScreenState();
}

class _UnifiedMapScreenState extends State<UnifiedMapScreen> with WidgetsBindingObserver {
  final fmap.MapController _mapController = fmap.MapController();
  final TextRoomService textRoomService = TextRoomService();
  final LandmarkService _landmarkService = LandmarkService();
  final AudioService _audioService = AudioService();
  final LocationService _locationService = LocationService();
  final TranslationService _translationService = TranslationService();

  // Location Guide関連
  double? latitude;
  double? longitude;
  bool _isInitializing = true;
  bool _hasError = false;

  // 観光地点関連
  Map<String, dynamic>? _currentLandmark;
  List<Map<String, dynamic>> _landmarks = [];
  List<Map<String, dynamic>> _languages = [];
  bool _isPlaying = false;
  Timer? _proximityCheckTimer;

  // Bus Guide (WebRTC) 関連
  JanusClient? _janusClient;
  JanusSession? _session;
  JanusAudioBridgePlugin? _audioPlugin;
  bool _isConnected = false;
  bool _isJoined = false;
  int _selectedLanguageId = 1;
  String? currentDeviceId;

  // Display settings
  bool _showStatusPanel = false; // デフォルトは非表示

  // Debug status messages
  final List<String> _statusMessages = [];

  // Tour information
  String _tourName = ''; // ツアー名

  // カリフォルニア側の基準点（City Run の最初あたり）
  final double sourceLat = 37.330248;
  final double sourceLon = -122.02724276;

  // 日本側の基準点（大分あたり）
  final double targetLat = 33.32804474487834;
  final double targetLon = 131.47903040889947;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // アプリのライフサイクルを監視
    _addStatus('🚀 [INIT] アプリ初期化開始');
    _loadStatusPanelSetting();
    _loadTourName();
    _initializeLocation();
    _initializeLandmarks();
    // 地図が描画された後に初期位置を設定
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _forceMapRefresh();
    });
    // Bus Guide (WebRTC) 接続を初期化
    _initializeBusGuide();
    // 近接検知タイマーを開始（5秒ごと）
    _proximityCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkLandmarkProximity();
    });
    _addStatus('✅ [INIT] 初期化完了');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // アプリが再びアクティブになった時（他の画面から戻ってきた時）にツアー名を再読み込み
    if (state == AppLifecycleState.resumed) {
      print('🔄 [UnifiedMap] App resumed, reloading tour name');
      _loadTourName();
    }
  }

  @override
  void didUpdateWidget(UnifiedMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 画面が更新された時にツアー名を再読み込み
    _loadTourName();
  }

  Future<void> _loadTourName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _tourName = prefs.getString('tour_name') ?? '';
      });
    } catch (e) {
      print('❌ [INIT] ツアー名の読み込みエラー: $e');
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

  Future<void> _initializeLandmarks() async {
    try {
      print("🗺️ [UnifiedMap] 観光地点データ取得開始");
      final landmarks = await _landmarkService.refreshLandmarks();

      // 言語データも取得
      try {
        final apiService = ApiService();
        final languages = await apiService.getLanguages();
        setState(() {
          _landmarks = landmarks;
          _languages = languages;
        });
        print("✅ [UnifiedMap] 言語データ取得完了: ${languages.length}件");
      } catch (e) {
        print("⚠️ [UnifiedMap] 言語データ取得エラー: $e");
        setState(() {
          _landmarks = landmarks;
        });
      }

      print("✅ [UnifiedMap] 観光地点データ取得完了: ${landmarks.length}件");
    } catch (e) {
      print("❌ [UnifiedMap] 観光地点データ取得エラー: $e");
    }
  }

  Future<void> _checkLandmarkProximity() async {
    if (latitude == null || longitude == null) return;
    if (_isPlaying) return; // 音声再生中はチェックしない

    try {
      final position = Position(
        latitude: latitude!,
        longitude: longitude!,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      final nearbyLandmarks = await _landmarkService.getNearbyLandmarks(position);

      if (mounted) {
        final previousLandmark = _currentLandmark;
        setState(() {
          _currentLandmark = nearbyLandmarks.isNotEmpty ? nearbyLandmarks.first : null;
        });

        // 新しい観光地点に接近した場合のみステータスメッセージを追加
        if (_currentLandmark != null && previousLandmark?['id'] != _currentLandmark!['id']) {
          _addStatus('🎯 [LANDMARK] 接近: ${_currentLandmark!['name']}');
          print("🎯 [UnifiedMap] 観光地点接近: ${_currentLandmark!['name']}");
        }
      }
    } catch (e) {
      print("❌ [UnifiedMap] 近接検知エラー: $e");
    }
  }

  Future<void> _initializeBusGuide() async {
    try {
      print("🚀 [UnifiedMap] Bus Guide初期化開始");
      // TextRoom初期化
      await textRoomService.initializeClient();
      String myId = (await getDeviceId()) ?? "ID0";
      currentDeviceId = myId;
      print("📱 [UnifiedMap] デバイスID: $myId");
      await textRoomService.joinTextRoom(myId);

      // 言語設定読み込み
      await _loadSelectedLanguage();

      // 自動接続開始（待機時間を1秒に短縮）
      print("⏳ [UnifiedMap] 1秒後に自動接続を開始します...");
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && !_isConnected) {
        print("🔗 [UnifiedMap] 自動接続を実行します");
        await _connectWebRTC();
      } else {
        print("ℹ️ [UnifiedMap] 既に接続済みです (_isConnected: $_isConnected)");
      }
    } catch (e) {
      // ignore: avoid_print
      print("❌ [UnifiedMap] Bus Guide初期化エラー: $e");
    }
  }

  Future<void> _loadSelectedLanguage() async {
    final config = await RoomConfigService.getConfig();
    final prefs = await SharedPreferences.getInstance();
    final languageId = prefs.getInt('selected_language_id') ?? config.defaultLanguageId;
    setState(() {
      _selectedLanguageId = languageId;
    });
  }

  void _addStatus(String message) {
    final statusMessage =
        '[${DateTime.now().toString().substring(11, 19)}] $message';
    print(statusMessage);
    setState(() {
      _statusMessages.add(statusMessage);
      if (_statusMessages.length > 50) {
        _statusMessages.removeAt(0);
      }
    });
  }

  void _forceMapRefresh() {
    // 地図の強制リフレッシュ - 地図が完全にレンダリングされるまで待つ
    Future.delayed(const Duration(milliseconds: 300), () {
      try {
        if (latitude != null && longitude != null) {
          // 実際の位置に適切なズームレベルで移動
          _mapController.move(LatLng(latitude!, longitude!), 16.0);
          print("🗺️ [UnifiedMap] 実際の位置に地図移動: lat=$latitude, lon=$longitude");
        } else {
          // エミュレータの初期位置（大分周辺）を表示
          _mapController.move(const LatLng(33.32804, 131.47903), 15.0);
          print("🗺️ [UnifiedMap] 初期位置（大分）に地図移動");
        }
        print("🗺️ [UnifiedMap] 地図を強制リフレッシュ");
      } catch (e) {
        print("⚠️ [UnifiedMap] 地図リフレッシュエラー: $e");
        // さらに1秒後にリトライ
        Future.delayed(const Duration(seconds: 1), () {
          try {
            // エミュレータの初期位置でリトライ
            _mapController.move(const LatLng(33.32804, 131.47903), 15.0);
            print("🗺️ [UnifiedMap] 地図リフレッシュリトライ成功");
          } catch (e2) {
            print("⚠️ [UnifiedMap] 地図リフレッシュリトライエラー: $e2");
          }
        });
      }
    });
  }

  Future<void> _initializeLocation() async {
    try {
      _addStatus('🗺️ [LOCATION] 位置情報初期化開始');
      print("🗺️ [UnifiedMap] 位置情報初期化開始");
      setState(() {
        _isInitializing = true;
        _hasError = false;
      });

      await _getCurrentLocation();
      _setupLocationTracking();

      setState(() {
        _isInitializing = false;
      });
      _addStatus('✅ [LOCATION] 位置情報初期化完了');
      print("✅ [UnifiedMap] 位置情報初期化完了");

    } catch (e) {
      _addStatus('❌ [LOCATION] 初期化エラー: $e');
      print("❌ [UnifiedMap] 位置情報初期化エラー: $e");
      setState(() {
        _isInitializing = false;
        _hasError = true;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    final location = loc.Location();

    try {
      _addStatus('📍 [LOCATION] 位置情報取得開始');
      print("📍 [UnifiedMap] パーミッション確認開始");
      // パーミッション確認
      var hasPermission = await location.hasPermission();
      print("📍 [UnifiedMap] パーミッション状態: $hasPermission");

      if (hasPermission == loc.PermissionStatus.denied) {
        print("📍 [UnifiedMap] パーミッション要求中...");
        hasPermission = await location.requestPermission();
        print("📍 [UnifiedMap] パーミッション要求結果: $hasPermission");
        if (hasPermission != loc.PermissionStatus.granted) {
          throw Exception('位置情報の許可が得られませんでした: $hasPermission');
        }
      }

      print("📍 [UnifiedMap] 位置情報サービス確認開始");
      // 位置情報サービスが有効かチェック
      bool serviceEnabled = await location.serviceEnabled();
      print("📍 [UnifiedMap] 位置情報サービス状態: $serviceEnabled");

      if (!serviceEnabled) {
        print("📍 [UnifiedMap] 位置情報サービス有効化要求中...");
        serviceEnabled = await location.requestService();
        print("📍 [UnifiedMap] 位置情報サービス有効化結果: $serviceEnabled");
        if (!serviceEnabled) {
          throw Exception('位置情報サービスが無効です');
        }
      }

      print("📍 [UnifiedMap] 現在位置取得開始");
      // 現在位置取得（タイムアウト設定）
      final locData = await location.getLocation().timeout(
        Duration(seconds: 30),
      );

      final rawLat = locData.latitude ?? 0.0;
      final rawLon = locData.longitude ?? 0.0;
      print("📍 [UnifiedMap] 取得した位置: lat=$rawLat, lon=$rawLon");

      if (rawLat == 0 && rawLon == 0) {
        throw Exception('無効な位置情報を取得しました（0, 0）');
      }

      setState(() {
        latitude = rawLat;
        longitude = rawLon;
      });

      // 地図を現在位置に移動（即座に実行）
      if (latitude != null && longitude != null) {
        try {
          _mapController.move(LatLng(latitude!, longitude!), 16.0);
          print("📍 [UnifiedMap] 地図を現在位置に移動完了");
        } catch (e) {
          print("⚠️ [UnifiedMap] 地図移動エラー: $e");
          // PostFrameCallbackでリトライ
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              _mapController.move(LatLng(latitude!, longitude!), 16.0);
              print("📍 [UnifiedMap] 地図移動リトライ成功");
            } catch (e2) {
              print("⚠️ [UnifiedMap] 地図移動リトライ失敗: $e2");
            }
          });
        }
      }
    } catch (e) {
      print("❌ [UnifiedMap] 位置情報取得エラー: $e");
      rethrow;
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

  void _setupLocationTracking() async {
    try {
      print("🗺️ [UnifiedMap] 位置情報追跡開始");

      // LocationServiceを使用して自動追跡を開始
      await _locationService.startAutoLocationTracking();

      print("🔍 [UnifiedMap] autoLocationStream取得中...");
      // 位置情報更新を監視
      final locationStream = _locationService.autoLocationStream;
      print("🔍 [UnifiedMap] locationStream: ${locationStream != null ? 'available' : 'null'}");

      if (locationStream != null) {
        print("🔍 [UnifiedMap] stream listenerを設定中...");
        locationStream.listen((position) {
          _addStatus('📍 [LOCATION] 位置変更: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}');
          print("📍 [UnifiedMap] 位置変更検出: lat=${position.latitude}, lon=${position.longitude}");

          setState(() {
            latitude = position.latitude;
            longitude = position.longitude;
          });

          // 近接検知を実行
          _checkLandmarkProximity();

          // 地図を自動で追跡（音声再生中でない場合）
          if (!_isPlaying && latitude != null && longitude != null) {
            try {
              _mapController.move(LatLng(latitude!, longitude!), _mapController.camera.zoom);
              print("📍 [UnifiedMap] 地図を新しい位置に移動完了");
            } catch (e) {
              print("⚠️ [UnifiedMap] 地図追跡エラー（無視可）: $e");
            }
          }
        }, onError: (error) {
          print("❌ [UnifiedMap] 位置情報追跡エラー: $error");
        });
        print("✅ [UnifiedMap] 位置情報追跡設定完了（設定画面の値を使用）");
      } else {
        print("⚠️ [UnifiedMap] 自動追跡が設定で無効化されています");
      }
    } catch (e) {
      print("❌ [UnifiedMap] 位置情報追跡設定エラー: $e");
    }
  }

  Future<void> updateLocation() async {
    await _getCurrentLocation();
  }

  List<fmap.Marker> _buildMarkers() {
    List<fmap.Marker> markers = [];

    // 観光地点マーカー
    for (final landmark in _landmarks) {
      final isNearby = _currentLandmark != null && _currentLandmark!['id'] == landmark['id'];
      markers.add(
        fmap.Marker(
          point: LatLng(landmark['latitude'], landmark['longitude']),
          child: GestureDetector(
            onTap: () => _showLandmarkInfo(landmark),
            child: Icon(
              Icons.place,
              color: isNearby ? Colors.green : Colors.red,
              size: 40,
            ),
          ),
        ),
      );
    }

    // 現在位置マーカー（最後に追加して最上位に表示）
    if (latitude != null && longitude != null) {
      markers.add(
        fmap.Marker(
          point: LatLng(latitude!, longitude!),
          child: const Icon(
            Icons.my_location,
            color: Colors.blue,
            size: 30,
          ),
        ),
      );
    }

    return markers;
  }

  void _showLandmarkInfo(Map<String, dynamic> landmark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(landmark['name']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('緯度: ${landmark['latitude']}'),
            Text('経度: ${landmark['longitude']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _playAudio() async {
    print("🔵 [UnifiedMap] _playAudio() 関数が呼ばれました");
    if (_currentLandmark == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('近くに観光地点がありません'),
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
      final landmarkName = _currentLandmark!['name'];
      print("🎵 [UnifiedMap] 音声再生開始: $landmarkName (ID: $landmarkId)");
      print("🎵 [UnifiedMap] 選択言語ID: $_selectedLanguageId");

      final success = await _audioService.playLandmarkAudio(landmarkId);

      if (!mounted) return;

      if (success) {
        print("✅ [UnifiedMap] 音声再生成功");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('音声再生開始'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        print("⚠️ [UnifiedMap] 音声ファイルが見つかりませんでした");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('この観光地点の音声ファイルが見つかりません'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // 音声完了を監視
      _monitorAudioCompletion();
    } catch (e) {
      print("❌ [UnifiedMap] 音声再生エラー: $e");
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('音声再生エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
          print("✅ [UnifiedMap] 音声再生完了");
        }
      }
    });
  }

  Future<void> _stopAudio() async {
    await _audioService.stopAudio();
    setState(() {
      _isPlaying = false;
    });
    print("⏹️ [UnifiedMap] 音声停止");
  }

  String _getPlayButtonText() {
    // 言語IDから言語コードを取得
    String languageCode = 'ja'; // デフォルトは日本語

    for (final language in _languages) {
      if (language['id'] == _selectedLanguageId) {
        final code = language['code']?.toString() ?? 'ja';
        languageCode = _translationService.extractLanguageCode(code);
        break;
      }
    }

    return _translationService.getPlayButtonText(languageCode, _isPlaying);
  }

  // WebRTC接続
  Future<void> _connectWebRTC() async {
    try {
      _addStatus('🔗 [WEBRTC] 接続開始...');
      // 権限確認
      final micStatus = await perm.Permission.microphone.request();
      if (!micStatus.isGranted) {
        _addStatus('⚠️ [WEBRTC] マイク権限拒否');
        // ignore: avoid_print
        print("⚠️ [UnifiedMap] マイク権限が拒否されました");
        return;
      }

      _janusClient = JanusClient(
        transport: WebSocketJanusTransport(url: AppConfig.janusWebSocketUrl),
        iceServers: [
          RTCIceServer(urls: "stun:stun.l.google.com:19302"),
          RTCIceServer(
            urls: AppConfig.turnServerUrl,
            username: AppConfig.turnUsername,
            credential: AppConfig.turnCredential,
          ),
        ],
        isUnifiedPlan: true,
        withCredentials: false,
      );

      _session = await _janusClient!.createSession();
      _audioPlugin = await _session!.attach<JanusAudioBridgePlugin>();

      await _audioPlugin!.initializeMediaDevices(
        mediaConstraints: {
          'audio': {
            'echoCancellation': false,
            'noiseSuppression': false,
            'autoGainControl': false,
            'volume': 0.0,
          },
          'video': false,
        },
      );

      // ローカル音声トラック無効化
      final localStreams = _audioPlugin!.peerConnection!.getLocalStreams();
      for (final stream in localStreams) {
        if (stream != null) {
          final audioTracks = stream.getAudioTracks();
          for (final track in audioTracks) {
            track.enabled = false;
          }
        }
      }

      setState(() {
        _isConnected = true;
      });

      await Future.delayed(const Duration(milliseconds: 500));
      await _joinRoom();

      _addStatus('✅ [WEBRTC] 接続成功');
      // ignore: avoid_print
      print("✅ [UnifiedMap] WebRTC接続成功");
    } catch (e) {
      _addStatus('❌ [WEBRTC] 接続エラー: $e');
      // ignore: avoid_print
      print("❌ [UnifiedMap] WebRTC接続エラー: $e");
      setState(() {
        _isConnected = false;
      });
    }
  }

  // WebRTC切断
  Future<void> _disconnectWebRTC() async {
    try {
      _addStatus('🔌 [WEBRTC] 切断中...');
      if (_audioPlugin != null) {
        await _audioPlugin!.hangup();
        _audioPlugin = null;
      }
      if (_session != null) {
        _session = null;
      }
      if (_janusClient != null) {
        _janusClient = null;
      }
      setState(() {
        _isConnected = false;
        _isJoined = false;
      });
      _addStatus('✅ [WEBRTC] 切断完了');
      // ignore: avoid_print
      print("✅ [UnifiedMap] WebRTC切断完了");
    } catch (e) {
      _addStatus('❌ [WEBRTC] 切断エラー: $e');
      // ignore: avoid_print
      print("❌ [UnifiedMap] WebRTC切断エラー: $e");
    }
  }

  // ルーム参加
  Future<void> _joinRoom() async {
    try {
      // ツアーデータから音声ルーム番号を取得
      final companyId = await AppConfig.getCompanyId();
      final companyTourId = await AppConfig.getCompanyTourId();

      final tourData = await PostgrestService.getTourData(companyId, companyTourId);
      if (tourData == null) {
        // ignore: avoid_print
        print("❌ [UnifiedMap] ツアーデータ取得失敗");
        return;
      }

      final tourId = tourData['id'] as int;
      final languageId = _selectedLanguageId;

      final roomNumber = await PostgrestService.getAudioRoomId(tourId, languageId);
      if (roomNumber == null) {
        // ignore: avoid_print
        print("❌ [UnifiedMap] 音声ルーム番号取得失敗");
        return;
      }

      await _audioPlugin!.joinRoom(roomNumber, display: currentDeviceId ?? "User");
      setState(() {
        _isJoined = true;
      });
      // ignore: avoid_print
      print("✅ [UnifiedMap] ルーム参加成功: room=$roomNumber");
    } catch (e) {
      // ignore: avoid_print
      print("❌ [UnifiedMap] ルーム参加エラー: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // オブザーバーを解除
    _proximityCheckTimer?.cancel();
    _disconnectWebRTC();
    _locationService.stopAutoLocationTracking();
    textRoomService.dispose();
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('案内地図'),
            if (_tourName.isNotEmpty) ...[
              const SizedBox(width: 8),
              const Text('・', style: TextStyle(fontWeight: FontWeight.normal)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tourName,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                ),
              ),
            ],
          ],
        ),
        toolbarHeight: _tourName.isNotEmpty ? 80 : 56,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Location Guide 設定ボタン
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LocationGuideSettingsScreen(),
                ),
              );
              // 設定変更後に再初期化
              await _initializeLandmarks();
              // 位置情報追跡設定を再適用
              await _locationService.updateTrackingSettings();
              // 音声言語設定を再読み込み
              final newLanguageId = await _audioService.getSelectedLanguageId();
              if (mounted && newLanguageId != _selectedLanguageId) {
                setState(() {
                  _selectedLanguageId = newLanguageId;
                });
                print("🔄 [UnifiedMap] 言語設定変更: $_selectedLanguageId");
              }
              // ステータスパネル表示設定を再読み込み
              await _loadStatusPanelSetting();
            },
            tooltip: 'Location Guide設定',
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('位置情報を取得中...'),
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
                      const Text('位置情報の取得に失敗しました'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          _initializeLocation();
                        },
                        child: const Text('再試行'),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    // 地図エリア (全画面表示)
                    fmap.FlutterMap(
                      mapController: _mapController,
                      options: fmap.MapOptions(
                        initialCenter: const LatLng(33.32804, 131.47903), // エミュレータの初期位置（大分）
                        initialZoom: 16.0, // ズームレベルを上げて詳細表示
                        maxZoom: 18.0,
                        minZoom: 5.0,
                        backgroundColor: Colors.grey.shade300, // 背景色を設定
                        interactionOptions: const fmap.InteractionOptions(
                          enableMultiFingerGestureRace: true,
                          flags: fmap.InteractiveFlag.all,
                        ),
                      ),
                      children: [
                        fmap.TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.flutter_busappall',
                          retinaMode: false, // レティナモードを無効化
                          tileSize: 256, // タイルサイズを明示的に指定
                          maxZoom: 18,
                          keepBuffer: 5, // タイルのバッファを増やして滑らかに
                          panBuffer: 2, // パン時のバッファ
                          maxNativeZoom: 18, // ネイティブズームレベルを明示
                          tileDisplay: const fmap.TileDisplay.fadeIn(
                            duration: Duration(milliseconds: 200), // フェードイン効果を追加
                          ),
                        ),
                        fmap.MarkerLayer(
                          markers: _buildMarkers(),
                        ),
                      ],
                    ),
                    // コントロールパネル（接続・切断ボタンなど、常に表示）
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildMainControlPanel(),
                    ),
                    // デバッグステータスパネル（設定で表示/非表示切り替え可能、コントロールパネルの上）
                    if (_showStatusPanel)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 130, // コントロールパネルの上に配置
                        child: _buildDebugStatusPanel(),
                      ),
                    // 観光地点情報と再生ボタン（画面上部に配置）
                    if (_currentLandmark != null)
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 16,
                        child: _buildLandmarkInfoPanel(),
                      ),
                    // ズームコントロールボタン（観光地点情報とガイド再生ボタンの上に配置）
                    Positioned(
                      right: 16,
                      top: 80,
                      child: _buildZoomControls(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildDebugStatusPanel() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300), // デバッグステータスパネルの高さ
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ステータスパネルヘッダー
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              children: [
                Icon(Icons.bug_report, size: 16, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text(
                  'Debug Status',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ステータスメッセージリスト
          Expanded(
            child: ListView.builder(
              reverse: false, // 最新が下
              itemCount: _statusMessages.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.0),
                  child: Text(
                    _statusMessages[index],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Colors.greenAccent,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ズームインボタン
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.add, size: 24),
            onPressed: () {
              final currentZoom = _mapController.camera.zoom;
              _mapController.move(
                _mapController.camera.center,
                (currentZoom + 1).clamp(5.0, 18.0),
              );
            },
            tooltip: 'ズームイン',
          ),
        ),
        const SizedBox(height: 8),
        // ズームアウトボタン
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.remove, size: 24),
            onPressed: () {
              final currentZoom = _mapController.camera.zoom;
              _mapController.move(
                _mapController.camera.center,
                (currentZoom - 1).clamp(5.0, 18.0),
              );
            },
            tooltip: 'ズームアウト',
          ),
        ),
        const SizedBox(height: 8),
        // 現在位置に戻るボタン
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.my_location, size: 24, color: Colors.blue),
            onPressed: () {
              if (latitude != null && longitude != null) {
                _mapController.move(
                  LatLng(latitude!, longitude!),
                  16.0,
                );
              }
            },
            tooltip: '現在位置',
          ),
        ),
      ],
    );
  }

  Widget _buildLandmarkInfoPanel() {
    // 観光地点情報と再生ボタン（画面上部に表示）
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 観光地点情報表示
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.green[100],
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            _currentLandmark!['name'],
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        // 音声再生ボタン
        ElevatedButton.icon(
          onPressed: () {
            print("🔵🔵🔵 [UnifiedMap] ボタンがタップされました！");
            if (_isPlaying) {
              _stopAudio();
            } else {
              _playAudio();
            }
          },
          icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
          label: Text(_getPlayButtonText()),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isPlaying ? Colors.red : Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            shadowColor: Colors.black.withValues(alpha: 0.3),
            elevation: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildMainControlPanel() {
    // メインコントロールパネル（接続・切断ボタンなど）
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      padding: const EdgeInsets.all(12.0),
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // 位置情報表示
          if (latitude != null && longitude != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.gps_fixed, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // Bus Guide & Location Guide ボタン
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeviceIdScreen(
                          onIdChanged: () async {},
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person, size: 16),
                  label: const Text('ユーザー設定', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CompanyTourConfigScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tour, size: 16),
                  label: const Text('ツアー設定', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (_isConnected) {
                      await _disconnectWebRTC();
                    } else {
                      await _connectWebRTC();
                    }
                  },
                  icon: Icon(
                    _isConnected ? Icons.link_off : Icons.link,
                    size: 16,
                  ),
                  label: Text(
                    _isConnected ? '切断' : '接続',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}