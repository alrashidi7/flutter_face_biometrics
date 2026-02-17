# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-02-17

### Changed

- **Package renamed** from `flutter_export_biometrics` to `flutter_face_biometrics`. Update imports to `package:flutter_face_biometrics/flutter_face_biometrics.dart` and dependency name to `flutter_face_biometrics`. Asset paths use `packages/flutter_face_biometrics/...`.

### Added

- **Face liveness**: `FaceLivenessScanner` with blink-to-capture and ML Kit face detection (single face, position/size checks).
- **Face embedding**: 128D FaceNet embedding via `tensorflow_face_verification`; configurable model path.
- **Device signature** (optional): Integration with `secure_device_signature` for hardware-backed signing.
- **Enrollment flow**: `BiometricEnrollmentFlow` — liveness → embedding → optional sign → local save.
- **Verification flow**: `BiometricVerificationFlow` — camera or gallery verification against stored data.
- **Local storage**: `BiometricLocalStorage` for JSON + enrolled image; configurable filenames.
- **Local verifier**: `BiometricLocalVerifier` with configurable similarity threshold and signature check.
- **Server integration**: `BiometricExportService.uploadBiometricData`, `verifyWithChallenge`, `verifyAndUploadBiometricData`.
- **Models**: `BiometricExportData`, `BiometricVerificationResult`, `LocalVerificationResult`.
- **Errors**: `BiometricExportException` and subtypes (no face, multiple faces, hardware unavailable, embedding, user canceled, upload).
- **Documentation**: README with installation, parent app setup (assets, Android/iOS permissions), configuration tables, and server API reference.

### Dependencies

- `flutter`, `camera`, `google_mlkit_face_detection`, `tensorflow_face_verification`, `secure_device_signature`, `http`, `image`, `path_provider`, `path`, `image_picker`.
