import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/utils/validators.dart';

void main() {
  group('Validators', () {
    group('validateSemanticVersion', () {
      test('accepts valid semantic versions', () {
        expect(Validators.validateSemanticVersion('1.0.0'), isNull);
        expect(Validators.validateSemanticVersion('0.0.1'), isNull);
        expect(Validators.validateSemanticVersion('10.20.30'), isNull);
        expect(Validators.validateSemanticVersion('999.999.999'), isNull);
      });

      test('rejects invalid semantic versions', () {
        expect(Validators.validateSemanticVersion('1.0'), isNotNull);
        expect(Validators.validateSemanticVersion('1'), isNotNull);
        expect(Validators.validateSemanticVersion('v1.0.0'), isNotNull);
        expect(Validators.validateSemanticVersion('1.0.0-beta'), isNotNull);
        expect(Validators.validateSemanticVersion('1.0.0+build'), isNotNull);
        expect(Validators.validateSemanticVersion('1.2.a'), isNotNull);
        expect(Validators.validateSemanticVersion('a.b.c'), isNotNull);
      });

      test('rejects empty or null values', () {
        expect(Validators.validateSemanticVersion(null), isNotNull);
        expect(Validators.validateSemanticVersion(''), isNotNull);
        expect(Validators.validateSemanticVersion('   '), isNotNull);
      });

      test('returns appropriate error messages', () {
        final nullError = Validators.validateSemanticVersion(null);
        expect(nullError, contains('required'));

        final formatError = Validators.validateSemanticVersion('1.0');
        expect(formatError, contains('X.Y.Z'));
      });
    });

    group('isValidSemanticVersion', () {
      test('returns true for valid versions', () {
        expect(Validators.isValidSemanticVersion('1.0.0'), isTrue);
        expect(Validators.isValidSemanticVersion('0.0.1'), isTrue);
        expect(Validators.isValidSemanticVersion('10.20.30'), isTrue);
      });

      test('returns false for invalid versions', () {
        expect(Validators.isValidSemanticVersion('1.0'), isFalse);
        expect(Validators.isValidSemanticVersion('v1.0.0'), isFalse);
        expect(Validators.isValidSemanticVersion(''), isFalse);
      });
    });

    group('compareSemanticVersions', () {
      test('compares major versions correctly', () {
        expect(Validators.compareSemanticVersions('2.0.0', '1.0.0'), greaterThan(0));
        expect(Validators.compareSemanticVersions('1.0.0', '2.0.0'), lessThan(0));
        expect(Validators.compareSemanticVersions('1.0.0', '1.0.0'), equals(0));
      });

      test('compares minor versions correctly', () {
        expect(Validators.compareSemanticVersions('1.2.0', '1.1.0'), greaterThan(0));
        expect(Validators.compareSemanticVersions('1.1.0', '1.2.0'), lessThan(0));
        expect(Validators.compareSemanticVersions('1.1.0', '1.1.0'), equals(0));
      });

      test('compares patch versions correctly', () {
        expect(Validators.compareSemanticVersions('1.0.2', '1.0.1'), greaterThan(0));
        expect(Validators.compareSemanticVersions('1.0.1', '1.0.2'), lessThan(0));
        expect(Validators.compareSemanticVersions('1.0.1', '1.0.1'), equals(0));
      });

      test('handles different digit counts', () {
        expect(Validators.compareSemanticVersions('10.0.0', '9.0.0'), greaterThan(0));
        expect(Validators.compareSemanticVersions('1.10.0', '1.9.0'), greaterThan(0));
        expect(Validators.compareSemanticVersions('1.0.10', '1.0.9'), greaterThan(0));
      });

      test('sorts versions correctly', () {
        final versions = ['2.0.0', '1.5.0', '1.10.0', '1.0.0', '1.0.10'];
        versions.sort(Validators.compareSemanticVersions);
        expect(versions, equals(['1.0.0', '1.0.10', '1.5.0', '1.10.0', '2.0.0']));
      });
    });

    group('validateEmail', () {
      test('accepts valid emails', () {
        expect(Validators.validateEmail('test@example.com'), isNull);
        expect(Validators.validateEmail('user.name@domain.co.uk'), isNull);
        expect(Validators.validateEmail('user+tag@example.com'), isNull);
      });

      test('rejects invalid emails', () {
        expect(Validators.validateEmail('invalid'), isNotNull);
        expect(Validators.validateEmail('@example.com'), isNotNull);
        expect(Validators.validateEmail('user@'), isNotNull);
        expect(Validators.validateEmail('user @example.com'), isNotNull);
      });

      test('rejects empty or null values', () {
        expect(Validators.validateEmail(null), isNotNull);
        expect(Validators.validateEmail(''), isNotNull);
      });
    });

    group('validateUrl', () {
      test('accepts valid URLs', () {
        expect(Validators.validateUrl('https://example.com'), isNull);
        expect(Validators.validateUrl('http://example.com'), isNull);
        expect(Validators.validateUrl('https://sub.example.com/path'), isNull);
      });

      test('rejects invalid URLs', () {
        expect(Validators.validateUrl('not-a-url'), isNotNull);
        expect(Validators.validateUrl('example.com'), isNotNull);
        expect(Validators.validateUrl('ftp://example.com'), isNotNull);
      });

      test('rejects empty or null values', () {
        expect(Validators.validateUrl(null), isNotNull);
        expect(Validators.validateUrl(''), isNotNull);
      });
    });

    group('validateRequired', () {
      test('accepts non-empty values', () {
        expect(Validators.validateRequired('value'), isNull);
        expect(Validators.validateRequired('  value  '), isNull);
      });

      test('rejects empty or null values', () {
        expect(Validators.validateRequired(null), isNotNull);
        expect(Validators.validateRequired(''), isNotNull);
        expect(Validators.validateRequired('   '), isNotNull);
      });

      test('uses custom field name in error message', () {
        final error = Validators.validateRequired(null, fieldName: 'Username');
        expect(error, contains('Username'));
      });
    });

    group('validateMinLength', () {
      test('accepts values meeting minimum length', () {
        expect(Validators.validateMinLength('hello', 5), isNull);
        expect(Validators.validateMinLength('hello world', 5), isNull);
      });

      test('rejects values below minimum length', () {
        expect(Validators.validateMinLength('hi', 5), isNotNull);
        expect(Validators.validateMinLength('test', 5), isNotNull);
      });

      test('handles null values', () {
        expect(Validators.validateMinLength(null, 5), isNotNull);
      });

      test('includes length in error message', () {
        final error = Validators.validateMinLength('hi', 5);
        expect(error, contains('5'));
      });
    });

    group('validateMaxLength', () {
      test('accepts values within maximum length', () {
        expect(Validators.validateMaxLength('hello', 10), isNull);
        expect(Validators.validateMaxLength('test', 10), isNull);
      });

      test('rejects values exceeding maximum length', () {
        expect(Validators.validateMaxLength('hello world', 5), isNotNull);
        expect(Validators.validateMaxLength('testing', 5), isNotNull);
      });

      test('handles null values', () {
        expect(Validators.validateMaxLength(null, 10), isNull);
      });

      test('includes length in error message', () {
        final error = Validators.validateMaxLength('too long', 5);
        expect(error, contains('5'));
      });
    });
  });
}
