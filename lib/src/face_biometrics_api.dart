import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:tensorflow_face_verification/tensorflow_face_verification.dart';

import 'face_embedding_export.dart';

/// Core API for face embedding extraction — use without widgets.
///
/// For developers who build their own UI or don't need the package widgets:
///
/// ```dart
/// final api = FlutterFaceBiometricsApi(modelPath: 'assets/models/facenet.tflite');
/// // or use default: FlutterFaceBiometricsApi()
/// await api.ensureInitialized();
///
/// // Extract embedding from any image (file or bytes)
/// final embedding = await api.extractEmbeddingFromFile(myImageFile);
/// // Use embedding in your app (compare, store, upload, etc.)
/// ```
///
/// - [extractEmbeddingFromFile]: Extract 128D face embedding from a file.
/// - [extractEmbeddingFromBytes]: Extract embedding from image bytes.
/// - No widgets, no storage, no signature — just face detection + embedding.
class FlutterFaceBiometricsApi {
  FlutterFaceBiometricsApi({String? modelPath})
      : modelPath = modelPath ?? kDefaultFacenetModelPath,
        _export = FaceEmbeddingExport(modelPath: modelPath ?? kDefaultFacenetModelPath);

  final String modelPath;
  final FaceEmbeddingExport _export;

  bool _initialized = false;

  /// Whether the FaceNet model is loaded.
  bool get isInitialized => _initialized || _export.isInitialized;

  /// Loads the FaceNet model. Call once before extracting embeddings.
  Future<void> ensureInitialized() async {
    if (isInitialized) return;
    await _export.init();
    _initialized = true;
  }

  /// Extracts a 128D face embedding from [imageFile].
  ///
  /// - Extracts the face region and computes the FaceNet embedding.
  /// - Throws [NoFaceDetectedException] if no face is found.
  /// - Throws [MultipleFacesDetectedException] if more than one face.
  /// - Throws [EmbeddingException] on model or extraction errors.
  ///
  /// Returns the embedding vector for your app to store, compare, or upload.
  Future<List<double>> extractEmbeddingFromFile(File imageFile) async {
    await ensureInitialized();
    return _export.getEmbeddingFromFile(imageFile);
  }

  /// Extracts embedding from image [bytes].
  ///
  /// Writes bytes to a temp file and calls [extractEmbeddingFromFile].
  /// Throws the same exceptions as [extractEmbeddingFromFile].
  Future<List<double>> extractEmbeddingFromBytes(List<int> bytes) async {
    await ensureInitialized();
    final tempDir = await _getTempDir();
    final file = File('${tempDir.path}/ffb_${DateTime.now().millisecondsSinceEpoch}.jpg');
    try {
      await file.writeAsBytes(bytes);
      return await _export.getEmbeddingFromFile(file);
    } finally {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

  /// Compares two face embeddings. Returns similarity 0.0–1.0 (higher = more similar).
  ///
  /// Uses FaceNet's default comparison. For custom logic, implement your own
  /// and pass [FaceMatcher] to [BiometricLocalVerifier.customMatcher].
  static double compareEmbeddings(List<double> enrolled, List<double> probe) =>
      FaceVerification.instance.getSimilarityScore(enrolled, probe);

  /// Convenience: check if [similarityScore] passes [threshold].
  static bool isMatch(double similarityScore, {double threshold = 0.6}) =>
      similarityScore >= threshold;

  Future<Directory> _getTempDir() async =>
      await getTemporaryDirectory();
}
