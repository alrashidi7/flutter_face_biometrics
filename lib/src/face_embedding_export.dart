import 'dart:io';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:tensorflow_face_verification/tensorflow_face_verification.dart';

import 'export_errors.dart';
import 'utils/image_utils.dart';

/// Default path to the FaceNet TFLite model in assets.
/// App must include this asset (e.g. from package or app assets).
const String kDefaultFacenetModelPath = 'assets/models/facenet.tflite';

/// Service for extracting face embeddings from [CameraImage] or [File].
/// Wraps [FaceEmbeddingExport] and adds [extractEmbedding] for camera frames.
class FaceEmbeddingService {
  FaceEmbeddingService({required this.modelPath})
      : _export = FaceEmbeddingExport(modelPath: modelPath);

  final String modelPath;
  final FaceEmbeddingExport _export;

  /// Initializes the FaceNet model. Call before extracting embeddings.
  Future<void> init() => _export.init();

  /// Extracts a 128D face embedding from [cameraImage].
  ///
  /// Saves the image to a temp file, then uses tensorflow_face_verification
  /// to extract the face region and compute the embedding.
  ///
  /// Throws [NoFaceDetectedException], [MultipleFacesDetectedException], [EmbeddingException].
  Future<List<double>> extractEmbedding(CameraImage cameraImage) async {
    final image = cameraImageToImage(cameraImage);
    if (image == null) {
      throw EmbeddingException(
        'Failed to convert CameraImage',
        'Format: ${cameraImage.format.group}',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      path.join(
        tempDir.path,
        'flutter_face_biometrics_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );
    try {
      final jpeg = img.encodeJpg(image);
      if (jpeg.isEmpty) throw EmbeddingException('Failed to encode image as JPEG');
      await tempFile.writeAsBytes(jpeg);
      return _export.getEmbeddingFromFile(tempFile);
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Extracts embedding from a file path (e.g. from saved selfie).
  Future<List<double>> extractEmbeddingFromFile(File file) =>
      _export.getEmbeddingFromFile(file);
}

/// Extracts a high-dimensional face embedding from an image file using
/// [tensorflow_face_verification] (FaceNet). Call [init] once before use.
class FaceEmbeddingExport {
  FaceEmbeddingExport({this.modelPath = kDefaultFacenetModelPath});

  final String modelPath;
  bool _initialized = false;

  /// Whether the FaceNet model is loaded.
  bool get isInitialized =>
      _initialized || FaceVerification.isInitialized;

  /// Loads the TFLite FaceNet model. Call once (e.g. at app start or before first capture).
  Future<void> init() async {
    if (FaceVerification.isInitialized) {
      _initialized = true;
      return;
    }
    try {
      await FaceVerification.init(modelPath: modelPath);
      _initialized = true;
    } catch (e) {
      throw EmbeddingException(
        'Failed to load face verification model',
        e.toString(),
      );
    }
  }

  /// Extracts the face embedding from [imageFile].
  /// Throws [NoFaceDetectedException] if no face is found in the image.
  /// Throws [EmbeddingException] if model is not loaded or extraction fails.
  ///
  /// Applies EXIF orientation first (critical for gallery images).
  /// If the first attempt fails, retries with rotated versions (90°, 180°, 270°)
  /// to handle orientation differences across devices.
  Future<List<double>> getEmbeddingFromFile(File imageFile) async {
    if (!imageFile.existsSync()) {
      throw EmbeddingException('Image file does not exist', imageFile.path);
    }
    if (!isInitialized) {
      await init();
    }

    File fileToProcess = imageFile;
    final normalized = await _normalizeImageOrientation(imageFile);
    if (normalized != null) {
      fileToProcess = normalized;
    }

    NoFaceDetectedException? lastError;
    final anglesToTry = [0, 90, 180, 270];

    for (final angle in anglesToTry) {
      try {
        File fileToUse = fileToProcess;
        if (angle != 0) {
          fileToUse = await _rotateAndSaveTemp(fileToProcess, angle);
        }
        final faceImage = await FaceVerification.instance.extractFaceRegion(
          fileToUse,
        );
        if (faceImage != null) {
          final embedding = await FaceVerification.instance.extractFaceEmbedding(
            faceImage,
          );
          if (embedding.isNotEmpty) {
            if (fileToUse.path != fileToProcess.path) {
              try {
                fileToUse.deleteSync();
              } catch (_) {}
            }
            if (normalized != null && normalized.path != imageFile.path) {
              try {
                normalized.deleteSync();
              } catch (_) {}
            }
            return embedding;
          }
        }
        if (fileToUse.path != fileToProcess.path) {
          try {
            fileToUse.deleteSync();
          } catch (_) {}
        }
      } on NoFaceDetectedException catch (e) {
        lastError = e;
      } on BiometricExportException {
        rethrow;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('no face') || msg.contains('face not found')) {
          lastError = NoFaceDetectedException(e.toString());
        }
      }
    }

    throw lastError ??
        const NoFaceDetectedException(
          'No face found in image by face verification',
        );
  }

  /// Decodes image, applies EXIF orientation, saves to temp. Returns null if decode fails.
  Future<File?> _normalizeImageOrientation(File source) async {
    try {
      final bytes = await source.readAsBytes();
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      decoded = img.bakeOrientation(decoded);
      final jpeg = img.encodeJpg(decoded, quality: 95);
      if (jpeg.isEmpty) return null;
      final tempDir = await getTemporaryDirectory();
      final out = File(
        path.join(
          tempDir.path,
          'exif_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
      await out.writeAsBytes(jpeg);
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<File> _rotateAndSaveTemp(File source, int angle) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw EmbeddingException('Could not decode image');
    final rotated = img.copyRotate(decoded, angle: angle.toDouble());
    final jpeg = img.encodeJpg(rotated, quality: 95);
    if (jpeg.isEmpty) throw EmbeddingException('Could not encode rotated image');
    final tempDir = await getTemporaryDirectory();
    final out = File(
      path.join(
        tempDir.path,
        'rotated_${angle}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );
    await out.writeAsBytes(jpeg);
    return out;
  }
}
