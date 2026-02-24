/// Liveness-only exports — use without enrollment, embedding, or matching.
///
/// Import this when you only need the liveness scanner to capture a live selfie
/// from the camera. Use the returned image with your own embedding and matching logic.
///
/// ```dart
/// import 'package:flutter_face_biometrics/face_liveness.dart';
///
/// FaceLivenessScanner(
///   config: LivenessConfig.strict,  // optional
///   onCaptured: (File image) {
///     // Use image — extract embedding, verify, upload, etc.
///   },
///   onError: (e) => ...,
/// )
/// ```
library;

export 'src/export_errors.dart' show
    BiometricExportException,
    EmbeddingException,
    MultipleFacesDetectedException,
    NoFaceDetectedException;
export 'src/face_liveness_scanner.dart';
export 'src/liveness_config.dart';
