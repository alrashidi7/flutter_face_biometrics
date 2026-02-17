import 'dart:convert';
import 'dart:io';

import 'package:secure_device_signature/device_integrity_signature.dart'
    as device_integrity;
import 'package:http/http.dart' as http;

import 'export_errors.dart';
import 'export_models.dart';
import 'face_embedding_export.dart';

/// Service that extracts face embedding from liveness selfie, optionally with device signature.
///
/// **Core:** [getEmbeddingFromFile] and [buildExportDataFromFile] with [withSignature: false]
/// - Liveness selfie → embedding only (no device_integrity dependency required).
///
/// **Optional:** Pass [signatureService] and use [withSignature: true] when you need
/// device verification via [device_integrity.SignatureService].
class BiometricExportService {
  BiometricExportService({
    FaceEmbeddingExport? embeddingExport,
    device_integrity.SignatureService? signatureService,
    String? modelPath,
  }) : _embedding =
           embeddingExport ??
           FaceEmbeddingExport(
             modelPath: modelPath ?? kDefaultFacenetModelPath,
           ),
       _signature = signatureService;

  final FaceEmbeddingExport _embedding;
  final device_integrity.SignatureService? _signature;

  /// Default HTTP client; override for testing or custom headers.
  http.Client get client => _client;
  final http.Client _client = http.Client();

  /// Ensures the FaceNet model is loaded. Call once before first capture/export.
  Future<void> ensureModelLoaded() async {
    await _embedding.init();
  }

  /// Whether [SignatureService] is configured (non-null).
  bool get hasSignatureService => _signature != null;

  /// Checks if biometric hardware is available for signing. False when [signatureService] is null.
  Future<bool> get isBiometricAvailable async {
    final sig = _signature;
    return sig != null ? await sig.isAvailable : false;
  }

  /// Extracts face embedding only from [file] (no biometric signature). Use for verification from gallery.
  Future<List<double>> getEmbeddingFromFile(File file) async {
    await ensureModelLoaded();
    return _embedding.getEmbeddingFromFile(file);
  }

  /// Builds [BiometricExportData] from a captured image [file].
  ///
  /// - [withSignature: false] (default when [signatureService] is null): embedding only.
  /// - [withSignature: true]: also signs with [SignatureService]; requires [signatureService] to be set.
  Future<BiometricExportData> buildExportDataFromFile(
    File file, {
    bool? withSignature,
  }) async {
    await ensureModelLoaded();

    final embedding = await _embedding.getEmbeddingFromFile(file);
    final doSign = withSignature ?? (_signature != null);

    if (!doSign) {
      return BiometricExportData.embeddingOnly(embedding);
    }

    if (_signature == null) {
      throw BiometricHardwareUnavailableException(
        'SignatureService not configured. Pass signatureService to BiometricExportService, or use withSignature: false.',
      );
    }

    device_integrity.SignResult signResult;
    try {
      signResult = await _signature.signEmbedding(embedding);
    } on device_integrity.BiometricHardwareUnavailableException catch (e) {
      throw BiometricHardwareUnavailableException(e.details);
    } on device_integrity.UserCanceledException catch (e) {
      throw UserCanceledException(e.details);
    } catch (e) {
      throw EmbeddingException('Signing failed', e.toString());
    }

    return BiometricExportData(
      embedding: embedding,
      biometricSignature: signResult.signature,
      biometricPublicKey: signResult.publicKey,
      signedPayload: signResult.signedPayload,
      deviceSignature: signResult.deviceSignature,
    );
  }

  /// POSTs [data] to [apiUrl] as JSON. Returns the response body on success.
  /// Throws on network or server error.
  Future<String> uploadBiometricData(String apiUrl, BiometricExportData data) {
    return uploadBiometricDataRaw(apiUrl, data.toJson());
  }

  /// Verifies device ownership by signing a [challenge] from the server and POSTing to [apiUrl].
  /// Requires [signatureService] to be set.
  ///
  /// Flow: server sends challenge → user authenticates with biometric → signs challenge →
  /// POST {biometricSignature, biometricPublicKey, signedPayload: challenge}. Server verifies
  /// signature and checks publicKey is enrolled for this user.
  ///
  /// Returns [BiometricVerificationSignatureInvalid] when this device is not enrolled
  /// (user changed phone) → app should trigger recovery: capture selfie, verify embedding,
  /// then call [verifyAndUploadBiometricData] to recovery endpoint to enroll new device.
  Future<BiometricVerificationResult> verifyWithChallenge(
    String apiUrl,
    String challenge, {
    Map<String, String>? headers,
  }) async {
    if (_signature == null) {
      throw BiometricHardwareUnavailableException(
        'verifyWithChallenge requires SignatureService. Pass signatureService to BiometricExportService.',
      );
    }
    device_integrity.SignResult signResult;
    try {
      signResult = await _signature.signChallenge(challenge);
    } on device_integrity.BiometricHardwareUnavailableException catch (e) {
      throw BiometricHardwareUnavailableException(e.details);
    } on device_integrity.UserCanceledException catch (e) {
      throw UserCanceledException(e.details);
    }
    final payload = {
      'biometricSignature': signResult.signature,
      if (signResult.publicKey != null)
        'biometricPublicKey': signResult.publicKey,
      'signedPayload': signResult.signedPayload,
      'deviceSignature': signResult.deviceSignature,
    };
    return _postAndParseVerificationResult(apiUrl, payload, headers: headers);
  }

  /// Shared logic to POST payload and parse verification response.
  Future<BiometricVerificationResult> _postAndParseVerificationResult(
    String apiUrl,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) async {
    final defaultHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final allHeaders = {...defaultHeaders, ...?headers};

    try {
      final uri = Uri.parse(apiUrl);
      final body = utf8.encode(jsonEncode(payload));
      final response = await _client.post(uri, headers: allHeaders, body: body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return BiometricVerificationError(
          message: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>?;
      if (json == null) {
        return BiometricVerificationError(message: 'Invalid response');
      }

      final code = (json['code'] ?? json['status'])?.toString().toLowerCase();
      final message = json['message']?.toString();

      switch (code) {
        case 'success':
        case 'verified':
          return BiometricVerificationSuccess(message: message);
        case 'signature_invalid':
        case 'signature_not_registered':
          return BiometricVerificationSignatureInvalid(
            message:
                message ??
                'Signature not valid. Please add this device to your account.',
          );
        case 'embedding_mismatch':
        case 'face_mismatch':
          return BiometricVerificationEmbeddingMismatch(
            message: message ?? 'Your face does not match our records.',
          );
        default:
          return BiometricVerificationError(
            message: message ?? 'Unknown response: $code',
          );
      }
    } catch (e) {
      return BiometricVerificationError(message: e.toString());
    }
  }

  /// Uploads [data] and parses the server's verification response.
  ///
  /// Expected server response JSON:
  /// ```json
  /// { "code": "success" }           // or "verified"
  /// { "code": "signature_invalid" } // signature/publicKey not registered
  /// { "code": "embedding_mismatch" }// face doesn't match user record
  /// ```
  /// Pass [headers] for auth (e.g. `{"Authorization": "Bearer $token"}`).
  ///
  /// Use for: (1) registration, (2) recovery (enroll new device) — same payload; server
  /// uses different endpoint/logic: recovery verifies embedding first, then adds new key.
  Future<BiometricVerificationResult> verifyAndUploadBiometricData(
    String apiUrl,
    BiometricExportData data, {
    Map<String, String>? headers,
  }) async {
    return _postAndParseVerificationResult(
      apiUrl,
      data.toJson(),
      headers: headers,
    );
  }

  /// POSTs [payload] (must be JSON-serializable) to [apiUrl]. Returns the response body.
  Future<String> uploadBiometricDataRaw(
    String apiUrl,
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse(apiUrl);
    final body = utf8.encode(jsonEncode(payload));
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw UploadException(
      'Upload failed',
      'HTTP ${response.statusCode}: ${response.body}',
    );
  }

  /// Releases resources (e.g. HTTP client). Optional.
  void close() {
    _client.close();
  }
}
