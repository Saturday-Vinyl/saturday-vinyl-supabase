import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/widgets/auth/social_sign_in_button.dart';

/// Signup screen for creating a new account.
///
/// Supports:
/// - Email/password registration
/// - Social auth signup (Apple on iOS, Google on all platforms)
/// - Navigation back to login
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isAppleLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _signupSuccess = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  Future<void> _handleSignup() async {
    _clearError();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final authService = ref.read(authServiceProvider);
    final result = await authService.signUpWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      fullName: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : null,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result.success) {
      setState(() => _signupSuccess = true);
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

    // Show success message if signup was successful
    if (_signupSuccess) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: Spacing.pagePadding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 80,
                  color: SaturdayColors.success,
                ),
                const SizedBox(height: 24),
                Text(
                  'Check your email',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'We sent a confirmation link to\n${_emailController.text.trim()}',
                  style: TextStyle(
                    color: SaturdayColors.secondary,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Click the link in the email to verify your account.',
                  style: TextStyle(
                    color: SaturdayColors.secondary,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: () => context.go(RoutePaths.login),
                  child: const Text('Back to Sign In'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text(''),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: Spacing.pagePadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                // Logo and title
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.album,
                        size: 64,
                        color: SaturdayColors.primaryDark,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Create Account',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Join Saturday and start tracking your vinyl',
                        style: TextStyle(
                          color: SaturdayColors.secondary,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

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

                // Full name field
                TextFormField(
                  controller: _nameController,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  enabled: !isAnyLoading,
                  onChanged: (_) => _clearError(),
                  decoration: const InputDecoration(
                    labelText: 'Full Name (optional)',
                    hintText: 'Your name',
                    prefixIcon: Icon(Icons.person_outlined),
                  ),
                ),

                const SizedBox(height: 16),

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
                  onFieldSubmitted: (_) => _handleSignup(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    helperText: 'At least 8 characters',
                    helperMaxLines: 1,
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
                      return 'Please enter a password';
                    }
                    if (value.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // Signup button
                ElevatedButton(
                  onPressed: isAnyLoading ? null : _handleSignup,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SaturdayColors.white,
                          ),
                        )
                      : const Text('Create Account'),
                ),

                const SizedBox(height: 16),

                // Sign in link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(color: SaturdayColors.secondary),
                    ),
                    TextButton(
                      onPressed: isAnyLoading
                          ? null
                          : () => context.go(RoutePaths.login),
                      child: const Text('Sign In'),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

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

                const SizedBox(height: 24),

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
