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
    if (githubToken.isEmpty) {
      missingVars.add(AppConstants.githubTokenKey);
    }
    if (githubRepoOwner.isEmpty) {
      missingVars.add(AppConstants.githubRepoOwnerKey);
    }
    if (githubRepoName.isEmpty) {
      missingVars.add(AppConstants.githubRepoNameKey);
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

  // GitHub Configuration
  static String get githubToken => _get(AppConstants.githubTokenKey);
  static String get githubRepoOwner => _get(AppConstants.githubRepoOwnerKey);
  static String get githubRepoName => _get(AppConstants.githubRepoNameKey);

  // RFID Configuration
  /// Access password for locking/unlocking RFID tags (8 hex characters = 4 bytes)
  /// Example: "AABBCCDD" -> [0xAA, 0xBB, 0xCC, 0xDD]
  /// If not set, defaults to "00000000" (unlocked tags)
  static String get rfidAccessPassword =>
      _get(AppConstants.rfidAccessPasswordKey);

  /// Get RFID access password as bytes (4 bytes)
  static List<int> get rfidAccessPasswordBytes {
    final hex = rfidAccessPassword;
    if (hex.isEmpty || hex.length != 8) {
      return [0x00, 0x00, 0x00, 0x00]; // Default for unlocked tags
    }
    return [
      int.parse(hex.substring(0, 2), radix: 16),
      int.parse(hex.substring(2, 4), radix: 16),
      int.parse(hex.substring(4, 6), radix: 16),
      int.parse(hex.substring(6, 8), radix: 16),
    ];
  }

  /// Check if environment is loaded
  static bool get isLoaded => dotenv.isInitialized;

  /// Get all environment variables (for debugging - use with caution)
  /// Do not log sensitive values in production!
  static Map<String, String> get all => dotenv.env;
}
