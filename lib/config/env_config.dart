import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Environment configuration loader and validator.
///
/// Loads environment variables from .env file and provides
/// type-safe access to configuration values.
class EnvConfig {
  EnvConfig._();

  static bool _initialized = false;

  /// Loads and validates environment configuration.
  ///
  /// Must be called before accessing any configuration values.
  /// Throws [EnvironmentConfigException] if required variables are missing.
  static Future<void> load() async {
    if (_initialized) return;

    await dotenv.load(fileName: '.env');
    _validateRequiredVariables();
    _initialized = true;
  }

  /// Validates that all required environment variables are present.
  static void _validateRequiredVariables() {
    final missingVars = <String>[];

    for (final key in _requiredVariables) {
      if (!dotenv.isEveryDefined([key])) {
        missingVars.add(key);
      }
    }

    if (missingVars.isNotEmpty) {
      throw EnvironmentConfigException(
        'Missing required environment variables: ${missingVars.join(', ')}. '
        'Please check your .env file.',
      );
    }
  }

  /// List of required environment variables.
  static const List<String> _requiredVariables = [
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
  ];

  /// Supabase project URL.
  static String get supabaseUrl => dotenv.env['SUPABASE_URL']!;

  /// Supabase anonymous key.
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY']!;

  /// Base URL for Saturday web services.
  static String get appBaseUrl =>
      dotenv.env['APP_BASE_URL'] ?? 'https://saturdayvinyl.com';

  /// Discogs API key.
  static String? get discogsApiKey => dotenv.env['DISCOGS_API_KEY'];

  /// Discogs API secret.
  static String? get discogsApiSecret => dotenv.env['DISCOGS_API_SECRET'];

  /// Whether the configuration has been loaded.
  static bool get isInitialized => _initialized;
}

/// Exception thrown when environment configuration is invalid.
class EnvironmentConfigException implements Exception {
  final String message;

  EnvironmentConfigException(this.message);

  @override
  String toString() => 'EnvironmentConfigException: $message';
}
