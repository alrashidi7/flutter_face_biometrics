import 'dart:io';

import 'package:secure_device_signature/device_integrity_signature.dart'
    as device_integrity;
import 'package:flutter/material.dart';

import '../biometric_export_service.dart';
import '../biometric_local_storage.dart';
import '../flutter_face_biometrics_config.dart';
import '../export_errors.dart';
import '../export_models.dart';
import '../face_liveness_scanner.dart';
import 'biometric_info_section.dart';
import 'biometric_result_card.dart';

/// Complete drop-in enrollment flow: liveness → embedding → sign → save.
///
/// - Hero header ("We secure you")
/// - FaceLivenessScanner with face oval overlay
/// - Checklist: Position face → Blink → Extract embedding → Sign → Done
/// - Expandable info section
/// - Save button, success card
class BiometricEnrollmentFlow extends StatefulWidget {
  const BiometricEnrollmentFlow({
    super.key,
    this.config,
    this.title = 'We secure you',
    this.subtitle = 'Enroll your face to protect your identity',
    this.service,
    this.storage,
    this.modelPath,
    this.useSignature = false,
    this.onSaved,
    this.onError,
    this.showInfoSection = true,
  });

  /// Optional config. When [FlutterFaceBiometricsConfig.requireInjectedDependencies]
  /// is true, [service] and [storage] must be provided (no internal creation).
  final FlutterFaceBiometricsConfig? config;

  /// Optional model path for FaceNet (e.g. 'packages/flutter_face_biometrics/assets/models/facenet.tflite').
  final String? modelPath;

  /// If true and [service] is null, uses [SignatureService] to sign the embedding (device verification).
  /// If false, generates embedding only (default).
  final bool useSignature;

  final String title;
  final String subtitle;
  final BiometricExportService? service;
  final BiometricLocalStorage? storage;
  final void Function(BiometricExportData data)? onSaved;
  final void Function(Object error)? onError;
  final bool showInfoSection;

  @override
  State<BiometricEnrollmentFlow> createState() => _BiometricEnrollmentFlowState();
}

class _BiometricEnrollmentFlowState extends State<BiometricEnrollmentFlow> {
  late BiometricExportService _service;
  late BiometricLocalStorage _storage;
  bool _initialized = false;
  String? _initError;
  bool _showScanner = true;
  BiometricExportData? _data;
  File? _enrolledImageFile;
  String _status = 'Position your face and blink to capture';
  bool _saving = false;
  bool _infoExpanded = false;
  int _step = 0; // 0=position, 1=blink, 2=extract, 3=sign, 4=done

  bool get _requireInjected =>
      widget.config?.requireInjectedDependencies ?? false;

  @override
  void initState() {
    super.initState();
    if (_requireInjected) {
      if (widget.service == null) {
        throw StateError(
          'BiometricEnrollmentFlow: service is required when config.requireInjectedDependencies is true. '
          'Provide service from your dependency injection.',
        );
      }
      if (widget.storage == null) {
        throw StateError(
          'BiometricEnrollmentFlow: storage is required when config.requireInjectedDependencies is true. '
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
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _service.ensureModelLoaded();
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _initError = null;
        _step = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialized = false;
        _initError = e.toString();
      });
      widget.onError?.call(e);
    }
  }

  void _onCaptured(File imageFile) {
    setState(() {
      _step = 2;
      _status = 'Extracting embedding...';
    });

    _service.buildExportDataFromFile(imageFile).then((data) {
      if (!mounted) return;
      setState(() {
        _step = widget.useSignature ? 4 : 3;
        _data = data;
        _enrolledImageFile = imageFile;
        _showScanner = false;
        _status = 'Done – ready to save';
      });
    }).catchError((Object e) {
      if (!mounted) return;
      final message = e is Exception ? e.toString() : 'Capture failed – try again';
      setState(() {
        _step = 0;
        _showScanner = true;
        _data = null;
        _enrolledImageFile = null;
        _status = 'Position your face and blink to capture';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
      widget.onError?.call(e);
    });
  }

  Future<void> _save() async {
    if (_data == null) return;

    setState(() => _saving = true);
    try {
      await _storage.save(_data!, enrolledImage: _enrolledImageFile);
      if (!mounted) return;
      widget.onSaved?.call(_data!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
      widget.onError?.call(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onError(BiometricExportException e) {
    setState(() {
      _step = 0;
      _showScanner = true;
      _data = null;
      _enrolledImageFile = null;
      _status = 'Position your face and blink to capture';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString()),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () =>
              ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
    widget.onError?.call(e);
  }

  void _retry() {
    setState(() {
      _data = null;
      _enrolledImageFile = null;
      _showScanner = true;
      _step = 0;
      _status = 'Position your face and blink to capture';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(cs),
                const SizedBox(height: 16),
                if (widget.showInfoSection) _buildInfoSection(),
                const SizedBox(height: 16),
                _buildChecklist(cs),
                const SizedBox(height: 16),
                if (!_showScanner) _buildResult(cs),
              ],
            ),
          ),
        ),
        if (_showScanner)
          SizedBox(
            height: (MediaQuery.of(context).size.height * 0.42).clamp(280.0, 420.0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _buildScanner(),
            ),
          ),
      ],
    );
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
              Text(
                _initError!,
                style: TextStyle(color: Colors.red.shade900),
              ),
              const SizedBox(height: 8),
              Text(
                'Ensure facenet.tflite is in assets/models/',
                style: TextStyle(fontSize: 12, color: Colors.red.shade800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                Icons.shield_rounded,
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
      ],
    );
  }

  Widget _buildInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _infoExpanded = !_infoExpanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  'How we secure you',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Icon(
                  _infoExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: BiometricInfoSection(compact: true),
          ),
          crossFadeState:
              _infoExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildChecklist(ColorScheme cs) {
    final steps = [
      'Position face',
      'Blink to capture',
      'Extract embedding',
      if (widget.useSignature) 'Sign with device key',
      'Done',
    ];
    final doneStep = steps.length - 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Steps',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(steps.length, (idx) {
            final done = _step > idx || (_step == doneStep && idx == doneStep);
            final active = _step == idx;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: done
                        ? Icon(Icons.check_circle_rounded,
                            size: 24, color: cs.primary)
                        : Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active
                                  ? cs.primary.withValues(alpha: 0.25)
                                  : cs.outline.withValues(alpha: 0.25),
                            ),
                            child: active
                                ? Center(
                                    child: SizedBox(
                                      width: 8,
                                      height: 8,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.primary,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    steps[idx],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                      color: active
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: done ? 0.9 : 0.6),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            FaceLivenessScanner(
              onCaptured: _onCaptured,
              onError: _onError,
              instructionText: _status,
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _FaceOvalPainter(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(ColorScheme cs) {
    return Column(
      children: [
        BiometricResultCard(
          success: true,
          message: 'Enrollment complete',
          detail:
              'Embedding (${_data!.embedding.length}D) and device signature extracted. Save to finish.',
          actionLabel: 'Save to device',
          onAction: _saving ? null : _save,
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Capture again'),
        ),
      ],
    );
  }
}

/// Face oval overlay for the camera preview.
class _FaceOvalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final center = Offset(size.width / 2, size.height / 2);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.9,
      height: size.height * 0.8,
    );
    canvas.drawOval(ovalRect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
