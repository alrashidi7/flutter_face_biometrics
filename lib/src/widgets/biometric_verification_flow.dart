import 'dart:io';

import 'package:flutter_face_biometrics/flutter_face_biometrics.dart';
import 'package:secure_device_signature/device_integrity_signature.dart'
    as device_integrity;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Verification flow: camera or gallery → compare with stored data.
class BiometricVerificationFlow extends StatefulWidget {
  const BiometricVerificationFlow({
    super.key,
    this.config,
    this.title = 'Verify your identity',
    this.subtitle = 'Use camera or choose a photo from gallery',
    this.service,
    this.storage,
    this.verifier,
    this.modelPath,
    this.useSignature = false,
    this.similarityThreshold,
    this.onVerified,
    this.onError,
  });

  /// Optional config. When [FlutterFaceBiometricsConfig.requireInjectedDependencies]
  /// is true, [service] and [storage] must be provided (no internal creation).
  final FlutterFaceBiometricsConfig? config;

  /// Optional model path for FaceNet (e.g. 'packages/flutter_face_biometrics/assets/models/facenet.tflite').
  final String? modelPath;

  /// Similarity threshold for face match. Default 0.6. Use [kLenientSimilarityThreshold] (0.4) for gallery vs camera.
  final double? similarityThreshold;

  /// If true and [service] is null, uses [SignatureService] for camera verification.
  /// If false, embedding-only (default).
  final bool useSignature;

  final String title;
  final String subtitle;
  final BiometricExportService? service;
  final BiometricLocalStorage? storage;
  final BiometricLocalVerifier? verifier;
  final void Function(LocalVerificationSuccess result)? onVerified;
  final void Function(LocalVerificationResult result)? onError;

  @override
  State<BiometricVerificationFlow> createState() =>
      _BiometricVerificationFlowState();
}

class _BiometricVerificationFlowState extends State<BiometricVerificationFlow> {
  late BiometricExportService _service;
  late BiometricLocalStorage _storage;
  late BiometricLocalVerifier _verifier;
  bool _initialized = false;
  String? _initError;
  bool _hasStoredData = false;
  bool _showScanner = false;

  /// True while showing the preview screen (before comparison starts).
  bool _showPreview = false;

  bool _verifying = false;
  LocalVerificationResult? _result;

  /// The image that was captured/picked for this verification attempt.
  File? _verificationImageFile;

  /// Path to the enrolled face image (loaded from stored data).
  String? _enrolledImagePath;

  bool get _requireInjected =>
      widget.config?.requireInjectedDependencies ?? false;

  @override
  void initState() {
    super.initState();
    if (_requireInjected) {
      if (widget.service == null) {
        throw StateError(
          'BiometricVerificationFlow: service is required when config.requireInjectedDependencies is true. '
          'Provide service from your dependency injection.',
        );
      }
      if (widget.storage == null) {
        throw StateError(
          'BiometricVerificationFlow: storage is required when config.requireInjectedDependencies is true. '
          'Provide storage from your dependency injection.',
        );
      }
    }
    _service =
        widget.service ??
        BiometricExportService(
          modelPath: widget.modelPath,
          signatureService: widget.useSignature
              ? device_integrity.SignatureService()
              : null,
        );
    _storage = widget.storage ?? BiometricLocalStorage();
    _verifier =
        widget.verifier ??
        BiometricLocalVerifier(
          storage: _storage,
          similarityThreshold:
              widget.similarityThreshold ?? kDefaultSimilarityThreshold,
          embeddingExtractor: (f) => _service.getEmbeddingFromFile(f),
        );
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _service.ensureModelLoaded();
      final has = await _storage.hasStoredData();
      // Load enrolled image path upfront for the face comparison widget.
      String? enrolledPath;
      if (has) {
        final stored = await _storage.load();
        enrolledPath = stored?.enrolledImagePath;
      }
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _initError = null;
        _hasStoredData = has;
        _enrolledImagePath = enrolledPath;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialized = false;
        _initError = e.toString();
      });
    }
  }

  void _startCameraVerify() {
    setState(() {
      _showScanner = true;
      _result = null;
      _showPreview = false;
    });
  }

  /// Called when the scanner delivers a captured image.
  /// Crops to face-only (with upscaling + enhancement) before showing the
  /// preview — the full frame is kept as fallback if crop fails.
  void _onCaptured(File imageFile) {
    setState(() {
      _showScanner = false;
      _verificationImageFile = imageFile; // show immediately while cropping
      _showPreview = true;
    });
    _cropToFaceAndUpdatePreview(imageFile);
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;

    final file = File(xFile.path);
    setState(() {
      _result = null;
      _verificationImageFile = file; // show immediately while cropping
      _showPreview = true;
    });
    _cropToFaceAndUpdatePreview(file);
  }

  /// Crops [original] to face-only and updates [_verificationImageFile] if
  /// successful. Runs after the preview is already visible so the UI is
  /// responsive — the image simply updates in place when the crop is ready.
  Future<void> _cropToFaceAndUpdatePreview(File original) async {
    final cropped = await _service.extractFaceCropFile(original);
    if (!mounted || cropped == null) return;
    setState(() => _verificationImageFile = cropped);
  }

  /// Runs after the user confirms on the preview screen.
  Future<void> _runComparison() async {
    final file = _verificationImageFile;
    if (file == null) return;
    setState(() {
      _showPreview = false;
      _verifying = true;
    });

    try {
      final result = await _verifier.verifyWithImage(file);
      if (!mounted) return;
      _handleResult(result);
    } catch (e) {
      if (!mounted) return;
      _handleResult(LocalVerificationError(message: e.toString()));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _handleResult(LocalVerificationResult result) {
    setState(() {
      _result = result;
      _showScanner = false;
    });

    switch (result) {
      case LocalVerificationSuccess():
        widget.onVerified?.call(result);
      default:
        widget.onError?.call(result);
    }
  }

  void _onScanError(BiometricExportException e) {
    setState(() => _showScanner = false);
  }

  void _retake() {
    setState(() {
      _result = null;
      _verificationImageFile = null;
      _showScanner = false;
      _showPreview = false;
    });
  }

  void _retry() {
    setState(() {
      _result = null;
      _verificationImageFile = null;
      _showScanner = false;
      _showPreview = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_initError != null) {
      return _buildInitError();
    }

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasStoredData) {
      return _buildNoStoredData(cs);
    }

    if (_showScanner) {
      return _buildScanner(cs);
    }

    if (_showPreview && _verificationImageFile != null) {
      return _buildPreview(cs);
    }

    if (_verifying) {
      return _buildVerifying(cs);
    }

    if (_result != null) {
      return _buildResult(cs);
    }

    return _buildModeSelector(cs);
  }

  Widget _buildInitError() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 10),
                  Text(
                    'Initialization failed',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_initError!, style: TextStyle(color: Colors.red.shade900)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoStoredData(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: BiometricResultCard(
        success: false,
        message: 'No biometric enrolled',
        detail: 'Enroll your face first, then you can verify.',

        actionLabel: 'Enroll your face',
        onAction: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                body: BiometricEnrollmentFlow(
                  title: 'We secure you',
                  subtitle: 'Enroll your face to protect your identity',
                  useSignature: true,
                  onSaved: (BiometricExportData data) {
                    // Optionally upload to server
                    // await exportService.verifyAndUploadBiometricData(registerUrl, data);
                    Navigator.pop(context);
                  },
                  onError: (e) => debugPrint('Enrollment error: $e'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildModeSelector(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.verified_user_rounded,
                  size: 32,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _ModeCard(
            icon: Icons.camera_alt_rounded,
            title: 'Verify with camera',
            description: 'Live liveness check + device signature',
            onTap: _startCameraVerify,
            colorScheme: cs,
          ),
          const SizedBox(height: 12),
          _ModeCard(
            icon: Icons.photo_library_rounded,
            title: 'Verify with gallery',
            description: 'Pick a photo – embedding only (no device check)',
            onTap: _pickFromGallery,
            colorScheme: cs,
          ),

          const SizedBox(height: 12),
          _ModeCard(
            icon: Icons.photo_library_rounded,
            title: 'Enroll you biometric',
            description: 'Enroll your face to protect your identity',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: BiometricEnrollmentFlow(
                      title: 'We secure you',
                      subtitle: 'Enroll your face to protect your identity',
                      useSignature: true,
                      onSaved: (BiometricExportData data) {
                        // Optionally upload to server
                        // await exportService.verifyAndUploadBiometricData(registerUrl, data);
                        Navigator.pop(context);
                      },
                      onError: (e) => debugPrint('Enrollment error: $e'),
                    ),
                  ),
                ),
              );
            },
            colorScheme: cs,
          ),
        ],
      ),
    );
  }

  Widget _buildScanner(ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _showScanner = false),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Position your face and blink to verify',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: FaceLivenessScanner(
                onCaptured: _onCaptured,
                onError: _onScanError,
                instructionText: 'Position your face and blink to capture',
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Shows enrolled + captured faces before any comparison runs.
  /// User can tap "Compare faces" to proceed or "Retake" to go back.
  Widget _buildPreview(ColorScheme cs) {
    final captured = _verificationImageFile!;
    final enrolledFile = _enrolledImagePath != null
        ? File(_enrolledImagePath!)
        : null;
    final hasEnrolled = enrolledFile != null && enrolledFile.existsSync();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.compare_rounded, size: 26, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review your photo',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Make sure your face is clear before comparing',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Side-by-side faces (no result indicator yet)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: cs.outline.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'ENROLLED  vs  CAPTURED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _FaceCard(
                        label: 'Enrolled face',
                        imagePath: _enrolledImagePath,
                        imageFile: null,
                        cs: cs,
                        badge: hasEnrolled
                            ? null
                            : const _FaceBadge(
                                label: 'No image saved',
                                color: Colors.orange,
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 50),
                      child: Column(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary.withValues(alpha: 0.1),
                              border: Border.all(
                                color: cs.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Icon(
                              Icons.compare_arrows_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _FaceCard(
                        label: 'Your photo',
                        imagePath: null,
                        imageFile: captured,
                        cs: cs,
                        badge: const _FaceBadge(
                          label: 'Just captured',
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Primary action: compare
          FilledButton.icon(
            onPressed: _runComparison,
            icon: const Icon(Icons.compare_rounded, size: 20),
            label: const Text(
              'Compare faces',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Secondary action: retake
          OutlinedButton.icon(
            onPressed: _retake,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text('Retake photo', style: TextStyle(fontSize: 15)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifying(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'Verifying...',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Comparing your face with stored data',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(ColorScheme cs) {
    final result = _result!;

    // Face comparison widget shown inside every result card, below the button.
    final faceComparison = _FaceComparisonWidget(
      enrolledImagePath: _enrolledImagePath,
      verificationImage: _verificationImageFile,
      success: result is LocalVerificationSuccess,
      result: result,
    );

    final Widget card;
    switch (result) {
      case LocalVerificationSuccess(:final similarityScore):
        card = BiometricResultCard(
          success: true,
          message: 'Verification successful',
          detail: similarityScore != null
              ? 'Similarity score: ${(similarityScore * 100).toStringAsFixed(1)}%'
              : null,
          actionLabel: 'Verify again',
          onAction: _retry,
          bottomWidget: faceComparison,
        );
      case LocalVerificationNoStoredData():
        card = BiometricResultCard(
          success: false,
          message: 'No stored biometric',
          detail: 'Enroll first.',
          actionLabel: 'Retry',
          onAction: _retry,
        );
      case LocalVerificationEmbeddingMismatch(
        :final similarityScore,
        :final message,
      ):
        card = BiometricResultCard(
          success: false,
          message: 'Face mismatch',
          detail:
              message ??
              (similarityScore != null
                  ? 'Similarity score: ${(similarityScore * 100).toStringAsFixed(1)}%'
                  : null),
          actionLabel: 'Try again',
          onAction: _retry,
          bottomWidget: faceComparison,
        );
      case LocalVerificationSignatureMismatch(:final message):
        card = BiometricResultCard(
          success: false,
          message: 'Different device',
          detail: message ?? 'This device is not the one that enrolled.',
          actionLabel: 'Try again',
          onAction: _retry,
          bottomWidget: faceComparison,
        );
      case LocalVerificationError(:final message):
        card = BiometricResultCard(
          success: false,
          message: 'Verification failed',
          detail: message,
          actionLabel: 'Retry',
          onAction: _retry,
          bottomWidget: faceComparison,
        );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: card,
    );
  }
}

/// Shows the enrolled face and the verification face side-by-side with
/// a match/mismatch indicator between them.
class _FaceComparisonWidget extends StatelessWidget {
  const _FaceComparisonWidget({
    required this.enrolledImagePath,
    required this.verificationImage,
    required this.success,
    required this.result,
  });

  final String? enrolledImagePath;
  final File? verificationImage;
  final bool success;
  final LocalVerificationResult result;

  double? get _similarity {
    return switch (result) {
      LocalVerificationSuccess(:final similarityScore) => similarityScore,
      LocalVerificationEmbeddingMismatch(:final similarityScore) =>
        similarityScore,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final matchColor = success ? cs.primary : cs.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: matchColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Face comparison',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.65),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Enrolled face.
              Expanded(
                child: _FaceCard(
                  label: 'Enrolled',
                  imagePath: enrolledImagePath,
                  imageFile: null,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 10),
              // Match indicator.
              Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: matchColor.withValues(alpha: 0.12),
                      border: Border.all(
                        color: matchColor.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      success ? Icons.check_rounded : Icons.close_rounded,
                      color: matchColor,
                      size: 22,
                    ),
                  ),
                  if (_similarity != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${(_similarity! * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: matchColor,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 10),
              // Verification face.
              Expanded(
                child: _FaceCard(
                  label: 'Captured',
                  imagePath: null,
                  imageFile: verificationImage,
                  cs: cs,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FaceCard extends StatelessWidget {
  const _FaceCard({
    required this.label,
    required this.imagePath,
    required this.imageFile,
    required this.cs,
    this.badge,
  });

  final String label;
  final String? imagePath;
  final File? imageFile;
  final ColorScheme cs;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final File? file =
        imageFile ?? (imagePath != null ? File(imagePath!) : null);
    final bool hasImage = file != null && file.existsSync();

    return Column(
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: hasImage
                    ? Image.file(
                        file,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            if (badge != null)
              Positioned(bottom: 6, left: 4, right: 4, child: badge!),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: 40,
          color: cs.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

class _FaceBadge extends StatelessWidget {
  const _FaceBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.colorScheme,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 28, color: colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
