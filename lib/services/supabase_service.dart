import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saturday_consumer_app/config/env_config.dart';

/// Singleton service for Supabase client access.
///
/// Provides centralized access to the Supabase client for database
/// operations, authentication, and real-time subscriptions.
class SupabaseService {
  SupabaseService._();

  static SupabaseService? _instance;
  static bool _initialized = false;

  /// Returns the singleton instance.
  ///
  /// Throws [StateError] if [initialize] has not been called.
  static SupabaseService get instance {
    if (_instance == null || !_initialized) {
      throw StateError(
        'SupabaseService has not been initialized. '
        'Call SupabaseService.initialize() before accessing instance.',
      );
    }
    return _instance!;
  }

  /// Initializes the Supabase client.
  ///
  /// Must be called once during app startup, after [EnvConfig.load()].
  /// Typically called in main.dart before runApp().
  static Future<void> initialize() async {
    if (_initialized) return;

    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );

    _instance = SupabaseService._();
    _initialized = true;
  }

  /// Returns whether the service has been initialized.
  static bool get isInitialized => _initialized;

  /// The Supabase client instance.
  SupabaseClient get client => Supabase.instance.client;

  /// The current authenticated user, or null if not signed in.
  User? get currentUser => client.auth.currentUser;

  /// Stream of authentication state changes.
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  /// Returns true if a user is currently authenticated.
  bool get isAuthenticated => currentUser != null;

  /// Signs out the current user.
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Refreshes the current session if needed.
  Future<Session?> refreshSession() async {
    final response = await client.auth.refreshSession();
    return response.session;
  }

  /// Returns the current session, or null if not authenticated.
  Session? get currentSession => client.auth.currentSession;

  /// Checks if the current session is expired.
  bool get isSessionExpired {
    final session = currentSession;
    if (session == null) return true;

    final expiresAt = session.expiresAt;
    if (expiresAt == null) return true;

    final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    return DateTime.now().isAfter(expiryTime);
  }
}
