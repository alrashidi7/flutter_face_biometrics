import 'dart:io';

import 'package:tensorflow_face_verification/tensorflow_face_verification.dart';

import 'biometric_local_storage.dart';
import 'export_models.dart';

/// Default similarity threshold (≥ this = same person). Typical FaceNet threshold is 0.6.
const double kDefaultSimilarityThreshold = 0.6;

/// Lenient threshold for gallery vs camera (different lighting, angle). Use when gallery images fail with same person.
const double kLenientSimilarityThreshold = 0.4;

/// Result of local verification against stored biometric data.
sealed class LocalVerificationResult {}

/// Embedding and signature both matched. Verification successful.
final class LocalVerificationSuccess extends LocalVerificationResult {
  LocalVerificationSuccess({this.similarityScore});
  final double? similarityScore;
}

/// No stored data to verify against.
final class LocalVerificationNoStoredData extends LocalVerificationResult {}

/// Embedding does not match (face mismatch).
final class LocalVerificationEmbeddingMismatch extends LocalVerificationResult {
  LocalVerificationEmbeddingMismatch({this.similarityScore, this.message});
  final double? similarityScore;
  final String? message;
}

/// Signature/public key does not match (different device).
final class LocalVerificationSignatureMismatch extends LocalVerificationResult {
  LocalVerificationSignatureMismatch({this.message});
  final String? message;
}

/// Error during verification.
final class LocalVerificationError extends LocalVerificationResult {
  LocalVerificationError({this.message});
  final String? message;
}

/// Callback to extract face embedding from an image file.
/// Uses extractFaceRegion → extractFaceEmbedding (same as tensorflow_face_verification example).
typedef EmbeddingExtractor = Future<List<double>> Function(File imageFile);

/// Verifies new biometric data against locally stored data.
class BiometricLocalVerifier {
  BiometricLocalVerifier({
    BiometricLocalStorage? storage,
    this.similarityThreshold = kDefaultSimilarityThreshold,
    this.verifySignature = true,
    this.embeddingExtractor,
  }) : storage = storage ?? BiometricLocalStorage();

  final BiometricLocalStorage storage;
  final double similarityThreshold;
  final bool verifySignature;

  /// Extracts embedding via extractFaceRegion → extractFaceEmbedding. Required for [verifyWithImage].
  final EmbeddingExtractor? embeddingExtractor;

  /// Verifies [newImage] by extracting face from both images, then comparing embeddings.
  /// Same flow as tensorflow_face_verification:
  ///   extractFaceRegion(image) → extractFaceEmbedding(faceRegion) for each image, then getSimilarityScore.
  /// Requires [embeddingExtractor]. If stored has [enrolledImagePath], extracts from both; else uses stored embedding.
  Future<LocalVerificationResult> verifyWithImage(File newImage) async {
    if (embeddingExtractor == null) {
      return LocalVerificationError(
        message: 'verifyWithImage requires embeddingExtractor',
      );
    }
    final stored = await storage.load();
    if (stored == null) {
      return LocalVerificationNoStoredData();
    }

    try {
      List<double> embedding1;
      final enrolledPath = stored.enrolledImagePath;
      if (enrolledPath != null) {
        final enrolledFile = File(enrolledPath);
        if (await enrolledFile.exists()) {
          embedding1 = await _extractEmbeddingViaFaceRegion(enrolledFile);
        } else {
          embedding1 = stored.embedding;
        }
      } else {
        embedding1 = stored.embedding;
      }

      final embedding2 = await _extractEmbeddingViaFaceRegion(newImage);

      final score = FaceVerification.instance.getSimilarityScore(
        embedding1,
        embedding2,
      );

      if (score < similarityThreshold) {
        return LocalVerificationEmbeddingMismatch(
          similarityScore: score,
          message:
              'Face does not match. Similarity: ${score.toStringAsFixed(2)} (need ≥ $similarityThreshold)',
        );
      }
      return LocalVerificationSuccess(similarityScore: score);
    } catch (e) {
      return LocalVerificationError(message: e.toString());
    }
  }

  /// Extracts embedding via extractFaceRegion → extractFaceEmbedding (same as tensorflow_face_verification).
  /// Falls back to [embeddingExtractor] when extractFaceRegion returns null (e.g. needs EXIF/rotation).
  Future<List<double>> _extractEmbeddingViaFaceRegion(File imageFile) async {
    final faceRegion = await FaceVerification.instance.extractFaceRegion(
      imageFile,
    );
    if (faceRegion != null) {
      final embedding = await FaceVerification.instance.extractFaceEmbedding(
        faceRegion,
      );
      if (embedding.isNotEmpty) return embedding;
    }
    return embeddingExtractor!(imageFile);
  }

  /// Verifies using only [newEmbedding] (e.g. from gallery image). Skips signature check.
  /// Prefer [verifyWithImage] to extract face from both images for consistency.
  Future<LocalVerificationResult> verifyWithEmbedding(
    List<double> newEmbedding,
  ) async {
    final stored = await storage.load();
    if (stored == null) {
      return LocalVerificationNoStoredData();
    }
    try {
      final score = FaceVerification.instance.getSimilarityScore(
        stored.embedding,
        newEmbedding,
      );
      if (score < similarityThreshold) {
        return LocalVerificationEmbeddingMismatch(
          similarityScore: score,
          message:
              'Face does not match. Similarity: ${score.toStringAsFixed(2)} (need ≥ $similarityThreshold)',
        );
      }
      return LocalVerificationSuccess(similarityScore: score);
    } catch (e) {
      return LocalVerificationError(message: e.toString());
    }
  }

  /// Verifies [newData] against stored data.
  ///
  /// 1. Loads stored data
  /// 2. Compares embedding similarity (FaceNet)
  /// 3. Optionally checks public key match (same device)
  Future<LocalVerificationResult> verify(BiometricExportData newData) async {
    final stored = await storage.load();
    if (stored == null) {
      return LocalVerificationNoStoredData();
    }

    try {
      final score = FaceVerification.instance.getSimilarityScore(
        stored.embedding,
        newData.embedding,
      );

      if (score < similarityThreshold) {
        return LocalVerificationEmbeddingMismatch(
          similarityScore: score,
          message:
              'Face does not match. Similarity: ${score.toStringAsFixed(2)} (need ≥ $similarityThreshold)',
        );
      }

      if (verifySignature &&
          stored.biometricPublicKey != null &&
          newData.biometricPublicKey != null &&
          stored.biometricPublicKey != newData.biometricPublicKey) {
        return LocalVerificationSignatureMismatch(
          message:
              'Signature does not match. This device is not the one that enrolled.',
        );
      }

      return LocalVerificationSuccess(similarityScore: score);
    } catch (e) {
      return LocalVerificationError(message: e.toString());
    }
  }
}
