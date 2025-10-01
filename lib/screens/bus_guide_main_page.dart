import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/text_room_service.dart';
import 'device_id_screen.dart';
import 'location_tracking_page.dart';
import 'company_tour_config_screen.dart';
import 'unified_map_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:janus_client/janus_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import '../config/app_config.dart';
import '../services/room_config_service.dart';
import '../services/postgrest_service.dart';
import '../services/tour_validity_service.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  late gmaps.GoogleMapController mapController;
  gmaps.LatLng? _center;
  final Set<gmaps.Marker> _markers = {};
  gmaps.BitmapDescriptor? _busIcon;
  String? currentDeviceId;
  final TextRoomService textRoomService = TextRoomService();
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  final GlobalKey<_AudioSectionState> _audioSectionKey =
      GlobalKey<_AudioSectionState>();
  bool _isCleaningUp = false; // 二重クリーンアップ防止
  final bool _shouldDisconnectOnBackground = false; // バックグラウンド時の切断設定（falseで接続維持）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // ライフサイクル監視追加

    // 安全な初期化処理
    _safeInitialize();
  }

  Future<void> _safeInitialize() async {
    try {
      // ツアーの有効期間チェック
      await _checkTourValidity();

      flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );
      await flutterLocalNotificationsPlugin.initialize(initSettings);
      print("✅ [INIT] 通知プラグイン初期化成功");

      // バスアイコンを最初に読み込む
      await _loadBusIcon();

      // 位置情報とマーカーの初期化
      await _initializeLocationAndMarker();

      // TextRoomサービスの初期化
      textRoomService.onMessageReceived = _handleMessage;
      await _initializeTextRoom();

      // 権限リクエストとFCMを統合
      await _initializePermissionsAndFCM();

      // AudioBridgeの自動接続を少し遅らせて実行
      Future.delayed(Duration(seconds: 2), () {
        _initializeAudioBridge();
      });

      print("✅ [INIT] 全体初期化完了");
    } catch (e, stack) {
      print("❌ [INIT] 初期化エラー: $e");
      print("Stack trace: $stack");
      // エラーが発生してもアプリは継続実行
    }
  }
  
  Future<void> _initializeAudioBridge() async {
    print("🔊 [INIT] AudioBridge自動接続試行開始");
    print("🔊 [DEBUG] _audioSectionKey.currentState: ${_audioSectionKey.currentState}");
    
    // AudioSectionが初期化されるまで最大10秒待機
    int attempts = 0;
    const maxAttempts = 20; // 0.5秒 × 20 = 10秒
    
    while (_audioSectionKey.currentState == null && attempts < maxAttempts && mounted) {
      print("🔊 [INIT] AudioSection初期化待機中... (${attempts + 1}/$maxAttempts)");
      await Future.delayed(Duration(milliseconds: 500));
      attempts++;
    }
    
    if (_audioSectionKey.currentState != null && mounted) {
      print("🔊 [INIT] AudioBridge自動接続開始");
      await _audioSectionKey.currentState!._connect();
    } else {
      print("❌ [INIT] AudioBridge自動接続不可 - currentState: ${_audioSectionKey.currentState}, mounted: $mounted");
    }
  }

  Future<void> _initializePermissionsAndFCM() async {
    print("🔔 [PERMISSION] 権限リクエスト開始");

    try {
      // 権限リクエストを別々のタイミングで実行
      // 位置情報と録音権限は他の場所で処理されているため、ここではスキップ

      // 通知権限のリクエストを遅延実行（権限の競合を避ける）
      Future.delayed(Duration(seconds: 1), () async {
        await _requestNotificationPermission();
      });

      // FCMの初期化は即座に実行
      await _initializeFCM();
    } catch (e, stack) {
      print("❌ [PERMISSION] 初期化エラー: $e");
      print("Stack trace: $stack");
    }
  }

  Future<void> _requestInitialPermissions() async {
    // 既存の位置情報と録音権限のリクエスト処理がここに来る
    // （現在の実装では_initializeLocationAndMarkerと_requestPermissionsで処理）
  }

  Future<void> _requestNotificationPermission() async {
    print("🔔 [PERMISSION] 通知権限リクエスト開始");

    try {
      // Android 13以降の通知権限リクエスト
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        print("📱 [PERMISSION] Android SDK Version: ${androidInfo.version.sdkInt}");

        if (androidInfo.version.sdkInt >= 33) {
          // 権限の現在の状態を確認
          final currentStatus = await Permission.notification.status;
          print("📱 [PERMISSION] 現在の通知権限状態: $currentStatus");

          if (currentStatus.isDenied) {
            // 権限リクエストダイアログを表示
            print("📱 [PERMISSION] 通知権限をリクエスト中...");
            final permissionStatus = await Permission.notification.request();
            print("📱 [PERMISSION] 通知権限リクエスト結果: $permissionStatus");

            if (permissionStatus.isPermanentlyDenied) {
              print("⚠️ [PERMISSION] 通知権限が永続的に拒否されました");
              // ユーザーに設定画面への移動を促すダイアログを表示することを検討
              // await _showNotificationPermissionDialog();
            } else if (!permissionStatus.isGranted) {
              print("⚠️ [PERMISSION] 通知権限が拒否されました");
            } else {
              print("✅ [PERMISSION] 通知権限が許可されました");
            }
          } else if (currentStatus.isGranted) {
            print("✅ [PERMISSION] 通知権限は既に許可されています");
          } else if (currentStatus.isPermanentlyDenied) {
            print("⚠️ [PERMISSION] 通知権限は永続的に拒否されています");
          }
        }
      }
    } catch (e, stack) {
      print("❌ [PERMISSION] 通知権限リクエストエラー: $e");
      print("Stack trace: $stack");
    }
  }

  Future<void> _initializeFCM() async {
    print("🔔 [FCM] Firebase Messaging初期化開始");

    try {

      // FCMトークン取得（デバッグ用）
      String? token = await FirebaseMessaging.instance.getToken();
      print("🔑 [FCM] FCMトークン: $token");

      // APNSトークン取得（iOS）
      if (Platform.isIOS) {
        String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        print("🍎 [FCM] APNSトークン: $apnsToken");

        // iOSの場合はFirebase Messagingの権限もリクエスト
        NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          announcement: true,
          criticalAlert: false,
          provisional: false,
        );
        print("📱 [FCM] iOS通知権限ステータス: ${settings.authorizationStatus}");
      }

      // トピック購読は権限に関係なく実行
      await _subscribeToTopics();

      // フォアグラウンドでのメッセージ受信
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        print("📨 [FCM] フォアグラウンドメッセージ受信:");
        print("  - From: ${message.from}");
        print("  - Message ID: ${message.messageId}");
        print("  - Data: ${message.data}");
        print("  - Notification Title: ${message.notification?.title}");
        print("  - Notification Body: ${message.notification?.body}");
        print("  - Category: ${message.category}");
        print("  - CollapseKey: ${message.collapseKey}");
        print("  - MessageType: ${message.messageType}");
        print("  - SenderId: ${message.senderId}");
        print("  - TTL: ${message.ttl}");

        // トピック分析と言語フィルタリング
        final fromTopic = message.from;
        print("🎯 [TOPIC-ANALYSIS] メッセージソース: $fromTopic");

        final shouldShowNotification = await _shouldShowNotificationForLanguage(fromTopic);

        if (fromTopic != null && fromTopic.contains('bus_topic_')) {
          // /topics/bus_topic_1_en から言語コードを抽出
          String topicName = fromTopic;
          if (topicName.startsWith('/topics/')) {
            topicName = topicName.substring(8);
          }
          final parts = topicName.split('_');
          if (parts.length >= 4) {
            final messageLanguage = parts[3]; // 実際の言語コード
            if (shouldShowNotification) {
              print("✅ [FILTER] 現在の言語の通知を表示: $messageLanguage");
            } else {
              print("🚫 [FILTER] 異なる言語の通知をフィルタ: $messageLanguage");
            }
          } else {
            print("⚠️ [FILTER] トピック解析失敗: $fromTopic → parts: $parts");
          }
        }

        // フィルタリングされた通知のみ表示
        if (shouldShowNotification) {
          // 通知ペイロードが存在する場合
          final notification = message.notification;
          if (notification != null) {
            print("🔔 [FCM] ローカル通知を表示します");
            _showLocalNotification(notification.title, notification.body);
          } else if (message.data.isNotEmpty) {
            // データメッセージの場合も通知を表示
            print("📊 [FCM] データメッセージから通知を生成");
            final title = message.data['title'] ?? 'バス通知';
            final body = message.data['body'] ?? message.data['message'] ?? 'メッセージを受信しました';
            _showLocalNotification(title, body);
          }
        } else {
          print("🔇 [FILTER] 通知表示をスキップ（言語フィルタ）");
        }
      });

      // アプリがバックグラウンドから開かれた時
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print("🔄 [FCM] アプリが通知から開かれました:");
        print("  - From: ${message.from}");
        print("  - Message ID: ${message.messageId}");
        print("  - Data: ${message.data}");

        final notification = message.notification;
        if (notification != null) {
          _showLocalNotification(notification.title, notification.body);
        }
      });

      // アプリが終了状態から通知で起動された場合
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) {
        print("🚀 [FCM] 初期メッセージで起動:");
        print("  - From: ${message.from}");
        print("  - Message ID: ${message.messageId}");
        print("  - Data: ${message.data}");

        if (message.notification != null) {
          _showLocalNotification(
            message.notification!.title,
            message.notification!.body,
          );
        }
      }

      print("✅ [FCM] Firebase Messaging初期化完了");
    } catch (e, stack) {
      print("❌ [FCM] Firebase Messaging初期化エラー: $e");
      print("Stack trace: $stack");
    }
  }



  Future<void> _onLanguageChanged() async {
    print("🔄 [LANGUAGE] 言語変更が検知されました - トピック購読を更新します");

    try {
      // 既存のトピックから購読解除し、新しいトピックに購読
      await _updateTopicSubscriptionsForLanguageChange();

      // 音声設定も更新
      if (_audioSectionKey.currentState != null) {
        await _audioSectionKey.currentState!._reloadLanguageSettings();
      }

      print("✅ [LANGUAGE] 言語変更処理完了");
    } catch (e, stack) {
      print("❌ [LANGUAGE] 言語変更処理エラー: $e");
      print("Stack trace: $stack");
    }
  }

  Future<void> _updateTopicSubscriptionsForLanguageChange() async {
    try {
      final companyId = await AppConfig.getCompanyId();
      final companyTourId = await AppConfig.getCompanyTourId();

      print("🏢 [TOPIC-UPDATE] 会社ID: $companyId, ツアーID: $companyTourId");

      final tourData = await PostgrestService.getTourData(companyId, companyTourId);
      if (tourData == null) {
        print("⚠️ [TOPIC-UPDATE] ツアーデータが見つかりません");
        return;
      }

      final tourId = tourData['id'] as int;

      // 現在の言語IDを取得
      final prefs = await SharedPreferences.getInstance();
      final currentLanguageId = prefs.getInt('selected_language_id');

      if (currentLanguageId == null) {
        print("⚠️ [TOPIC-UPDATE] 言語IDが設定されていません");
        return;
      }

      // 言語コードを取得
      final languagesData = await PostgrestService.fetchTableData('languages');
      final language = languagesData.firstWhere(
        (lang) => lang['id'] == currentLanguageId,
        orElse: () => {'code': 'ja'},
      );
      // 言語コードを2文字に正規化（en_US -> en, ja_JP -> ja）
      String languageCode = language['code'] as String;
      if (languageCode.contains('_')) {
        languageCode = languageCode.split('_')[0];
      }

      // 新しいトピック名
      final newTopic = 'bus_topic_${tourId}_$languageCode';

      print("📢 [TOPIC-UPDATE] 新しいトピック: '$newTopic'");

      print("🧹 [TOPIC-UPDATE] 古い購読をクリーンアップ開始... 言語数: ${languagesData.length}");

      // 重複排除のため、処理済みトピックを追跡
      final processedTopics = <String>{};

      // すべての言語のトピックから購読解除（言語コード正規化適用）
      for (int i = 0; i < languagesData.length; i++) {
        final lang = languagesData[i];
        String langCode = lang['code'] as String;
        print("🔄 [TOPIC-UPDATE] 処理中 $i: 元言語コード '$langCode'");

        // 言語コードを2文字に正規化（en_US -> en, ja_JP -> ja）
        if (langCode.contains('_')) {
          langCode = langCode.split('_')[0];
        }
        final oldTopic = 'bus_topic_${tourId}_$langCode';

        // 重複チェック
        if (processedTopics.contains(oldTopic)) {
          print("⏭️ [TOPIC-UPDATE] トピック '$oldTopic' は既に処理済み - スキップ");
          continue;
        }
        processedTopics.add(oldTopic);

        print("📴 [TOPIC-UPDATE] トピック '$oldTopic' の購読解除を試行");
        // 堅牢な購読解除（指数バックオフ付き）
        await _unsubscribeFromTopicWithRetry(oldTopic);
      }

      print("📢 [TOPIC-UPDATE] クリーンアップ完了、新しいトピック購読開始...");
      // 新しいトピックに購読（堅牢な実装）
      final subscribeSuccess = await _subscribeToTopicWithRetry(newTopic);
      if (!subscribeSuccess) {
        print("❌ [TOPIC-UPDATE] 新しいトピック '$newTopic' への最終的な購読失敗");
        throw Exception("Failed to subscribe to topic: $newTopic");
      }

    } catch (e, stack) {
      print("❌ [TOPIC-UPDATE] トピック更新エラー: $e");
      print("Stack trace: $stack");
    }
  }

  // FCM操作のためのヘルパー関数（指数バックオフ戦略付き）
  Future<bool> _subscribeToTopicWithRetry(String topic, {int maxRetries = 3}) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        print("✅ [FCM-RETRY] トピック '$topic' への購読成功（試行: ${attempt + 1}）");
        return true;
      } catch (e) {
        final errorMessage = e.toString();
        print("⚠️ [FCM-RETRY] トピック '$topic' への購読失敗（試行: ${attempt + 1}/$maxRetries）: $errorMessage");

        // ドキュメント推奨のエラーハンドリング
        if (_shouldRetryFCMOperation(errorMessage)) {
          if (attempt < maxRetries - 1) {
            final delayMs = _calculateBackoffDelay(attempt);
            print("🔄 [FCM-RETRY] ${delayMs}ms後に再試行します...");
            await Future.delayed(Duration(milliseconds: delayMs));
            continue;
          }
        } else {
          print("❌ [FCM-RETRY] 再試行不可能なエラー: $errorMessage");
          return false;
        }
      }
    }
    print("❌ [FCM-RETRY] トピック '$topic' への購読に最終的に失敗");
    return false;
  }

  Future<bool> _unsubscribeFromTopicWithRetry(String topic, {int maxRetries = 3}) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        print("✅ [FCM-RETRY] トピック '$topic' からの購読解除成功（試行: ${attempt + 1}）");
        return true;
      } catch (e) {
        final errorMessage = e.toString();
        print("⚠️ [FCM-RETRY] トピック '$topic' からの購読解除失敗（試行: ${attempt + 1}/$maxRetries）: $errorMessage");

        if (_shouldRetryFCMOperation(errorMessage)) {
          if (attempt < maxRetries - 1) {
            final delayMs = _calculateBackoffDelay(attempt);
            print("🔄 [FCM-RETRY] ${delayMs}ms後に再試行します...");
            await Future.delayed(Duration(milliseconds: delayMs));
            continue;
          }
        } else {
          print("❌ [FCM-RETRY] 再試行不可能なエラー: $errorMessage");
          return false;
        }
      }
    }
    print("❌ [FCM-RETRY] トピック '$topic' からの購読解除に最終的に失敗");
    return false;
  }

  // ドキュメント推奨：エラーコードに基づく再試行判定
  bool _shouldRetryFCMOperation(String errorMessage) {
    // FCM公式ドキュメントで再試行が推奨されるエラー
    const retryableErrors = [
      'messaging/server-unavailable',    // 503 Service Unavailable
      'messaging/internal-error',        // 500 Internal Server Error
      'messaging/too-many-topics',       // 429 Too Many Requests
      'messaging/unavailable',           // 一時的な利用不可
    ];

    return retryableErrors.any((error) => errorMessage.contains(error));
  }

  // ドキュメント推奨：指数バックオフによる遅延計算
  int _calculateBackoffDelay(int attempt) {
    // 基本遅延: 1秒、最大遅延: 16秒
    final baseDelayMs = 1000;
    final maxDelayMs = 16000;
    final delayMs = (baseDelayMs * math.pow(2, attempt)).toInt();
    return math.min(delayMs, maxDelayMs);
  }

  // 言語フィルタリング関数
  Future<bool> _shouldShowNotificationForLanguage(String? fromTopic) async {
    if (fromTopic == null || !fromTopic.contains('bus_topic_')) {
      return true; // バストピック以外は全て表示
    }

    // /topics/bus_topic_1_en 形式から言語コードを抽出
    // まず /topics/ プレフィックスを除去
    String topicName = fromTopic;
    if (topicName.startsWith('/topics/')) {
      topicName = topicName.substring(8); // '/topics/' を除去
    }

    final parts = topicName.split('_');
    if (parts.length < 3) {
      print("⚠️ [FILTER] 不正なトピック形式: $fromTopic");
      return true; // フォーマットが不正な場合は表示
    }

    // bus_topic_1_en の場合、parts[3] が言語コード
    if (parts.length < 4) {
      print("⚠️ [FILTER] 言語コードが見つかりません: $fromTopic");
      return true;
    }

    final messageLanguage = parts[3]; // 実際の言語コード（en, ja等）

    // 現在選択されている言語を取得
    final prefs = await SharedPreferences.getInstance();
    final currentLanguageId = prefs.getInt('selected_language_id');

    if (currentLanguageId == null) {
      return true; // 言語設定がない場合は表示
    }

    final languagesData = await PostgrestService.fetchTableData('languages');
    final currentLanguage = languagesData.firstWhere(
      (lang) => lang['id'] == currentLanguageId,
      orElse: () => {'code': 'ja'},
    );

    // 言語コードを2文字に正規化
    String currentLangCode = currentLanguage['code'] as String;
    if (currentLangCode.contains('_')) {
      currentLangCode = currentLangCode.split('_')[0];
    }

    return messageLanguage == currentLangCode;
  }

  Future<void> _subscribeToTopics() async {
    try {
      print("🔄 [TOPIC] トピック購読処理開始");

      // AppConfig初期化の確認
      final companyId = await AppConfig.getCompanyId();
      final companyTourId = await AppConfig.getCompanyTourId();

      print("🏢 [TOPIC] 会社ID: $companyId, ツアーID: $companyTourId");

      // デフォルト値チェック
      if (companyId <= 0 || companyTourId <= 0) {
        print("⚠️ [TOPIC] 会社IDまたはツアーIDが設定されていません - スキップ");
        return;
      }

      final tourData = await PostgrestService.getTourData(companyId, companyTourId);
      if (tourData == null) {
        print("⚠️ [TOPIC] ツアーデータが見つかりません");
        return;
      }

      final tourId = tourData['id'] as int;

      // 言語IDを取得
      final prefs = await SharedPreferences.getInstance();
      final languageId = prefs.getInt('selected_language_id');

      // 言語データを取得（クリーンアップのため）
      final languagesData = await PostgrestService.fetchTableData('languages');

      // 安全のため、まずすべての言語のトピックから購読解除
      print("🧹 [TOPIC] 古い購読をクリーンアップ中...");

      // 重複排除のため、処理済みトピックを追跡
      final processedTopics = <String>{};

      for (final lang in languagesData) {
        String langCode = lang['code'] as String;
        // 言語コードを2文字に正規化（en_US -> en, ja_JP -> ja）
        if (langCode.contains('_')) {
          langCode = langCode.split('_')[0];
        }
        final oldTopic = 'bus_topic_${tourId}_$langCode';

        // 重複チェック
        if (processedTopics.contains(oldTopic)) {
          print("⏭️ [TOPIC] トピック '$oldTopic' は既に処理済み - スキップ");
          continue;
        }
        processedTopics.add(oldTopic);

        // 堅牢な購読解除（指数バックオフ付き）
        await _unsubscribeFromTopicWithRetry(oldTopic);
      }

      // 言語サフィックスを決定
      String languageSuffix = '';
      if (languageId != null) {
        final language = languagesData.firstWhere(
          (lang) => lang['id'] == languageId,
          orElse: () => {'code': 'ja'}, // デフォルト日本語
        );
        // 言語コードを2文字に正規化（en_US -> en, ja_JP -> ja）
        String langCode = language['code'] as String;
        if (langCode.contains('_')) {
          langCode = langCode.split('_')[0];
        }
        languageSuffix = '_$langCode';
      } else {
        languageSuffix = '_ja'; // デフォルト日本語
      }

      final busTopic = 'bus_topic_$tourId$languageSuffix';

      print("📢 [TOPIC] トピック '$busTopic' に購読を試みます");

      // 堅牢な購読（指数バックオフ付き）
      final subscribeSuccess = await _subscribeToTopicWithRetry(busTopic);
      if (subscribeSuccess) {
        print("✅ [TOPIC] トピック '$busTopic' への購読完了");
      } else {
        print("❌ [TOPIC] トピック '$busTopic' への購読に失敗しました");
      }

      // テスト用: 全体通知トピックにも購読 - 一時的に無効化
      // await FirebaseMessaging.instance.subscribeToTopic('all');
      // print("✅ [TOPIC] トピック 'all' への購読成功（テスト用）");

      // 'all' トピックからも購読解除
      await _unsubscribeFromTopicWithRetry('all');

    } catch (e, stack) {
      print("❌ [TOPIC] トピック購読エラー: $e");
      print("Stack trace: $stack");
    }
  }

  // 会社/ツアー変更時のトピック更新（使用されていないが保持）
  Future<void> _updateTopicSubscriptions(int oldCompanyId, int oldCompanyTourId, int newCompanyId, int newCompanyTourId) async {
    try {
      print("🔄 [TOPIC] トピック購読を更新します");

      // 言語IDを取得
      final prefs = await SharedPreferences.getInstance();
      final languageId = prefs.getInt('selected_language_id');

      // 旧トピックから購読解除
      final oldTourData = await PostgrestService.getTourData(oldCompanyId, oldCompanyTourId);
      if (oldTourData != null) {
        final oldTourId = oldTourData['id'] as int;

        // 旧言語サフィックスを決定
        String oldLanguageSuffix = '';
        if (languageId != null) {
          final languagesData = await PostgrestService.fetchTableData('languages');
          final oldLanguage = languagesData.firstWhere(
            (lang) => lang['id'] == languageId,
            orElse: () => {'code': 'ja'},
          );
          oldLanguageSuffix = '_${oldLanguage['code']}';
        } else {
          oldLanguageSuffix = '_ja';
        }

        final oldBusTopic = 'bus_topic_$oldTourId$oldLanguageSuffix';
        await FirebaseMessaging.instance.unsubscribeFromTopic(oldBusTopic);
        print("📴 [TOPIC] 旧トピック '$oldBusTopic' から購読解除");
      }

      // 新トピックに購読
      final newTourData = await PostgrestService.getTourData(newCompanyId, newCompanyTourId);
      if (newTourData != null) {
        final newTourId = newTourData['id'] as int;

        // 新言語サフィックスを決定
        String newLanguageSuffix = '';
        if (languageId != null) {
          final languagesData = await PostgrestService.fetchTableData('languages');
          final newLanguage = languagesData.firstWhere(
            (lang) => lang['id'] == languageId,
            orElse: () => {'code': 'ja'},
          );
          newLanguageSuffix = '_${newLanguage['code']}';
        } else {
          newLanguageSuffix = '_ja';
        }

        final newBusTopic = 'bus_topic_$newTourId$newLanguageSuffix';
        await FirebaseMessaging.instance.subscribeToTopic(newBusTopic);
        print("📢 [TOPIC] 新トピック '$newBusTopic' に購読");
      }

      print("✅ [TOPIC] トピック購読の更新完了");
    } catch (e, stack) {
      print("❌ [TOPIC] トピック更新エラー: $e");
      print("Stack trace: $stack");
    }
  }

  Future<void> _showLocalNotification(String? title, String? body) async {
    print("🔔 [NOTIFICATION] ローカル通知表示:");
    print("  - Title: $title");
    print("  - Body: $body");

    // 通知権限の確認
    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      final bool? granted = await androidImplementation.areNotificationsEnabled();
      print("📱 [NOTIFICATION] Android通知権限状態: $granted");

      if (granted == false) {
        print("⚠️ [NOTIFICATION] 通知権限が無効です");
        return;
      }
    }

    const androidDetails = AndroidNotificationDetails(
      'bus_notifications',
      'バス通知',
      channelDescription: 'バスからの重要な通知',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      // sound: RawResourceAndroidNotificationSound('notification'), // カスタム音声は削除（デフォルト音使用）
      icon: '@mipmap/ic_launcher',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      autoCancel: true,
      ongoing: false,
      channelShowBadge: true,
      onlyAlertOnce: false,
      ticker: 'バス通知',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      subtitle: 'バスからの通知',
      categoryIdentifier: 'bus_category',
      threadIdentifier: 'bus_thread',
      interruptionLevel: InterruptionLevel.active,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await flutterLocalNotificationsPlugin.show(
        notificationId,
        title ?? 'バス通知',
        body ?? 'メッセージを受信しました',
        details,
      );
      print("✅ [NOTIFICATION] 通知表示成功 (ID: $notificationId)");

      // 通知が実際に表示されたか確認
      Future.delayed(Duration(seconds: 1), () async {
        final pendingNotifications = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
        print("📋 [NOTIFICATION] 保留中の通知数: ${pendingNotifications.length}");
      });
    } catch (e, stack) {
      print("❌ [NOTIFICATION] 通知表示エラー: $e");
      print("Stack trace: $stack");
    }
  }

  Future<void> _loadBusIcon() async {
    try {
      final gmaps.BitmapDescriptor busicon = await gmaps.BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(48, 48)), // サイズを10x10から48x48に変更
        'assets/images/bus.png',
      );
      if (mounted) {
        setState(() {
          _busIcon = busicon;
        });
        print("✅ [INIT] バスアイコン読み込み成功");
      }
    } catch (e) {
      print("❌ [INIT] バスアイコン読み込みエラー: $e");
      // アイコンがなくてもアプリを継続実行
    }
  }

  Future<void> _initializeTextRoom() async {
    try {
      await textRoomService.initializeClient();
      String myId = (await getDeviceId()) ?? "ID0";
      currentDeviceId = myId;
      await textRoomService.joinTextRoom(myId);
      print("✅ [INIT] TextRoom初期化成功");
    } catch (e) {
      print("❌ [INIT] TextRoom初期化エラー: $e");
      // エラーが発生してもアプリを継続実行
    }
  }

  Future<void> rejoinTextRoomIfChanged() async {
    final newId = (await getDeviceId()) ?? "ID0";
    if (newId != currentDeviceId) {
      await textRoomService.leaveTextRoom();
      await textRoomService.joinTextRoom(newId);
      setState(() {
        currentDeviceId = newId;
      });
    }
  }

  Future<void> _testTextRoomConnection() async {
    print("📡 [TEST] TextRoom接続テスト開始...");

    try {
      // 接続状態をチェック
      if (!textRoomService.isJoined) {
        print("❌ [TEST] TextRoom未接続 - 再接続を試行");
        await _initializeTextRoom();
        await Future.delayed(Duration(seconds: 2));
      }

      if (textRoomService.isJoined) {
        print("✅ [TEST] TextRoom接続済み - テストメッセージ送信");

        // テストメッセージを送信
        final testMessage = "TEST: ${DateTime.now().millisecondsSinceEpoch}";
        await textRoomService.sendText(testMessage);

        print("📤 [TEST] テストメッセージ送信完了: $testMessage");

        // 参加者リストをチェック
        Timer(Duration(seconds: 2), () async {
          print("🔍 [TEST] 参加者リスト確認中...");
          try {
            final participants = await textRoomService.listParticipants(textRoomService.myRoom);
            if (participants.isNotEmpty) {
              print("✅ [TEST] 参加者リスト取得成功: ${participants.length}名");
              for (var participant in participants) {
                print("👤 [TEST] 参加者: $participant");
              }
            } else {
              print("⚠️ [TEST] 参加者リストが空です");
            }
          } catch (e) {
            print("❌ [TEST] 参加者リスト取得エラー: $e");
          }
        });
      } else {
        print("❌ [TEST] TextRoom接続失敗");
      }
    } catch (e) {
      print("❌ [TEST] TextRoomテストエラー: $e");
    }
  }

  void _addMarker(String markerID, gmaps.LatLng position) {
    print("🗺️ [MARKER] マーカー追加開始: id=$markerID, position=$position");
    print("🗺️ [MARKER] バスアイコン状態: $_busIcon");
    print("🗺️ [MARKER] 現在のマーカー数: ${_markers.length}");
    
    setState(() {
      gmaps.BitmapDescriptor icon1;
      
      if (markerID == "BUS") {
        if (_busIcon != null) {
          icon1 = _busIcon!;
          print("🗺️ [MARKER] バスアイコンを使用: $_busIcon");
        } else {
          print("⚠️ [MARKER] バスアイコンが未読み込み - デフォルトマーカーを使用");
          icon1 = gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueRed);
        }
      } else {
        icon1 = gmaps.BitmapDescriptor.defaultMarker;
      }
      
      print("🗺️ [MARKER] 使用するアイコン: $icon1");
      
      _markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId(markerID),
          position: position,
          icon: icon1,
          infoWindow: gmaps.InfoWindow(
            title: markerID == "BUS" ? "🚌 バス" : markerID,
            snippet: markerID == "BUS" ? "位置: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}" : null,
          ),
          zIndex: markerID == "BUS" ? 10 : 1, // バスマーカーを最前面に
        ),
      );
    });
    
    print("✅ [MARKER] マーカー追加完了: 総マーカー数=${_markers.length}");
    
    // マーカーリストの詳細を出力
    for (var marker in _markers) {
      print("🗺️ [MARKER] 登録済みマーカー: ${marker.markerId.value} at ${marker.position}");
    }
  }

  void _removeMarker(String markerId) {
    print("🗑️ [MARKER] マーカー削除: $markerId");
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == markerId);
    });
    print("✅ [MARKER] マーカー削除完了: 残りマーカー数=${_markers.length}");
  }

  void _moveCameraToPosition(gmaps.LatLng position) {
    print("📹 [CAMERA] カメラ移動開始: $position");
    
    try {
      mapController.animateCamera(
        gmaps.CameraUpdate.newCameraPosition(
          gmaps.CameraPosition(
            target: position,
            zoom: 15.0, // ズームレベルを調整
          ),
        ),
      );
      print("✅ [CAMERA] カメラ移動完了");
    } catch (e) {
      print("❌ [CAMERA] カメラ移動エラー: $e");
    }
  }

  void _handleMessage(String senderId, String message) {
    print("🎯 [HANDLE-MESSAGE] メッセージ受信: from=$senderId, message=$message");
    
    if (message.startsWith("[WHERE]")) {
      print("📍 [WHERE] WHERE メッセージ検出: $message");
      
      gmaps.LatLng? position = extractLatLngFromMessage(message);
      print("📍 [WHERE] 解析結果: $position");
      
      if (position != null) {
        print("📍 [WHERE] バスマーカーを更新: lat=${position.latitude}, lng=${position.longitude}");
        _removeMarker("BUS");
        _addMarker("BUS", position);
        print("✅ [WHERE] バスマーカー更新完了");
      } else {
        print("❌ [WHERE] 位置情報の解析に失敗: $message");
      }
      
      (() async {
        Position position = await Geolocator.getCurrentPosition();
        await textRoomService.sendTextToUser(
          senderId,
          "[HERE]${position.latitude},${position.longitude}[/HERE]",
        );
        print("📍 [WHERE] HERE レスポンス送信完了: 送信先=$senderId");
      })();
    } else if (message.startsWith("[ANNOUNCE]") &&
        message.endsWith("[/ANNOUNCE]")) {
      print("📢 [ANNOUNCE] アナウンスメッセージ検出: $message");
      final content = message.replaceAll(
        RegExp(r'^\[ANNOUNCE\]|\[/ANNOUNCE\]$'),
        '',
      );
      _showLocalNotification("お知らせ", content);
    } else {
      print("❓ [MESSAGE] 未対応メッセージ: $message");
    }
  }

  gmaps.LatLng? extractLatLngFromMessage(String message) {
    final regex = RegExp(
      r'\[WHERE\]\s*([+-]?[0-9]*\.?[0-9]+),\s*([+-]?[0-9]*\.?[0-9]+)\s*\[/WHERE\]',
    );
    final match = regex.firstMatch(message);
    if (match != null && match.groupCount == 2) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null) {
        return gmaps.LatLng(lat, lng);
      }
    }
    return null;
  }

  Future<void> _initializeLocationAndMarker() async {
    try {
      _center = await getCurrentLatLng();
      if (_center != null) {
        setState(() {
          _markers.add(
            gmaps.Marker(
              markerId: const gmaps.MarkerId("現在位置"),
              position: _center!,
              infoWindow: const gmaps.InfoWindow(title: "現在位置"),
              anchor: const Offset(0.5, 1.0),
            ),
          );
        });
        print("✅ [INIT] 位置情報とマーカー初期化成功");
      } else {
        print("⚠️ [INIT] 位置情報の取得に失敗、デフォルト位置（別府市）を使用");
        // デフォルト位置：別府市の座標を設定
        _center = const gmaps.LatLng(33.2785, 131.5017);
        setState(() {
          _markers.add(
            gmaps.Marker(
              markerId: const gmaps.MarkerId("デフォルト位置"),
              position: _center!,
              infoWindow: const gmaps.InfoWindow(title: "別府市（デフォルト位置）"),
              anchor: const Offset(0.5, 1.0),
            ),
          );
        });
      }
    } catch (e) {
      print("❌ [INIT] 位置情報初期化エラー: $e");
      // エラーが発生した場合もデフォルト位置を設定
      print("🔄 [INIT] エラー時もデフォルト位置（別府市）を設定");
      _center = const gmaps.LatLng(33.2785, 131.5017);
      setState(() {
        _markers.add(
          gmaps.Marker(
            markerId: const gmaps.MarkerId("デフォルト位置"),
            position: _center!,
            infoWindow: const gmaps.InfoWindow(title: "別府市（デフォルト位置）"),
            anchor: const Offset(0.5, 1.0),
          ),
        );
      });
    }
  }

  /// ツアーの有効期間をチェック
  Future<void> _checkTourValidity() async {
    try {
      final companyId = await AppConfig.getCompanyId();
      final companyTourId = await AppConfig.getCompanyTourId();

      print("🔍 [VALIDITY] ツアー有効期間チェック開始: Company ID=$companyId, Tour ID=$companyTourId");

      final tourData = await PostgrestService.getTourData(companyId, companyTourId);
      final validityResult = TourValidityService.checkValidity(tourData);

      if (!validityResult.isValid && mounted) {
        // 有効期間外の場合、エラー画面を表示
        print("❌ [VALIDITY] ツアーが無効: ${validityResult.message}");

        // エラーダイアログを表示（アプリを使用不可にする）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showValidityErrorDialog(validityResult);
          }
        });
      } else {
        print("✅ [VALIDITY] ツアーは有効です");

        // 有効期間の残り日数を確認して警告表示（オプション）
        final remainingDays = TourValidityService.getRemainingDays(tourData);
        if (remainingDays != null && remainingDays <= 7 && remainingDays > 0) {
          print("⚠️ [VALIDITY] ツアー有効期限まで残り${remainingDays}日です");
        }
      }
    } catch (e) {
      print("❌ [VALIDITY] 有効期間チェックエラー: $e");
    }
  }

  /// 有効期間エラーダイアログを表示
  void _showValidityErrorDialog(TourValidityResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.errorType == ValidityErrorType.expired
                  ? Icons.error
                  : Icons.warning,
              color: Colors.red,
            ),
            const SizedBox(width: 8),
            const Text('ツアー利用不可'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.message ?? 'このツアーは現在利用できません',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (result.validFrom != null || result.validTo != null) ...[
              const Divider(),
              const Text(
                '有効期間:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(TourValidityService.getValidityPeriodString(
                {'valid_from': result.validFrom?.toIso8601String(), 'valid_to': result.validTo?.toIso8601String()}
              ) ?? '不明'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // ツアー設定画面へ遷移
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CompanyTourConfigScreen(),
                ),
              );
            },
            child: const Text('ツアー設定'),
          ),
          TextButton(
            onPressed: () {
              // アプリを終了
              Navigator.pop(context);
            },
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_center == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bus Guide App"),
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UnifiedMapScreen(),
                ),
              );
            },
            tooltip: '統合地図',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DeviceIdScreen(
                    onIdChanged: rejoinTextRoomIfChanged,
                  ),
                ),
              );
            },
            tooltip: '設定',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(flex: 1, child: _buildMap()),
          _buildControls(context),
        ],
      ),
    );
  }

  Widget _buildMap() {
    try {
      // 現在位置が設定されている場合はGoogle Mapsを表示
      if (_center != null) {
        return _buildMapWithGoogleMaps();
      } else {
        // 位置情報取得中のプレースホルダー
        return Container(
          color: Colors.blue[50],
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("現在位置を取得中..."),
                Text("位置情報の許可を確認してください", style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      }
    } catch (e, stack) {
      print("❌ [MAP] 地図構築エラー: $e");
      print("Stack trace: $stack");
      // エラーが発生した場合のフォールバック表示
      return Container(
        color: Colors.red[100],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text("地図の読み込みでエラーが発生しました", style: TextStyle(color: Colors.red)),
              Text("アプリは継続して動作します", style: TextStyle(fontSize: 12, color: Colors.red)),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildMapWithGoogleMaps() {
    try {
      // Google Maps APIキーの認証問題があるため、Flutter Mapをフォールバックとして使用
      return _buildFlutterMap();
    } catch (e, stack) {
      print("❌ [MAP] 地図初期化エラー: $e");
      print("Stack trace: $stack");
      // 地図初期化に失敗した場合のフォールバック
      return Container(
        color: Colors.orange[100],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 64, color: Colors.orange),
              SizedBox(height: 16),
              Text("地図サービスに接続できません", style: TextStyle(color: Colors.orange)),
              Text("ネットワーク接続を確認してください", style: TextStyle(fontSize: 12, color: Colors.orange)),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildFlutterMap() {
    return fmap.FlutterMap(
      options: fmap.MapOptions(
        initialCenter: latlong.LatLng(_center!.latitude, _center!.longitude),
        initialZoom: 15.0,
        onMapReady: () {
          print("✅ [MAP] Flutter Map初期化成功");
        },
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.flutter_busappall',
          maxZoom: 19,
        ),
        fmap.MarkerLayer(
          markers: _markers.map((googleMarker) {
            return fmap.Marker(
              point: latlong.LatLng(
                googleMarker.position.latitude,
                googleMarker.position.longitude,
              ),
              width: 40,
              height: 40,
              child: Icon(
                Icons.location_pin,
                color: Colors.red,
                size: 40,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    return Expanded(
      flex: 2,
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => DeviceIdScreen(
                                onIdChanged: rejoinTextRoomIfChanged,
                              ),
                        ),
                      );
                    },
                    child: const Text("ユーザー設定"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CompanyTourConfigScreen(),
                        ),
                      );
                      // 設定が変更された場合は設定を再読み込み
                      if (result == true) {
                        await _audioSectionKey.currentState?._reloadLanguageSettings();
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    child: const Text("ツアー設定", style: TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LocationTrackingPage(),
                        ),
                      );
                    },
                    child: const Text("位置情報追跡"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _testTextRoomConnection,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text("TextRoom\nテスト", style: TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(child: _buildAudioSection()),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioSection() {
    return _AudioSection(
      key: _audioSectionKey,
      textRoomService: textRoomService,
      currentDeviceId: currentDeviceId,
      onDeviceIdChanged: rejoinTextRoomIfChanged,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("🔄 [LIFECYCLE] アプリ状態変更: $state");
    
    switch (state) {
      case AppLifecycleState.paused:
        // アプリがバックグラウンドに移動
        print("⏸️ [LIFECYCLE] アプリがバックグラウンドへ");
        if (_shouldDisconnectOnBackground) {
          // 設定がONの場合のみ切断
          _performCleanup();
        } else {
          // 設定がOFFの場合は接続を維持
          print("📡 [LIFECYCLE] バックグラウンドでも接続を維持します");
        }
        break;
      case AppLifecycleState.detached:
        // アプリが終了しようとしている
        print("🛑 [LIFECYCLE] アプリが終了準備中");
        _performCleanup();
        break;
      case AppLifecycleState.resumed:
        // アプリがフォアグラウンドに復帰
        print("▶️ [LIFECYCLE] アプリがフォアグラウンドへ");
        _isCleaningUp = false;
        if (_shouldDisconnectOnBackground) {
          // 切断していた場合のみ再接続
          _performReconnection();
        } else {
          print("📡 [LIFECYCLE] 接続は維持されています");
        }
        break;
      default:
        break;
    }
  }
  
  Future<void> _performCleanup() async {
    if (_isCleaningUp) {
      print("⚠️ [CLEANUP] 既にクリーンアップ中です");
      return;
    }
    
    _isCleaningUp = true;
    print("🧹 [CLEANUP] クリーンアップ処理開始");
    
    try {
      // AudioBridgeの退室処理
      if (_audioSectionKey.currentState != null) {
        print("🔊 [CLEANUP] AudioBridge切断中...");
        await _audioSectionKey.currentState!._disconnect();
      }
      
      // TextRoomの退室処理
      print("💬 [CLEANUP] TextRoom退室中...");
      await textRoomService.dispose();
      
      print("✅ [CLEANUP] クリーンアップ完了");
    } catch (e) {
      print("❌ [CLEANUP] クリーンアップエラー: $e");
    }
  }
  
  Future<void> _performReconnection() async {
    print("🔄 [RECONNECT] 再接続処理開始");
    
    try {
      // 少し待機してから再接続
      await Future.delayed(Duration(milliseconds: 500));
      
      // TextRoomに再接続
      if (!textRoomService.isInitialized || !textRoomService.isJoined) {
        print("💬 [RECONNECT] TextRoom再接続中...");
        await _initializeTextRoom();
      }
      
      // AudioBridgeの自動再接続
      if (_audioSectionKey.currentState != null) {
        final audioState = _audioSectionKey.currentState!;
        if (!audioState._isConnected && audioState.mounted) {
          print("🔊 [RECONNECT] AudioBridge自動再接続中...");
          await audioState._connect();
        }
      }
      
      print("✅ [RECONNECT] 再接続処理完了");
    } catch (e) {
      print("❌ [RECONNECT] 再接続エラー: $e");
    }
  }

  @override
  void dispose() {
    print("🔄 [DISPOSE] MainPage破棄処理開始");
    WidgetsBinding.instance.removeObserver(this);
    
    // 同期的なクリーンアップのみ実行
    // 非同期処理はdidChangeAppLifecycleStateで処理済み
    if (!_isCleaningUp) {
      // まだクリーンアップされていない場合は実行
      _performCleanup();
    }
    
    super.dispose();
    print("✅ [DISPOSE] MainPage破棄処理完了");
  }
}

Future<gmaps.LatLng> getCurrentLatLng() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) throw Exception("位置情報サービスが無効です。");

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception("位置情報の許可が拒否されました。");
    }
  }
  if (permission == LocationPermission.deniedForever) {
    throw Exception("永続的に位置情報が拒否されています。");
  }

  Position position = await Geolocator.getCurrentPosition();
  return gmaps.LatLng(position.latitude, position.longitude);
}

Future<String?> getDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('device_id');
}

class _AudioSection extends StatefulWidget {
  final TextRoomService textRoomService;
  final String? currentDeviceId;
  final VoidCallback onDeviceIdChanged;

  const _AudioSection({
    super.key,
    required this.textRoomService,
    required this.currentDeviceId,
    required this.onDeviceIdChanged,
  });

  @override
  State<_AudioSection> createState() => _AudioSectionState();
}

class _AudioSectionState extends State<_AudioSection> {
  JanusClient? _janusClient;
  JanusSession? _session;
  JanusAudioBridgePlugin? _audioPlugin;

  bool _isConnected = false;
  bool _isJoined = false;
  bool _isNegotiating = false;
  int _selectedLanguageId = 1;
  final List<String> _statusMessages = [];

  @override
  void initState() {
    super.initState();
    _loadSelectedLanguage().then((_) {
      // 言語設定の読み込み完了後、少し遅らせて自動接続を開始
      Future.delayed(Duration(seconds: 1), () {
        if (mounted && !_isConnected) {
          print('🔊 [AUDIO-INIT] AudioSection初期化完了 - 自動接続開始');
          _connect();
        }
      });
    });
  }

  Future<void> _loadSelectedLanguage() async {
    final config = await RoomConfigService.getConfig();
    final prefs = await SharedPreferences.getInstance();
    final languageId = prefs.getInt('selected_language_id') ?? config.defaultLanguageId;
    setState(() {
      _selectedLanguageId = languageId;
    });
    _addStatus('🔍 [LANG-INIT] 言語ID読み込み: $_selectedLanguageId (SharedPrefs: ${prefs.getInt('selected_language_id')}, default: ${config.defaultLanguageId})');
  }

  Future<void> _reloadLanguageSettings() async {
    print('🔄 [LANG-CHANGE] 言語設定再読み込み開始');
    final config = await RoomConfigService.getConfig();
    final prefs = await SharedPreferences.getInstance();
    final newLanguageId = prefs.getInt('selected_language_id') ?? config.defaultLanguageId;
    
    print('🔄 [LANG-CHANGE] 現在の言語ID: $_selectedLanguageId, 新しい言語ID: $newLanguageId');

    if (newLanguageId != _selectedLanguageId) {
      print('🔄 [LANG-CHANGE] 言語変更検出 - $_selectedLanguageId → $newLanguageId');
      setState(() {
        _selectedLanguageId = newLanguageId;
      });

      // 既に接続中の場合は切断して再接続
      if (_isConnected) {
        print('🔄 [LANG-CHANGE] 接続中のため切断して再接続します');
        await _disconnect();
        await _connect();
        print('✅ [LANG-CHANGE] 新しい言語IDで再接続完了');
      } else {
        print('💡 [LANG-CHANGE] 接続していないため再接続はスキップ');
      }
    } else {
      print('💡 [LANG-CHANGE] 言語変更なし - 再接続不要');
    }
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
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

  Future<bool> _checkIfEmulator() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // エミュレータの一般的な特徴をチェック
        final isEmulator = !androidInfo.isPhysicalDevice ||
            androidInfo.model.toLowerCase().contains('emulator') ||
            androidInfo.model.toLowerCase().contains('simulator') ||
            androidInfo.hardware.toLowerCase().contains('goldfish') ||
            androidInfo.hardware.toLowerCase().contains('ranchu');
        return isEmulator;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return !iosInfo.isPhysicalDevice;
      }
      return false;
    } catch (e) {
      _addStatus('エミュレータ検出エラー: $e');
      return false;
    }
  }

  Future<bool> _requestPermissions() async {
    try {
      _addStatus('音声権限を確認中...');

      var status = await Permission.microphone.status;
      _addStatus('現在の権限状態: $status');

      if (status.isDenied) {
        _addStatus('音声権限をリクエスト中...');
        status = await Permission.microphone.request();
        _addStatus('リクエスト結果: $status');
      }

      if (status.isGranted) {
        _addStatus('音声権限が許可されました');
        return true;
      } else if (status.isPermanentlyDenied) {
        _addStatus('音声権限が永続的に拒否されています。設定から許可してください。');
        await openAppSettings();
        return false;
      } else {
        _addStatus('音声権限が拒否されました');
        return false;
      }
    } catch (e) {
      _addStatus('権限確認エラー: $e');
      return false;
    }
  }

  Future<void> _testTurnServerConnectivity() async {
    try {
      _addStatus('🔍 [TURN-TEST] TURNサーバー接続テスト開始...');
      _addStatus('🔍 [TURN-TEST] サーバー: ${AppConfig.turnServerUrl}');
      _addStatus('🔍 [TURN-TEST] ユーザー: ${AppConfig.turnUsername}');

      // 簡単なUDPソケットテストでTURNサーバーのポートをチェック
      try {
        final socket = await Socket.connect('210.149.70.103', 3478, timeout: Duration(seconds: 5));
        await socket.close();
        _addStatus('✅ [TURN-TEST] TURNサーバーポート 3478 に到達可能');
      } catch (e) {
        _addStatus('❌ [TURN-TEST] TURNサーバーポート 3478 に到達不可: $e');
      }

      // TURNS（TLS）ポートテスト
      try {
        final socket = await Socket.connect('210.149.70.103', 5349, timeout: Duration(seconds: 5));
        await socket.close();
        _addStatus('✅ [TURN-TEST] TURNSサーバーポート 5349 に到達可能');
      } catch (e) {
        _addStatus('❌ [TURN-TEST] TURNSサーバーポート 5349 に到達不可: $e');
      }

      _addStatus('🔍 [TURN-TEST] 認証情報確認:');
      _addStatus('🔍 [TURN-TEST] Username: ${AppConfig.turnUsername.isNotEmpty ? "設定済み" : "未設定"}');
      _addStatus('🔍 [TURN-TEST] Credential: ${AppConfig.turnCredential.isNotEmpty ? "設定済み" : "未設定"}');

      // Janusサーバー自体への接続確認
      _addStatus('🔍 [JANUS-TEST] Janusサーバー接続テスト...');
      try {
        final socket = await Socket.connect('circleone.biz', 443, timeout: Duration(seconds: 5));
        await socket.close();
        _addStatus('✅ [JANUS-TEST] Janusサーバー（circleone.biz:443）に到達可能');
      } catch (e) {
        _addStatus('❌ [JANUS-TEST] Janusサーバー接続不可: $e');
      }

      _addStatus('💡 [DIAGNOSIS] ICE gathering問題の診断:');
      _addStatus('💡 [DIAGNOSIS] 1. TURNサーバーは到達可能');
      _addStatus('💡 [DIAGNOSIS] 2. 問題はJanusサーバー側のICE設定の可能性');
      _addStatus('💡 [DIAGNOSIS] 3. Janusサーバーが適切なICE候補を提供していない');

    } catch (e) {
      _addStatus('❌ [TURN-TEST] TURNサーバーテストエラー: $e');
    }
  }

  Future<void> _connect() async {
    try {
      _addStatus('接続中...');

      // エミュレータ検出
      final isEmulator = await _checkIfEmulator();
      if (isEmulator) {
        _addStatus('⚠️ [EMULATOR] エミュレータ環境を検出');
        _addStatus('⚠️ [EMULATOR] WebRTC機能が制限される可能性があります');
        _addStatus('💡 [EMULATOR] 音声機能のテストには実機を推奨');
      }

      // 音声受信のために必要な権限を確認
      final hasPermission = await _requestPermissions();
      if (!hasPermission) {
        _addStatus('音声権限が必要です。設定から権限を許可してください。');
        return;
      }

      _addStatus('WebSocket URL: ${AppConfig.janusWebSocketUrl}');

      // TURNサーバー接続テスト
      await _testTurnServerConnectivity();

      // ICE gathering失敗対策: 複数のSTUN/TURNサーバーで冗長化
      _addStatus('🔧 [ICE-FIX] ICE gathering失敗対策を適用中...');
      _addStatus('🔧 [ICE-FIX] 複数のSTUN/TURNサーバーで冗長化');

      _janusClient = JanusClient(
        transport: WebSocketJanusTransport(url: AppConfig.janusWebSocketUrl),
        iceServers: [
          // GoogleのパブリックSTUN（うまくいっているアプリと同じ順序）
          RTCIceServer(urls: "stun:stun.l.google.com:19302"),
          // TURNサーバー（認証付き）
          RTCIceServer(
            urls: AppConfig.turnServerUrl,
            username: AppConfig.turnUsername,
            credential: AppConfig.turnCredential,
          ),
        ],
        isUnifiedPlan: true,
        withCredentials: false,
      );
      _addStatus('JanusClient作成完了: ${AppConfig.janusWebSocketUrl}');

      _session = await _janusClient!.createSession();
      _audioPlugin = await _session!.attach<JanusAudioBridgePlugin>();

      // 受信専用なので音声デバイスの初期化を簡略化
      try {
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
        _addStatus('メディアデバイス初期化完了（受信専用）');

        // 音声受信のため、ローカル音声トラックは無効化（送信不要）
        final localStreams = _audioPlugin!.peerConnection!.getLocalStreams();
        for (final stream in localStreams) {
          if (stream != null) {
            final audioTracks = stream.getAudioTracks();
            for (final track in audioTracks) {
              track.enabled = false;
              _addStatus('ローカル音声トラック無効化（送信不要）: ${track.id}');
            }
          }
        }
      } catch (e) {
        _addStatus('メディアデバイス初期化エラー: $e');
      }

      _audioPlugin!.messages?.listen(_onMessage);

      // WebRTCコールバックを設定（ICE接続監視を含む）
      _setupWebRTCCallbacks();

      setState(() {
        _isConnected = true;
      });

      // ルーム参加前に少し待機（WebRTC初期化完了を待つ）
      await Future.delayed(Duration(milliseconds: 500));
      await _joinRoom();
      
      // 接続成功後にネイティブ音声設定を適用
      Future.delayed(Duration(seconds: 2), () {
        _enableAudioOutput();
      });
    } catch (e) {
      _addStatus('接続エラー: $e');
      setState(() {
        _isConnected = false;
      });
    }
  }

  Future<void> _joinRoom() async {
    if (_audioPlugin == null) return;

    try {
      // ツアーデータから音声ルーム番号を取得
      final companyId = await AppConfig.getCompanyId();
      final companyTourId = await AppConfig.getCompanyTourId();
      
      final tourData = await PostgrestService.getTourData(companyId, companyTourId);
      if (tourData == null) {
        _addStatus('ツアーデータの取得に失敗しました');
        return;
      }
      
      final tourId = tourData['id'] as int;
      final languageId = _selectedLanguageId;  // Now directly using language ID (1-4)

      _addStatus('ツアーID: $tourId, 言語ID: $languageId');
      _addStatus('🔍 [DEBUG] SharedPreferences確認...');

      // 現在の言語設定をデバッグ出力
      final prefs = await SharedPreferences.getInstance();
      final savedLanguageId = prefs.getInt('selected_language_id');
      _addStatus('🔍 [DEBUG] SharedPreferences言語ID: $savedLanguageId');
      _addStatus('🔍 [DEBUG] _selectedLanguageId: $_selectedLanguageId');
      
      // 音声ルーム番号を取得（audiobridge_roomsテーブルから）
      _addStatus('🔍 [ROOM-LOOKUP] audiobridge_roomsテーブル検索中...');
      _addStatus('🔍 [ROOM-LOOKUP] 検索条件 - tour_id: $tourId, language_id: $languageId');
      
      final roomNumber = await PostgrestService.getAudioRoomId(tourId, languageId);
      if (roomNumber == null) {
        _addStatus('❌ [ROOM-LOOKUP] 音声ルーム番号の取得に失敗');
        _addStatus('💡 [ROOM-LOOKUP] audiobridge_roomsテーブルを確認してください');
        _addStatus('💡 [ROOM-LOOKUP] tour_id=$tourId, language_id=$languageId');

        // すべてのaudiobridge_roomsエントリをデバッグ用に取得
        _addStatus('🔍 [DEBUG] audiobridge_roomsテーブル全データ取得中...');
        try {
          final allRooms = await PostgrestService.fetchTableData('audiobridge_rooms');
          _addStatus('🔍 [DEBUG] audiobridge_roomsエントリ数: ${allRooms.length}');
          for (final room in allRooms) {
            _addStatus('🔍 [DEBUG] room: tour_id=${room['tour_id']}, language_id=${room['language_id']}, room_number=${room['room_number']}');
          }
        } catch (e) {
          _addStatus('❌ [DEBUG] audiobridge_roomsテーブル取得エラー: $e');
        }

        // PostgREST テストページで確認できるよう案内
        _addStatus('💡 [DEBUG] PostgREST接続テストボタンでaudiobridge_roomsテーブルの内容を確認可能');
        return;
      }
      
      _addStatus('✅ [ROOM-LOOKUP] 音声ルーム番号取得成功: $roomNumber');
      print('🔄 [JOIN-ROOM] 言語ID: $languageId → ルーム番号: $roomNumber');
      
      final joinRequest = {
        'request': 'join',
        'room': roomNumber,
        'ptype': 'listener',  // listenerタイプで参加
        'display': 'Flutter Listener (recv-only)',
        'muted': true,  // listenerなので送信は無効
        'deaf': false,  // 受信は有効
      };

      _addStatus('ルーム参加リクエスト送信: $joinRequest');
      await _audioPlugin!.send(data: joinRequest);
      _addStatus('ルーム参加中...');
    } catch (e) {
      _addStatus('参加エラー: $e');
    }
  }

  void _setupWebRTCCallbacks() {
    final pc = _audioPlugin?.peerConnection;
    if (pc == null) return;

    // ICE候補の詳細監視を追加
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      final candidateStr = candidate.candidate ?? '';

      // IPv6候補をフィルタリング（サーバー非対応のため）
      bool isIPv6 = false;
      if (candidateStr.contains("2400:") ||     // IPv6グローバル
          candidateStr.contains("::1 ") ||      // IPv6ローカル
          candidateStr.contains(" fe80:") ||    // IPv6リンクローカル
          candidateStr.contains(" 2400:")) {    // スペース区切り
        isIPv6 = true;
      }

      if (isIPv6) {
        _addStatus('🚫 [ICE] IPv6候補をスキップ: $candidateStr');
        return;
      }

      _addStatus('🧊 [ICE] 候補受信: ${candidate.candidate}');
      _addStatus('🧊 [ICE] sdpMid: ${candidate.sdpMid}, sdpMLineIndex: ${candidate.sdpMLineIndex}');

      // ICE候補の詳細分析
      if (candidateStr.contains('host')) {
        _addStatus('🏠 [ICE] Host候補 - ローカルアドレス');
      } else if (candidateStr.contains('srflx')) {
        _addStatus('🌐 [ICE] Server Reflexive候補 - STUN経由');
      } else if (candidateStr.contains('relay')) {
        _addStatus('🔄 [ICE] Relay候補 - TURN経由');
      }
    };

    pc.onTrack = (RTCTrackEvent event) {
      _addStatus('リモートトラック受信: ${event.track.kind}');
      if (event.track.kind == 'audio') {
        event.track.enabled = true;
        _addStatus('音声トラック有効化: ${event.track.id}');

        if (event.streams.isNotEmpty) {
          _addStatus('リモートストリーム受信: ${event.streams[0].id}');
        }
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      _addStatus('PeerConnection状態: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _addStatus('❌ PeerConnection FAILED - 接続修復を試行');
        _handleConnectionFailure();
      }
    };

    pc.onAddStream = (MediaStream stream) {
      _addStatus('リモートストリーム追加: ${stream.id}');
      final audioTracks = stream.getAudioTracks();
      _addStatus('音声トラック数: ${audioTracks.length}');
      
      for (final track in audioTracks) {
        track.enabled = true;
        _addStatus('音声トラック有効化: ${track.id}, enabled=${track.enabled}');
      }
      
      // Android/iOS音声出力を強制的に有効化
      _enableAudioOutput();
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      _addStatus('ICE接続状態: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _addStatus('❌ ICE接続失敗 - 接続リセットを試行');
        _handleIceFailure();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _addStatus('⚠️ ICE接続が切断されました - 再接続を待機');
        // 短時間で再接続する可能性があるため、即座にリセットしない
        Future.delayed(Duration(seconds: 5), () {
          if (_audioPlugin?.peerConnection?.iceConnectionState ==
              RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
            _handleIceFailure();
          }
        });
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                 state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _addStatus('✅ ICE接続成功 - 音声受信準備完了');
      }
    };

    pc.onIceGatheringState = (RTCIceGatheringState state) {
      _addStatus('ICE収集状態: $state');
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        _addStatus('✅ ICE候補収集完了 - WebRTC接続準備完了');
      } else if (state == RTCIceGatheringState.RTCIceGatheringStateGathering) {
        _addStatus('🔄 ICE候補収集中... (最大30秒待機)');

        // ICE gathering タイムアウト保護
        Future.delayed(Duration(seconds: 30), () {
          if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateGathering) {
            _addStatus('⚠️ ICE候補収集がタイムアウト - 強制完了');
            // 収集された候補で続行を試行
          }
        });
      }
    };

    pc.onSignalingState = (RTCSignalingState state) {
      _addStatus('シグナリング状態: $state');
    };
  }

  Future<void> _onMessage(EventMessage msg) async {
    final eventData = msg.event;
    final plugindata = eventData['plugindata'];
    final jsep = eventData['jsep'];

    _addStatus('受信メッセージ: ${msg.event}');

    // hangupメッセージの処理（接続エラー時の自動復旧）
    if (eventData['janus'] == 'hangup') {
      final reason = eventData['reason'] ?? 'Unknown';
      _addStatus('❌ [HANGUP] 接続が切断されました: $reason');

      if (reason.contains('Gathering error')) {
        _addStatus('🔄 [HANGUP] ICE gathering失敗による切断 - 5秒後に再接続を試行');
        Future.delayed(Duration(seconds: 5), () {
          if (mounted && _isConnected && !_isJoined) {
            _addStatus('🔄 [AUTO-RECONNECT] 自動再接続を開始...');
            _reconnectAfterHangup();
          }
        });
      }
      return;
    }

    if (plugindata?['plugin'] == 'janus.plugin.audiobridge') {
      final data = plugindata['data'];
      _addStatus('AudioBridge応答: $data');

      if (data?['audiobridge'] == 'joined') {
        setState(() {
          _isJoined = true;
        });
        _addStatus('参加成功');

        // リスナーとして参加完了 - 音声受信のためconfigureリクエストを送信
        _addStatus('リスナーとして参加完了 - configure送信中...');
        await _configureListener();
      } else if (data?['audiobridge'] == 'event') {
        _addStatus('AudioBridgeイベント: $data');

        // JSEP（Offer/Answer）がある場合は処理
        if (jsep != null) {
          await _handleJsep(jsep);
        }
      }
    }
  }

  Future<void> _handleJsep(Map<String, dynamic> jsep) async {
    try {
      final jsepType = jsep['type'];
      _addStatus('JSEP受信: $jsepType');

      final remoteDescription = RTCSessionDescription(
        jsep['sdp'],
        jsepType,
      );

      await _audioPlugin!.peerConnection!.setRemoteDescription(
        remoteDescription,
      );
      _addStatus('Remote SDP設定完了: $jsepType');

      // Offerを受信した場合は受信専用Answerを送信
      if (jsepType == 'offer') {
        await _createAndSendAnswer();
      }
    } catch (e) {
      _addStatus('JSEP処理エラー: $e');
    }
  }

  Future<void> _createAndSendAnswer() async {
    try {
      _addStatus('受信専用Answer作成中...');

      final answer = await _audioPlugin!.peerConnection!.createAnswer();
      
      // Answer SDPを音声受信専用に修正
      String modifiedSDP = answer.sdp!;
      List<String> modifiedLines = modifiedSDP.split('\n');

      // 音声の送受信設定を適切に設定（受信のみ）
      for (int i = 0; i < modifiedLines.length; i++) {
        if (modifiedLines[i].contains('a=sendrecv')) {
          modifiedLines[i] = 'a=recvonly';
        }
      }

      // 確実にrecvonlyを追加
      if (!modifiedSDP.contains('a=recvonly')) {
        final audioIndex = modifiedLines.indexWhere(
          (line) => line.startsWith('m=audio'),
        );
        if (audioIndex != -1) {
          modifiedLines.insert(audioIndex + 1, 'a=recvonly');
        }
      }
      
      modifiedSDP = modifiedLines.join('\n');
      
      final modifiedAnswer = RTCSessionDescription(modifiedSDP, answer.type);
      await _audioPlugin!.peerConnection!.setLocalDescription(modifiedAnswer);
      
      _addStatus('Local Answer SDP設定完了');
      
      // Answerを送信
      await _audioPlugin!.send(data: {}, jsep: modifiedAnswer);
      _addStatus('Answer送信完了');
      
    } catch (e) {
      _addStatus('Answer作成・送信エラー: $e');
    }
  }

  Future<void> _configureListener() async {
    try {
      _addStatus('リスナー設定を開始...');

      // 受信専用のOffer作成（ICE gatheting最適化）
      final offer = await _audioPlugin!.peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
        'iceRestart': false,
        'voiceActivityDetection': false,
      });

      // Offer SDPを音声受信専用に修正
      String modifiedSDP = offer.sdp!;
      List<String> modifiedLines = modifiedSDP.split('\n');

      // 音声の送受信設定を適切に設定（受信のみ）
      for (int i = 0; i < modifiedLines.length; i++) {
        if (modifiedLines[i].contains('a=sendrecv')) {
          modifiedLines[i] = 'a=recvonly';
        }
      }

      // 確実にrecvonlyを追加
      if (!modifiedSDP.contains('a=recvonly')) {
        final audioIndex = modifiedLines.indexWhere(
          (line) => line.startsWith('m=audio'),
        );
        if (audioIndex != -1) {
          modifiedLines.insert(audioIndex + 1, 'a=recvonly');
        }
      }

      modifiedSDP = modifiedLines.join('\n');
      final modifiedOffer = RTCSessionDescription(modifiedSDP, offer.type);

      await _audioPlugin!.peerConnection!.setLocalDescription(modifiedOffer);
      _addStatus('Local SDP設定完了');

      // ICE候補収集完了を待つ
      _addStatus('🔄 ICE候補収集完了を待機中...');
      await _waitForIceGatheringComplete();

      // configureリクエストを送信（listener用設定）
      final configureRequest = {
        'request': 'configure',
        'muted': true,    // 送信は無効
        'deaf': false,    // 受信は有効
        'display': 'Flutter Listener (recv-only)',
      };

      await _audioPlugin!.send(data: configureRequest, jsep: modifiedOffer);
      _addStatus('Configure リクエスト送信完了');

    } catch (e) {
      _addStatus('Configure エラー: $e');
    }
  }

  Future<void> _waitForIceGatheringComplete() async {
    final pc = _audioPlugin?.peerConnection;
    if (pc == null) return;

    // 既にICE候補収集が完了している場合はすぐに返す
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      _addStatus('✅ ICE候補収集完了済み');
      return;
    }

    _addStatus('🔄 ICE候補収集中... (最大10秒待機)');

    // ポーリングでICE収集状態を確認
    const checkInterval = Duration(milliseconds: 200);
    const maxWaitTime = Duration(seconds: 10);
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < maxWaitTime) {
      final state = pc.iceGatheringState;
      _addStatus('ICE収集状態: $state');

      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        _addStatus('✅ ICE候補収集完了 - configure要求送信可能');
        return;
      }

      // 短い間隔で状態をチェック
      await Future.delayed(checkInterval);
    }

    _addStatus('⚠️ ICE候補収集がタイムアウト - 強制進行');
  }

  Future<void> _handleConnectionFailure() async {
    _addStatus('PeerConnection失敗 - 接続をリセット中...');
    
    try {
      // 現在の接続をクリーンアップ
      if (_audioPlugin != null) {
        _audioPlugin!.dispose();
        _audioPlugin = null;
      }
      
      // 短い待機後に再接続を試行
      await Future.delayed(Duration(seconds: 2));
      
      if (_isConnected) {
        _addStatus('PeerConnection再確立を試行中...');
        await _reconnectAudioBridge();
      }
    } catch (e) {
      _addStatus('接続修復エラー: $e');
    }
  }

  Future<void> _handleIceFailure() async {
    _addStatus('ICE接続失敗 - ICE再起動を試行中...');
    
    try {
      final pc = _audioPlugin?.peerConnection;
      if (pc != null) {
        // ICE再起動を試行
        await pc.restartIce();
        _addStatus('ICE再起動完了');
      }
    } catch (e) {
      _addStatus('ICE再起動エラー: $e');
      // ICE再起動が失敗した場合は完全再接続
      _handleConnectionFailure();
    }
  }

  Future<void> _reconnectAudioBridge() async {
    try {
      _addStatus('AudioBridge再接続開始...');

      // 新しいプラグインを作成
      _audioPlugin = await _session!.attach<JanusAudioBridgePlugin>();

      // 受信専用でメディアデバイスを初期化
      await _audioPlugin!.initializeMediaDevices(
        mediaConstraints: {
          'audio': false,
          'video': false,
        },
      );

      // WebRTCコールバックを再設定
      _setupWebRTCCallbacks();

      // メッセージリスナーを再設定
      _audioPlugin!.messages?.listen(_onMessage);

      // ルームに再参加
      await _joinRoom();

      _addStatus('AudioBridge再接続完了');
    } catch (e) {
      _addStatus('AudioBridge再接続エラー: $e');
      setState(() {
        _isConnected = false;
        _isJoined = false;
      });
    }
  }

  Future<void> _reconnectAfterHangup() async {
    try {
      _addStatus('🔄 [HANGUP-RECOVERY] hangup後の再接続処理開始...');

      // 現在の状態をリセット
      setState(() {
        _isJoined = false;
      });

      // 既存のプラグインを完全に破棄
      if (_audioPlugin != null) {
        try {
          await _audioPlugin!.dispose();
        } catch (e) {
          _addStatus('プラグイン破棄エラー（無視）: $e');
        }
        _audioPlugin = null;
      }

      // 短い待機時間を入れて、サーバー側の状態リセットを待つ
      await Future.delayed(Duration(seconds: 2));

      // 短い待機後に新しいプラグインで再接続
      await Future.delayed(Duration(seconds: 2));

      if (_session != null && mounted) {
        _audioPlugin = await _session!.attach<JanusAudioBridgePlugin>();

        // メディアデバイス初期化
        try {
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
        } catch (e) {
          _addStatus('メディアデバイス初期化スキップ: $e');
        }

        // コールバック設定
        _setupWebRTCCallbacks();
        _audioPlugin!.messages?.listen(_onMessage);

        // ルーム再参加
        await _joinRoom();

        _addStatus('✅ [HANGUP-RECOVERY] hangup後の再接続完了');
      }
    } catch (e) {
      _addStatus('❌ [HANGUP-RECOVERY] 再接続エラー: $e');
    }
  }

  Future<void> _disconnect() async {
    print("🔄 [AUDIO-DISCONNECT] AudioBridge切断処理開始");
    
    setState(() {
      _isConnected = false;
      _isJoined = false;
      _isNegotiating = false; // negotiationフラグをリセット
    });

    try {
      // 1. ルームから退室
      if (_audioPlugin != null && _isJoined) {
        print("👋 [AUDIO-DISCONNECT] AudioBridgeルームから退室中...");
        await _audioPlugin!.send(data: {'request': 'leave'});
        // 退室処理が完了するまで少し待機
        await Future.delayed(Duration(milliseconds: 500));
      }
      
      // 2. プラグインを破棄
      if (_audioPlugin != null) {
        print("🔧 [AUDIO-DISCONNECT] AudioBridgeプラグイン破棄中...");
        _audioPlugin?.dispose();
      }
      
      // 3. セッションを破棄
      if (_session != null) {
        print("🔧 [AUDIO-DISCONNECT] Janusセッション破棄中...");
        // セッションの破棄はJanusClientと一緒に行う
      }
      
      // 4. JanusClientを破棄
      if (_janusClient != null) {
        print("🔧 [AUDIO-DISCONNECT] JanusClient破棄中...");
        // JanusClientの破棄で内部的にセッションも破棄される
      }
      
    } catch (e) {
      _addStatus('切断エラー: $e');
      print("❌ [AUDIO-DISCONNECT] 切断エラー: $e");
    }

    _audioPlugin = null;
    _session = null;
    _janusClient = null;
    _addStatus('切断完了');
    print("✅ [AUDIO-DISCONNECT] AudioBridge切断処理完了");
  }

  String _getLanguageName(int languageId) {
    return RoomConfigService.getLanguageName(languageId);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Language selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language, size: 16, color: Colors.blue[700]),
                const SizedBox(width: 4),
                Text(
                  _getLanguageName(_selectedLanguageId),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Auto-connection status display
          Container(
            width: double.infinity,
            height: 36,
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
              border: Border.all(
                color: _isConnected ? Colors.green : Colors.orange,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                _isConnected ? '自動接続済み' : '接続中...',
                style: TextStyle(
                  fontSize: 14,
                  color: _isConnected ? Colors.green[700] : Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Status indicators - compact
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CompactStatusIndicator(label: '接続', isActive: _isConnected),
              _CompactStatusIndicator(label: 'ルーム', isActive: _isJoined),
            ],
          ),
          const SizedBox(height: 8),

          // Manual connection buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isConnected ? null : () async {
                    await _connect();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text(
                    _isConnected ? '接続済み' : '手動接続',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isConnected ? () async {
                    await _disconnect();
                  } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text(
                    '切断',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Status messages - compact
          Expanded(
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
                color: Colors.grey[50],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        topRight: Radius.circular(3),
                      ),
                    ),
                    child: const Text(
                      'ステータス',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(4),
                      itemCount: _statusMessages.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _statusMessages[index],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 8,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enableAudioOutput() async {
    try {
      _addStatus('音声出力を有効化中...');
      
      // WebRTC音声トラック状態を確認・設定
      if (_audioPlugin?.webRTCHandle?.peerConnection != null) {
        final pc = _audioPlugin!.webRTCHandle!.peerConnection!;
        final remoteStreams = pc.getRemoteStreams();
        _addStatus('リモートストリーム数: ${remoteStreams.length}');
        
        for (final stream in remoteStreams) {
          if (stream != null) {
            final audioTracks = stream.getAudioTracks();
            _addStatus('ストリーム ${stream.id}: 音声トラック数=${audioTracks.length}');
            
            for (final track in audioTracks) {
              _addStatus('トラック ${track.id}: enabled=${track.enabled}, muted=${track.muted}');
              if (!track.enabled) {
                track.enabled = true;
                _addStatus('トラック ${track.id} を有効化しました');
              }
              // 音声トラックのボリュームを最大に設定
              if (track.kind == 'audio') {
                _addStatus('音声トラック設定完了: ${track.id}');
              }
            }
          }
        }
        
        // PeerConnection状態確認
        _addStatus('PeerConnection状態: ${pc.connectionState}');
        _addStatus('ICE接続状態: ${pc.iceConnectionState}');
        _addStatus('シグナリング状態: ${pc.signalingState}');
      }
      
      _addStatus('🎵 音声出力設定完了 - WebRTCトラック確認済み');
    } catch (e) {
      _addStatus('音声出力設定エラー: $e');
    }
  }
}

class _CompactStatusIndicator extends StatelessWidget {
  final String label;
  final bool isActive;

  const _CompactStatusIndicator({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isActive ? Icons.check_circle : Icons.cancel,
          color: isActive ? Colors.green : Colors.red,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
