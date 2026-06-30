import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/diagnostic_service.dart';
import '../models/verification_output.dart';
import '../utils/location_utils.dart';

class ReportScreen extends StatefulWidget {
  /// Coordinates passed in from the home map — either the device's current
  /// GPS position, or a location the user marked/circled on the map.
  final LatLng? location;

  const ReportScreen({super.key, this.location});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _currentStep = 0;
  final int _totalSteps = 3;

  // Step 1: Camera / Media variables
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  List<XFile> _imageFiles = [];
  final ImagePicker _picker = ImagePicker();
  bool _isCameraInitialized = false;

  // Step 2: Details variables
  final TextEditingController _notesController = TextEditingController();
  String _urgency = 'Medium';
  bool _isAnalyzing = false;
  VerificationOutput? _verificationResult;
  String? _analysisError;
  Position? _resolvedPosition;

  // Step 3: Location / Submission variables
  final String _fallbackLocation = "Varanasi, UP (25.3176° N, 82.9739° E)";

  String get _locationText {
    if (_resolvedPosition != null) {
      return '${_resolvedPosition!.latitude.toStringAsFixed(5)}° N, '
          '${_resolvedPosition!.longitude.toStringAsFixed(5)}° E';
    }
    final loc = widget.location;
    if (loc != null) {
      return '${loc.latitude.toStringAsFixed(5)}° N, ${loc.longitude.toStringAsFixed(5)}° E';
    }
    return _fallbackLocation;
  }

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _cameraController = CameraController(
          _cameras[0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Camera init error: $e");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      final XFile photo = await _cameraController!.takePicture();
      setState(() {
        _imageFiles.add(photo);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error taking photo: $e')),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final List<XFile> selected = await _picker.pickMultiImage();
      if (selected.isNotEmpty) {
        setState(() {
          _imageFiles.addAll(selected);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting image: $e')),
      );
    }
  }

  void _viewFullScreenImage(int initialIndex) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              PageView.builder(
                controller: PageController(initialPage: initialIndex),
                itemCount: _imageFiles.length,
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    child: Center(
                      child: Image.file(
                        File(_imageFiles[index].path),
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                top: 20,
                left: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddPhotoOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),
              if (_isCameraInitialized)
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Take a Photo'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _currentStep = 0;
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _analyzeIssue() async {
    if (_imageFiles.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _verificationResult = null;
      _analysisError = null;
    });

    try {
      // 1. Resolve current coordinates from the location service.
      double latitude;
      double longitude;
      if (widget.location != null) {
        // A location was explicitly picked on the map — prefer it.
        latitude = widget.location!.latitude;
        longitude = widget.location!.longitude;
      } else {
        final position = await determineCurrentPosition();
        if (mounted) {
          setState(() => _resolvedPosition = position);
        }
        latitude = position.latitude;
        longitude = position.longitude;
      }

      // 2. Send images + description + coordinates, wait for the agent.
      final result = await DiagnosticService.analyzeIssue(
        images: _imageFiles.map((x) => File(x.path)).toList(),
        description: _notesController.text,
        latitude: latitude,
        longitude: longitude,
      );

      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _verificationResult = result;
        // Sync urgency from the AI's risk score so Step 3 reflects it.
        if (result.riskAssessment != null) {
          final score = result.riskAssessment!.riskScore;
          _urgency = score >= 70 ? 'High' : (score >= 40 ? 'Medium' : 'Low');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _analysisError = e.toString();
      });
    }
  }

  void _nextStep() {
    if (_currentStep == 0 && _imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture or pick an image first.')),
      );
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep++;
      });
      if (_currentStep == 1) {
        _analyzeIssue();
      }
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  // --- Step 1: Full Screen Camera View ---
  Widget _buildStepCapture() {
    // Camera Preview or Fallback
    if (!_isCameraInitialized) {
      return Container(
        color: Colors.black,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_imageFiles.isEmpty) ...[
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                'Initializing Camera...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ] else ...[
              const Icon(Icons.image, size: 64, color: Colors.white54),
              const SizedBox(height: 10),
              Text(
                '${_imageFiles.length} Photos Selected',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              // Show horizontal thumbnail list
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _imageFiles.length,
                  itemBuilder: (context, index) {
                    final file = _imageFiles[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _viewFullScreenImage(index),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(file.path),
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _imageFiles.removeAt(index);
                                });
                              },
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.close, color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _pickFromGallery,
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick from Gallery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_cameraController!),

        // Thumbnail Strip overlay above camera controls
        if (_imageFiles.isNotEmpty)
          Positioned(
            bottom: 150,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 90,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _imageFiles.length,
                itemBuilder: (context, index) {
                  final file = _imageFiles[index];
                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    width: 90,
                    height: 90,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => _viewFullScreenImage(index),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(file.path),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _imageFiles.removeAt(index);
                              });
                            },
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

        // Camera Overlay Controls
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Gallery Button
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.photo_library, color: Colors.white, size: 28),
                  onPressed: _pickFromGallery,
                ),
              ),
              // Capture Button
              GestureDetector(
                onTap: _takePicture,
                child: Container(
                  height: 80,
                  width: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              // Image count badge
              _imageFiles.isNotEmpty
                  ? Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_imageFiles.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : const SizedBox(width: 56),
            ],
          ),
        ),
      ],
    );
  }

  // --- Step 2: Issue Details Form ---
  Widget _buildStepDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Captured Photos Carousel
          if (_imageFiles.isNotEmpty) ...[
            const Text(
              'Captured Photos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _imageFiles.length + 1,
                itemBuilder: (context, index) {
                  if (index == _imageFiles.length) {
                    // Add Photo button card at the end
                    return GestureDetector(
                      onTap: () => _showAddPhotoOptions(context),
                      child: Container(
                        width: 120,
                        height: 120,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!, width: 1),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, color: Colors.grey[600]),
                            const SizedBox(height: 8),
                            Text(
                              'Add Photo',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final file = _imageFiles[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: () => _viewFullScreenImage(index),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(file.path),
                              height: 120,
                              width: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _imageFiles.removeAt(index);
                              });
                            },
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Notes
          TextField(
            controller: _notesController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Notes & Description',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              hintText: 'Provide details about the issue...',
            ),
          ),
          const SizedBox(height: 20),

          // Urgency Custom Card Selector
          const Text(
            'Urgency Level',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Row(
            children: ['Low', 'Medium', 'High'].map((level) {
              final isSelected = _urgency == level;
              Color cardColor = Colors.grey[200]!;
              Color textColor = Colors.black;
              if (isSelected) {
                if (level == 'Low') {
                  cardColor = Colors.green[100]!;
                  textColor = Colors.green[800]!;
                } else if (level == 'Medium') {
                  cardColor = Colors.orange[100]!;
                  textColor = Colors.orange[800]!;
                } else {
                  cardColor = Colors.red[100]!;
                  textColor = Colors.red[800]!;
                }
              }

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _urgency = level;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? textColor : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        level,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 25),

          if (_isAnalyzing) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                border: Border.all(color: Colors.teal[200]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'AI is analyzing the issue...',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal[800], fontSize: 14),
                  ),
                ],
              ),
            ),
          ] else if (_analysisError != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red[200]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Analysis failed',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800], fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_analysisError!, style: TextStyle(fontSize: 13, color: Colors.red[900])),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _analyzeIssue,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ] else if (_verificationResult != null) ...[
            _buildVerificationResultCard(_verificationResult!),
          ],
        ],
      ),
    );
  }

  // --- Renders the parsed VerificationOutput as tags + risk summary ---
  Widget _buildVerificationResultCard(VerificationOutput result) {
    final cat = result.issueCategorization;
    final risk = result.riskAssessment;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text(
                'AI Verification',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 15),
              ),
            ],
          ),
          const Divider(),

          // Clarifying questions take priority — the agent needs more info.
          if (result.needsClarification) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline, color: Colors.amber[800], size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'A few more details would help',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber[900], fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...result.clarifyingQuestions.map(
                    (q) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('•  $q', style: TextStyle(fontSize: 13, color: Colors.amber[900])),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Category tag, in the category's color.
          if (cat != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(cat.icon, color: Colors.white, size: 18),
                  label: Text(
                    cat.category,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: cat.color,
                ),
                if (cat.subcategory != null)
                  Chip(
                    label: Text(cat.subcategory!),
                    backgroundColor: cat.color.withOpacity(0.12),
                    labelStyle: TextStyle(color: cat.color, fontWeight: FontWeight.w600),
                  ),
                Chip(
                  label: Text('${(cat.confidence * 100).toStringAsFixed(0)}% confidence'),
                  backgroundColor: Colors.grey[200],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              cat.visualEvidenceSummary,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ],

          // Risk badge.
          if (risk != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: risk.color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: risk.color.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed, color: risk.color, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Risk Score: ${risk.riskScore}/100',
                        style: TextStyle(fontWeight: FontWeight.bold, color: risk.color, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(risk.recommendation, style: const TextStyle(fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepSubmit() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 80, color: Colors.blue),
          const SizedBox(height: 20),
          const Text(
            'Ready to Submit',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'Please review your report details before submitting to the community map.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 30),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.location_on, color: Colors.blue),
                    title: const Text('Location'),
                    subtitle: Text(_locationText),
                  ),
                  if (_verificationResult?.issueCategorization != null)
                    ListTile(
                      leading: Icon(
                        _verificationResult!.issueCategorization!.icon,
                        color: _verificationResult!.issueCategorization!.color,
                      ),
                      title: const Text('Category'),
                      subtitle: Text(_verificationResult!.issueCategorization!.category),
                    ),
                  ListTile(
                    leading: const Icon(Icons.photo_library, color: Colors.blue),
                    title: const Text('Photos'),
                    subtitle: Text('${_imageFiles.length} photos attached'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.warning, color: Colors.orange),
                    title: const Text('Urgency'),
                    subtitle: Text(_urgency),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description, color: Colors.grey),
                    title: const Text('Description'),
                    subtitle: Text(
                      _notesController.text.isEmpty ? 'No notes provided.' : _notesController.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Issue submitted successfully!')),
              );
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Submit Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- Sleek Custom Horizontal Progress Bar ---
  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      color: Colors.white,
      child: Row(
        children: List.generate(_totalSteps, (index) {
          final isCompleted = index < _currentStep;
          final isCurrent = index == _currentStep;
          return Expanded(
            child: Row(
              children: [
                // Step Circle
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? Colors.blue
                        : isCurrent
                            ? Colors.blue[100]
                            : Colors.grey[200],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCurrent || isCompleted ? Colors.blue : Colors.grey[350]!,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isCurrent ? Colors.blue[800] : Colors.grey[650],
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                  ),
                ),
                // Connector Line (except for last step)
                if (index < _totalSteps - 1)
                  Expanded(
                    child: Container(
                      height: 3,
                      color: isCompleted ? Colors.blue : Colors.grey[200],
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Current step body
    Widget stepBody;
    if (_currentStep == 0) {
      stepBody = _buildStepCapture();
    } else if (_currentStep == 1) {
      stepBody = _buildStepDetails();
    } else {
      stepBody = _buildStepSubmit();
    }

    return Scaffold(
      backgroundColor: _currentStep == 0 ? Colors.black : Colors.white,
      appBar: AppBar(
        title: const Text('Report Issue'),
        centerTitle: true,
        backgroundColor: _currentStep == 0 ? Colors.black : Colors.white,
        foregroundColor: _currentStep == 0 ? Colors.white : Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _currentStep == 0 ? () => Navigator.pop(context) : _prevStep,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Stepper
            _buildStepIndicator(),
            Expanded(child: stepBody),

            // Bottom Navigation for Step 1 & 2
            if (_currentStep < _totalSteps - 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: _currentStep == 0 ? Colors.black : Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back/Cancel
                    TextButton(
                      onPressed: _currentStep == 0 ? () => Navigator.pop(context) : _prevStep,
                      child: Text(
                        _currentStep == 0 ? 'Cancel' : 'Back',
                        style: TextStyle(
                          color: _currentStep == 0 ? Colors.white70 : Colors.black54,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    // Next Button (Only active in Step 1 if image is picked/taken)
                    ElevatedButton(
                      onPressed: (_currentStep == 0 && _imageFiles.isEmpty) ? null : _nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
