import 'package:flutter/material.dart';
import 'screens/bus_guide_screen.dart';
import 'screens/proper_location_guide_screen.dart';

void main() {
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
      home: const AppHomePage(),
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
