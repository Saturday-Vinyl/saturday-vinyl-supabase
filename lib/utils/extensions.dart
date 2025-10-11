import 'package:intl/intl.dart';

/// String extensions
extension StringExtensions on String {
  /// Get initials from a full name
  /// Examples:
  /// - "John Doe" → "JD"
  /// - "John" → "J"
  /// - "John Paul Smith" → "JS"
  /// - "" → "?"
  String get initials {
    final trimmed = trim();
    if (trimmed.isEmpty) return '?';

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  /// Capitalize first letter of each word
  String get titleCase {
    if (isEmpty) return this;

    return split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Convert snake_case to Title Case
  String get snakeToTitleCase {
    return split('_')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }
}

/// DateTime extensions
extension DateTimeExtensions on DateTime {
  /// Format date as "Oct 8, 2025"
  String get friendlyDate {
    return DateFormat('MMM d, y').format(this);
  }

  /// Format date as "October 8, 2025"
  String get fullDate {
    return DateFormat('MMMM d, y').format(this);
  }

  /// Format date as "10/8/2025"
  String get shortDate {
    return DateFormat('M/d/y').format(this);
  }

  /// Format time as "2:30 PM"
  String get friendlyTime {
    return DateFormat('h:mm a').format(this);
  }

  /// Format date and time as "Oct 8, 2025 at 2:30 PM"
  String get friendlyDateTime {
    return '$friendlyDate at $friendlyTime';
  }

  /// Get relative time string like "2 hours ago" or "in 3 days"
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(this);

    if (difference.isNegative) {
      // Future date
      final futureDiff = difference.abs();
      if (futureDiff.inDays > 365) {
        final years = (futureDiff.inDays / 365).floor();
        return 'in $years ${years == 1 ? 'year' : 'years'}';
      } else if (futureDiff.inDays > 30) {
        final months = (futureDiff.inDays / 30).floor();
        return 'in $months ${months == 1 ? 'month' : 'months'}';
      } else if (futureDiff.inDays > 0) {
        return 'in ${futureDiff.inDays} ${futureDiff.inDays == 1 ? 'day' : 'days'}';
      } else if (futureDiff.inHours > 0) {
        return 'in ${futureDiff.inHours} ${futureDiff.inHours == 1 ? 'hour' : 'hours'}';
      } else if (futureDiff.inMinutes > 0) {
        return 'in ${futureDiff.inMinutes} ${futureDiff.inMinutes == 1 ? 'minute' : 'minutes'}';
      } else {
        return 'in a few seconds';
      }
    }

    // Past date
    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'just now';
    }
  }
}
