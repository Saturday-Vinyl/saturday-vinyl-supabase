import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../utils/app_logger.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isSigningIn = false;
  String? _errorMessage;

  Future<void> _handleSignIn() async {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signInWithGoogle();
      AppLogger.info('User signed in successfully');
      // Navigation will be handled automatically by auth state changes
    } catch (error, stackTrace) {
      AppLogger.error('Sign in failed', error, stackTrace);

      String errorMsg = 'Sign in failed. Please try again.';
      if (error.toString().contains('saturdayvinyl.com')) {
        errorMsg = 'Only @saturdayvinyl.com accounts are allowed.';
      } else if (error.toString().contains('popup_closed_by_user')) {
        errorMsg = 'Sign in cancelled.';
      }

      setState(() {
        _errorMessage = errorMsg;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaturdayColors.light,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: SaturdayColors.primaryDark,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text(
                      'S!',
                      style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // App name
                Text(
                  AppConstants.appName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: SaturdayColors.primaryDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  'Production Management',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
                ),
                const SizedBox(height: 48),

                // Sign in button or loading indicator
                if (_isSigningIn)
                  const LoadingIndicator(message: 'Signing in...')
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: AppButton(
                      text: 'Sign in with Google',
                      icon: Icons.login,
                      onPressed: _handleSignIn,
                      width: double.infinity,
                    ),
                  ),

                // Error message
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SaturdayColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: SaturdayColors.error,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: SaturdayColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: SaturdayColors.error,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 48),

                // Help text
                Text(
                  'Sign in with your @saturdayvinyl.com account',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
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
