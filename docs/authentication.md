# Authentication and Authorization Developer's Guide

## Overview

This document provides a comprehensive guide for implementing the Saturday! Admin App's authentication and authorization strategy. The system uses Google OAuth for authentication (restricted to a company domain) with Supabase as the backend, and a role-based permission system for authorization.

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App                              │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────────────┐    │
│  │ LoginScreen │───▶│ AuthService │───▶│ SupabaseService  │    │
│  └─────────────┘    └─────────────┘    └──────────────────┘    │
│         │                  │                    │               │
│         ▼                  ▼                    ▼               │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────────────┐    │
│  │AuthProvider │───▶│UserRepository───▶│  Supabase DB     │    │
│  │  (Riverpod) │    │             │    │  (PostgreSQL)    │    │
│  └─────────────┘    └─────────────┘    └──────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Libraries and Dependencies

Add these to your `pubspec.yaml`:

```yaml
dependencies:
  # Authentication
  google_sign_in: ^6.2.1
  supabase_flutter: ^2.3.4

  # State Management
  flutter_riverpod: ^2.4.9

  # Utilities
  flutter_dotenv: ^5.1.0
  equatable: ^2.0.5
```

## Environment Configuration

### Required Environment Variables

Create a `.env` file with these variables:

```env
# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key

# Google OAuth Configuration
GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com

# Application Configuration
APP_BASE_URL=https://your-app-domain.com
```

### EnvConfig Loader

Create a configuration loader that validates required variables:

```dart
// lib/config/env_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  EnvConfig._();

  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
    _validate();
  }

  static void _validate() {
    final requiredVars = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'GOOGLE_CLIENT_ID'];
    final missingVars = requiredVars.where((key) => _get(key).isEmpty).toList();

    if (missingVars.isNotEmpty) {
      throw Exception('Missing required environment variables: ${missingVars.join(', ')}');
    }
  }

  static String _get(String key) => dotenv.get(key, fallback: '');

  static String get supabaseUrl => _get('SUPABASE_URL');
  static String get supabaseAnonKey => _get('SUPABASE_ANON_KEY');
  static String get googleClientId => _get('GOOGLE_CLIENT_ID');
}
```

### Constants

```dart
// lib/config/constants.dart
class AppConstants {
  AppConstants._();

  // Allowed Email Domain - restricts authentication to company emails only
  static const String allowedEmailDomain = '@yourcompany.com';

  // Session Configuration
  static const Duration sessionDuration = Duration(days: 7);

  // Error Messages
  static const String authErrorMessage = 'Authentication failed. Please sign in again.';
  static const String permissionErrorMessage = 'You do not have permission to perform this action.';
}
```

## Database Schema

### Users Table

```sql
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_id TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    is_admin BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_google_id ON public.users(google_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
```

### Permissions Table

```sql
CREATE TABLE IF NOT EXISTS public.permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Insert your application's permissions
INSERT INTO public.permissions (name, description) VALUES
    ('manage_products', 'Can create, edit, and delete products'),
    ('manage_firmware', 'Can upload and manage firmware files'),
    ('manage_production', 'Can manage production units and QR codes')
ON CONFLICT (name) DO NOTHING;
```

### User Permissions Join Table

```sql
CREATE TABLE IF NOT EXISTS public.user_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    granted_by UUID REFERENCES public.users(id),
    UNIQUE(user_id, permission_id)
);

CREATE INDEX IF NOT EXISTS idx_user_permissions_user_id ON public.user_permissions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_permissions_permission_id ON public.user_permissions(permission_id);
```

### Row Level Security (RLS) Policies

```sql
-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;

-- Users table policies
CREATE POLICY "Authenticated users can read users"
    ON public.users FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can update own last_login"
    ON public.users FOR UPDATE
    USING (auth.jwt() ->> 'email' = email)
    WITH CHECK (auth.jwt() ->> 'email' = email);

CREATE POLICY "Allow insert for authenticated users"
    ON public.users FOR INSERT TO authenticated
    WITH CHECK (auth.jwt() ->> 'email' = email);

-- Permissions table policies
CREATE POLICY "Authenticated users can read permissions"
    ON public.permissions FOR SELECT TO authenticated USING (true);

-- User permissions table policies
CREATE POLICY "Authenticated users can read user permissions"
    ON public.user_permissions FOR SELECT TO authenticated USING (true);
```

### Helper Functions

```sql
-- Function to check if user has a permission
CREATE OR REPLACE FUNCTION user_has_permission(user_email TEXT, permission_name TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    user_is_admin BOOLEAN;
    has_perm BOOLEAN;
BEGIN
    -- Admins have all permissions
    SELECT is_admin INTO user_is_admin FROM public.users WHERE email = user_email;
    IF user_is_admin THEN RETURN TRUE; END IF;

    -- Check specific permission
    SELECT EXISTS (
        SELECT 1 FROM public.user_permissions up
        INNER JOIN public.users u ON u.id = up.user_id
        INNER JOIN public.permissions p ON p.id = up.permission_id
        WHERE u.email = user_email AND p.name = permission_name
    ) INTO has_perm;

    RETURN has_perm;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## Core Services

### SupabaseService

Singleton service providing centralized Supabase client access.

```dart
// lib/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static SupabaseService? _instance;
  static SupabaseClient? _client;

  static SupabaseService get instance {
    _instance ??= SupabaseService._();
    return _instance!;
  }

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
    );
    _client = Supabase.instance.client;
  }

  SupabaseClient get client {
    if (_client == null) {
      throw Exception('Supabase not initialized. Call SupabaseService.initialize() first.');
    }
    return _client!;
  }

  User? get currentUser => client.auth.currentUser;
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  Future<void> signOut() async {
    await client.auth.signOut();
  }
}
```

### AuthService

Handles Google OAuth flow with domain validation and Supabase integration.

```dart
// lib/services/auth_service.dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class AuthService {
  AuthService._();

  static AuthService? _instance;
  static GoogleSignIn? _googleSignIn;

  static AuthService get instance {
    _instance ??= AuthService._();
    return _instance!;
  }

  static void initialize() {
    _googleSignIn = GoogleSignIn(
      clientId: EnvConfig.googleClientId,
      scopes: ['email', 'profile'],
    );
  }

  GoogleSignIn get _googleSignInInstance {
    if (_googleSignIn == null) {
      throw Exception('Google Sign In not initialized.');
    }
    return _googleSignIn!;
  }

  /// Sign in with Google OAuth
  /// Validates email domain and authenticates with Supabase
  Future<supabase.User> signInWithGoogle() async {
    // 1. Initiate Google Sign In
    final googleUser = await _googleSignInInstance.signIn();
    if (googleUser == null) {
      throw Exception('Google Sign In was cancelled by user');
    }

    // 2. Validate email domain
    if (!googleUser.email.endsWith(AppConstants.allowedEmailDomain)) {
      await _googleSignInInstance.signOut();
      throw Exception(
        'Only ${AppConstants.allowedEmailDomain} accounts are allowed. '
        'Please sign in with your company email.',
      );
    }

    // 3. Get authentication tokens
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null || accessToken == null) {
      throw Exception('Failed to get Google authentication tokens');
    }

    // 4. Authenticate with Supabase using Google credentials
    final response = await SupabaseService.instance.client.auth.signInWithIdToken(
      provider: supabase.OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Failed to authenticate with Supabase');
    }

    return user;
  }

  /// Sign out from both Google and Supabase
  Future<void> signOut() async {
    await _googleSignInInstance.signOut();
    await SupabaseService.instance.signOut();
  }

  supabase.User? getCurrentUser() => SupabaseService.instance.currentUser;

  Stream<supabase.AuthState> get authStateChanges =>
      SupabaseService.instance.authStateChanges;

  bool get isSignedIn => getCurrentUser() != null;

  /// Check if session is valid and not expired
  bool isSessionValid() {
    final session = SupabaseService.instance.client.auth.currentSession;
    if (session == null) return false;

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000);
    return DateTime.now().isBefore(expiresAt);
  }

  /// Refresh the current session
  Future<bool> refreshSession() async {
    try {
      final session = await SupabaseService.instance.client.auth.refreshSession();
      return session.session != null;
    } catch (e) {
      return false;
    }
  }

  /// Check if session needs refresh (less than 10 minutes until expiry)
  bool shouldRefreshSession() {
    final session = SupabaseService.instance.client.auth.currentSession;
    if (session?.expiresAt == null) return false;

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(session!.expiresAt! * 1000);
    final timeUntilExpiry = expiresAt.difference(DateTime.now());
    return timeUntilExpiry.inMinutes < 10;
  }
}
```

## Data Models

### User Model

```dart
// lib/models/user.dart
import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String googleId;
  final String email;
  final String? fullName;
  final bool isAdmin;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLogin;

  const User({
    required this.id,
    required this.googleId,
    required this.email,
    this.fullName,
    required this.isAdmin,
    required this.isActive,
    required this.createdAt,
    this.lastLogin,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      googleId: json['google_id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      isAdmin: json['is_admin'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastLogin: json['last_login'] != null
          ? DateTime.parse(json['last_login'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'google_id': googleId,
    'email': email,
    'full_name': fullName,
    'is_admin': isAdmin,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
    'last_login': lastLogin?.toIso8601String(),
  };

  User copyWith({
    String? id,
    String? googleId,
    String? email,
    String? fullName,
    bool? isAdmin,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLogin,
  }) {
    return User(
      id: id ?? this.id,
      googleId: googleId ?? this.googleId,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      isAdmin: isAdmin ?? this.isAdmin,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }

  @override
  List<Object?> get props => [id, googleId, email, fullName, isAdmin, isActive, createdAt, lastLogin];
}
```

### Permission Model

```dart
// lib/models/permission.dart
import 'package:equatable/equatable.dart';

class Permission extends Equatable {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;

  const Permission({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
  });

  // Predefined permission constants
  static const String manageProducts = 'manage_products';
  static const String manageFirmware = 'manage_firmware';
  static const String manageProduction = 'manage_production';

  factory Permission.fromJson(Map<String, dynamic> json) {
    return Permission(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'created_at': createdAt.toIso8601String(),
  };

  @override
  List<Object?> get props => [id, name, description, createdAt];
}
```

## User Repository

Handles database operations for user management and permission checking.

```dart
// lib/repositories/user_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class UserRepository {
  final SupabaseService _supabaseService;

  UserRepository({SupabaseService? supabaseService})
      : _supabaseService = supabaseService ?? SupabaseService.instance;

  /// Get or create user after Google authentication
  /// Creates new user with default permissions if not exists
  /// Updates lastLogin if user exists
  Future<User> getOrCreateUser(supabase.User supabaseUser) async {
    final client = _supabaseService.client;
    final email = supabaseUser.email;
    final googleId = supabaseUser.id;

    if (email == null) {
      throw Exception('User email is required');
    }

    // Check if user exists
    final response = await client
        .from('users')
        .select()
        .eq('google_id', googleId)
        .maybeSingle();

    if (response != null) {
      // User exists - update last login
      final updatedResponse = await client
          .from('users')
          .update({'last_login': DateTime.now().toIso8601String()})
          .eq('google_id', googleId)
          .select()
          .single();

      return User.fromJson(updatedResponse);
    } else {
      // Create new user
      final newUser = {
        'google_id': googleId,
        'email': email,
        'full_name': supabaseUser.userMetadata?['full_name'] as String?,
        'is_admin': false,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'last_login': DateTime.now().toIso8601String(),
      };

      final createdResponse = await client
          .from('users')
          .insert(newUser)
          .select()
          .single();

      return User.fromJson(createdResponse);
    }
  }

  /// Get user permissions from database
  Future<List<String>> getUserPermissions(String userId) async {
    final response = await _supabaseService.client
        .from('user_permissions')
        .select('permissions(name)')
        .eq('user_id', userId);

    return (response as List)
        .map((item) => item['permissions']['name'] as String)
        .toList();
  }

  /// Check if user has a specific permission
  Future<bool> hasPermission(String userId, String permissionName) async {
    final user = await getUser(userId);

    // Admins have all permissions
    if (user.isAdmin) return true;

    final permissions = await getUserPermissions(userId);
    return permissions.contains(permissionName);
  }

  Future<User> getUser(String userId) async {
    final response = await _supabaseService.client
        .from('users')
        .select()
        .eq('id', userId)
        .single();

    return User.fromJson(response);
  }

  // ADMIN-ONLY METHODS

  Future<void> grantPermission({
    required String userId,
    required String permissionId,
    required String grantedBy,
  }) async {
    await _supabaseService.client.from('user_permissions').insert({
      'user_id': userId,
      'permission_id': permissionId,
      'granted_by': grantedBy,
      'granted_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> revokePermission({
    required String userId,
    required String permissionId,
  }) async {
    await _supabaseService.client
        .from('user_permissions')
        .delete()
        .eq('user_id', userId)
        .eq('permission_id', permissionId);
  }

  Future<void> updateUserAdminStatus({
    required String userId,
    required bool isAdmin,
  }) async {
    await _supabaseService.client
        .from('users')
        .update({'is_admin': isAdmin})
        .eq('id', userId);
  }
}
```

## State Management (Riverpod Providers)

```dart
// lib/providers/auth_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Provider for AuthService singleton
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService.instance;
});

/// Provider for UserRepository
final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});

/// Stream of authentication state changes
final authStateProvider = StreamProvider<supabase.AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

/// Current Supabase user (null if not authenticated)
final currentSupabaseUserProvider = Provider<supabase.User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (state) => state.session?.user,
    loading: () => null,
    error: (_, __) => null,
  );
});

/// Current User model from database
final currentUserProvider = FutureProvider<User?>((ref) async {
  final supabaseUser = ref.watch(currentSupabaseUserProvider);
  if (supabaseUser == null) return null;

  final userRepository = ref.watch(userRepositoryProvider);
  return await userRepository.getOrCreateUser(supabaseUser);
});

/// Current user's permissions
final userPermissionsProvider = FutureProvider<List<String>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];

  final userRepository = ref.watch(userRepositoryProvider);
  return await userRepository.getUserPermissions(user.id);
});

/// Check if user has a specific permission
/// Usage: ref.watch(hasPermissionProvider('manage_products'))
final hasPermissionProvider = FutureProvider.family<bool, String>((ref, permissionName) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return false;

  // Admins have all permissions
  if (user.isAdmin) return true;

  final permissions = await ref.watch(userPermissionsProvider.future);
  return permissions.contains(permissionName);
});

/// Check if current user is admin
final isAdminProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  return user?.isAdmin ?? false;
});

/// Check if user is signed in
final isSignedInProvider = Provider<bool>((ref) {
  final supabaseUser = ref.watch(currentSupabaseUserProvider);
  return supabaseUser != null;
});
```

## Application Initialization

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 1. Load environment variables
    await EnvConfig.load();

    // 2. Initialize Supabase
    await SupabaseService.initialize();

    // 3. Initialize Auth Service
    AuthService.initialize();

    runApp(
      const ProviderScope(
        child: MyApp(),
      ),
    );
  } catch (error) {
    runApp(ErrorApp(error: error.toString()));
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Your App',
      home: const AuthRouter(),
    );
  }
}

/// Routes user based on auth state
class AuthRouter extends ConsumerWidget {
  const AuthRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (state) {
        if (state.session != null) {
          return const MainScreen(); // Your main app screen
        } else {
          return const LoginScreen();
        }
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        body: Center(child: Text('Authentication Error: $error')),
      ),
    );
  }
}
```

## Login Screen Implementation

```dart
// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      // Navigation handled automatically by auth state changes
    } catch (error) {
      String errorMsg = 'Sign in failed. Please try again.';

      if (error.toString().contains(AppConstants.allowedEmailDomain)) {
        errorMsg = 'Only ${AppConstants.allowedEmailDomain} accounts are allowed.';
      } else if (error.toString().contains('cancelled')) {
        errorMsg = 'Sign in cancelled.';
      }

      setState(() => _errorMessage = errorMsg);
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Your logo here
              const SizedBox(height: 48),

              if (_isSigningIn)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: _handleSignIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],

              const SizedBox(height: 24),
              Text('Sign in with your ${AppConstants.allowedEmailDomain} account'),
            ],
          ),
        ),
      ),
    );
  }
}
```

## Permission Checking in UI

### Checking Permissions in Widgets

```dart
class ProtectedScreen extends ConsumerWidget {
  const ProtectedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPermission = ref.watch(hasPermissionProvider(Permission.manageProducts));

    return hasPermission.when(
      data: (allowed) {
        if (!allowed) {
          return const Center(child: Text('Access Denied'));
        }
        return const ProductManagementScreen();
      },
      loading: () => const CircularProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
    );
  }
}
```

### Admin-Only Features

```dart
class AdminPanel extends ConsumerWidget {
  const AdminPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);

    return isAdmin.when(
      data: (admin) {
        if (!admin) {
          return const SizedBox.shrink(); // Hide for non-admins
        }
        return const AdminSettingsPanel();
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
```

### Conditional UI Elements

```dart
class ProductCard extends ConsumerWidget {
  final Product product;

  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(hasPermissionProvider(Permission.manageProducts));

    return Card(
      child: Column(
        children: [
          Text(product.name),
          // Only show edit button if user has permission
          canEdit.maybeWhen(
            data: (allowed) => allowed
                ? IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editProduct(context),
                  )
                : null,
            orElse: () => null,
          ),
        ],
      ),
    );
  }
}
```

## Google Cloud Console Setup

### 1. Create OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable "Google+ API" or "Google People API"
4. Go to "Credentials" > "Create Credentials" > "OAuth client ID"
5. Configure the OAuth consent screen:
   - User type: Internal (for company-only access)
   - App name, support email, developer contact
6. Create credentials for each platform:
   - **iOS**: Application type "iOS", provide Bundle ID
   - **Android**: Application type "Android", provide package name and SHA-1
   - **macOS**: Application type "Desktop app"
   - **Web**: Application type "Web application" (for Supabase redirect)

### 2. Configure Supabase

1. Go to Supabase Dashboard > Authentication > Providers
2. Enable Google provider
3. Add your Google Client ID and Client Secret
4. Configure redirect URLs for your platforms

## Platform-Specific Configuration

### macOS

Add to `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

### iOS

Add to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

### Android

Add to `android/app/build.gradle`:

```gradle
android {
    defaultConfig {
        manifestPlaceholders = [
            'appAuthRedirectScheme': 'com.yourcompany.yourapp'
        ]
    }
}
```

## Security Considerations

1. **Domain Validation**: Always validate email domains server-side as well. The client-side check is for UX; the database RLS policies enforce security.

2. **Session Management**: Implement automatic session refresh before expiry to prevent disruption.

3. **Admin Actions**: Always verify admin status before allowing admin operations. Use RLS policies in the database as the source of truth.

4. **Environment Variables**: Never commit `.env` files. Use `.env.example` as a template.

5. **Token Storage**: Supabase Flutter handles secure token storage. Don't manually store tokens.

## Testing

### Unit Test Structure

```dart
// test/services/auth_service_test.dart
void main() {
  group('AuthService', () {
    test('instance returns singleton', () {
      final instance1 = AuthService.instance;
      final instance2 = AuthService.instance;
      expect(instance1, same(instance2));
    });

    group('domain validation', () {
      test('only allows emails from allowed domain', () {
        expect(AppConstants.allowedEmailDomain, '@yourcompany.com');
      });
    });
  });
}
```

### Integration Testing

For integration tests:
1. Set up a test Supabase project
2. Create test Google OAuth credentials
3. Use environment-specific `.env` files
4. Clean up test data after tests

## Summary

This authentication system provides:

- **Authentication**: Google OAuth with company domain restriction
- **Backend**: Supabase for auth and PostgreSQL database
- **Authorization**: Role-based permissions with admin override
- **State Management**: Riverpod for reactive auth state
- **Security**: RLS policies, domain validation, session management

Key files in the implementation:
- `lib/services/supabase_service.dart` - Supabase client singleton
- `lib/services/auth_service.dart` - Google OAuth + Supabase auth
- `lib/repositories/user_repository.dart` - User and permission database operations
- `lib/providers/auth_provider.dart` - Riverpod state management
- `lib/models/user.dart` - User data model
- `lib/models/permission.dart` - Permission data model
- `supabase/migrations/000_users_and_permissions.sql` - Database schema
