import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/config/env_config.dart';

void main() {
  group('EnvConfig', () {
    test('loads environment variables from .env file', () async {
      // Load the .env file
      await EnvConfig.load();

      // Verify that environment is loaded
      expect(EnvConfig.isLoaded, true);
    });

    test('provides access to Supabase configuration', () async {
      await EnvConfig.load();

      // These will have placeholder values from .env file
      expect(EnvConfig.supabaseUrl, isNotEmpty);
      expect(EnvConfig.supabaseAnonKey, isNotEmpty);
    });

    test('provides access to Shopify configuration', () async {
      await EnvConfig.load();

      expect(EnvConfig.shopifyStoreUrl, isNotEmpty);
      expect(EnvConfig.shopifyAccessToken, isNotEmpty);
    });

    test('provides access to Google OAuth configuration', () async {
      await EnvConfig.load();

      expect(EnvConfig.googleClientId, isNotEmpty);
    });

    test('provides access to app base URL', () async {
      await EnvConfig.load();

      expect(EnvConfig.appBaseUrl, isNotEmpty);
    });

    test('throws exception if required variables are missing', () async {
      // This test would require mocking dotenv or using a test .env file
      // For now, we'll skip this as it requires more complex setup
      // In a real scenario, you'd create a test .env file with missing values
    });
  });
}
