/// Validation utilities for forms and user input
class Validators {
  Validators._(); // Private constructor to prevent instantiation

  /// Validate semantic versioning format (X.Y.Z)
  ///
  /// Returns null if valid, error message if invalid
  /// Valid examples: 1.0.0, 2.3.1, 10.0.15
  /// Invalid examples: 1.0, v1.0.0, 1.0.0-beta
  static String? validateSemanticVersion(String? value) {
    if (value == null || value.isEmpty) {
      return 'Version is required';
    }

    // Regex for semantic versioning: X.Y.Z where X, Y, Z are numbers
    final regex = RegExp(r'^\d+\.\d+\.\d+$');

    if (!regex.hasMatch(value)) {
      return 'Version must be in format X.Y.Z (e.g., 1.0.0)';
    }

    return null;
  }

  /// Validate email format
  ///
  /// Returns null if valid, error message if invalid
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }

    // Basic email regex pattern
    final regex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!regex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Validate URL format
  ///
  /// Returns null if valid, error message if invalid
  static String? validateUrl(String? value) {
    if (value == null || value.isEmpty) {
      return 'URL is required';
    }

    // URL regex pattern
    final regex = RegExp(
      r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$',
    );

    if (!regex.hasMatch(value)) {
      return 'Please enter a valid URL';
    }

    return null;
  }

  /// Validate required field
  ///
  /// Returns null if not empty, error message if empty
  static String? validateRequired(String? value, {String fieldName = 'Field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Validate minimum length
  ///
  /// Returns null if length is valid, error message if too short
  static String? validateMinLength(
    String? value,
    int minLength, {
    String fieldName = 'Field',
  }) {
    if (value == null || value.isEmpty) {
      return '$fieldName is required';
    }

    if (value.length < minLength) {
      return '$fieldName must be at least $minLength characters';
    }

    return null;
  }

  /// Validate maximum length
  ///
  /// Returns null if length is valid, error message if too long
  static String? validateMaxLength(
    String? value,
    int maxLength, {
    String fieldName = 'Field',
  }) {
    if (value != null && value.length > maxLength) {
      return '$fieldName must be at most $maxLength characters';
    }

    return null;
  }

  /// Check if a string is a valid semantic version
  ///
  /// Returns true if valid, false if invalid
  static bool isValidSemanticVersion(String value) {
    final regex = RegExp(r'^\d+\.\d+\.\d+$');
    return regex.hasMatch(value);
  }

  /// Compare two semantic versions
  ///
  /// Returns:
  /// - negative if v1 < v2
  /// - 0 if v1 == v2
  /// - positive if v1 > v2
  static int compareSemanticVersions(String v1, String v2) {
    final parts1 = v1.split('.').map(int.parse).toList();
    final parts2 = v2.split('.').map(int.parse).toList();

    // Compare major version
    if (parts1[0] != parts2[0]) {
      return parts1[0].compareTo(parts2[0]);
    }

    // Compare minor version
    if (parts1[1] != parts2[1]) {
      return parts1[1].compareTo(parts2[1]);
    }

    // Compare patch version
    return parts1[2].compareTo(parts2[2]);
  }
}
