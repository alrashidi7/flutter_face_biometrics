import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'export_errors.dart';
import 'utils/image_utils.dart';

// ─── Liveness thresholds ──────────────────────────────────────────────────────
const double _kEyeClosedThreshold = 0.25;
const double _kEyeOpenThreshold = 0.45;

// ─── Oval guide ───────────────────────────────────────────────────────────────
/// Normalized half-axes of the face oval guide.
/// Wider than the visual oval to account for ML Kit reporting face center in
/// sensor coordinates which can differ from the displayed preview coordinates.
const double _kOvalHalfWidth = 0.42;
const double _kOvalHalfHeight = 0.40;

// ─── Face size ────────────────────────────────────────────────────────────────
const double _kFaceSizeMin = 0.18;
const double _kFaceSizeMax = 0.55;

// ─── Head pose thresholds (degrees) ──────────────────────────────────────────
/// Max yaw (Y-axis, left/right turn).
const double _kMaxYawDeg = 20.0;

/// Max roll (Z-axis, tilt).
const double _kMaxRollDeg = 20.0;

/// Max pitch (X-axis, nod up/down).
const double _kMaxPitchDeg = 20.0;

/// Min eye-open probability for the progress chip indicator only.
/// Not used as a blocking gate — blink detection handles eye-open verification.
const double _kEyesOpenMin = 0.50;

// ─── Progress ─────────────────────────────────────────────────────────────────
/// Tracks which scan conditions the user has satisfied.
class ScanProgress {
  const ScanProgress({
    this.faceDetected = false,
    this.faceInOval = false,
    this.faceGoodSize = false,
    this.lookingAtCamera = false,
    this.eyesOnCamera = false,
  });

  factory ScanProgress.initial() => const ScanProgress();

  final bool faceDetected;
  final bool faceInOval;
  final bool faceGoodSize;

  /// Yaw, roll, and pitch all within threshold (face perpendicular to lens).
  final bool lookingAtCamera;

  /// Both eyes open and directed at lens.
  final bool eyesOnCamera;
}

// ─── Widget ───────────────────────────────────────────────────────────────────
/// Widget that captures a liveness-verified selfie with exactly one face.
///
/// Requirements enforced before accepting the blink capture:
///  1. Single face detected in frame.
///  2. Face centered inside the oval.
///  3. Face at good size (not too close / too far).
///  4. Head perfectly straight: yaw, pitch, and roll all ≤ 12°.
///  5. Both eyes open and directed at the camera.
///  6. Blink (close → open) to confirm liveness.
///
/// The saved capture is **cropped to the face region** (with padding) so the
/// embedding model receives the face only — no background noise.
class FaceLivenessScanner extends StatefulWidget {
  const FaceLivenessScanner({
    super.key,
    required this.onCaptured,
    required this.onError,
    this.instructionText = 'Position your face and blink to capture',
    this.minFaceSize = 0.15,
  });

  /// Called with a face-cropped temp JPEG when liveness passes.
  final void Function(File imageFile) onCaptured;

  /// Called when an error occurs.
  final void Function(BiometricExportException) onError;

  /// Shown above the camera preview.
  final String instructionText;

  /// Minimum face size (0.0–1.0) for ML Kit.
  final double minFaceSize;

  @override
  State<FaceLivenessScanner> createState() => _FaceLivenessScannerState();
}

class _FaceLivenessScannerState extends State<FaceLivenessScanner>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
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

  // The last frame where all checks passed AND eyes were fully open.
  // Used as the capture source so the saved image always shows open eyes
  // in a valid position — not the post-blink re-open frame which may be
  // momentarily blurry or mis-positioned.
  CameraImage? _lastGoodFrame;

  bool _eyesWereClosed = false;
  bool _captured = false;
  String _statusMessage = 'Initializing...';
  ScanProgress _progress = ScanProgress.initial();
  bool _initialized = false;
  String? _initError;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

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
        ResolutionPreset.high,
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
        widget.onError(
            EmbeddingException('Camera initialization failed', e.toString()));
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
      if (_isProcessing || _captured) return;
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

  bool _isInsideOval(double nx, double ny) {
    final dx = (nx - 0.5) / _kOvalHalfWidth;
    final dy = (ny - 0.5) / _kOvalHalfHeight;
    return dx * dx + dy * dy <= 1.0;
  }

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
    final faceSizeNorm =
        (rect.width / imageWidth + rect.height / imageHeight) / 2;

    final inOval = _isInsideOval(nx, ny);
    final goodSize =
        faceSizeNorm >= _kFaceSizeMin && faceSizeNorm <= _kFaceSizeMax;

    // All three head pose axes must be within threshold for a 90° straight shot.
    final yaw = face.headEulerAngleY ?? 0.0;
    final roll = face.headEulerAngleZ ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0;
    final anglesAvailable = face.headEulerAngleY != null &&
        face.headEulerAngleZ != null;
    final lookingAtCamera = !anglesAvailable ||
        (yaw.abs() <= _kMaxYawDeg &&
            roll.abs() <= _kMaxRollDeg &&
            pitch.abs() <= _kMaxPitchDeg);

    // Both eyes must be clearly open and directed at the lens.
    final leftEyeOpen = face.leftEyeOpenProbability ?? 0.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 0.0;
    final eyesOnCamera =
        leftEyeOpen >= _kEyesOpenMin && rightEyeOpen >= _kEyesOpenMin;

    final progress = ScanProgress(
      faceDetected: true,
      faceInOval: inOval,
      faceGoodSize: goodSize,
      lookingAtCamera: lookingAtCamera,
      eyesOnCamera: eyesOnCamera && lookingAtCamera,
    );

    if (!inOval) {
      return (
        progress: progress,
        nextStep: 'Center your face in the oval',
        canCapture: false,
      );
    }
    if (!goodSize) {
      return (
        progress: progress,
        nextStep: faceSizeNorm > _kFaceSizeMax
            ? 'Move back – face too close'
            : 'Move closer – face too far',
        canCapture: false,
      );
    }
    if (!lookingAtCamera) {
      final hint = yaw.abs() > _kMaxYawDeg
          ? 'Turn face straight – do not turn left or right'
          : roll.abs() > _kMaxRollDeg
              ? 'Keep head upright – do not tilt'
              : 'Lift chin straight – do not nod';
      return (progress: progress, nextStep: hint, canCapture: false);
    }
    // eyesOnCamera is shown as a progress chip but is not a blocking gate.
    // Blink detection (close → open) already verifies the eyes are open at
    // capture time, so an extra gate here only causes users to get stuck.
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
      setState(() {
        _progress = check.progress;
        _statusMessage = 'Open your eyes to complete';
      });
    } else if (_eyesWereClosed &&
        leftOpen >= _kEyeOpenThreshold &&
        rightOpen >= _kEyeOpenThreshold) {
      _captured = true;
      _stopStream();
      await _captureAndDeliver();
    } else {
      // Eyes are open and all checks pass — save as candidate capture frame.
      if (leftOpen >= _kEyeOpenThreshold && rightOpen >= _kEyeOpenThreshold) {
        _lastGoodFrame = image;
      }
      setState(() {
        _progress = check.progress;
        _statusMessage = check.nextStep;
      });
    }
  }

  Future<void> _captureAndDeliver() async {
    // Prefer the last good open-eyes frame; fall back to the latest frame.
    final frameToCapture = _lastGoodFrame ?? _latestImage;

    if (frameToCapture == null) {
      widget.onError(const NoFaceDetectedException('No frame to capture'));
      return;
    }
    try {
      final orientation = _controller?.description.sensorOrientation ?? 0;
      final file = await _cameraImageToFaceCropFile(
        frameToCapture,
        null,
        sensorOrientation: orientation,
      );
      if (mounted) widget.onCaptured(file);
    } catch (e) {
      if (mounted) {
        widget.onError(
            EmbeddingException('Failed to save capture', e.toString()));
      }
    }
  }

  /// Converts the camera frame to an upright JPEG ready for face embedding.
  ///
  /// We deliberately send the **full rotated frame** (not a pre-cropped face)
  /// because [FaceVerification.extractFaceRegion] runs its own ML Kit face
  /// detector internally. Sending a tight face-crop as input to that detector
  /// removes the surrounding context it needs to locate the face, causing
  /// "No face detected" even when the face is clearly visible.
  Future<File> _cameraImageToFaceCropFile(
    CameraImage cameraImage,
    Rect? boundingBox, // kept for API compat; not used — full frame is saved
    {
    int sensorOrientation = 0,
  }) async {
    img.Image? image = cameraImageToImage(cameraImage);
    if (image == null) throw Exception('Failed to convert CameraImage');

    // Rotate to display-upright. img.copyRotate uses clockwise degrees and
    // sensorOrientation is already the CW angle needed to bring image upright.
    if (sensorOrientation != 0) {
      image = img.copyRotate(image, angle: sensorOrientation.toDouble());
    }

    // Front cameras stream a horizontally mirrored image — flip so the
    // saved selfie is not a mirror image.
    final isFront =
        _controller?.description.lensDirection == CameraLensDirection.front;
    if (isFront) {
      image = img.flipHorizontal(image);
    }

    final jpeg = img.encodeJpg(image, quality: 95);
    if (jpeg.isEmpty) throw Exception('Failed to encode capture as JPEG');
    final tempDir = await getTemporaryDirectory();
    final file = File(
      path.join(
        tempDir.path,
        'face_capture_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );
    await file.writeAsBytes(jpeg);
    return file;
  }

  void _stopStream() {
    if (!_isStreaming || _controller == null) return;
    _controller!.stopImageStream();
    _isStreaming = false;
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
        // Animated face oval overlay.
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) => CustomPaint(
            painter: _FaceOvalPainter(
              progress: _progress,
              pulseValue: _pulseController.value,
            ),
          ),
        ),
        _InstructionOverlay(
          progress: _progress,
          nextStep: _statusMessage,
          eyesWereClosed: _eyesWereClosed,
        ),
      ],
    );
  }
}

// ─── Oval painter ─────────────────────────────────────────────────────────────
class _FaceOvalPainter extends CustomPainter {
  const _FaceOvalPainter({
    required this.progress,
    required this.pulseValue,
  });

  final ScanProgress progress;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width * _kOvalHalfWidth;
    final ry = size.height * _kOvalHalfHeight;
    final ovalRect =
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);

    // Dim outside the oval.
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    // Oval border color: green when all checks pass, amber mid-way, white otherwise.
    final allReady = progress.faceInOval &&
        progress.faceGoodSize &&
        progress.lookingAtCamera &&
        progress.eyesOnCamera;
    final midReady =
        progress.faceInOval && progress.faceGoodSize && progress.lookingAtCamera;

    final borderColor = allReady
        ? Color.lerp(
            const Color(0xFF4CAF50),
            const Color(0xFF81C784),
            pulseValue,
          )!
        : midReady
            ? const Color(0xFFFFC107)
            : Colors.white.withValues(alpha: 0.85);

    canvas.drawOval(
      ovalRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = allReady ? 3.5 : 2.5
        ..color = borderColor,
    );

    // Corner tick marks (top/bottom/left/right).
    _drawTick(canvas, Offset(cx, cy - ry), const Offset(0, -1), borderColor);
    _drawTick(canvas, Offset(cx, cy + ry), const Offset(0, 1), borderColor);
    _drawTick(canvas, Offset(cx - rx, cy), const Offset(-1, 0), borderColor);
    _drawTick(canvas, Offset(cx + rx, cy), const Offset(1, 0), borderColor);
  }

  void _drawTick(Canvas canvas, Offset pos, Offset dir, Color color) {
    canvas.drawLine(
      pos,
      pos + dir * 14,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_FaceOvalPainter old) =>
      old.progress != progress || old.pulseValue != pulseValue;
}

// ─── Instruction overlay ──────────────────────────────────────────────────────
class _InstructionOverlay extends StatelessWidget {
  const _InstructionOverlay({
    required this.progress,
    required this.nextStep,
    required this.eyesWereClosed,
  });

  final ScanProgress progress;
  final String nextStep;
  final bool eyesWereClosed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _InstructionStrip(
          icon: Icons.face_retouching_natural_rounded,
          text: eyesWereClosed
              ? 'Blink detected!'
              : 'Face straight · Eyes open · Look at lens',
          subtext: eyesWereClosed
              ? 'Now open your eyes to complete'
              : 'Hold still then blink once to capture',
        ),
        const Spacer(),
        _ProgressAndNextStep(progress: progress, nextStep: nextStep),
      ],
    );
  }
}

class _ProgressAndNextStep extends StatelessWidget {
  const _ProgressAndNextStep(
      {required this.progress, required this.nextStep});

  final ScanProgress progress;
  final String nextStep;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          color: Colors.black.withValues(alpha: 0.65),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ProgressChip(
                        done: progress.faceDetected, label: 'Face detected'),
                    _ProgressChip(done: progress.faceInOval, label: 'In oval'),
                    _ProgressChip(
                        done: progress.faceGoodSize, label: 'Distance OK'),
                    _ProgressChip(
                        done: progress.lookingAtCamera, label: 'Straight'),
                    _ProgressChip(
                        done: progress.eyesOnCamera, label: 'Eyes on lens'),
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
                    shadows: [
                      Shadow(blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            done ? Colors.green.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: done
              ? Colors.green.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: done ? Colors.white : Colors.white.withValues(alpha: 0.55),
            size: 15,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: done ? Colors.white : Colors.white.withValues(alpha: 0.7),
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
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: Colors.black.withValues(alpha: 0.65),
          child: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 24),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtext != null && subtext!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtext!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
