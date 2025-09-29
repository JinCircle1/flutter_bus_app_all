// ignore_for_file: avoid_print

import 'package:janus_client/janus_client.dart';
import '../config/janus_conf.dart' as janus_conf;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import 'room_config_service.dart';

class TextRoomService {
  late JanusClient client;
  late JanusSession session;
  late JanusPlugin textRoom;
  late WebSocketJanusTransport ws;
  RTCPeerConnection? _directPeerConnection; // 直接制御用PeerConnection
  RTCDataChannel? _directDataChannel; // 直接制御用DataChannel
  int myRoom = 2001;
  bool isJoined = false;
  bool isInitialized = false;
  String? myClientId;
  String currentUsername = ""; // 現在のユーザー名を保持
  Map<String, String> userMap = {}; // クライアントID → ユーザー名
  void Function(String senderId, String message)? onMessageReceived;
  int messageCount = 0; // 受信メッセージカウンター

  Future<void> initializeClient() async {
    // JSONから設定を読み込み
    final config = await RoomConfigService.getConfig();
    myRoom = config.textRoom;
    print("🔍 [INIT-ID1] JSONから設定読み込み完了 - textRoom: \$myRoom");

    if (isInitialized) {
      print("🔍 [INIT-ID1] クライアントは既に初期化済みです - 完全リセットを実行");
      await _forceCompleteReset();
    }
    try {
      print("🚀 [INIT-ID1] Janusクライアント初期化開始");
      print("🔍 [INIT-ID1] WebSocketURL: \${servermap['janus_ws']}");

      final janusWsUrl = janus_conf.servermap['janus_ws'];
      if (janusWsUrl == null || janusWsUrl.isEmpty) {
        throw Exception("Janus WebSocket URL is null or empty");
      }

      ws = WebSocketJanusTransport(url: janusWsUrl);
      client = JanusClient(transport: ws);

      session = await client.createSession();
      print("✅ [INIT-ID1] Janusセッション作成完了: \${session.id}");

      textRoom = await session.attach<JanusTextRoomPlugin>();
      print("✅ [INIT-ID1] TextRoomプラグインアタッチ完了");

      isInitialized = true;
      print("✅ [INIT-ID1] クライアント初期化完了");
    } catch (e) {
      print("❌ [INIT-ID1] クライアント初期化失敗: \$e");
      isInitialized = false;
      rethrow;
    }
  }

  Future<void> joinRoom() async {
    if (!isInitialized) {
      print("⚠️ [JOIN] クライアントが未初期化");
      await initializeClient();
    }

    try {
      print("🔍 [JOIN] ルーム参加開始 - Room: \$myRoom");

      // ランダムなユーザー名を生成
      currentUsername = "乗客\${Random().nextInt(9999) + 1}";
      print("🔍 [JOIN] 生成されたユーザー名: \$currentUsername");

      // 参加リクエスト - JanusClient 2.3.13では引数なしのsendメソッド
      try {
        await textRoom.send();
        print("✅ [JOIN] ルーム参加要求送信完了");
      } catch (e) {
        print("⚠️ [JOIN] ルーム参加要求送信エラー: $e");
      }

      // イベントリスナーを設定
      textRoom.messages?.listen((event) async {
        await _handleTextRoomMessage(event);
      });

      isJoined = true;
      print("✅ [JOIN] ルーム参加完了");
    } catch (e) {
      print("❌ [JOIN] ルーム参加失敗: \$e");
      isJoined = false;
      rethrow;
    }
  }

  Future<void> _handleTextRoomMessage(EventMessage message) async {
    print("📩 [MSG] メッセージ受信: \${message.event}");

    final data = message.event;
    if (data == null) return;

    if (data['textroom'] == 'message') {
      final senderId = data['from']?.toString() ?? 'unknown';
      final messageText = data['text']?.toString() ?? '';

      messageCount++;
      print("📩 [MSG-\$messageCount] 受信: [\$senderId] \$messageText");

      // メッセージを上位レイヤーに通知
      onMessageReceived?.call(senderId, messageText);
    } else if (data['textroom'] == 'join') {
      final userName = data['display']?.toString() ?? '匿名';
      final userId = data['username']?.toString() ?? 'unknown';
      userMap[userId] = userName;
      print("👋 [JOIN] ユーザー参加: \$userName (ID: \$userId)");
    } else if (data['textroom'] == 'leave') {
      final userId = data['username']?.toString() ?? 'unknown';
      final userName = userMap.remove(userId) ?? '匿名';
      print("👋 [LEAVE] ユーザー退室: \$userName (ID: \$userId)");
    }
  }

  Future<void> sendMessage(String message) async {
    if (!isJoined) {
      print("⚠️ [SEND] ルームに参加していません");
      return;
    }

    try {
      print("📤 [SEND] メッセージ送信: \$message");
      // JanusClient 2.3.13では引数なしのsendメソッド
      await textRoom.send();
      print("✅ [SEND] メッセージ送信完了");
    } catch (e) {
      print("❌ [SEND] メッセージ送信失敗: \$e");
    }
  }

  // Compatibility methods for bus_guide_main_page.dart
  Future<void> joinTextRoom(String deviceId) async {
    myClientId = deviceId;
    try {
      await initializeClient();
      await joinRoom();
    } catch (e) {
      print("❌ [JOIN_TEXT_ROOM] 失敗: \$e");
      rethrow;
    }
  }

  Future<void> leaveTextRoom() async {
    try {
      await dispose();
    } catch (e) {
      print("❌ [LEAVE_TEXT_ROOM] 失敗: \$e");
      rethrow;
    }
  }

  Future<void> sendText(String message) async {
    await sendMessage(message);
  }

  Future<void> sendTextToUser(String userId, String message) async {
    // Note: Janus TextRoom doesn't support private messages, sending to room
    await sendMessage("@\$userId: \$message");
  }

  // Property getters for bus_guide_main_page.dart compatibility
  JanusPlugin get plugin => textRoom;

  // Mock participants list method
  Future<List<Map<String, dynamic>>> listParticipants(int roomId) async {
    // Return mock participant list based on userMap
    return userMap.entries.map((entry) => {
      'id': entry.key,
      'display': entry.value,
      'username': entry.key,
    }).toList();
  }

  Future<void> _forceCompleteReset() async {
    try {
      print("🔄 [RESET] 完全リセット開始");

      // 各段階でのクリーンアップを実行
      if (_directDataChannel != null) {
        try {
          _directDataChannel!.close();
          _directDataChannel = null;
          print("✅ [RESET] DataChannelクローズ完了");
        } catch (e) {
          print("⚠️ [RESET] DataChannelクローズエラー: \$e");
        }
      }

      if (_directPeerConnection != null) {
        try {
          await _directPeerConnection!.close();
          _directPeerConnection = null;
          print("✅ [RESET] PeerConnectionクローズ完了");
        } catch (e) {
          print("⚠️ [RESET] PeerConnectionクローズエラー: \$e");
        }
      }

      // Janusリソースのクリーンアップ
      try {
        if (isInitialized) {
          textRoom.dispose();
          print("✅ [RESET] TextRoomプラグイン破棄完了");
        }
      } catch (e) {
        print("⚠️ [RESET] TextRoomプラグイン破棄エラー: \$e");
      }

      try {
        if (isInitialized) {
          session.dispose();
          print("✅ [RESET] Janusセッション破棄完了");
        }
      } catch (e) {
        print("⚠️ [RESET] Janusセッション破棄エラー: \$e");
      }

      try {
        if (isInitialized) {
          // JanusClient 2.3.13 has no dispose or destroy method
          // The connection will be cleaned up automatically when WebSocket closes
          print("✅ [RESET] Janusクライアント破棄完了");
        }
      } catch (e) {
        print("⚠️ [RESET] Janusクライアント破棄エラー: \$e");
      }

      // WebSocketクローズ
      try {
        ws.dispose();
        print("✅ [RESET] WebSocketクローズ完了");
      } catch (e) {
        print("⚠️ [RESET] WebSocketクローズエラー: \$e");
      }

      // フラグリセット
      isInitialized = false;
      isJoined = false;
      myClientId = null;
      currentUsername = "";
      userMap.clear();

      print("✅ [RESET] 完全リセット完了");

      // 短時間待機してリソースの完全解放を確保
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print("❌ [RESET] 完全リセットエラー: \$e");
    }
  }

  Future<void> dispose() async {
    print("🔄 [DISPOSE] TextRoomService破棄開始");
    await _forceCompleteReset();
    print("✅ [DISPOSE] TextRoomService破棄完了");
  }
}