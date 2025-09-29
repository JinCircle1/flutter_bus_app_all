import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../config/app_config.dart';
import '../services/postgrest_service.dart';
import '../services/room_config_service.dart';

class CompanyTourConfigScreen extends StatefulWidget {
  const CompanyTourConfigScreen({super.key});

  @override
  State<CompanyTourConfigScreen> createState() => _CompanyTourConfigScreenState();
}

class _CompanyTourConfigScreenState extends State<CompanyTourConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyIdController = TextEditingController();
  final _companyTourIdController = TextEditingController();
  
  bool _isLoading = true;
  bool _isSaving = false;

  static const String _companyIdKey = 'company_id_override';
  static const String _companyTourIdKey = 'company_tour_id_override';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 保存された値があればそれを使用、なければデフォルト値
      final companyId = prefs.getInt(_companyIdKey) ?? 1;
      final companyTourId = prefs.getInt(_companyTourIdKey) ?? 1;
      
      setState(() {
        _companyIdController.text = companyId.toString();
        _companyTourIdController.text = companyTourId.toString();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('設定の読み込みに失敗しました: $e')),
        );
      }
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // 現在の設定を取得
      final oldCompanyId = await AppConfig.getCompanyId();
      final oldCompanyTourId = await AppConfig.getCompanyTourId();
      
      // 新しい設定
      final newCompanyId = int.parse(_companyIdController.text);
      final newCompanyTourId = int.parse(_companyTourIdController.text);

      // SharedPreferencesに保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_companyIdKey, newCompanyId);
      await prefs.setInt(_companyTourIdKey, newCompanyTourId);

      // Firebase Messaging Topic更新
      if (oldCompanyId != newCompanyId || oldCompanyTourId != newCompanyTourId) {
        await _updateTopicSubscriptions(oldCompanyId, oldCompanyTourId, newCompanyId, newCompanyTourId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('設定を保存しました。Topic設定も更新されました。')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('設定の保存に失敗しました: $e')),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  /// Firebase Messaging Topic更新
  Future<void> _updateTopicSubscriptions(int oldCompanyId, int oldCompanyTourId, int newCompanyId, int newCompanyTourId) async {
    try {
      print('🔔 [CONFIG] Topic更新開始');
      
      // 現在の言語設定を取得
      final prefs = await SharedPreferences.getInstance();
      final config = await RoomConfigService.getConfig();
      final selectedLanguageId = prefs.getInt('selected_language_id') ?? config.defaultLanguageId;
      final languageSuffix = _getLanguageSuffix(selectedLanguageId);
      
      // 古いtour_idを取得して登録解除（全言語）
      final oldTourData = await PostgrestService.getTourData(oldCompanyId, oldCompanyTourId);
      if (oldTourData != null) {
        final oldTourId = oldTourData['id'] as int;
        // 全言語のトピックから登録解除
        await FirebaseMessaging.instance.unsubscribeFromTopic('bus_topic_${oldTourId}_ja');
        await FirebaseMessaging.instance.unsubscribeFromTopic('bus_topic_${oldTourId}_en');
        await FirebaseMessaging.instance.unsubscribeFromTopic('bus_topic_${oldTourId}_ko');
        await FirebaseMessaging.instance.unsubscribeFromTopic('bus_topic_${oldTourId}_zh');
        print('  - 登録解除: bus_topic_${oldTourId}_* (全言語)');
      }
      
      // 新しいtour_idを取得して購読（現在の言語）
      final newTourData = await PostgrestService.getTourData(newCompanyId, newCompanyTourId);
      if (newTourData != null) {
        final newTourId = newTourData['id'] as int;
        final newBusTopic = 'bus_topic_$newTourId$languageSuffix';
        
        print('  - 新規購読: $newBusTopic');
        await FirebaseMessaging.instance.subscribeToTopic(newBusTopic);
      }
      
      print('🔔 [CONFIG] Topic更新完了');
    } catch (e) {
      print('🔔 [CONFIG] Topic更新エラー: $e');
      // エラーでも設定保存は続行
    }
  }
  
  String _getLanguageSuffix(int languageId) {
    switch (languageId) {
      case 1:
        return '_ja';
      case 2:
        return '_en';
      case 3:
        return '_ko';
      case 4:
        return '_zh';
      default:
        return '_ja';
    }
  }

  Future<void> _resetToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認'),
        content: const Text('設定をデフォルト値（Company ID: 1, Company Tour ID: 1）に戻しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('リセット'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // 現在の設定を取得
      final oldCompanyId = await AppConfig.getCompanyId();
      final oldCompanyTourId = await AppConfig.getCompanyTourId();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_companyIdKey);
      await prefs.remove(_companyTourIdKey);
      
      // デフォルト値（1, 1）でTopic更新
      if (oldCompanyId != 1 || oldCompanyTourId != 1) {
        await _updateTopicSubscriptions(oldCompanyId, oldCompanyTourId, 1, 1);
      }
      
      setState(() {
        _companyIdController.text = '1';
        _companyTourIdController.text = '1';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('デフォルト設定に戻しました。Topic設定も更新されました。')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('リセットに失敗しました: $e')),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  /// SharedPreferencesから設定値を取得
  static Future<Map<String, int>> getStoredConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'companyId': prefs.getInt(_companyIdKey) ?? 1,
        'companyTourId': prefs.getInt(_companyTourIdKey) ?? 1,
      };
    } catch (e) {
      return {'companyId': 1, 'companyTourId': 1};
    }
  }

  @override
  void dispose() {
    _companyIdController.dispose();
    _companyTourIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ツアー設定'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _saveConfig,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '保存',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ツアー設定',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _companyIdController,
                            decoration: const InputDecoration(
                              labelText: 'Company ID',
                              helperText: 'データベースの会社ID',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Company IDを入力してください';
                              }
                              final intValue = int.tryParse(value);
                              if (intValue == null || intValue <= 0) {
                                return '有効な数値を入力してください';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _companyTourIdController,
                            decoration: const InputDecoration(
                              labelText: 'Company Tour ID',
                              helperText: 'データベースの会社ツアーID',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'External Tour IDを入力してください';
                              }
                              final intValue = int.tryParse(value);
                              if (intValue == null || intValue <= 0) {
                                return '有効な数値を入力してください';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 注意事項
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              const Text(
                                '設定について',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '• これらの値はデータベースから設定を読み込む際に使用されます\n'
                            '• データベースに対応するツアーデータが存在する必要があります\n'
                            '• 設定変更後はアプリを完全に再起動してください\n'
                            '• 間違った値を設定するとエラーが発生する可能性があります',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // リセットボタン
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : _resetToDefault,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text('デフォルト設定に戻す'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}