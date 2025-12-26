import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/constants.dart';
import 'package:saturday_app/config/env_config.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/rfid_settings_provider.dart';
import 'package:saturday_app/screens/auth/login_screen.dart';
import 'package:saturday_app/screens/main_scaffold.dart';
import 'package:saturday_app/services/auth_service.dart';
import 'package:saturday_app/services/shopify_service.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Load environment variables
    AppLogger.info('Loading environment configuration...');
    await EnvConfig.load();
    AppLogger.info('Environment configuration loaded successfully');

    // Initialize Supabase
    await SupabaseService.initialize();

    // Initialize Auth Service
    AuthService.initialize();

    // Initialize Shopify Service
    ShopifyService().initialize();

    // Initialize SharedPreferences for RFID settings
    final sharedPreferences = await SharedPreferences.getInstance();

    // Run the app with SharedPreferences override
    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ],
        child: const MyApp(),
      ),
    );
  } catch (error, stackTrace) {
    // Log initialization error
    AppLogger.error(
      'Failed to initialize application',
      error,
      stackTrace,
    );

    // Show error screen
    runApp(ErrorApp(error: error.toString()));
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: SaturdayTheme.lightTheme,
      darkTheme: SaturdayTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const AuthRouter(),
    );
  }
}

/// Routes user to appropriate screen based on auth state
class AuthRouter extends ConsumerWidget {
  const AuthRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (state) {
        if (state.session != null) {
          // User is signed in - show main app with navigation
          return const MainScaffold();
        } else {
          // User is not signed in - show login screen
          return const LoginScreen();
        }
      },
      loading: () => const Scaffold(
        body: LoadingIndicator(message: 'Loading...'),
      ),
      error: (error, stack) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: SaturdayColors.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Authentication Error',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error app displayed when initialization fails
class ErrorApp extends StatelessWidget {
  final String error;

  const ErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Initialization Error',
      theme: SaturdayTheme.lightTheme,
      home: Scaffold(
        backgroundColor: SaturdayColors.error,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: SaturdayColors.white,
                  size: 64,
                ),
                const SizedBox(height: 24),
                Text(
                  'Failed to Start',
                  style: SaturdayTheme.lightTheme.textTheme.headlineMedium
                      ?.copyWith(color: SaturdayColors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  error,
                  style: const TextStyle(color: SaturdayColors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                const Text(
                  'Please check your .env configuration and try again.',
                  style: TextStyle(color: SaturdayColors.white),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
