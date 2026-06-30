import 'package:geolocator/geolocator.dart';

/// Resolves the device's current GPS position, handling service/permission
/// checks. Throws a descriptive String error if location can't be obtained.
Future<Position> determineCurrentPosition() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw 'Location services are disabled.';
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw 'Location permissions are denied';
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw 'Location permissions are permanently denied.';
  }

  return await Geolocator.getCurrentPosition();
}
