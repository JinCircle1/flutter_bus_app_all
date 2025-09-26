import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/audio_service.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final ApiService _apiService = ApiService();
  final AudioService _audioService = AudioService();
  Map<String, dynamic>? _testResult;
  bool _isLoading = false;
  String _selectedBaseUrl = 'https://circleone.biz/api';
  String? _audioTestResult;

  @override
  void initState() {
    super.initState();
    // Initialize with default server configuration
  }

  Future<void> _testConnection() async {
    setState(() {
      _isLoading = true;
      _testResult = null;
    });

    try {
      final result = await _apiService.testConnection();

      // 音声ファイルの詳細データも取得
      await _testAudioData(result);

      setState(() {
        _testResult = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _testResult = {'error': 'Connection test failed: $e'};
        _isLoading = false;
      });
    }
  }

  Future<void> _testAudioData(Map<String, dynamic> result) async {
    print('=== TESTING AUDIO DATA ===');

    try {
      // 全ランドマーク音声データを取得
      final allAudios = await _apiService.get('landmark_audios');
      print('Total landmark_audios records: ${allAudios.length}');

      result['audio_details'] = {
        'total_count': allAudios.length,
        'records': [],
      };

      for (int i = 0; i < allAudios.length && i < 10; i++) { // 最大10件表示
        final audio = allAudios[i] as Map<String, dynamic>;
        final audioDetail = {
          'id': audio['id'],
          'landmark_id': audio['landmark_id'],
          'language_id': audio['language_id'],
          'audio_url': audio['audio_url'],
          'filename': audio['filename'],
          'title': audio['title'],
        };
        result['audio_details']['records'].add(audioDetail);
        print('Audio record ${i + 1}: $audioDetail');
      }

      // 利用可能なlandmark_idを確認
      print('=== CHECKING AVAILABLE LANDMARK_IDS FOR AUDIO ===');
      final availableLandmarkIds = <int>{};
      for (final audio in allAudios) {
        final landmarkId = audio['landmark_id'] as int;
        availableLandmarkIds.add(landmarkId);
      }
      print('Available landmark_ids with audio: ${availableLandmarkIds.toList()..sort()}');

      // 各landmark_idの音声ファイル数を確認
      for (final landmarkId in availableLandmarkIds) {
        final audiosForLandmark = allAudios.where((audio) => audio['landmark_id'] == landmarkId).toList();
        print('Landmark $landmarkId has ${audiosForLandmark.length} audio files:');
        for (final audio in audiosForLandmark) {
          print('  - Language ${audio['language_id']}: ${audio['audio_url']}');
        }
      }

      result['available_landmark_ids'] = availableLandmarkIds.toList()..sort();

      // 特定のlandmark_id=3をテスト
      await _testSpecificLandmarkId(3, result);

      // landmark_audiosエンドポイントの問題を調査
      await _investigateLandmarkAudiosEndpoint(result);

    } catch (e) {
      print('Error testing audio data: $e');
      result['audio_error'] = e.toString();
    }
  }

  Future<void> _testSpecificLandmarkId(int landmarkId, Map<String, dynamic> result) async {
    print('=== TESTING SPECIFIC LANDMARK_ID $landmarkId ===');

    try {
      // Direct test for landmark_id=3 with language_id=1 (Japanese)
      final endpoint = 'landmark_audios?landmark_id=eq.$landmarkId&language_id=eq.1';
      print('Testing endpoint: $endpoint');

      final baseUrl = await _apiService.getBaseUrl();
      final fullUrl = '$baseUrl/$endpoint';
      print('Full URL: $fullUrl');

      final audios = await _apiService.getLandmarkAudios(landmarkId, 1);
      print('Result for landmark_id=$landmarkId, language_id=1: ${audios.length} records');

      result['landmark_${landmarkId}_test'] = {
        'endpoint': endpoint,
        'full_url': fullUrl,
        'result_count': audios.length,
        'records': audios,
      };

      if (audios.isEmpty) {
        print('No audio found for landmark_id=$landmarkId');

        // Test with all languages
        for (int langId = 1; langId <= 4; langId++) {
          try {
            final langAudios = await _apiService.getLandmarkAudios(landmarkId, langId);
            print('Landmark $landmarkId, Language $langId: ${langAudios.length} records');
          } catch (e) {
            print('Error testing landmark $landmarkId, language $langId: $e');
          }
        }
      }

    } catch (e) {
      print('Error testing landmark_id $landmarkId: $e');
      result['landmark_${landmarkId}_error'] = e.toString();
    }
  }

  Future<void> _investigateLandmarkAudiosEndpoint(Map<String, dynamic> result) async {
    print('=== INVESTIGATING LANDMARK_AUDIOS ENDPOINT ===');

    try {
      final baseUrl = await _apiService.getBaseUrl();

      // Test different endpoint variations
      final endpointsToTest = [
        'landmark_audios',
        'landmark_audios?select=*',
        'landmark_audios?order=id',
        'landmark_audios?limit=5',
        'landmark_audios?landmark_id=is.not.null',
      ];

      final endpointResults = <String, dynamic>{};

      for (final endpoint in endpointsToTest) {
        try {
          print('Testing endpoint variation: $endpoint');
          final response = await http.get(
            Uri.parse('$baseUrl/$endpoint'),
            headers: {'Accept': 'application/json'},
          );

          endpointResults[endpoint] = {
            'status': response.statusCode,
            'body_length': response.body.length,
            'success': response.statusCode == 200,
          };

          if (response.statusCode == 200) {
            try {
              final data = jsonDecode(response.body) as List;
              endpointResults[endpoint]['record_count'] = data.length;
              if (data.isNotEmpty) {
                endpointResults[endpoint]['sample'] = data.first;
              }
              print('✅ $endpoint: ${data.length} records');
            } catch (e) {
              endpointResults[endpoint]['decode_error'] = e.toString();
              print('❌ $endpoint: JSON decode error - $e');
            }
          } else {
            endpointResults[endpoint]['error_body'] = response.body;
            print('❌ $endpoint: Status ${response.statusCode} - ${response.body}');
          }

        } catch (e) {
          endpointResults[endpoint] = {
            'error': e.toString(),
            'success': false,
          };
          print('❌ $endpoint: Connection error - $e');
        }
      }

      result['endpoint_investigation'] = endpointResults;

    } catch (e) {
      print('Error investigating endpoints: $e');
      result['endpoint_investigation_error'] = e.toString();
    }
  }

  Future<void> _testLogin() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // First, let's test the basic API endpoint
      await _testBasicApi();

      // Then test different login endpoints
      await _testLoginEndpoints();

      final success = await _apiService.login('admin@example.com', 'admin123');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Login successful!' : 'Login failed - check debug logs',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }

      // Refresh the connection test after login
      if (success) {
        await _testConnection();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testBasicApi() async {
    print('=== Testing Basic API: https://circleone.biz/api ===');

    try {
      final response = await http.get(Uri.parse('https://circleone.biz/api'));
      print('Basic API Status: ${response.statusCode}');
      final body = response.body;
      final preview = body.length > 300 ? '${body.substring(0, 300)}...' : body;
      print('Basic API Response: $preview');

      // Test PostgREST info
      final schemaResponse = await http.get(
        Uri.parse('https://circleone.biz/api'),
        headers: {'Accept': 'application/openapi+json'},
      );
      print('Schema Status: ${schemaResponse.statusCode}');
      if (schemaResponse.statusCode == 200) {
        print('PostgREST is running!');
      }

      // Test data tables directly
      final tables = ['landmarks', 'languages', 'landmark_audios'];
      for (final table in tables) {
        try {
          final tableResponse = await http.get(
            Uri.parse('https://circleone.biz/api/$table'),
            headers: {'Accept': 'application/json'},
          );
          print('$table - Status: ${tableResponse.statusCode}');
          if (tableResponse.statusCode == 200) {
            final data = jsonDecode(tableResponse.body);
            print('$table - Records: ${data.length}');
            if (data.length > 0) {
              print('$table - Sample: ${data.first}');
            }
          } else {
            print('$table - Error Body: ${tableResponse.body}');
          }
        } catch (e) {
          print('$table - Error: $e');
        }
      }
    } catch (e) {
      print('Basic API Error: $e');
    }

    print('=== End Basic API Testing ===\n');
  }

  Future<void> _testLoginEndpoints() async {
    final baseUrls = [
      'https://circleone.biz/api',
      'https://circleone.biz/api/mydb',
      'https://circleone.biz/mydb',
      'https://circleone.biz/rest/mydb',
    ];

    for (final baseUrl in baseUrls) {
      print('=== Testing Base URL: $baseUrl ===');

      // Test if API server is accessible
      try {
        print('Testing API server availability...');
        final response = await http.get(Uri.parse(baseUrl));
        print('API Server Status: ${response.statusCode}');
        final body = response.body;
        final preview = body.length > 200
            ? '${body.substring(0, 200)}...'
            : body;
        print('API Server Response: $preview');
      } catch (e) {
        print('API Server Error: $e');
      }

      // Test root endpoint for PostgREST info
      try {
        final response = await http.get(
          Uri.parse(baseUrl),
          headers: {'Accept': 'application/openapi+json'},
        );
        print('OpenAPI Schema Status: ${response.statusCode}');
        if (response.statusCode == 200) {
          print('PostgREST is running at $baseUrl!');
        }
      } catch (e) {
        print('OpenAPI Schema Error: $e');
      }

      // Test data endpoints without authentication
      final dataEndpoints = ['landmarks', 'languages', 'landmark_audios'];
      for (final endpoint in dataEndpoints) {
        try {
          final response = await http.get(
            Uri.parse('$baseUrl/$endpoint'),
            headers: {'Accept': 'application/json'},
          );
          print('$endpoint - Status: ${response.statusCode}');
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            print('$endpoint - Success! Found ${data.length} records');
            if (data.isNotEmpty) {
              print('Sample: ${data.first}');
            }
          }
        } catch (e) {
          print('$endpoint - Error: $e');
        }
      }

      // Test login endpoints
      final loginEndpoints = [
        '/rpc/login',
        '/login',
        '/auth/login',
        '/rpc/authenticate',
      ];

      for (final endpoint in loginEndpoints) {
        try {
          print('Testing login endpoint: $baseUrl$endpoint');
          final response = await http.post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': 'admin@example.com',
              'password': 'admin123',
            }),
          );
          print(
            '$endpoint - Status: ${response.statusCode}, Body: ${response.body}',
          );
        } catch (e) {
          print('$endpoint - Error: $e');
        }
      }

      print('=== End of $baseUrl testing ===\n');
    }
  }

  Future<void> _testAudioPlayback() async {
    setState(() {
      _isLoading = true;
      _audioTestResult = null;
    });

    try {
      print('=== TESTING AUDIO PLAYBACK FOR LANDMARK_ID 3 ===');

      // Test landmark_id=3 audio playback directly (using fallback mechanisms)
      print('Testing landmark_id=3 audio playback with fallback support...');
      final success = await _audioService.playLandmarkAudio(3);

      if (success) {
        _audioTestResult = '✅ Audio playback for landmark_id=3 started successfully';
      } else {
        _audioTestResult = '❌ Audio playback for landmark_id=3 failed';
      }

      print('Audio test result: $_audioTestResult');

    } catch (e) {
      print('Audio test error: $e');
      _audioTestResult = '❌ Audio test error: $e';
    } finally {
      setState(() {
        _isLoading = false;
      });

      // Show result to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_audioTestResult ?? 'Audio test completed'),
            backgroundColor: _audioTestResult?.startsWith('✅') == true
              ? Colors.green
              : Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Widget _buildEndpointStatus(String endpoint, Map<String, dynamic> data) {
    final isSuccess = data['status'] == 'success';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSuccess ? Icons.check_circle : Icons.error,
                  color: isSuccess ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  endpoint,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (isSuccess) ...[
              Text('Count: ${data['count']}'),
              Text('Response Time: ${data['responseTime']}'),
              if (data['sample'] != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Sample Data:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    data['sample'].toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ] else ...[
              Text(
                'Error: ${data['error']}',
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAudioDataDetails(Map<String, dynamic> audioData) {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '音声データの詳細',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text('総音声レコード数: ${audioData['total_count']}'),
            const SizedBox(height: 8),

            if (audioData['records'] != null && audioData['records'].isNotEmpty) ...[
              const Text(
                'サンプル音声データ:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...audioData['records'].map<Widget>((record) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID: ${record['id']}, Landmark: ${record['landmark_id']}, Language: ${record['language_id']}'),
                      Text('Title: ${record['title'] ?? 'N/A'}'),
                      Text('Filename: ${record['filename'] ?? 'N/A'}'),
                      Text('URL: ${record['audio_url'] ?? 'N/A'}',
                           style: TextStyle(color: record['audio_url'] != null ? Colors.green : Colors.red)),
                    ],
                  ),
                );
              }).toList(),
            ] else ...[
              const Text(
                '音声データが見つかりません',
                style: TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLandmarkTestResults(int landmarkId, Map<String, dynamic> testData) {
    return Card(
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Landmark ID $landmarkId テスト結果',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            Text('エンドポイント: ${testData['endpoint']}'),
            Text('完全URL: ${testData['full_url']}'),
            Text('結果レコード数: ${testData['result_count']}'),
            const SizedBox(height: 8),
            if (testData['records'] != null && testData['records'].isNotEmpty) ...[
              const Text(
                '取得データ:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...testData['records'].map<Widget>((record) {
                return Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(record.toString()),
                );
              }).toList(),
            ] else ...[
              const Text(
                '該当するデータが見つかりません',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEndpointInvestigationResults(Map<String, dynamic> investigation) {
    return Card(
      color: Colors.purple[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'エンドポイント調査結果',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 8),
            ...investigation.entries.map<Widget>((entry) {
              final endpoint = entry.key;
              final data = entry.value as Map<String, dynamic>;
              final isSuccess = data['success'] == true;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSuccess ? Colors.green[50] : Colors.red[50],
                  border: Border.all(
                    color: isSuccess ? Colors.green : Colors.red,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isSuccess ? Icons.check_circle : Icons.error,
                          color: isSuccess ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            endpoint,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    Text('Status: ${data['status']}'),
                    if (data['record_count'] != null)
                      Text('Records: ${data['record_count']}'),
                    if (data['error'] != null)
                      Text('Error: ${data['error']}', style: const TextStyle(color: Colors.red)),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Debug'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'API Base URL Selection:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value: _selectedBaseUrl,
                      isExpanded: true,
                      items:
                          [
                            'https://circleone.biz/api',
                            'https://circleone.biz/api/mydb',
                            'https://circleone.biz/mydb',
                            'https://circleone.biz/rest/mydb',
                          ].map((url) {
                            return DropdownMenuItem(
                              value: url,
                              child: Text(url),
                            );
                          }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedBaseUrl = newValue;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testLogin,
                    icon: const Icon(Icons.login),
                    label: const Text('Login First'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testConnection,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find),
                    label: const Text('Test Connection'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testAudioPlayback,
              icon: const Icon(Icons.volume_up),
              label: const Text('Test Audio Playback (Landmark ID 3)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // Audio test result display
            if (_audioTestResult != null) ...[
              Card(
                color: _audioTestResult!.startsWith('✅') ? Colors.green[50] : Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        _audioTestResult!.startsWith('✅') ? Icons.volume_up : Icons.volume_off,
                        color: _audioTestResult!.startsWith('✅') ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _audioTestResult!,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _audioTestResult!.startsWith('✅') ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_testResult != null) ...[
              if (_testResult!['error'] != null) ...[
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.error, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Connection Failed',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(_testResult!['error']),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connection Info',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Base URL: ${_testResult!['baseUrl']}'),
                        Text('Has Token: ${_testResult!['hasToken']}'),
                        Text(
                          'Token Value: ${_testResult!['tokenValue'] ?? 'null'}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'API Endpoints',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: ListView(
                    children: [
                      // API エンドポイント
                      ..._testResult!['endpoints'].entries
                          .map<Widget>(
                            (entry) =>
                                _buildEndpointStatus(entry.key, entry.value),
                          )
                          .toList(),

                      // 音声データの詳細
                      if (_testResult!['audio_details'] != null)
                        _buildAudioDataDetails(_testResult!['audio_details']),

                      // Landmark ID 3 テスト結果
                      if (_testResult!['landmark_3_test'] != null)
                        _buildLandmarkTestResults(3, _testResult!['landmark_3_test']),

                      // エンドポイント調査結果
                      if (_testResult!['endpoint_investigation'] != null)
                        _buildEndpointInvestigationResults(_testResult!['endpoint_investigation']),

                      // 音声データエラー
                      if (_testResult!['audio_error'] != null)
                        Card(
                          color: Colors.red[50],
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Audio Data Error',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(_testResult!['audio_error']),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ] else if (!_isLoading) ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'データベース接続テスト手順:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('✅ データベース接続成功！認証なしでデータアクセス可能'),
                      Text('1. 「Test Connection」ボタンでAPI接続を確認'),
                      Text('2. 各エンドポイントからのデータを確認'),
                      SizedBox(height: 8),
                      Text(
                        '認証情報: admin@example.com / admin123',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
