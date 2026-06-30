import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_id/android_id.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../utils/location_utils.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Background notification received: ${message.notification?.title} - ${message.notification?.body}");
}

class UserService {
  static const String _userIdKey = 'registered_user_id';
  static StreamSubscription<Position>? _positionStreamSubscription;

  /// Main entry point to initialize user registration and notifications
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString(_userIdKey);

      // 1. Collect hardware and platform identifiers
      String? androidId;
      String? uniqueIdentifier;

      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        androidId = await const AndroidId().getId();
        final androidInfo = await deviceInfo.androidInfo;
        uniqueIdentifier = androidInfo.id; // Build ID
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        uniqueIdentifier = iosInfo.identifierForVendor;
      }

      // Fallback uniqueIdentifier if none found
      uniqueIdentifier ??= 'unknown_${DateTime.now().millisecondsSinceEpoch}';

      // 2. Request FCM permissions & get token
      final fcmToken = await _setupNotifications();

      // 3. Gather initial location
      List<double> initialLocation = [0.0, 0.0];
      try {
        final position = await determineCurrentPosition();
        initialLocation = [position.latitude, position.longitude];
      } catch (e) {
        debugPrint("Could not obtain initial location: $e");
      }

      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();

      if (userId == null) {
        // App opened for the first time on this device
        // Generate unique user id based on "date & time first appeared" and androidId
        final firstAppearedTime = now.millisecondsSinceEpoch;
        final cleanId = androidId ?? uniqueIdentifier;
        userId = 'user_${cleanId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}_$firstAppearedTime';

        // Create user document in Firestore
        await firestore.collection('users').doc(userId).set({
          'androidId': androidId ?? 'N/A',
          'uniqueIdentifier': uniqueIdentifier,
          'lastlocation': initialLocation,
          'fcmTokens': fcmToken != null ? [fcmToken] : [],
          'issues': [],
          'firstAppeared': Timestamp.fromDate(now),
          'lastOpened': Timestamp.fromDate(now),
          'xp': 0,
          'level': 1,
          'contributionList': [],
        });

        // Save generated user ID locally
        await prefs.setString(_userIdKey, userId);
        debugPrint("Device registered for the first time with User ID: $userId");
      } else {
        // App opened subsequent times
        // Prepare data to update
        final Map<String, dynamic> updateData = {
          'lastOpened': Timestamp.fromDate(now),
          'lastlocation': initialLocation,
        };

        if (fcmToken != null) {
          updateData['fcmTokens'] = FieldValue.arrayUnion([fcmToken]);
        }

        // Update the existing user document
        await firestore.collection('users').doc(userId).update(updateData);
        debugPrint("Device registration checked. User ID: $userId updated.");
      }

      // 4. Start listening to location changes to keep updating location in array/field
      startLocationUpdates(userId);

    } catch (e) {
      debugPrint("Error in UserService initialization: $e");
    }
  }

  /// Request notification permissions and fetch the FCM token
  static Future<String?> _setupNotifications() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('Notification user permission status: ${settings.authorizationStatus}');

      // Get token
      final token = await messaging.getToken();
      debugPrint('FCM Token generated: $token');

      // Listen to token refresh
      messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM Token refreshed: $newToken');
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString(_userIdKey);
        if (userId != null) {
          await FirebaseFirestore.instance.collection('users').doc(userId).update({
            'fcmTokens': FieldValue.arrayUnion([newToken]),
          });
        }
      });

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Foreground notification received: ${message.notification?.title} - ${message.notification?.body}');
      });

      // User clicked notification listener
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Notification clicked: ${message.notification?.title}');
      });

      return token;
    } catch (e) {
      debugPrint("Error setting up notifications/FCM: $e");
      return null;
    }
  }

  /// Keep updating the device's location in Firestore when it changes
  static void startLocationUpdates(String userId) {
    _positionStreamSubscription?.cancel();
    
    // We register a location stream with Geolocator
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Trigger update only if user moves at least 10 meters
      ),
    ).listen(
      (Position position) async {
        try {
          await FirebaseFirestore.instance.collection('users').doc(userId).update({
            'lastlocation': [position.latitude, position.longitude],
          });
          debugPrint('Real-time location updated in Firestore: [${position.latitude}, ${position.longitude}]');
        } catch (e) {
          debugPrint('Error updating real-time location in Firestore: $e');
        }
      },
      onError: (error) {
        debugPrint('Error in location update stream: $error');
      },
    );
  }

  /// Safely dispose location subscription if needed
  static void dispose() {
    _positionStreamSubscription?.cancel();
  }
}
