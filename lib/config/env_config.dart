import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:saturday_app/config/constants.dart';

/// Environment configuration loader
/// Loads and validates environment variables from .env file
class EnvConfig {
  EnvConfig._(); // Private constructor to prevent instantiation

  /// Load environment variables from .env file
  /// Throws [Exception] if required variables are missing
  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
    _validate();
  }

  /// Validate that all required environment variables are present
  static void _validate() {
    final missingVars = <String>[];

    if (supabaseUrl.isEmpty) {
      missingVars.add(AppConstants.supabaseUrlKey);
    }
    if (supabaseAnonKey.isEmpty) {
      missingVars.add(AppConstants.supabaseAnonKeyKey);
    }
    if (shopifyStoreUrl.isEmpty) {
      missingVars.add(AppConstants.shopifyStoreUrlKey);
    }
    if (shopifyAccessToken.isEmpty) {
      missingVars.add(AppConstants.shopifyAccessTokenKey);
    }
    if (googleClientId.isEmpty) {
      missingVars.add(AppConstants.googleClientIdKey);
    }
    if (appBaseUrl.isEmpty) {
      missingVars.add(AppConstants.appBaseUrlKey);
    }

    if (missingVars.isNotEmpty) {
      throw Exception(
        'Missing required environment variables: ${missingVars.join(', ')}\n'
        'Please ensure your .env file is configured correctly.',
      );
    }
  }

  /// Get environment variable value
  static String _get(String key) {
    return dotenv.get(key, fallback: '');
  }

  // Supabase Configuration
  static String get supabaseUrl => _get(AppConstants.supabaseUrlKey);
  static String get supabaseAnonKey => _get(AppConstants.supabaseAnonKeyKey);

  // Shopify Configuration
  static String get shopifyStoreUrl => _get(AppConstants.shopifyStoreUrlKey);
  static String get shopifyAccessToken =>
      _get(AppConstants.shopifyAccessTokenKey);

  // Google OAuth Configuration
  static String get googleClientId => _get(AppConstants.googleClientIdKey);

  // Application Configuration
  static String get appBaseUrl => _get(AppConstants.appBaseUrlKey);

  /// Check if environment is loaded
  static bool get isLoaded => dotenv.isInitialized;

  /// Get all environment variables (for debugging - use with caution)
  /// Do not log sensitive values in production!
  static Map<String, String> get all => dotenv.env;
}
