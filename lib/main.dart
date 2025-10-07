import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/bus_guide_screen.dart';
import 'screens/proper_location_guide_screen.dart';
import 'screens/startup_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Custom HttpOverrides to handle SSL certificate issues with WebSocket connections
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Accept all certificates for development (you may want to add specific host checks in production)
        return true;
      };
  }
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  RemoteNotification? notification = message.notification;
  if (notification != null) {
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notification.title ?? 'バス通知',
      notification.body ?? 'メッセージを受信しました',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bus_notifications',
          'バス通知',
          channelDescription: 'バスからの重要な通知',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set custom HttpOverrides to handle SSL issues with WebSocket connections
  HttpOverrides.global = MyHttpOverrides();

  // dart-defineで渡された値を読み込み
  const deviceId = String.fromEnvironment('DEVICE_ID');
  const companyId = String.fromEnvironment('COMPANY_ID');
  const tourId = String.fromEnvironment('TOUR_ID');

  // 値が指定されている場合はSharedPreferencesに保存
  // 重要：起動前に確実に保存を完了させる
  if (deviceId.isNotEmpty || companyId.isNotEmpty || tourId.isNotEmpty) {
    print("📝 [MAIN] dart-defineで渡された値を保存中...");
    final prefs = await SharedPreferences.getInstance();

    if (deviceId.isNotEmpty) {
      await prefs.setString('device_id', deviceId);
      print("✅ [MAIN] デバイスIDを設定: $deviceId");
    }

    if (companyId.isNotEmpty) {
      final companyIdInt = int.tryParse(companyId);
      if (companyIdInt != null) {
        await prefs.setInt('company_id_override', companyIdInt);
        print("✅ [MAIN] Company IDを設定: $companyIdInt");
      }
    }

    if (tourId.isNotEmpty) {
      final tourIdInt = int.tryParse(tourId);
      if (tourIdInt != null) {
        await prefs.setInt('company_tour_id_override', tourIdInt);
        print("✅ [MAIN] Tour IDを設定: $tourIdInt");
      }
    }

    // 保存が完了したことを確認
    print("✅ [MAIN] すべての設定値を保存完了");
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    print("✅ [MAIN] Firebase初期化成功");
  } catch (e) {
    print("❌ [MAIN] Firebase初期化エラー: $e");
    // Firebaseエラーが発生してもアプリを継続実行
  }

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  const initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // Android通知チャネルを明示的に作成
  const androidChannel = AndroidNotificationChannel(
    'bus_notifications',
    'バス通知',
    description: 'バスからの重要な通知',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  runApp(const BusAppAll());
}

class BusAppAll extends StatelessWidget {
  const BusAppAll({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bus & Location Guide App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const StartupScreen(),
    );
  }
}

class AppHomePage extends StatelessWidget {
  const AppHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bus & Location Guide'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome to Bus & Location Guide App',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BusGuideScreen()),
                );
              },
              icon: const Icon(Icons.directions_bus),
              label: const Text('Bus Guide'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 60),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProperLocationGuideScreen()),
                );
              },
              icon: const Icon(Icons.location_on),
              label: const Text('Location Guide'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 60),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}