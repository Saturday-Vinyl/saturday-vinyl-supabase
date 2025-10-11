import 'package:logger/logger.dart';

/// Application logger wrapper
/// Provides consistent logging throughout the app
class AppLogger {
  AppLogger._(); // Private constructor

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2, // Number of method calls to be displayed
      errorMethodCount: 8, // Number of method calls if stacktrace is provided
      lineLength: 120, // Width of the output
      colors: true, // Colorful log messages
      printEmojis: true, // Print an emoji for each log message
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart, // Include timestamp
    ),
  );

  /// Log debug message
  /// Use for detailed information during development
  static void debug(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log info message
  /// Use for general informational messages
  static void info(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log warning message
  /// Use for potentially harmful situations
  static void warning(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log error message
  /// Use for error events that might still allow the app to continue
  static void error(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log fatal error message
  /// Use for very severe error events that will presumably lead the app to abort
  static void fatal(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }

  /// Log with custom level
  static void log(Level level, dynamic message,
      [dynamic error, StackTrace? stackTrace]) {
    _logger.log(level, message, error: error, stackTrace: stackTrace);
  }

  /// Close the logger
  /// Call this when the app is shutting down
  static void close() {
    _logger.close();
  }
}
