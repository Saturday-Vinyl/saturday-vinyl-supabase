import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/app.dart';
import 'package:saturday_consumer_app/config/env_config.dart';
import 'package:saturday_consumer_app/services/auth_service.dart';
import 'package:saturday_consumer_app/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment configuration
  try {
    await EnvConfig.load();
  } catch (e) {
    // Show error screen if env loading fails
    runApp(EnvErrorApp(error: e.toString()));
    return;
  }

  // Initialize Supabase
  try {
    await SupabaseService.initialize();
  } catch (e) {
    runApp(EnvErrorApp(error: 'Failed to initialize Supabase: $e'));
    return;
  }

  // Initialize AuthService (depends on Supabase being initialized)
  AuthService.initialize();

  // Run the app with Riverpod provider scope
  runApp(
    const ProviderScope(
      child: SaturdayApp(),
    ),
  );
}

/// Error screen displayed when environment configuration fails to load.
class EnvErrorApp extends StatelessWidget {
  final String error;

  const EnvErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFE2DAD0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Color(0xFFF35345),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Configuration Error',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3F3A34),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF3F3A34),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
