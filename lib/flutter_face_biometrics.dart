// Barrel file: single import for all package features.
//
// Usage:
//   import 'package:flutter_face_biometrics/flutter_face_biometrics.dart';
//
// Core API (no widgets) — for custom UI or headless flows:
//   final api = FlutterFaceBiometricsApi();
//   await api.ensureInitialized();
//   final embedding = await api.extractEmbeddingFromFile(imageFile);
//
// Required: Include facenet.tflite in your app's assets:
//   flutter:
//     assets:
//       - assets/models/facenet.tflite
//
// Optional: secure_device_signature — only if you need device signing.
// Add to your pubspec and use useSignature: true when constructing flows.

export 'src/export_errors.dart';
export 'src/export_models.dart';
export 'src/flutter_face_biometrics_config.dart';
export 'src/face_embedding_export.dart';
export 'src/face_biometrics_api.dart';
export 'src/face_liveness_scanner.dart';
export 'src/liveness_config.dart';
export 'src/biometric_export_service.dart';
export 'src/biometric_local_storage.dart';
export 'src/biometric_local_verifier.dart';
export 'src/widgets/biometric_enrollment_flow.dart';
export 'src/widgets/biometric_verification_flow.dart';
export 'src/widgets/biometric_info_section.dart';
export 'src/widgets/biometric_result_card.dart';
export 'package:secure_device_signature/device_integrity_signature.dart'
    show SignatureService, SignResult, DeviceIntegrityReport;
