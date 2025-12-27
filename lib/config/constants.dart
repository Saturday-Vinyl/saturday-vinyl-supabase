/// Application-wide constants
class AppConstants {
  AppConstants._(); // Private constructor to prevent instantiation

  // App Information
  static const String appName = 'Saturday!';
  static const String appFullName = 'Saturday Vinyl';

  // Environment Variables (loaded from .env)
  // These will be populated by EnvConfig
  static const String supabaseUrlKey = 'SUPABASE_URL';
  static const String supabaseAnonKeyKey = 'SUPABASE_ANON_KEY';
  static const String shopifyStoreUrlKey = 'SHOPIFY_STORE_URL';
  static const String shopifyAccessTokenKey = 'SHOPIFY_ACCESS_TOKEN';
  static const String googleClientIdKey = 'GOOGLE_CLIENT_ID';
  static const String appBaseUrlKey = 'APP_BASE_URL';
  static const String githubTokenKey = 'GITHUB_TOKEN';
  static const String githubRepoOwnerKey = 'GITHUB_REPO_OWNER';
  static const String githubRepoNameKey = 'GITHUB_REPO_NAME';
  static const String rfidAccessPasswordKey = 'RFID_ACCESS_PASSWORD';

  // API Timeouts (in milliseconds)
  static const int apiTimeoutShort = 10000; // 10 seconds
  static const int apiTimeoutMedium = 30000; // 30 seconds
  static const int apiTimeoutLong = 60000; // 60 seconds

  // File Upload Limits
  static const int maxFileSize = 52428800; // 50 MB in bytes
  static const int maxFirmwareFileSize = 104857600; // 100 MB in bytes

  // Pagination
  static const int defaultPageSize = 50;
  static const int defaultProductsPageSize = 25;
  static const int defaultUnitsPageSize = 50;

  // Session
  static const Duration sessionDuration = Duration(days: 7);

  // Minimum Supported Versions
  static const String minIosVersion = '14.0';
  static const String minAndroidVersion = '8.0'; // API Level 26
  static const String minMacOsVersion = '10.15';

  // QR Code Configuration
  static const String qrCodeUrlScheme = 'https';
  static const String qrCodePathPrefix = '/unit/';
  static const String qrCodeTagPathPrefix = '/tags/';

  // Allowed Email Domain
  static const String allowedEmailDomain = '@saturdayvinyl.com';

  // Cache Durations
  static const Duration productsCacheDuration = Duration(minutes: 5);
  static const Duration deviceTypesCacheDuration = Duration(minutes: 10);
  static const Duration firmwareCacheDuration = Duration(minutes: 5);

  // Supabase Storage Buckets
  static const String productionFilesBucket = 'production-files';
  static const String firmwareBinariesBucket = 'firmware-binaries';
  static const String qrCodesBucket = 'qr-codes';
  static const String assetsBucket = 'assets';

  // Default Values
  static const String defaultCurrency = 'USD';
  static const String defaultCountry = 'US';
  static const String defaultLanguage = 'en';

  // Error Messages
  static const String networkErrorMessage = 'Network error. Please check your connection and try again.';
  static const String authErrorMessage = 'Authentication failed. Please sign in again.';
  static const String permissionErrorMessage = 'You do not have permission to perform this action.';
  static const String genericErrorMessage = 'Something went wrong. Please try again.';

  // Success Messages
  static const String saveSuccessMessage = 'Saved successfully';
  static const String deleteSuccessMessage = 'Deleted successfully';
  static const String updateSuccessMessage = 'Updated successfully';
  static const String createSuccessMessage = 'Created successfully';
}
