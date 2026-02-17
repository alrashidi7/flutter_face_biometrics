import 'dart:io';

import 'package:secure_device_signature/device_integrity_signature.dart'
    as device_integrity;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../biometric_export_service.dart';
import '../biometric_local_storage.dart';
import '../biometric_local_verifier.dart';
import '../flutter_face_biometrics_config.dart';
import '../export_errors.dart';
import '../face_liveness_scanner.dart';
import 'biometric_result_card.dart';

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
  bool _verifying = false;
  LocalVerificationResult? _result;

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
    _service = widget.service ??
        BiometricExportService(
          modelPath: widget.modelPath,
          signatureService:
              widget.useSignature ? device_integrity.SignatureService() : null,
        );
    _storage = widget.storage ?? BiometricLocalStorage();
    _verifier = widget.verifier ??
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
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _initError = null;
        _hasStoredData = has;
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
    });
  }

  void _onCaptured(File imageFile) {
    setState(() {
      _showScanner = false;
      _verifying = true;
    });
    _verifyFromFile(imageFile);
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;

    setState(() {
      _verifying = true;
      _result = null;
    });
    _verifyFromFile(File(xFile.path));
  }

  Future<void> _verifyFromFile(File file) async {
    setState(() => _verifying = true);

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

  void _retry() {
    setState(() {
      _result = null;
      _showScanner = false;
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
                child: Icon(Icons.verified_user_rounded, size: 32, color: cs.primary),
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

  Widget _buildVerifying(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: cs.primary,
            ),
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
    final Widget card;

    switch (result) {
      case LocalVerificationSuccess(:final similarityScore):
        card = BiometricResultCard(
          success: true,
          message: 'Verification successful',
          detail: similarityScore != null
              ? 'Similarity: ${similarityScore.toStringAsFixed(2)}'
              : null,
          actionLabel: 'Verify again',
          onAction: _retry,
        );
      case LocalVerificationNoStoredData():
        card = BiometricResultCard(
          success: false,
          message: 'No stored biometric',
          detail: 'Enroll first.',
          actionLabel: 'Retry',
          onAction: _retry,
        );
      case LocalVerificationEmbeddingMismatch(:final similarityScore, :final message):
        card = BiometricResultCard(
          success: false,
          message: 'Face mismatch',
          detail: message ??
              (similarityScore != null
                  ? 'Similarity: ${similarityScore.toStringAsFixed(2)}'
                  : null),
          actionLabel: 'Try again',
          onAction: _retry,
        );
      case LocalVerificationSignatureMismatch(:final message):
        card = BiometricResultCard(
          success: false,
          message: 'Different device',
          detail: message ?? 'This device is not the one that enrolled.',
          actionLabel: 'Try again',
          onAction: _retry,
        );
      case LocalVerificationError(:final message):
        card = BiometricResultCard(
          success: false,
          message: 'Verification failed',
          detail: message,
          actionLabel: 'Retry',
          onAction: _retry,
        );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [card],
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
