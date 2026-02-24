/// Configuration for [FaceLivenessScanner] — customize liveness thresholds.
///
/// Use this when you want to adjust sensitivity for different environments
/// or user populations (e.g. stricter for high-security, looser for accessibility).
class LivenessConfig {
  const LivenessConfig({
    this.eyeClosedThreshold = 0.25,
    this.eyeOpenThreshold = 0.45,
    this.faceSizeMin = 0.18,
    this.faceSizeMax = 0.55,
    this.maxYawDeg = 20.0,
    this.maxRollDeg = 20.0,
    this.maxPitchDeg = 20.0,
    this.eyesOpenMinForIndicator = 0.50,
    this.minFaceSize = 0.15,
  });

  /// Eye-open probability below which both eyes count as "closed" (blink).
  /// Default 0.25.
  final double eyeClosedThreshold;

  /// Eye-open probability above which both eyes count as "open" (after blink).
  /// Default 0.45.
  final double eyeOpenThreshold;

  /// Minimum normalized face size (0.0–1.0). Face too far = reject.
  /// Default 0.18.
  final double faceSizeMin;

  /// Maximum normalized face size (0.0–1.0). Face too close = reject.
  /// Default 0.55.
  final double faceSizeMax;

  /// Max yaw (Y-axis, left/right turn) in degrees.
  /// Default 20.0.
  final double maxYawDeg;

  /// Max roll (Z-axis, tilt) in degrees.
  /// Default 20.0.
  final double maxRollDeg;

  /// Max pitch (X-axis, nod up/down) in degrees.
  /// Default 20.0.
  final double maxPitchDeg;

  /// Min eye-open probability for the progress chip indicator.
  /// Default 0.50.
  final double eyesOpenMinForIndicator;

  /// ML Kit face detector min face size (0.0–1.0).
  /// Default 0.15.
  final double minFaceSize;

  /// Default config — balanced for typical selfie conditions.
  static const LivenessConfig defaultConfig = LivenessConfig();

  /// Stricter config — smaller tolerance for head pose and face size.
  static const LivenessConfig strict = LivenessConfig(
    maxYawDeg: 12.0,
    maxRollDeg: 12.0,
    maxPitchDeg: 12.0,
    faceSizeMin: 0.22,
    faceSizeMax: 0.50,
  );

  /// Lenient config — more tolerance for head pose (accessibility).
  static const LivenessConfig lenient = LivenessConfig(
    maxYawDeg: 30.0,
    maxRollDeg: 30.0,
    maxPitchDeg: 30.0,
    faceSizeMin: 0.14,
    faceSizeMax: 0.60,
  );
}
