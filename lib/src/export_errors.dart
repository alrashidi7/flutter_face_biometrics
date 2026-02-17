/// Errors specific to the biometric export flow.
///
/// Use these for clean handling of "No Face Detected," "Multiple Faces Detected,"
/// and "Biometric Hardware Unavailable" as requested.
sealed class BiometricExportException implements Exception {
  const BiometricExportException(this.message, [this.details]);
  final String message;
  final String? details;

  @override
  String toString() => details != null ? '$message ($details)' : message;
}

/// No face was detected in the frame (e.g. during liveness or capture).
final class NoFaceDetectedException extends BiometricExportException {
  const NoFaceDetectedException([String? details])
      : super('No face detected', details);
}

/// More than one face was detected; the flow requires exactly one face.
final class MultipleFacesDetectedException extends BiometricExportException {
  const MultipleFacesDetectedException([String? details])
      : super('Multiple faces detected', details);
}

/// Device does not support or has no available biometric hardware for signing.
final class BiometricHardwareUnavailableException
    extends BiometricExportException {
  const BiometricHardwareUnavailableException([String? details])
      : super('Biometric hardware unavailable', details);
}

/// Face verification / embedding failed (e.g. model not loaded or extraction error).
final class EmbeddingException extends BiometricExportException {
  const EmbeddingException(super.message, [super.details]);
}

/// User canceled the flow (e.g. back button or biometric prompt dismissed).
final class UserCanceledException extends BiometricExportException {
  const UserCanceledException([String? details]) : super('User canceled', details);
}

/// Server upload failed (e.g. non-2xx response).
final class UploadException extends BiometricExportException {
  const UploadException(super.message, [super.details]);
}
