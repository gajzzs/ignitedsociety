import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/report_screen.dart';
import 'utils/location_utils.dart';
import 'services/user_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with current platform options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set the background messaging handler early on
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Run user registration, token generation, and start location updates
  await UserService.initialize();

  runApp(const IgnitedSocietyApp());
}

class IgnitedSocietyApp extends StatelessWidget {
  const IgnitedSocietyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IgnitedSociety',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  LatLng? _markedLocation;

  late final List<Widget> _screens = [
    HomeScreen(
      onLocationSelected: (latLng) => setState(() => _markedLocation = latLng),
    ),
    const Center(child: Text('Analytics')),
    const Center(child: Text('Profile')),
  ];

  Future<void> _openReportScreen() async {
    LatLng? location = _markedLocation;

    if (location == null) {
      try {
        final position = await determineCurrentPosition();
        location = LatLng(position.latitude, position.longitude);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
        return;
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ReportScreen(location: location)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green,
        onPressed: _openReportScreen,
        shape: const CircleBorder(),
        child: const Icon(Icons.camera_alt, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: const Icon(Icons.home),
              color: _currentIndex == 0 ? Theme.of(context).primaryColor : Colors.grey,
              onPressed: () => setState(() => _currentIndex = 0),
            ),
            IconButton(
              icon: const Icon(Icons.analytics),
              color: _currentIndex == 1 ? Theme.of(context).primaryColor : Colors.grey,
              onPressed: () => setState(() => _currentIndex = 1),
            ),
            const SizedBox(width: 48), // Space for FAB
            IconButton(
              icon: const Icon(Icons.leaderboard),
              color: Colors.grey,
              onPressed: () {}, // Leaderboard / gamification
            ),
            IconButton(
              icon: const Icon(Icons.person),
              color: _currentIndex == 2 ? Theme.of(context).primaryColor : Colors.grey,
              onPressed: () => setState(() => _currentIndex = 2),
            ),
          ],
        ),
      ),
    );
  }
}
