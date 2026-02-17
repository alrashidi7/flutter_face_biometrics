import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'export_models.dart';

/// Default filename for stored biometric data (acts as local DB).
const String kDefaultBiometricStorageFilename = 'biometric_export_data.json';

/// Default filename for stored enrolled face image.
const String kDefaultEnrolledImageFilename = 'enrolled_face.jpg';

/// Saves and loads [BiometricExportData] as JSON in a local file (acts as a simple DB).
class BiometricLocalStorage {
  BiometricLocalStorage({
    this.filename = kDefaultBiometricStorageFilename,
    this.enrolledImageFilename = kDefaultEnrolledImageFilename,
  });

  final String filename;
  final String enrolledImageFilename;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(path.join(dir.path, filename));
  }

  Future<File> _getEnrolledImageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(path.join(dir.path, enrolledImageFilename));
  }

  /// Saves [data] to the local JSON file. Overwrites existing data.
  /// If [enrolledImage] is provided, copies it to persistent storage for verify (extract face from both images).
  Future<void> save(
    BiometricExportData data, {
    File? enrolledImage,
  }) async {
    String? enrolledImagePath;
    if (enrolledImage != null && await enrolledImage.exists()) {
      final dest = await _getEnrolledImageFile();
      await enrolledImage.copy(dest.path);
      enrolledImagePath = dest.path;
    }

    final json = data.toJson();
    if (enrolledImagePath != null) {
      json['enrolledImagePath'] = enrolledImagePath;
    }
    json['savedAt'] = DateTime.now().toUtc().toIso8601String();

    final file = await _getFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
  }

  /// Loads the stored biometric data. Returns null if file does not exist or is invalid.
  Future<BiometricExportData?> load() async {
    final file = await _getFile();
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>?;
      if (json == null) return null;
      return BiometricExportData.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Returns true if stored data exists.
  Future<bool> hasStoredData() async {
    final file = await _getFile();
    return file.existsSync();
  }

  /// Deletes the stored file and enrolled image.
  Future<void> clear() async {
    final file = await _getFile();
    if (await file.exists()) {
      await file.delete();
    }
    final imgFile = await _getEnrolledImageFile();
    if (await imgFile.exists()) {
      await imgFile.delete();
    }
  }
}
