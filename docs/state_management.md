# State Management Developer's Guide

## Overview

This document describes the state management patterns and conventions used in the Saturday! Admin App. The application uses Flutter Riverpod as its primary state management solution.

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App                              │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────────────┐    │
│  │   Widgets   │───▶│  Providers  │───▶│    Services      │    │
│  │ (Consumer)  │    │ (Riverpod)  │    │                  │    │
│  └─────────────┘    └─────────────┘    └──────────────────┘    │
│         │                  │                    │               │
│         ▼                  ▼                    ▼               │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────────────┐    │
│  │     UI      │◀───│    State    │◀───│  Repositories    │    │
│  │  (Rebuild)  │    │  Notifiers  │    │  (Data Access)   │    │
│  └─────────────┘    └─────────────┘    └──────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Dependencies

The state management dependency in `pubspec.yaml`:

```yaml
dependencies:
  flutter_riverpod: ^2.4.0
```

## Provider Types

### Simple Provider

Use for singleton services and repositories that don't change.

```dart
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService.instance;
});
```

### FutureProvider

Use for asynchronous data fetching that returns a single value.

```dart
final currentUserProvider = FutureProvider<User?>((ref) async {
  final authService = ref.watch(authServiceProvider);
  return await authService.getCurrentUser();
});
```

### FutureProvider.family

Use for parameterized async queries (e.g., fetching by ID).

```dart
final unitByIdProvider = FutureProvider.family<ProductionUnit, String>((ref, id) async {
  final repository = ref.watch(productionUnitRepositoryProvider);
  return await repository.getById(id);
});
```

### StreamProvider

Use for real-time data streams.

```dart
final authStateProvider = StreamProvider<supabase.AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});
```

### StateNotifierProvider

Use for managing mutable state with complex business logic.

```dart
final scanModeProvider = StateNotifierProvider<ScanModeNotifier, ScanModeState>((ref) {
  return ScanModeNotifier(ref);
});
```

## State Classes

### Immutable State with copyWith

All state classes should be immutable and include a `copyWith` method for updates:

```dart
class ScanModeState {
  final bool isScanning;
  final bool isLoading;
  final Set<String> foundEpcs;
  final String? error;

  const ScanModeState({
    this.isScanning = false,
    this.isLoading = false,
    this.foundEpcs = const {},
    this.error,
  });

  ScanModeState copyWith({
    bool? isScanning,
    bool? isLoading,
    Set<String>? foundEpcs,
    String? error,
  }) {
    return ScanModeState(
      isScanning: isScanning ?? this.isScanning,
      isLoading: isLoading ?? this.isLoading,
      foundEpcs: foundEpcs ?? this.foundEpcs,
      error: error,
    );
  }
}
```

### State Class Conventions

- Include `isLoading` for async operations
- Include optional `error` field for error states
- Use `const` constructor with default values
- Clear error when starting new operations

## StateNotifier Implementation

```dart
class ScanModeNotifier extends StateNotifier<ScanModeState> {
  final Ref ref;

  ScanModeNotifier(this.ref) : super(const ScanModeState());

  Future<void> startScanning() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Perform operation
      state = state.copyWith(isScanning: true, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void reset() {
    state = const ScanModeState();
  }
}
```

## Widget Integration

### ConsumerWidget

Use `ConsumerWidget` for widgets that need to read providers:

```dart
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserProvider);

    return currentUserAsync.when(
      data: (user) => Text('Hello, ${user?.name}'),
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => Text('Error: $error'),
    );
  }
}
```

### ConsumerStatefulWidget

Use when you need both state management and local widget state:

```dart
class MyForm extends ConsumerStatefulWidget {
  const MyForm({super.key});

  @override
  ConsumerState<MyForm> createState() => _MyFormState();
}

class _MyFormState extends ConsumerState<MyForm> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(formProvider);
    // ...
  }
}
```

### ProviderScope

The app is wrapped with `ProviderScope` in `main.dart`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const MyApp(),
    ),
  );
}
```

## Reading Providers

### ref.watch()

Use in `build()` methods to reactively rebuild when state changes:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final state = ref.watch(myProvider);  // Rebuilds when state changes
  return Text(state.value);
}
```

### ref.read()

Use in event handlers and methods where you don't want to subscribe:

```dart
void onButtonPressed() {
  ref.read(myProvider.notifier).doSomething();  // One-time read
}
```

### ref.listen()

Use to perform side effects when state changes:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  ref.listen(authStateProvider, (previous, next) {
    if (next.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auth error: ${next.error}')),
      );
    }
  });
  // ...
}
```

## Cache Invalidation

Use `ref.invalidate()` to refresh provider data after mutations:

```dart
Future<void> createUnit(ProductionUnit unit) async {
  await repository.create(unit);

  // Invalidate to trigger refetch
  ref.invalidate(productionUnitsProvider);
  ref.invalidate(unitByIdProvider(unit.id));
}
```

## Directory Structure

All providers are organized in `/lib/providers/`:

```
lib/providers/
├── auth_provider.dart          # Authentication state
├── product_provider.dart       # Product management
├── production_unit_provider.dart
├── scan_mode_provider.dart     # RFID scanning state
├── rfid_settings_provider.dart
├── shared_preferences_provider.dart
└── ...
```

## Naming Conventions

| Type | Naming Pattern | Example |
|------|----------------|---------|
| Provider | `{name}Provider` | `authServiceProvider` |
| StateNotifier | `{Name}Notifier` | `ScanModeNotifier` |
| State class | `{Name}State` | `ScanModeState` |
| Family provider | `{name}ByIdProvider` | `unitByIdProvider` |

## Best Practices

1. **Keep providers focused**: Each provider should manage a single concern
2. **Use immutable state**: Always use `copyWith` for state updates
3. **Handle loading/error states**: Include these in your state classes
4. **Invalidate after mutations**: Refresh dependent providers after data changes
5. **Prefer watch over read**: Use `ref.watch()` in build methods for reactivity
6. **Use read for events**: Use `ref.read()` in callbacks and event handlers
7. **Dispose resources**: Clean up streams and controllers in StateNotifier `dispose()`

## AsyncValue Handling

When using `FutureProvider` or `StreamProvider`, use the `.when()` pattern:

```dart
final asyncValue = ref.watch(myFutureProvider);

return asyncValue.when(
  data: (data) => MyWidget(data: data),
  loading: () => const LoadingIndicator(),
  error: (error, stack) => ErrorWidget(error: error),
);
```

Or use convenience getters for simpler cases:

```dart
if (asyncValue.isLoading) return const LoadingIndicator();
if (asyncValue.hasError) return ErrorWidget(error: asyncValue.error);
return MyWidget(data: asyncValue.value!);
```
