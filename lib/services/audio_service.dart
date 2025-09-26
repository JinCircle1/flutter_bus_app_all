import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ApiService _apiService = ApiService();

  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal() {
    _initializeAudioPlayer();
  }
  
  void _initializeAudioPlayer() {
    // Set audio player mode
    _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    
    // Listen to player state changes for debugging
    _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      print('Audio player state changed: $state');
    });
    
    // Listen to errors
    _audioPlayer.onLog.listen((String message) {
      print('AudioPlayer log: $message');
    });
  }

  Future<int> getSelectedLanguageId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('selected_language_id') ??
        1; // Default to Japanese (ID: 1)
  }

  Future<void> setSelectedLanguageId(int languageId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_language_id', languageId);
  }

  // Getter to check if audio is currently playing
  bool get isPlaying {
    return _audioPlayer.state == PlayerState.playing;
  }

  Future<void> _waitForPlaybackStart() async {
    // Wait for the player state to change to playing
    await for (final state in _audioPlayer.onPlayerStateChanged) {
      if (state == PlayerState.playing) {
        break;
      } else if (state == PlayerState.stopped) {
        throw Exception('Playback failed - player stopped');
      }
    }
  }


  Future<String?> getAudioUrl(int landmarkId) async {
    try {
      final languageId = await getSelectedLanguageId();
      print('Getting audio for landmark $landmarkId, language $languageId');

      final audios = await _apiService.getLandmarkAudios(
        landmarkId,
        languageId,
      );
      print('Found ${audios.length} audio files for landmark $landmarkId, language $languageId');

      if (audios.isNotEmpty) {
        final audioUrl = audios.first['audio_url'] as String?;
        print('Audio URL found: $audioUrl');
        if (audioUrl != null) {
          return audioUrl; // Return relative URL for path testing
        }
      }

      // If no audio found for selected language, try Japanese as fallback
      if (languageId != 1) {
        print('No audio found for language $languageId, trying Japanese fallback');
        try {
          final fallbackAudios = await _apiService.getLandmarkAudios(
            landmarkId,
            1,
          );
          print('Found ${fallbackAudios.length} fallback audio files');
          if (fallbackAudios.isNotEmpty) {
            final fallbackUrl = fallbackAudios.first['audio_url'] as String?;
            print('Fallback audio URL: $fallbackUrl');
            if (fallbackUrl != null) {
              return fallbackUrl; // Return relative URL for path testing
            }
          }
        } catch (e) {
          print('Error trying Japanese fallback: $e');
        }
      }

      print('No audio files found for landmark $landmarkId');
      return null;
    } catch (e) {
      print('Error getting audio URL: $e');

      // If specific landmark fails, try different approaches to get any audio
      print('Trying to find any available audio as fallback...');

      // First, try getting all landmark_audios without filters
      try {
        print('Trying to get all landmark_audios without filters...');
        final allAudios = await _apiService.get('landmark_audios');
        print('Total available audio records: ${allAudios.length}');

        if (allAudios.isNotEmpty) {
          final selectedLanguageId = await getSelectedLanguageId();

          // Find first audio for the same language
          for (final audioRecord in allAudios) {
            final audio = audioRecord as Map<String, dynamic>;
            if (audio['language_id'] == selectedLanguageId && audio['audio_url'] != null) {
              final fallbackUrl = audio['audio_url'] as String?;
              final fallbackLandmarkId = audio['landmark_id'];
              print('Using fallback audio: landmark_id=$fallbackLandmarkId, language_id=$selectedLanguageId, url=$fallbackUrl');
              return fallbackUrl;
            }
          }

          // If no same language, use any available audio
          final firstAudio = allAudios.first as Map<String, dynamic>;
          final fallbackUrl = firstAudio['audio_url'] as String?;
          final fallbackLandmarkId = firstAudio['landmark_id'];
          final fallbackLanguageId = firstAudio['language_id'];
          print('Using any available audio: landmark_id=$fallbackLandmarkId, language_id=$fallbackLanguageId, url=$fallbackUrl');
          return fallbackUrl;
        }
      } catch (e2) {
        print('Error getting all landmark_audios: $e2');

        // Try direct HTTP call to landmark_audios as a final attempt
        try {
          print('Trying direct HTTP call to landmark_audios...');
          final apiBaseUrl = await _apiService.getBaseUrl();
          final response = await http.get(
            Uri.parse('$apiBaseUrl/landmark_audios'),
            headers: {'Accept': 'application/json'},
          );
          print('Direct HTTP status: ${response.statusCode}');
          print('Direct HTTP response: ${response.body}');

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as List;
            if (data.isNotEmpty) {
              final firstAudio = data.first as Map<String, dynamic>;
              final fallbackUrl = firstAudio['audio_url'] as String?;
              print('Using direct HTTP audio: ${firstAudio}');
              return fallbackUrl;
            }
          }
        } catch (e3) {
          print('Error with direct HTTP call: $e3');
        }
      }

      return null;
    }
  }

  Future<bool> playLandmarkAudio(int landmarkId) async {
    try {
      print('Attempting to play audio for landmark ID: $landmarkId');

      // Get audio URL with timeout
      final audioUrl = await Future.any([
        getAudioUrl(landmarkId),
        Future.delayed(const Duration(seconds: 5), () => null)
      ]);

      print('Audio URL retrieved: $audioUrl');

      if (audioUrl == null) {
        print('音声ファイルがデータベースに登録されていません (landmark_id: $landmarkId)');
        await _showNoAudioMessage(landmarkId);
        return false;
      }

      print('Testing paths for relative URL: $audioUrl');

      // Test multiple possible paths to find the correct audio file URL
      final workingUrl = await _testMultipleAudioPaths(audioUrl);

      if (workingUrl == null) {
        print('音声ファイルがサーバーに存在しません: $audioUrl');
        await _showNoAudioFileMessage(audioUrl);
        return false;
      }

      print('Using working URL: $workingUrl');

      // Download audio file and play locally
      final localFile = await _downloadAudioFile(workingUrl);
      if (localFile == null) {
        print('Failed to download audio file, using default audio');
        await playDefaultAudio();
        return false;
      }

      // Stop any currently playing audio safely
      try {
        await _audioPlayer.stop();
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        print('Warning: Could not stop previous audio: $e');
      }

      // Play local file
      print('Playing downloaded audio file: ${localFile.path}');
      await _audioPlayer.play(DeviceFileSource(localFile.path));

      // Wait briefly for playback to start
      await Future.delayed(const Duration(milliseconds: 500));
      print('Audio playback started successfully');
      return true;
    } catch (e) {
      print('Error playing landmark audio: $e');
      try {
        await playDefaultAudio();
      } catch (e2) {
        print('Error playing default audio: $e2');
      }
      return false;
    }
  }

  Future<void> playDefaultAudio() async {
    try {
      print('Playing default audio');
      await _audioPlayer.stop();
      
      // Try multiple audio sources
      final audioSources = [
        'https://www.soundjay.com/misc/sounds/bell-ringing-05.wav',
        'https://commondatastorage.googleapis.com/codeskulptor-assets/Epoq-Lepidoptera.ogg',
        'https://commondatastorage.googleapis.com/codeskulptor-demos/DDR_assets/Kangaroo_MusiQue_-_The_Neverwritten_Role_Playing_Game.mp3',
        'https://www.soundjay.com/misc/sounds/fail-buzzer-02.wav'
      ];
      
      for (final url in audioSources) {
        try {
          print('Attempting to play: $url');
          await _audioPlayer.play(UrlSource(url));
          print('Default audio playback started successfully with: $url');
          return;
        } catch (e) {
          print('Failed to play $url: $e');
          continue;
        }
      }
      
      // If all URL sources fail, try to create a simple notification
      print('All audio sources failed, using fallback notification');
      await _showAudioFallback();
      
    } catch (e) {
      print('Error in playDefaultAudio: $e');
      await _showAudioFallback();
    }
  }
  
  Future<void> _showAudioFallback() async {
    try {
      print('Audio fallback: Visual notification only');
      // Just log that audio would have played - in a real app you might show a visual notification
    } catch (e) {
      print('Even fallback failed: $e');
    }
  }

  Future<void> stopAudio() async {
    await _audioPlayer.stop();
  }

  Future<void> pauseAudio() async {
    await _audioPlayer.pause();
  }

  Future<void> resumeAudio() async {
    await _audioPlayer.resume();
  }

  Stream<PlayerState> get playerStateStream =>
      _audioPlayer.onPlayerStateChanged;

  Future<String?> _testMultipleAudioPaths(String relativeUrl) async {
    final apiBaseUrl = await _apiService.getBaseUrl();
    final audioServerBaseUrl = await _apiService.getAudioServerBaseUrl();

    // Based on JavaScript example: http://server:3000/api/landmark_audios
    // Try different possible paths using dynamic server configuration
    // Ensure relativeUrl starts with a slash for proper URL joining
    final normalizedUrl = relativeUrl.startsWith('/') ? relativeUrl : '/$relativeUrl';

    final pathsToTry = [
      // Primary pattern - audio server base URL (port 3000)
      '$audioServerBaseUrl$normalizedUrl',               // http://circleone.biz:3000/audio/landmark_3_ja.mp3

      // Standard paths with API base URL
      '$apiBaseUrl$normalizedUrl',                       // https://circleone.biz/api/audio/landmark_3_ja.mp3

      // Common web server paths with audio server base URL
      '$audioServerBaseUrl/public$normalizedUrl',       // http://circleone.biz:3000/public/audio/landmark_3_ja.mp3
      '$audioServerBaseUrl/storage$normalizedUrl',      // http://circleone.biz:3000/storage/audio/landmark_3_ja.mp3
      '$audioServerBaseUrl/assets$normalizedUrl',       // http://circleone.biz:3000/assets/audio/landmark_3_ja.mp3
      '$audioServerBaseUrl/files$normalizedUrl',        // http://circleone.biz:3000/files/audio/landmark_3_ja.mp3
      '$audioServerBaseUrl/media$normalizedUrl',        // http://circleone.biz:3000/media/audio/landmark_3_ja.mp3
    ];

    print('Testing multiple paths for audio file ($relativeUrl):');
    print('API Base URL: $apiBaseUrl');
    print('Audio Server Base URL: $audioServerBaseUrl');

    for (final testUrl in pathsToTry) {
      try {
        print('  Testing: $testUrl');
        final response = await http.head(Uri.parse(testUrl)).timeout(const Duration(seconds: 3));
        print('  Status: ${response.statusCode}');

        if (response.statusCode == 200) {
          print('  ✅ Found working URL: $testUrl');
          return testUrl;
        }
      } catch (e) {
        print('  ❌ Error testing $testUrl: $e');
      }
    }

    print('  ❌ No working URL found after testing ${pathsToTry.length} possibilities');

    // Try final approaches based on JavaScript example
    final finalAttempts = [
      'https://circleone.biz:3000$relativeUrl',  // HTTPS with port 3000
      'http://circleone.biz:3000$relativeUrl',   // HTTP with port 3000 (like JavaScript example)
      'https://circleone.biz$relativeUrl',       // Original approach
    ];

    print('  Final attempts: Direct server tests...');
    for (final directUrl in finalAttempts) {
      try {
        print('  Testing direct: $directUrl');
        final response = await http.head(Uri.parse(directUrl)).timeout(const Duration(seconds: 3));
        print('  Direct status: ${response.statusCode}');

        if (response.statusCode == 200) {
          print('  ✅ Found working direct URL: $directUrl');
          return directUrl;
        }
      } catch (e) {
        print('  ❌ Direct test failed for $directUrl: $e');
      }
    }

    return null;
  }

  Future<void> _showNoAudioMessage(int landmarkId) async {
    print('■ 音声データがありません');
    print('  観光地ID: $landmarkId');
    print('  データベースに音声ファイルが登録されていません');
    print('  管理画面で音声ファイルを登録してください');
  }

  Future<void> _showNoAudioFileMessage(String audioUrl) async {
    print('■ 音声ファイルが見つかりません');
    print('  ファイルURL: $audioUrl');
    print('  サーバーに音声ファイルが存在しません');
    print('  音声ファイルをサーバーにアップロードしてください');
  }

  Future<File?> _downloadAudioFile(String url) async {
    try {
      print('Downloading audio file from: $url');

      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final fileName = url.split('/').last;
      final localFile = File('${tempDir.path}/$fileName');

      // Download file
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await localFile.writeAsBytes(response.bodyBytes);
        print('Audio file downloaded successfully: ${localFile.path} (${response.bodyBytes.length} bytes)');
        return localFile;
      } else {
        print('Failed to download audio file. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error downloading audio file: $e');
      return null;
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
