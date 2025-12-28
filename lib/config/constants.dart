/// App-wide constants for the Saturday Consumer App.
class AppConstants {
  AppConstants._();

  /// App name displayed throughout the UI.
  static const String appName = 'Saturday';

  /// App display tagline.
  static const String appTagline = 'Your vinyl companion';

  /// Base URL for Saturday web services.
  static const String webBaseUrl = 'https://saturdayvinyl.com';

  /// Saturday EPC prefix (hex representation of "SV").
  static const String saturdayEpcPrefix = '5356';

  /// Expected length of a valid EPC identifier in hex characters.
  static const int epcHexLength = 24;

  /// URL pattern for tag deep links.
  static const String tagUrlPattern = '/tags/';

  /// URL pattern for album deep links.
  static const String albumUrlPattern = '/albums/';

  /// URL pattern for invite deep links.
  static const String inviteUrlPattern = '/invite/';
}

/// API and network constants.
class ApiConstants {
  ApiConstants._();

  /// Default timeout for API requests.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Default page size for paginated requests.
  static const int defaultPageSize = 20;

  /// Maximum page size for paginated requests.
  static const int maxPageSize = 100;
}

/// Cache constants.
class CacheConstants {
  CacheConstants._();

  /// Duration to cache album metadata.
  static const Duration albumCacheDuration = Duration(days: 7);

  /// Duration to cache images.
  static const Duration imageCacheDuration = Duration(days: 30);

  /// Maximum number of cached images.
  static const int maxCachedImages = 500;
}

/// Validation constants.
class ValidationConstants {
  ValidationConstants._();

  /// Minimum password length.
  static const int minPasswordLength = 8;

  /// Maximum library name length.
  static const int maxLibraryNameLength = 50;

  /// Maximum album notes length.
  static const int maxNotesLength = 500;
}
