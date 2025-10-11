import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/utils/extensions.dart';

void main() {
  group('StringExtensions', () {
    group('initials', () {
      test('extracts initials from full name', () {
        expect('John Doe'.initials, equals('JD'));
        expect('Jane Smith'.initials, equals('JS'));
      });

      test('extracts initial from single name', () {
        expect('John'.initials, equals('J'));
        expect('Madonna'.initials, equals('M'));
      });

      test('handles names with middle names', () {
        expect('John Paul Smith'.initials, equals('JS'));
        expect('Mary Jane Watson'.initials, equals('MW'));
      });

      test('handles extra whitespace', () {
        expect('  John   Doe  '.initials, equals('JD'));
        expect('John    Smith   Jones'.initials, equals('JJ'));
      });

      test('returns ? for empty string', () {
        expect(''.initials, equals('?'));
        expect('   '.initials, equals('?'));
      });

      test('converts to uppercase', () {
        expect('john doe'.initials, equals('JD'));
        expect('jane smith'.initials, equals('JS'));
      });
    });

    group('titleCase', () {
      test('capitalizes first letter of each word', () {
        expect('hello world'.titleCase, equals('Hello World'));
        expect('john doe'.titleCase, equals('John Doe'));
      });

      test('handles already capitalized text', () {
        expect('Hello World'.titleCase, equals('Hello World'));
      });

      test('handles mixed case', () {
        expect('hELLo WOrLD'.titleCase, equals('Hello World'));
      });

      test('handles empty string', () {
        expect(''.titleCase, equals(''));
      });

      test('handles single word', () {
        expect('hello'.titleCase, equals('Hello'));
      });
    });

    group('snakeToTitleCase', () {
      test('converts snake_case to Title Case', () {
        expect('manage_products'.snakeToTitleCase, equals('Manage Products'));
        expect('manage_firmware'.snakeToTitleCase, equals('Manage Firmware'));
        expect('manage_production'.snakeToTitleCase, equals('Manage Production'));
      });

      test('handles single word', () {
        expect('products'.snakeToTitleCase, equals('Products'));
      });

      test('handles uppercase snake_case', () {
        expect('MANAGE_PRODUCTS'.snakeToTitleCase, equals('Manage Products'));
      });

      test('handles empty string', () {
        expect(''.snakeToTitleCase, equals(''));
      });
    });
  });

  group('DateTimeExtensions', () {
    final testDate = DateTime(2025, 10, 8, 14, 30); // Oct 8, 2025 at 2:30 PM

    group('friendlyDate', () {
      test('formats date correctly', () {
        expect(testDate.friendlyDate, equals('Oct 8, 2025'));
      });
    });

    group('fullDate', () {
      test('formats date correctly', () {
        expect(testDate.fullDate, equals('October 8, 2025'));
      });
    });

    group('shortDate', () {
      test('formats date correctly', () {
        expect(testDate.shortDate, equals('10/8/2025'));
      });
    });

    group('friendlyTime', () {
      test('formats time correctly', () {
        expect(testDate.friendlyTime, equals('2:30 PM'));
      });

      test('formats AM time correctly', () {
        final morningTime = DateTime(2025, 10, 8, 9, 15);
        expect(morningTime.friendlyTime, equals('9:15 AM'));
      });
    });

    group('friendlyDateTime', () {
      test('formats date and time correctly', () {
        expect(testDate.friendlyDateTime, equals('Oct 8, 2025 at 2:30 PM'));
      });
    });

    group('timeAgo', () {
      test('shows "just now" for very recent times', () {
        final now = DateTime.now();
        expect(now.timeAgo, equals('just now'));
      });

      test('shows minutes ago', () {
        final fiveMinutesAgo = DateTime.now().subtract(const Duration(minutes: 5));
        expect(fiveMinutesAgo.timeAgo, equals('5 minutes ago'));

        final oneMinuteAgo = DateTime.now().subtract(const Duration(minutes: 1));
        expect(oneMinuteAgo.timeAgo, equals('1 minute ago'));
      });

      test('shows hours ago', () {
        final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2));
        expect(twoHoursAgo.timeAgo, equals('2 hours ago'));

        final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
        expect(oneHourAgo.timeAgo, equals('1 hour ago'));
      });

      test('shows days ago', () {
        final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
        expect(threeDaysAgo.timeAgo, equals('3 days ago'));

        final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
        expect(oneDayAgo.timeAgo, equals('1 day ago'));
      });

      test('shows months ago', () {
        final twoMonthsAgo = DateTime.now().subtract(const Duration(days: 60));
        expect(twoMonthsAgo.timeAgo, equals('2 months ago'));
      });

      test('shows years ago', () {
        final twoYearsAgo = DateTime.now().subtract(const Duration(days: 730));
        expect(twoYearsAgo.timeAgo, equals('2 years ago'));
      });

      test('shows future times', () {
        final inFiveMinutes = DateTime.now().add(const Duration(minutes: 5));
        expect(inFiveMinutes.timeAgo, equals('in 5 minutes'));

        final inTwoHours = DateTime.now().add(const Duration(hours: 2));
        expect(inTwoHours.timeAgo, equals('in 2 hours'));

        final inThreeDays = DateTime.now().add(const Duration(days: 3));
        expect(inThreeDays.timeAgo, equals('in 3 days'));
      });
    });
  });
}
