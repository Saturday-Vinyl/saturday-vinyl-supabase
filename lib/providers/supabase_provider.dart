import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for the SupabaseService singleton.
///
/// This provider gives access to the initialized SupabaseService
/// throughout the app via Riverpod.
final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService.instance;
});

/// Provider for the Supabase client.
///
/// Convenience provider for direct access to the SupabaseClient.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return ref.watch(supabaseServiceProvider).client;
});
