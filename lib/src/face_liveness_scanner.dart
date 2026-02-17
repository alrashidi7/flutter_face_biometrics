import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'export_errors.dart';
import 'utils/image_utils.dart';

/// Liveness: require eyes to close then open (blink) before capture.
const double _kEyeClosedThreshold = 0.25;
const double _kEyeOpenThreshold = 0.4;

/// Oval region (normalized 0–1) where face must be. Generous to match visual overlay across devices.
const double _kOvalHalfWidth = 0.45;   // 90% of frame width
const double _kOvalHalfHeight = 0.40;  // 80% of frame height

/// Face size (fraction of image): reject too close or too far.
const double _kFaceSizeMin = 0.20;
const double _kFaceSizeMax = 0.48;

/// Head pose: max abs angle (degrees) to consider "looking at camera".
const double _kMaxHeadAngleDeg = 18.0;

/// Progress through scan steps so the user sees what they passed.
class ScanProgress {
  const ScanProgress({
    this.faceDetected = false,
    this.faceInOval = false,
    this.faceGoodSize = false,
    this.lookingAtCamera = false,
  });

  factory ScanProgress.initial() =>
      const ScanProgress(faceDetected: false, faceInOval: false, faceGoodSize: false, lookingAtCamera: false);

  final bool faceDetected;
  final bool faceInOval;
  final bool faceGoodSize;
  final bool lookingAtCamera;
}

/// Widget that captures a liveness-verified selfie with exactly one face.
///
/// - Uses ML Kit for face detection; requires **exactly one** face (throws
///   [NoFaceDetectedException] / [MultipleFacesDetectedException] otherwise).
/// - Implements a simple liveness check: "blink to capture" to reduce photo spoofing.
/// - On success, saves the frame to a temp file and calls [onCaptured].
/// - On error, calls [onError] with the appropriate [BiometricExportException].
class FaceLivenessScanner extends StatefulWidget {
  const FaceLivenessScanner({
    super.key,
    required this.onCaptured,
    required this.onError,
    this.instructionText = 'Position your face and blink to capture',
    this.minFaceSize = 0.15,
  });

  /// Called when a single face is detected and liveness (blink) passed. [imageFile] is a temp JPEG.
  final void Function(File imageFile) onCaptured;

  /// Called when an error occurs (no face, multiple faces, or other).
  final void Function(BiometricExportException) onError;

  /// Shown above the camera preview.
  final String instructionText;

  /// Minimum face size (0.0–1.0) for ML Kit.
  final double minFaceSize;

  @override
  State<FaceLivenessScanner> createState() => _FaceLivenessScannerState();
}

class _FaceLivenessScannerState extends State<FaceLivenessScanner> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
      enableLandmarks: true,
      enableContours: false,
      enableClassification: true,
      enableTracking: false,
    ),
  );

  bool _isProcessing = false;
  bool _isStreaming = false;
  CameraImage? _latestImage;
  bool _eyesWereClosed = false;
  bool _captured = false;
  String _statusMessage = 'Initializing...';
  ScanProgress _progress = ScanProgress.initial();
  bool _initialized = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _initError = 'No cameras available';
          _statusMessage = _initError!;
        });
        return;
      }
      final front = _cameras
          .where((c) => c.lensDirection == CameraLensDirection.front)
          .toList();
      final camera = front.isNotEmpty ? front.first : _cameras.first;

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initialized = true;
        _statusMessage = widget.instructionText;
      });
      _startStream();
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _statusMessage = 'Camera error: $_initError';
        });
        widget.onError(EmbeddingException('Camera initialization failed', e.toString()));
      }
    }
  }

  void _startStream() {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isStreaming) {
      return;
    }
    _isStreaming = true;
    _controller!.startImageStream((CameraImage image) {
      if (_isProcessing || _captured) {
        return;
      }
      _isProcessing = true;
      _processFrame(image).whenComplete(() => _isProcessing = false);
    });
  }

  InputImage? _toInputImage(CameraImage image) {
    final (nv21, width, height) = cameraImageToNv21(image);
    if (width == 0 || height == 0) return null;
    final rotation = InputImageRotationValue.fromRawValue(
      _controller?.description.sensorOrientation ?? 0,
    );
    if (rotation == null) return null;
    final metadata = InputImageMetadata(
      size: Size(width.toDouble(), height.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: width,
    );
    return InputImage.fromBytes(bytes: nv21, metadata: metadata);
  }

  /// Returns true if (nx, ny) is inside the oval. nx, ny in 0–1.
  bool _isInsideOval(double nx, double ny) {
    final dx = (nx - 0.5) / _kOvalHalfWidth;
    final dy = (ny - 0.5) / _kOvalHalfHeight;
    return dx * dx + dy * dy <= 1.0;
  }

  /// Check face position, size, and head pose. Returns progress and next step.
  ({ScanProgress progress, String nextStep, bool canCapture}) _checkFace(
    Face face,
    double imageWidth,
    double imageHeight,
  ) {
    final rect = face.boundingBox;
    final centerX = (rect.left + rect.right) / 2;
    final centerY = (rect.top + rect.bottom) / 2;
    final nx = centerX / imageWidth;
    final ny = centerY / imageHeight;
    final faceSizeNorm = (rect.width / imageWidth + rect.height / imageHeight) / 2;

    final inOval = _isInsideOval(nx, ny);
    final goodSize = faceSizeNorm >= _kFaceSizeMin && faceSizeNorm <= _kFaceSizeMax;
    final headY = face.headEulerAngleY ?? 0.0;
    final headZ = face.headEulerAngleZ ?? 0.0;
    final headAnglesAvailable = face.headEulerAngleY != null && face.headEulerAngleZ != null;
    final lookingAtCamera = !headAnglesAvailable ||
        (headAnglesAvailable &&
            headY.abs() <= _kMaxHeadAngleDeg &&
            headZ.abs() <= _kMaxHeadAngleDeg);

    final progress = ScanProgress(
      faceDetected: true,
      faceInOval: inOval,
      faceGoodSize: goodSize,
      lookingAtCamera: lookingAtCamera,
    );

    if (!inOval) {
      return (progress: progress, nextStep: 'Center your face in the oval', canCapture: false);
    }
    if (!goodSize) {
      if (faceSizeNorm > _kFaceSizeMax) {
        return (progress: progress, nextStep: 'Move back – face too close', canCapture: false);
      }
      return (progress: progress, nextStep: 'Move closer – face too far', canCapture: false);
    }
    if (!lookingAtCamera) {
      return (progress: progress, nextStep: 'Look straight at the camera', canCapture: false);
    }
    return (progress: progress, nextStep: 'Blink to capture', canCapture: true);
  }

  Future<void> _processFrame(CameraImage image) async {
    final input = _toInputImage(image);
    if (input == null) return;

    if (_captured) return;
    _latestImage = image;

    final metadata = input.metadata;
    if (metadata == null) return;
    final imageWidth = metadata.size.width;
    final imageHeight = metadata.size.height;

    final faces = await _faceDetector.processImage(input);

    if (!mounted || _captured) return;

    if (faces.isEmpty) {
      setState(() {
        _progress = ScanProgress.initial();
        _statusMessage = 'No face detected – look at the camera';
      });
      return;
    }
    if (faces.length > 1) {
      _stopStream();
      widget.onError(const MultipleFacesDetectedException(
        'Please ensure only one person is in frame',
      ));
      return;
    }

    final face = faces.single;
    final check = _checkFace(face, imageWidth, imageHeight);

    if (!check.canCapture) {
      setState(() {
        _progress = check.progress;
        _statusMessage = check.nextStep;
      });
      return;
    }

    final leftOpen = face.leftEyeOpenProbability ?? 0;
    final rightOpen = face.rightEyeOpenProbability ?? 0;

    if (leftOpen < _kEyeClosedThreshold && rightOpen < _kEyeClosedThreshold) {
      _eyesWereClosed = true;
    }
    if (_eyesWereClosed &&
        leftOpen >= _kEyeOpenThreshold &&
        rightOpen >= _kEyeOpenThreshold) {
      _captured = true;
      _stopStream();
      await _captureAndDeliver();
    } else {
      setState(() {
        _progress = check.progress;
        _statusMessage = check.nextStep;
      });
    }
  }

  Future<void> _captureAndDeliver() async {
    if (_latestImage == null) {
      widget.onError(const NoFaceDetectedException('No frame to capture'));
      return;
    }
    try {
      final orientation = _controller?.description.sensorOrientation ?? 0;
      final file = await cameraImageToTempFile(
        _latestImage!,
        sensorOrientation: orientation,
      );
      if (mounted) {
        widget.onCaptured(file);
      }
    } catch (e) {
      if (mounted) {
        widget.onError(EmbeddingException('Failed to save capture', e.toString()));
      }
    }
  }

  void _stopStream() {
    if (!_isStreaming || _controller == null) return;
    _controller!.stopImageStream();
    _isStreaming = false;
  }

  @override
  void dispose() {
    _stopStream();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            _initError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }
    if (!_initialized || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final aspectRatio = _controller!.value.aspectRatio;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: CameraPreview(_controller!),
          ),
        ),
        _InstructionOverlay(progress: _progress, nextStep: _statusMessage),
      ],
    );
  }
}

/// Clear instructions overlaid on the camera preview, with progress and next step.
class _InstructionOverlay extends StatelessWidget {
  const _InstructionOverlay({required this.progress, required this.nextStep});

  final ScanProgress progress;
  final String nextStep;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _InstructionStrip(
          icon: Icons.face_retouching_natural_rounded,
          text: 'Position your face in the oval',
          subtext: 'Look straight at the camera',
        ),
        const Spacer(),
        _ProgressAndNextStep(progress: progress, nextStep: nextStep),
      ],
    );
  }
}

class _ProgressAndNextStep extends StatelessWidget {
  const _ProgressAndNextStep({required this.progress, required this.nextStep});

  final ScanProgress progress;
  final String nextStep;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                _ProgressChip(done: progress.faceDetected, label: 'Face detected'),
                _ProgressChip(done: progress.faceInOval, label: 'In oval'),
                _ProgressChip(done: progress.faceGoodSize, label: 'Distance OK'),
                _ProgressChip(done: progress.lookingAtCamera, label: 'Looking straight'),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              nextStep,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressChip extends StatelessWidget {
  const _ProgressChip({required this.done, required this.label});

  final bool done;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: done ? Colors.green.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done)
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16)
          else
            Icon(Icons.radio_button_unchecked_rounded, color: Colors.white.withValues(alpha: 0.6), size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: done ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionStrip extends StatelessWidget {
  const _InstructionStrip({
    required this.icon,
    required this.text,
    this.subtext,
  });

  final IconData icon;
  final String text;
  final String? subtext;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
      ),
      child: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (subtext != null && subtext!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtext!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
