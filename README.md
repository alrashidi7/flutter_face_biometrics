# flutter_face_biometrics

A Flutter package providing a unified flow for **liveness-verified selfie**, **face embedding** (FaceNet via `tensorflow_face_verification`), and **biometric signature export**, with optional server upload and challenge-based verification.

## Features

- **Face liveness**: Blink-to-capture with ML Kit face detection (single face, position/size checks).
- **Face embedding**: 128D FaceNet embedding extraction from captured selfie.
- **Device signature** (optional): Hardware-backed signing via `secure_device_signature` for device binding.
- **Local enrollment & verification**: Save/load biometric data locally; verify with camera or gallery.
- **Server integration**: Upload enrollment data, verify with challenge, and recovery (enroll new device).

## Installation

### 1. Add the package

**Option A – Local path (monorepo):**

```yaml
dependencies:
  flutter_face_biometrics:
    path: packages/flutter_face_biometrics
```

**Option B – Git:**

```yaml
dependencies:
  flutter_face_biometrics:
    git:
      url: https://github.com/your-org/flutter_face_biometrics.git
      ref: main
```

This package depends on **`secure_device_signature`**. If you use the path-based setup, ensure the parent app (or your workspace) also depends on it, for example:

```yaml
dependencies:
  secure_device_signature:
    path: packages/device_integrity_signature
  flutter_face_biometrics:
    path: packages/flutter_face_biometrics
```

### 2. Parent app setup

#### Assets (required)

The FaceNet model must be available to the app. Include the package’s assets in your app’s `pubspec.yaml`:

```yaml
flutter:
  assets:
    - packages/flutter_face_biometrics/assets/models/facenet.tflite
    - packages/flutter_face_biometrics/assets/models/
```

If you ship the model from your app’s own `assets` folder instead, use a custom `modelPath` when creating the service (see [Configuration](#configuration)).

#### Android

In `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest>
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="true" />
    <!-- Optional: if using gallery for verification -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    ...
</manifest>
```

Set `minSdkVersion` to at least **21** (or as required by `camera` / `google_mlkit_face_detection`) in `android/app/build.gradle`.

#### iOS

In `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for face verification.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app uses the photo library to verify your identity from a photo.</string>
```

---

## Quick start

```dart
import 'package:flutter_face_biometrics/flutter_face_biometrics.dart';

// Enrollment screen: liveness → embedding → optional sign → save
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

// Verification screen: camera or gallery → compare with stored data
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => Scaffold(
      body: BiometricVerificationFlow(
        title: 'Verify your identity',
        useSignature: false,
        onVerified: (result) => Navigator.pop(context, true),
        onError: (result) => debugPrint('Verification: $result'),
      ),
    ),
  ),
);
```

---

## Configuration

All parameters that the parent app can use are optional; defaults are applied when omitted.

### BiometricEnrollmentFlow

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `config` | `FlutterFaceBiometricsConfig?` | `null` | When `requireInjectedDependencies: true`, `service` and `storage` must be provided. |
| `title` | `String` | `'We secure you'` | Header title. |
| `subtitle` | `String` | `'Enroll your face to protect your identity'` | Header subtitle. |
| `service` | `BiometricExportService?` | `null` | If null and config does not require injection, a default service is created (see below). |
| `storage` | `BiometricLocalStorage?` | `null` | If null and config does not require injection, default local storage is used. |
| `modelPath` | `String?` | `null` | FaceNet model asset path. If null, package default `assets/models/facenet.tflite` is used. |
| `useSignature` | `bool` | `false` | If true and `service` is null, enrollment includes device signature. |
| `onSaved` | `void Function(BiometricExportData)?` | `null` | Called when enrollment is saved locally. |
| `onError` | `void Function(Object)?` | `null` | Called on initialization or save errors. |
| `showInfoSection` | `bool` | `true` | Show "How we secure you" expandable section. |

### BiometricVerificationFlow

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `config` | `FlutterFaceBiometricsConfig?` | `null` | When `requireInjectedDependencies: true`, `service` and `storage` must be provided. |
| `title` | `String` | `'Verify your identity'` | Header title. |
| `subtitle` | `String` | `'Use camera or choose a photo from gallery'` | Header subtitle. |
| `service` | `BiometricExportService?` | `null` | Used for embedding extraction; default created if null (unless config requires injection). |
| `storage` | `BiometricLocalStorage?` | `null` | Source of stored biometric data; default if null (unless config requires injection). |
| `verifier` | `BiometricLocalVerifier?` | `null` | If null, a default verifier is built from `storage` and `service`. |
| `modelPath` | `String?` | `null` | FaceNet model path (same as enrollment). |
| `useSignature` | `bool` | `false` | If true, camera verification uses device signature. |
| `similarityThreshold` | `double?` | `0.6` | Match threshold (0.0–1.0). Use `kLenientSimilarityThreshold` (0.4) for gallery. |
| `onVerified` | `void Function(LocalVerificationSuccess)?` | `null` | Called on successful verification. |
| `onError` | `void Function(LocalVerificationResult)?` | `null` | Called for any non-success result. |

### BiometricExportService

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `embeddingExport` | `FaceEmbeddingExport?` | `null` | If null, a default is created from `modelPath`. |
| `signatureService` | `SignatureService?` | `null` | From `secure_device_signature`. If null, embedding-only mode. |
| `modelPath` | `String?` | `kDefaultFacenetModelPath` | `'assets/models/facenet.tflite'`. |

Use the same `BiometricExportService` instance (with optional custom `http.Client`) when uploading or calling `verifyWithChallenge` / `verifyAndUploadBiometricData`.

### BiometricLocalStorage

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `filename` | `String` | `kDefaultBiometricStorageFilename` | JSON file name for biometric data. |
| `enrolledImageFilename` | `String` | `kDefaultEnrolledImageFilename` | File name for enrolled face image. |

### BiometricLocalVerifier

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storage` | `BiometricLocalStorage?` | `null` | Default storage if null. |
| `similarityThreshold` | `double` | `kDefaultSimilarityThreshold` (0.6) | Match threshold. |
| `verifySignature` | `bool` | `true` | Whether to require device signature match when present. |
| `embeddingExtractor` | `EmbeddingExtractor?` | `null` | If null, must be set by the flow (e.g. from service). |

### FaceLivenessScanner (standalone)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `onCaptured` | `void Function(File)` | required | Called with temp JPEG when liveness passes. |
| `onError` | `void Function(BiometricExportException)` | required | Called on no face, multiple faces, or other errors. |
| `instructionText` | `String` | `'Position your face and blink to capture'` | Shown above camera. |
| `minFaceSize` | `double` | `0.15` | Min face size (0.0–1.0) for detection. |

---

## API overview

| Class / export | Purpose |
|----------------|--------|
| `FlutterFaceBiometricsConfig` | Config for DI: `requireInjectedDependencies` to control internal instance creation. |
| `BiometricEnrollmentFlow` | Full enrollment UI: liveness → embedding → optional sign → save. |
| `BiometricVerificationFlow` | Verification UI: camera or gallery → compare with stored data. |
| `BiometricExportService` | Extract embedding, build `BiometricExportData`, upload, challenge verification, recovery upload. |
| `BiometricLocalStorage` | Save/load `BiometricExportData` and enrolled image path. |
| `BiometricLocalVerifier` | Compare new capture/gallery image with stored data (embedding ± signature). |
| `FaceLivenessScanner` | Camera widget with blink-to-capture liveness. |
| `BiometricExportData` | Embedding, optional signature, public key, signed payload, device signature, enrolled image path. |
| `BiometricVerificationResult` | Server result: success, signature invalid, embedding mismatch, error. |
| `LocalVerificationResult` | Local result: success, no stored data, embedding mismatch, signature mismatch, error. |
| `BiometricExportException` | No face, multiple faces, hardware unavailable, embedding, user canceled, upload. |
| `kDefaultFacenetModelPath` | Default FaceNet asset path: `'assets/models/facenet.tflite'`. |
| `kDefaultSimilarityThreshold` | Default match threshold: `0.6`. |
| `kLenientSimilarityThreshold` | Lenient threshold for gallery: `0.4`. |

See `lib/flutter_face_biometrics.dart` for full exports.

---

## Dependency injection

When using a DI container (GetIt, Provider, Riverpod, etc.), use `FlutterFaceBiometricsConfig` with `requireInjectedDependencies: true` so the flows never create internal instances of `BiometricExportService`, `BiometricLocalStorage`, or `BiometricLocalVerifier`.

```dart
// Register in your DI setup
getIt.registerSingleton<BiometricExportService>(BiometricExportService(
  modelPath: 'assets/models/facenet.tflite',
  signatureService: getIt<SignatureService>(),
));
getIt.registerSingleton<BiometricLocalStorage>(BiometricLocalStorage());

// Use in widgets – service and storage must be provided
BiometricEnrollmentFlow(
  config: FlutterFaceBiometricsConfig.diConfig,
  service: getIt<BiometricExportService>(),
  storage: getIt<BiometricLocalStorage>(),
  onSaved: (data) => Navigator.pop(context),
  onError: (e) => debugPrint('Error: $e'),
);
```

| Config | Behavior |
|--------|----------|
| `FlutterFaceBiometricsConfig.defaultConfig` | Null `service`/`storage` are replaced with internal defaults (default behavior). |
| `FlutterFaceBiometricsConfig.diConfig` | `service` and `storage` must be provided; missing values throw at init. |

---

## Error handling

Handle errors in `onError` and `onVerified` / `onError` callbacks. For programmatic use, catch:

- `NoFaceDetectedException`
- `MultipleFacesDetectedException`
- `BiometricHardwareUnavailableException`
- `EmbeddingException`
- `UserCanceledException`
- `UploadException`

```dart
try {
  final data = await exportService.buildExportDataFromFile(imageFile);
  // ...
} on BiometricExportException catch (e) {
  // e.message, e.details
}
```

---

## Server verification

For registration, challenge verification, and recovery (new device), see **[SERVER_VERIFICATION_API.md](SERVER_VERIFICATION_API.md)**. It describes:

- Registration: POST embedding + signature to `/biometric/register`
- Challenge: sign challenge → POST to `/biometric/verify-challenge`
- Recovery: POST same payload as registration to `/biometric/recover` when challenge returns `signature_invalid`

Example with auth header:

```dart
final result = await exportService.verifyAndUploadBiometricData(
  'https://api.example.com/biometric/register',
  data,
  headers: {'Authorization': 'Bearer $token'},
);
```

---

## License

See repository for license information.
