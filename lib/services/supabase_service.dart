import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saturday_app/config/env_config.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Supabase service singleton
/// Provides centralized access to Supabase client
class SupabaseService {
  SupabaseService._(); // Private constructor for singleton

  static SupabaseService? _instance;
  static SupabaseClient? _client;

  /// Get the singleton instance
  static SupabaseService get instance {
    _instance ??= SupabaseService._();
    return _instance!;
  }

  /// Initialize Supabase with configuration from environment
  static Future<void> initialize() async {
    try {
      AppLogger.info('Initializing Supabase...');

      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        anonKey: EnvConfig.supabaseAnonKey,
      );

      _client = Supabase.instance.client;

      AppLogger.info('Supabase initialized successfully');
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to initialize Supabase',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Get the Supabase client instance
  /// Throws if Supabase hasn't been initialized
  SupabaseClient get client {
    if (_client == null) {
      throw Exception(
        'Supabase has not been initialized. Call SupabaseService.initialize() first.',
      );
    }
    return _client!;
  }

  /// Check if Supabase is initialized
  bool get isInitialized => _client != null;

  /// Check connection status
  /// Returns true if connected to Supabase
  Future<bool> checkConnection() async {
    try {
      // Try a simple query to check connection
      await client.from('users').select('id').limit(1);
      return true;
    } catch (error) {
      AppLogger.warning('Supabase connection check failed', error);
      return false;
    }
  }

  /// Get current auth user
  User? get currentUser => client.auth.currentUser;

  /// Get auth state changes stream
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  /// Sign out current user
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
      AppLogger.info('User signed out successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to sign out', error, stackTrace);
      rethrow;
    }
  }
}
