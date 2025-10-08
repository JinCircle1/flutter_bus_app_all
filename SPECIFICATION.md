# バスガイドアプリケーション 技術仕様書

## 1. アプリケーション概要

### 1.1 プロジェクト名
Flutter Bus Guide App (flutter_busappall)

### 1.2 目的
観光バスツアー向けの多言語対応音声ガイドシステム。GPS位置情報に基づいて自動的に観光地点を検知し、選択した言語で音声ガイドを再生する。

### 1.3 主要機能
- **Location Guide機能**: GPS位置情報による観光地点の自動検知と音声ガイド再生
- **Bus Guide機能**: WebRTC（Janus）を使用したバスドライバーとの音声共有システム
- **多言語対応**: 日本語、英語、韓国語、中国語、ベトナム語に対応
- **自動位置追跡**: 時間・距離ベースの位置情報自動更新
- **ツアー管理**: 有効期限付きツアーの管理とQRコード読み取り

---

## 2. 技術スタック

### 2.1 フレームワーク・言語
- **Flutter**: 3.x以上
- **Dart**: 3.x以上
- **プラットフォーム**: Android, iOS

### 2.2 主要パッケージ
- `flutter_map`: 地図表示（OpenStreetMap）
- `geolocator`: GPS位置情報取得
- `location`: 位置情報サービス
- `audioplayers`: 音声再生
- `janus_client`: WebRTC通信（Janus Gateway）
- `qr_code_scanner`: QRコード読み取り
- `shared_preferences`: ローカル設定保存
- `http`: HTTP通信
- `firebase_core`: Firebase基盤
- `firebase_messaging`: プッシュ通知

### 2.3 バックエンド
- **データベース**: PostgreSQL
- **API**: PostgREST（RESTful API）
- **WebRTC**: Janus Gateway
- **認証**: Basic認証

---

## 3. データベース構造

### 3.1 主要テーブル

#### tours テーブル
ツアー情報を管理

| カラム名 | 型 | 説明 |
|---------|-----|------|
| id | INTEGER | ツアーID（主キー） |
| company_id | INTEGER | 会社ID |
| external_tour_id | INTEGER | 外部ツアーID |
| driver_language_id | INTEGER | ドライバー言語ID |
| start_time | TIMESTAMP | 開始日時 |
| end_time | TIMESTAMP | 終了日時 |
| name | VARCHAR | ツアー名 |

#### landmarks テーブル
観光地点情報

| カラム名 | 型 | 説明 |
|---------|-----|------|
| id | INTEGER | 観光地点ID（主キー） |
| name | VARCHAR | 地点名（日本語） |
| name_en | VARCHAR | 地点名（英語） |
| name_kana | VARCHAR | 地点名（フリガナ） |
| latitude | DOUBLE | 緯度 |
| longitude | DOUBLE | 経度 |
| radius_meters | INTEGER | 検知半径（メートル） |

#### languages テーブル
対応言語情報

| カラム名 | 型 | 説明 |
|---------|-----|------|
| id | INTEGER | 言語ID（主キー） |
| code | VARCHAR | 言語コード（例: ja, en, ko） |
| name | VARCHAR | 言語名（英語） |
| name_ja | VARCHAR | 言語名（日本語） |
| name_en | VARCHAR | 言語名（英語） |
| name_local | VARCHAR | 言語名（現地語） |

#### ui_translations テーブル（オプション）
UI翻訳テキスト

| カラム名 | 型 | 説明 |
|---------|-----|------|
| language_code | VARCHAR | 言語コード |
| translation_key | VARCHAR | 翻訳キー |
| translation_value | VARCHAR | 翻訳値 |

#### manager_rooms テーブル（Bus Guide用）
マネージャールーム情報

| カラム名 | 型 | 説明 |
|---------|-----|------|
| tour_id | INTEGER | ツアーID |
| text_room_id | INTEGER | テキストルームID |

#### audiobridge_rooms テーブル（Bus Guide用）
音声ブリッジルーム情報

| カラム名 | 型 | 説明 |
|---------|-----|------|
| tour_id | INTEGER | ツアーID |
| language_id | INTEGER | 言語ID |
| room_number | INTEGER | ルーム番号 |

---

## 4. 画面仕様

### 4.1 起動画面（StartupScreen）

#### 機能
- ツアーデータの取得と有効性チェック
- QRコード読み取り機能
- エラーハンドリング

#### 有効期限チェック
1. **有効**: ツアー開始前または期間内 → 地図画面へ遷移
2. **期限切れ**: ツアー終了後 → ダイアログ表示 → QRコード読み取り画面へ
3. **未開始**: ツアー開始前 → ダイアログ表示 → QRコード読み取り画面へ

#### QRコード読み取り
- フォーマット: `company_id,tour_id`（例: `2,5`）
- カメラ権限が必要

### 4.2 統合地図画面（UnifiedMapScreen）

#### 地図表示
- **ベース地図**: OpenStreetMap
- **現在位置マーカー**: 青い位置アイコン
- **観光地点マーカー**: 旗アイコン（近接時は緑、通常時は赤）
- **初期表示位置**: 日本（大分県）または設定された位置

#### 観光地点情報パネル
表示内容：
- 観光地点名（日本語）
- フリガナ（ローマ字変換）
- ガイド再生ボタン

#### 観光地点タップダイアログ
表示内容：
- 観光地点名（日本語）
- フリガナ（ローマ字）
- 距離: 現在位置からの距離（メートル）
- 方向: 8方位表示（北、北東、東、南東、南、南西、西、北西）
- 音声ガイド: 選択言語の音声ファイル有無

※すべてのラベルは選択言語で表示

#### ステータスパネル（オプション）
- 現在位置の緯度経度
- デバッグステータスメッセージ
- 設定で表示/非表示切り替え可能

#### ボタン
- **ガイド再生/停止**: 近接している観光地点の音声再生
- **設定**: 設定画面へ遷移
- **ユーザー設定**（オプション）: デバイスID設定画面へ

### 4.3 設定画面（LocationGuideSettingsScreen）

#### 言語設定
- 対応言語のリストから選択
- 言語ソート順序: ID順、コード順、日本語名順、英語名順

#### 位置情報設定
- **自動位置更新**: ON/OFF切り替え
- **時間間隔**: 秒単位（デフォルト: 30秒）
- **距離間隔**: メートル単位（デフォルト: 10メートル）

#### 表示設定
- **ステータスパネル表示**: ON/OFF

#### 管理者設定（PIN認証必要）
- **デフォルトPIN**: 1234
- **ユーザー設定ボタン表示**: ON/OFF（デフォルト: OFF）
- **サーバー設定**: ホスト、ポート、プロトコル
- **会社・ツアー設定**: 会社ID、ツアーID設定

---

## 5. サービス仕様

### 5.1 LocationService（位置情報サービス）

#### 機能
- GPS位置情報の取得
- 自動位置追跡（2つの方式）

#### 位置更新方式
1. **Geolocatorストリーム**
   - 設定した距離以上移動すると更新
   - `distanceFilter`パラメータを使用

2. **タイマーベース**
   - 設定した時間間隔で定期的にチェック
   - 前回位置から5メートル以上移動していれば更新
   - フォールバック機能として動作

#### 設定パラメータ
- `timeInterval`: 時間間隔（秒）
- `distanceInterval`: 距離間隔（メートル）
- `autoUpdateEnabled`: 自動更新有効/無効

### 5.2 AudioService（音声サービス）

#### 機能
- 観光地点の音声ファイル再生
- 音声ファイル存在チェック
- 複数パスでの音声ファイル検索

#### 音声ファイル命名規則
```
landmark_{landmarkId}_{languageCode}.mp3
```
例: `landmark_1_ja.mp3`, `landmark_1_en.mp3`

#### 音声ファイル検索パス
1. `/audio/landmark_{id}_{lang}.mp3`
2. `/landmark_{id}_{lang}.mp3`
3. `landmark_{id}_{lang}.mp3`

#### フォールバック動作
1. 選択言語の音声ファイルを検索
2. 見つからない場合、日本語（languageId=1）にフォールバック
3. それでも見つからない場合、エラーメッセージ表示

#### 再生ファイルがない場合の動作
- **観光地点が近くにない**: 「近くに観光地点がありません」（オレンジ）
- **音声ファイルなし**: 「この観光地点の音声ファイルが見つかりません」（オレンジ、2秒）
- **再生成功**: 「音声再生開始」（緑、1秒）
- **エラー**: 「音声再生エラー: {エラー内容}」（赤）

### 5.3 TranslationService（翻訳サービス）

#### 翻訳ソース
1. **データベース翻訳**（優先）
   - `ui_translations`テーブルから読み込み
   - アプリ起動時に初期化

2. **ハードコード翻訳**（フォールバック）
   - データベースにデータがない場合に使用
   - 5言語対応（ja, en, ko, zh, vi）

#### 主要翻訳キー
- `play`: ガイド再生
- `stop`: 音声停止
- `settings`: 設定
- `distance`: 距離
- `direction`: 方向
- `audio_guide`: 音声ガイド
- `audio_available`: あり/Available
- `audio_unavailable`: なし/Unavailable
- `unknown`: 不明/Unknown
- `error`: 確認エラー/Error
- `direction_north`, `direction_northeast`, ... : 8方位

### 5.4 LandmarkService（観光地点サービス）

#### 機能
- 観光地点データの取得とキャッシュ
- 近接検知
- 距離・方位計算

#### 近接検知
- Haversine公式を使用した距離計算
- 各観光地点の`radius_meters`内に入ると検知

#### 方位計算
- 方位角（0-360度）を計算
- 8方位に変換（北、北東、東、南東、南、南西、西、北西）
- 選択言語で表示

### 5.5 KanaToRomajiService（かな→ローマ字変換）

#### 機能
- ひらがな・カタカナをローマ字に変換
- 頭文字を大文字化

#### 変換例
- `ウミジゴク` → `Umijigoku`
- `かいちじごく` → `Kaichijigoku`

---

## 6. 位置情報機能

### 6.1 自動位置追跡

#### 起動時の動作
1. 位置情報権限チェック
2. 現在位置取得
3. LocationServiceで自動追跡開始
4. StreamSubscriptionで位置更新を監視

#### 設定変更時の動作
1. 既存のStreamSubscriptionをキャンセル
2. LocationServiceを新しい設定で再起動
3. 新しいStreamSubscriptionを作成

### 6.2 近接検知

#### 検知ロジック
1. 5秒ごとにタイマー実行
2. 全観光地点との距離を計算
3. `radius_meters`内の地点を検出
4. 最も近い地点を`_currentLandmark`に設定

#### UI更新
- 近接している観光地点の旗アイコンが緑色に変化
- 観光地点情報パネルを表示
- ガイド再生ボタンが有効化

---

## 7. Bus Guide機能（WebRTC）

### 7.1 概要
Janus Gatewayを使用したバスドライバーとの音声共有システム

### 7.2 必要なデータベース設定
1. **manager_rooms**: ツアーIDに対応するテキストルームID
2. **audiobridge_rooms**: 各言語ごとの音声ブリッジルーム番号

### 7.3 接続フロー
1. ツアーIDからテキストルームIDを取得
2. 言語IDから音声ブリッジルーム番号を取得
3. Janus Gatewayに接続
4. AudioBridgeプラグインに参加

### 7.4 エラーハンドリング
- データベースに設定がない場合: 初期化エラー（Location Guide機能は正常動作）
- 接続失敗: 30秒ごとに自動再接続試行

---

## 8. 設定項目

### 8.1 SharedPreferences保存項目

| キー | 型 | デフォルト値 | 説明 |
|-----|-----|------------|------|
| selected_language_id | int | 1 | 選択言語ID（1=日本語） |
| location_auto_update | bool | true | 自動位置更新ON/OFF |
| location_time_interval | int | 30 | 時間間隔（秒） |
| location_distance_interval | int | 10 | 距離間隔（メートル） |
| show_status_panel | bool | false | ステータスパネル表示 |
| show_user_settings_button | bool | false | ユーザー設定ボタン表示 |
| admin_pin_code | String | "1234" | 管理者PIN |
| device_id | String | - | デバイスID |
| company_id_override | int | - | 会社ID |
| company_tour_id_override | int | - | ツアーID |
| tour_name | String | - | ツアー名 |
| server_host | String | circleone.biz | サーバーホスト |
| server_port | int | 443 | サーバーポート |
| server_protocol | String | https | プロトコル |
| server_api_path | String | /api | APIパス |
| language_sort_order | String | id | 言語ソート順序 |

---

## 9. エラーハンドリング

### 9.1 起動時エラー

#### ツアーデータ取得失敗
- エラーメッセージ表示
- QRコード読み取り画面へ誘導

#### 位置情報権限エラー
- 権限リクエスト
- 拒否された場合: エラー画面表示、再試行ボタン

### 9.2 実行時エラー

#### 音声再生エラー
- スナックバーでエラーメッセージ表示
- 再生状態をリセット

#### WebRTC接続エラー
- 30秒ごとに自動再接続
- Location Guide機能は影響を受けない

#### 位置情報取得エラー
- タイマーベースのフォールバック機能で対応
- エラーログ出力

---

## 10. セキュリティ

### 10.1 認証
- **API認証**: Basic認証
- **管理者機能**: PIN認証（デフォルト: 1234）

### 10.2 権限
- **位置情報**: GPS位置取得に必要
- **カメラ**: QRコード読み取りに必要
- **インターネット**: API通信、WebRTC通信に必要

---

## 11. パフォーマンス最適化

### 11.1 データキャッシュ
- 観光地点データ: メモリキャッシュ（5分間有効）
- 言語データ: メモリキャッシュ
- 翻訳データ: 起動時に読み込み

### 11.2 位置情報更新の最適化
- 2つの更新方式を併用（距離ベース + タイマーベース）
- 5メートル未満の移動は無視（タイマーベース）

---

## 12. 開発・デバッグ

### 12.1 起動パラメータ
```bash
flutter run -d emulator-5554 \
  --dart-define=DEVICE_ID=5 \
  --dart-define=COMPANY_ID=2 \
  --dart-define=TOUR_ID=5
```

### 12.2 デバッグログ
- 🚀 [INIT]: 初期化
- 📍 [LOCATION]: 位置情報
- 🎵 [UnifiedMap]: 音声再生
- 🔍 [PostgrestService]: データベースクエリ
- 🌐 [TranslationService]: 翻訳
- ⏰ [LocationService]: 位置更新タイマー

### 12.3 エミュレータでの位置情報設定
```bash
adb -s emulator-5554 emu geo fix <経度> <緯度>
```

---

## 13. 今後の拡張可能性

### 13.1 データベース駆動の多言語対応
- `ui_translations`テーブルで言語追加が可能
- Flutter側の修正不要

### 13.2 観光地点の動的追加
- データベースに観光地点を追加するだけで自動反映
- 音声ファイルを配置するだけで再生可能

### 13.3 ツアー管理
- QRコードで新しいツアーに切り替え可能
- 有効期限の自動チェック

---

## 14. 制限事項

### 14.1 既知の制限
- Bus Guide機能は`manager_rooms`と`audiobridge_rooms`のデータベース設定が必要
- 音声ファイルは手動でサーバーに配置する必要がある
- オフライン動作には対応していない

### 14.2 対応プラットフォーム
- Android: 対応
- iOS: 対応（位置情報権限設定が必要）
- Web: 未対応

---

## 15. バージョン情報

### 15.1 最終更新
- 日付: 2025-10-08
- コミットハッシュ: bebcefa

### 15.2 主要な変更履歴
- データベース駆動翻訳システム実装
- 観光地点情報ダイアログの多言語対応
- 自動位置追跡の改善（設定変更時の動作修正）
- ローマ字変換サービス追加
- 起動時の言語設定読み込み追加

---

## 付録A: API エンドポイント

### ベースURL
```
https://circleone.biz/api
```

### エンドポイント一覧

| エンドポイント | メソッド | 説明 |
|--------------|---------|------|
| /tours | GET | ツアー一覧取得 |
| /tours?company_id=eq.{id}&external_tour_id=eq.{id} | GET | 特定ツアー取得 |
| /landmarks | GET | 観光地点一覧取得 |
| /languages | GET | 言語一覧取得 |
| /ui_translations | GET | UI翻訳一覧取得 |
| /manager_rooms?tour_id=eq.{id} | GET | マネージャールーム取得 |
| /audiobridge_rooms | GET | 音声ブリッジルーム一覧取得 |

---

## 付録B: 音声ファイル配置

### ディレクトリ構造
```
/audio/
  landmark_1_ja.mp3
  landmark_1_en.mp3
  landmark_1_ko.mp3
  landmark_2_ja.mp3
  landmark_2_en.mp3
  ...
```

### 命名規則
```
landmark_{観光地点ID}_{言語コード}.mp3
```

### サーバー設定
- ポート3000で音声ファイルを配信
- CORS設定が必要

---

## 付録C: データベース初期設定SQL例

### ui_translationsテーブル作成
```sql
CREATE TABLE ui_translations (
  language_code VARCHAR(10) NOT NULL,
  translation_key VARCHAR(50) NOT NULL,
  translation_value VARCHAR(200) NOT NULL,
  PRIMARY KEY (language_code, translation_key)
);

-- 日本語翻訳の例
INSERT INTO ui_translations VALUES
  ('ja', 'play', 'ガイド再生'),
  ('ja', 'stop', '音声停止'),
  ('ja', 'distance', '距離'),
  ('ja', 'direction', '方向');

-- 英語翻訳の例
INSERT INTO ui_translations VALUES
  ('en', 'play', 'Play Guide'),
  ('en', 'stop', 'Stop Audio'),
  ('en', 'distance', 'Distance'),
  ('en', 'direction', 'Direction');
```

### Bus Guide用テーブルの例
```sql
-- manager_rooms
INSERT INTO manager_rooms (tour_id, text_room_id)
VALUES (5, 1001);

-- audiobridge_rooms
INSERT INTO audiobridge_rooms (tour_id, language_id, room_number)
VALUES
  (5, 1, 2001),  -- 日本語
  (5, 2, 2002),  -- 英語
  (5, 3, 2003);  -- 韓国語
```
