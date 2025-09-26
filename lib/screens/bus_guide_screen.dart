import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class BusGuideScreen extends StatefulWidget {
  const BusGuideScreen({super.key});

  @override
  State<BusGuideScreen> createState() => _BusGuideScreenState();
}

class _BusGuideScreenState extends State<BusGuideScreen> {
  Position? _currentPosition;
  bool _isLoading = false;
  String _statusMessage = 'バス情報を取得するには位置情報を有効にしてください';

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '位置情報を取得中...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _statusMessage = '位置情報サービスが無効です';
          _isLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _statusMessage = '位置情報の許可が必要です';
            _isLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _statusMessage = '位置情報の許可が永続的に拒否されています';
          _isLoading = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        _statusMessage = '現在位置: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'エラー: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('バスガイド'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _getCurrentLocation,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(
                      Icons.directions_bus,
                      size: 64,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'バスガイドシステム',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_isLoading)
                      const CircularProgressIndicator()
                    else
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  _buildFeatureCard(
                    'QRスキャン',
                    Icons.qr_code_scanner,
                    () => _showFeatureComingSoon('QRスキャン'),
                  ),
                  _buildFeatureCard(
                    '音声ガイド',
                    Icons.volume_up,
                    () => _showFeatureComingSoon('音声ガイド'),
                  ),
                  _buildFeatureCard(
                    '位置追跡',
                    Icons.location_on,
                    () => _showLocationInfo(),
                  ),
                  _buildFeatureCard(
                    '通知設定',
                    Icons.notifications,
                    () => _showFeatureComingSoon('通知設定'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(String title, IconData icon, VoidCallback onTap) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Colors.blue),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFeatureComingSoon(String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(feature),
        content: Text('$featureは近日実装予定です。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showLocationInfo() {
    if (_currentPosition != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('現在位置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('緯度: ${_currentPosition!.latitude}'),
              Text('経度: ${_currentPosition!.longitude}'),
              Text('精度: ${_currentPosition!.accuracy}m'),
              Text('取得時刻: ${DateTime.fromMillisecondsSinceEpoch(_currentPosition!.timestamp.millisecondsSinceEpoch)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    } else {
      _getCurrentLocation();
    }
  }
}