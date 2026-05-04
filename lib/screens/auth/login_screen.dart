import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/widgets/auth/social_sign_in_button.dart';

/// Login screen for user authentication.
///
/// Supports:
/// - Email/password login
/// - Social auth (Apple on iOS, Google on all platforms)
/// - Navigation to signup and forgot password
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isAppleLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  Future<void> _handleEmailLogin() async {
    _clearError();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final authService = ref.read(authServiceProvider);
    final result = await authService.signInWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result.success) {
      context.go(RoutePaths.nowPlaying);
    } else {
      setState(() => _errorMessage = result.errorMessage);
    }
  }

  Future<void> _handleAppleSignIn() async {
    _clearError();
    setState(() => _isAppleLoading = true);

    final authService = ref.read(authServiceProvider);
    final result = await authService.signInWithApple();

    if (!mounted) return;

    setState(() => _isAppleLoading = false);

    if (!result.success && result.errorMessage != 'Waiting for OAuth callback...') {
      setState(() => _errorMessage = result.errorMessage);
    }
    // OAuth redirects handle success case automatically
  }

  Future<void> _handleGoogleSignIn() async {
    _clearError();
    setState(() => _isGoogleLoading = true);

    final authService = ref.read(authServiceProvider);
    final result = await authService.signInWithGoogle();

    if (!mounted) return;

    setState(() => _isGoogleLoading = false);

    if (!result.success && result.errorMessage != 'Waiting for OAuth callback...') {
      setState(() => _errorMessage = result.errorMessage);
    }
    // OAuth redirects handle success case automatically
  }

  @override
  Widget build(BuildContext context) {
    // Listen to auth state changes - navigate when signed in
    ref.listen(authStateChangesProvider, (previous, next) {
      next.whenData((state) {
        if (state.session != null) {
          context.go(RoutePaths.nowPlaying);
        }
      });
    });

    final isAnyLoading = _isLoading || _isAppleLoading || _isGoogleLoading;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: Spacing.pagePadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // Logo
                Center(
                  child: SvgPicture.asset(
                    'assets/images/saturday-logo.svg',
                    width: 220,
                    colorFilter: const ColorFilter.mode(
                      SaturdayColors.primaryDark,
                      BlendMode.srcIn,
                    ),
                  ),
                ),

                const SizedBox(height: 48),

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SaturdayColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: SaturdayColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: SaturdayColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: SaturdayColors.error,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: SaturdayColors.error,
                            size: 18,
                          ),
                          onPressed: _clearError,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  enabled: !isAnyLoading,
                  onChanged: (_) => _clearError(),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  enabled: !isAnyLoading,
                  onChanged: (_) => _clearError(),
                  onFieldSubmitted: (_) => _handleEmailLogin(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 8),

                // Forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: isAnyLoading
                        ? null
                        : () => context.push(RoutePaths.forgotPassword),
                    child: const Text('Forgot password?'),
                  ),
                ),

                const SizedBox(height: 24),

                // Login button
                ElevatedButton(
                  onPressed: isAnyLoading ? null : _handleEmailLogin,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SaturdayColors.white,
                          ),
                        )
                      : const Text('Sign In'),
                ),

                const SizedBox(height: 16),

                // Sign up link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(color: SaturdayColors.secondary),
                    ),
                    TextButton(
                      onPressed: isAnyLoading
                          ? null
                          : () => context.push(RoutePaths.signup),
                      child: const Text('Sign Up'),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'or',
                        style: TextStyle(color: SaturdayColors.secondary),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 32),

                // Social sign-in buttons
                if (SocialSignInButton.isAvailable(SocialSignInProvider.apple)) ...[
                  SocialSignInButton(
                    provider: SocialSignInProvider.apple,
                    onPressed: isAnyLoading ? null : _handleAppleSignIn,
                    isLoading: _isAppleLoading,
                  ),
                  const SizedBox(height: 12),
                ],

                SocialSignInButton(
                  provider: SocialSignInProvider.google,
                  onPressed: isAnyLoading ? null : _handleGoogleSignIn,
                  isLoading: _isGoogleLoading,
                ),

                const SizedBox(height: 32),

                // Continue without account (for browsing)
                OutlinedButton(
                  onPressed: isAnyLoading
                      ? null
                      : () => context.go(RoutePaths.nowPlaying),
                  child: const Text('Continue without account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
