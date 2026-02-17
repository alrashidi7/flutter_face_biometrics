/// Configuration for [flutter_face_biometrics] package behavior.
///
/// Use this when you rely on dependency injection in your main app and want
/// the package to **never** create internal instances of [BiometricExportService],
/// [BiometricLocalStorage], or [BiometricLocalVerifier].
///
/// **Example with DI (e.g. GetIt, Provider, Riverpod):**
/// ```dart
/// // In your DI setup
/// final config = FlutterFaceBiometricsConfig(
///   requireInjectedDependencies: true,
/// );
///
/// // In your widget - inject service & storage from DI
/// BiometricEnrollmentFlow(
///   config: config,
///   service: getIt<BiometricExportService>(),
///   storage: getIt<BiometricLocalStorage>(),
///   ...
/// )
/// ```
///
/// When [requireInjectedDependencies] is `true`:
/// - [BiometricEnrollmentFlow] requires [BiometricExportService] and [BiometricLocalStorage]
/// - [BiometricVerificationFlow] requires [BiometricExportService], [BiometricLocalStorage],
///   and optionally [BiometricLocalVerifier] (or it builds from service+storage)
/// - Internal fallback creation is skipped; missing dependencies throw at initialization
///
/// When [requireInjectedDependencies] is `false` (default):
/// - Null [service]/[storage]/[verifier] are replaced with internal defaults (current behavior)
class FlutterFaceBiometricsConfig {
  const FlutterFaceBiometricsConfig({
    this.requireInjectedDependencies = false,
  });

  /// When true, flows will not create internal instances. [service] and [storage]
  /// must be provided by the caller (e.g. via dependency injection).
  ///
  /// Use this when your app uses DI and you want full control over these instances.
  final bool requireInjectedDependencies;

  /// Default config: internal defaults are used when dependencies are null.
  static const FlutterFaceBiometricsConfig defaultConfig =
      FlutterFaceBiometricsConfig(requireInjectedDependencies: false);

  /// Config for DI apps: dependencies must be injected; no internal creation.
  static const FlutterFaceBiometricsConfig diConfig =
      FlutterFaceBiometricsConfig(requireInjectedDependencies: true);
}
