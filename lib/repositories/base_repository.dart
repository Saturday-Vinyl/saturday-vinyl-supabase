import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saturday_consumer_app/services/supabase_service.dart';

/// Base class for all repositories.
///
/// Provides common access to the Supabase client and shared utilities.
abstract class BaseRepository {
  SupabaseClient get client => SupabaseService.instance.client;
}
