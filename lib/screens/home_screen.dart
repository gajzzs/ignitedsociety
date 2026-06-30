import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/location_utils.dart';

enum _MapInteractionMode { none, marker, circle }

class HomeScreen extends StatefulWidget {
  /// Called whenever the user places a marker, or finishes drawing a
  /// circle, on the map. Lets the parent (bottom navigation) know which
  /// coordinates to use when the camera/report button is pressed.
  final ValueChanged<LatLng>? onLocationSelected;

  const HomeScreen({super.key, this.onLocationSelected});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? _mapController;
  // Approximating Varanasi coordinates as shown in the UI image reference
  final LatLng _initialCenter = const LatLng(25.3176, 82.9739);
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};

  _MapInteractionMode _mode = _MapInteractionMode.none;
  LatLng? _pendingCircleCenter;
  LatLng? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _addMockMarkers();
  }

  void _addMockMarkers() {
    setState(() {
      _markers.add(
        Marker(
          markerId: const MarkerId('mock_1'),
          position: const LatLng(25.3180, 82.9740),
          infoWindow: const InfoWindow(title: 'Pothole', snippet: 'Reported 2 hours ago'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('mock_2'),
          position: const LatLng(25.3170, 82.9730),
          infoWindow: const InfoWindow(title: 'Garbage', snippet: 'High Urgency'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
      );
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  String _formatLatLng(LatLng p) =>
      '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _setMode(_MapInteractionMode mode) {
    setState(() {
      _mode = _mode == mode ? _MapInteractionMode.none : mode;
      _pendingCircleCenter = null;
    });
  }

  void _clearUserSelections() {
    setState(() {
      _markers.removeWhere(
        (m) => m.markerId.value == 'user_selected' || m.markerId.value == 'circle_center',
      );
      _circles.clear();
      _pendingCircleCenter = null;
      _selectedLocation = null;
      _mode = _MapInteractionMode.none;
    });
  }

  void _handleMapTap(LatLng point) {
    switch (_mode) {
      case _MapInteractionMode.marker:
        _placeMarker(point);
        break;
      case _MapInteractionMode.circle:
        _handleCircleTap(point);
        break;
      case _MapInteractionMode.none:
        break;
    }
  }

  void _placeMarker(LatLng point) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'user_selected');
      _markers.add(
        Marker(
          markerId: const MarkerId('user_selected'),
          position: point,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: 'Selected Location', snippet: _formatLatLng(point)),
        ),
      );
      _selectedLocation = point;
    });
    widget.onLocationSelected?.call(point);
    _showSnack('Marker placed at ${_formatLatLng(point)}');
  }

  void _handleCircleTap(LatLng point) {
    if (_pendingCircleCenter == null) {
      setState(() {
        _pendingCircleCenter = point;
        _markers.removeWhere((m) => m.markerId.value == 'circle_center');
        _markers.add(
          Marker(
            markerId: const MarkerId('circle_center'),
            position: point,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
            infoWindow: InfoWindow(title: 'Circle Center', snippet: _formatLatLng(point)),
          ),
        );
      });
      _showSnack('Center set at ${_formatLatLng(point)}. Tap again to set radius.');
      return;
    }

    final center = _pendingCircleCenter!;
    final double radius = Geolocator.distanceBetween(
      center.latitude,
      center.longitude,
      point.latitude,
      point.longitude,
    );

    setState(() {
      _circles.removeWhere((c) => c.circleId.value == 'user_circle');
      _circles.add(
        Circle(
          circleId: const CircleId('user_circle'),
          center: center,
          radius: radius == 0 ? 50 : radius,
          fillColor: Colors.blue.withOpacity(0.15),
          strokeColor: Colors.blue,
          strokeWidth: 2,
        ),
      );
      _selectedLocation = center;
      _pendingCircleCenter = null;
    });

    widget.onLocationSelected?.call(center);
    _showSnack(
      'Circle drawn: ${radius.toStringAsFixed(1)} m radius, center ${_formatLatLng(center)}',
    );
  }

  Future<void> _goToCurrentLocation() async {
    try {
      Position position = await determineCurrentPosition();
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 16.0,
          ),
        ),
      );
    } catch (e) {
      _showSnack('Could not get location: $e');
    }
  }

  Widget _buildToolbar() {
    return Positioned(
      top: 16,
      left: 16,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Place marker',
                icon: Icon(
                  Icons.location_pin,
                  color: _mode == _MapInteractionMode.marker ? Colors.blue : Colors.grey[600],
                ),
                onPressed: () => _setMode(_MapInteractionMode.marker),
              ),
              IconButton(
                tooltip: 'Draw circle (tap center, then tap edge)',
                icon: Icon(
                  Icons.circle_outlined,
                  color: _mode == _MapInteractionMode.circle ? Colors.blue : Colors.grey[600],
                ),
                onPressed: () => _setMode(_MapInteractionMode.circle),
              ),
              IconButton(
                tooltip: 'Clear selections',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: _clearUserSelections,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoordinatesBanner() {
    if (_selectedLocation == null) return const SizedBox.shrink();
    return Positioned(
      top: 16,
      right: 16,
      left: 80,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.my_location, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _formatLatLng(_selectedLocation!),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('IgnitedSociety', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            Text('Current Location: Varanasi, UP', style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _initialCenter,
              zoom: 15.0,
            ),
            markers: _markers,
            circles: _circles,
            onTap: _handleMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),
          _buildToolbar(),
          _buildCoordinatesBanner(),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white,
              onPressed: _goToCurrentLocation,
              child: const Icon(Icons.my_location, color: Colors.black),
            ),
          )
        ],
      ),
    );
  }
}
