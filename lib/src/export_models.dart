/// Result of the export flow: liveness → embedding, optionally + device signature.
///
/// [embedding] is the high-dimensional face embedding (e.g. 128D from FaceNet).
/// [biometricSignature] is the device-backed signature (optional); when null/empty,
/// use [BiometricExportData.embeddingOnly] for embedding-only mode.
/// [biometricPublicKey], [signedPayload], [deviceSignature] are from [SignatureService].
class BiometricExportData {
  const BiometricExportData({
    required this.embedding,
    this.biometricSignature = '',
    this.biometricPublicKey,
    this.signedPayload,
    this.deviceSignature,
    this.enrolledImagePath,
  });

  /// Creates embedding-only data (no device signature). Use when [SignatureService] is not needed.
  factory BiometricExportData.embeddingOnly(List<double> embedding) =>
      BiometricExportData(embedding: embedding);

  /// Face embedding vector (e.g. 128 dimensions from FaceNet).
  final List<double> embedding;

  /// Hardware-backed signature (base64 or PEM string). Empty when embedding-only.
  final String biometricSignature;

  /// Whether this includes a device-backed signature.
  bool get hasSignature => biometricSignature.isNotEmpty;

  /// Public key corresponding to the key used for signing (optional).
  final String? biometricPublicKey;

  /// The exact payload string that was signed (base64 of embedding bytes). Required for server verification.
  final String? signedPayload;

  /// Device integrity signature from [DeviceIntegrityReport] (SHA-256 of hardware identifiers).
  final String? deviceSignature;

  /// Path to stored enrolled image. Used for verify: extract face from both images, then compare embeddings.
  final String? enrolledImagePath;

  /// Payload suitable for JSON (e.g. for [BiometricExportService.uploadBiometricData]).
  Map<String, dynamic> toJson() => {
        'embedding': embedding,
        if (biometricSignature.isNotEmpty) 'biometricSignature': biometricSignature,
        if (biometricPublicKey != null) 'biometricPublicKey': biometricPublicKey,
        if (signedPayload != null) 'signedPayload': signedPayload,
        if (deviceSignature != null) 'deviceSignature': deviceSignature,
        if (enrolledImagePath != null) 'enrolledImagePath': enrolledImagePath,
      };

  /// Parses from JSON (e.g. from [BiometricLocalStorage]).
  static BiometricExportData fromJson(Map<String, dynamic> json) {
    final emb = json['embedding'];
    final embedding = emb is List
        ? (emb).map((e) => (e is num) ? e.toDouble() : double.parse('$e')).toList()
        : <double>[];
    return BiometricExportData(
      embedding: embedding,
      biometricSignature: json['biometricSignature'] as String? ?? '',
      biometricPublicKey: json['biometricPublicKey'] as String?,
      signedPayload: json['signedPayload'] as String?,
      deviceSignature: json['deviceSignature'] as String?,
      enrolledImagePath: json['enrolledImagePath'] as String?,
    );
  }
}

/// Result of biometric verification on the server.
///
/// The server verifies: (1) signature matches device, (2) embedding matches user record.
sealed class BiometricVerificationResult {}

/// Signature and embedding both verified. New biometric was saved.
final class BiometricVerificationSuccess extends BiometricVerificationResult {
  BiometricVerificationSuccess({this.message});
  final String? message;
}

/// Signature is not valid or device not enrolled. User must add signature to their account.
final class BiometricVerificationSignatureInvalid extends BiometricVerificationResult {
  BiometricVerificationSignatureInvalid({this.message});
  final String? message;
}

/// Embedding does not match the user's stored record.
final class BiometricVerificationEmbeddingMismatch extends BiometricVerificationResult {
  BiometricVerificationEmbeddingMismatch({this.message});
  final String? message;
}

/// Other error (network, server error, etc.).
final class BiometricVerificationError extends BiometricVerificationResult {
  BiometricVerificationError({this.message});
  final String? message;
}
