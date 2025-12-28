import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/library.dart';
import 'package:saturday_consumer_app/models/library_member.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';

/// Result type for libraries with role info.
typedef LibraryWithRole = ({Library library, LibraryRole role});

/// FutureProvider for the current user's libraries.
///
/// Returns libraries along with the user's role in each.
final userLibrariesProvider =
    FutureProvider<List<LibraryWithRole>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final libraryRepo = ref.watch(libraryRepositoryProvider);
  return libraryRepo.getUserLibraries(userId);
});

/// StateProvider for the currently selected library ID.
///
/// Used to switch between libraries in the app.
final currentLibraryIdProvider = StateProvider<String?>((ref) {
  // Default to first library when libraries are loaded
  final libraries = ref.watch(userLibrariesProvider);
  return libraries.whenOrNull(
    data: (libs) => libs.isNotEmpty ? libs.first.library.id : null,
  );
});

/// Provider for the currently selected library.
final currentLibraryProvider = Provider<Library?>((ref) {
  final currentId = ref.watch(currentLibraryIdProvider);
  if (currentId == null) return null;

  final libraries = ref.watch(userLibrariesProvider);
  return libraries.whenOrNull(
    data: (libs) {
      try {
        return libs.firstWhere((l) => l.library.id == currentId).library;
      } catch (_) {
        return null;
      }
    },
  );
});

/// Provider for the user's role in the current library.
final currentLibraryRoleProvider = Provider<LibraryRole?>((ref) {
  final currentId = ref.watch(currentLibraryIdProvider);
  if (currentId == null) return null;

  final libraries = ref.watch(userLibrariesProvider);
  return libraries.whenOrNull(
    data: (libs) {
      try {
        return libs.firstWhere((l) => l.library.id == currentId).role;
      } catch (_) {
        return null;
      }
    },
  );
});

/// FutureProvider.family for fetching a library by ID.
final libraryByIdProvider =
    FutureProvider.family<Library?, String>((ref, libraryId) async {
  final libraryRepo = ref.watch(libraryRepositoryProvider);
  return libraryRepo.getLibrary(libraryId);
});

/// FutureProvider for members of the current library.
final currentLibraryMembersProvider =
    FutureProvider<List<LibraryMember>>((ref) async {
  final currentId = ref.watch(currentLibraryIdProvider);
  if (currentId == null) return [];

  final libraryRepo = ref.watch(libraryRepositoryProvider);
  return libraryRepo.getLibraryMembers(currentId);
});

/// Provider for the count of libraries the user has access to.
final libraryCountProvider = Provider<int>((ref) {
  final libraries = ref.watch(userLibrariesProvider);
  return libraries.whenOrNull(data: (libs) => libs.length) ?? 0;
});

/// Provider that returns whether the user can edit the current library.
final canEditCurrentLibraryProvider = Provider<bool>((ref) {
  final role = ref.watch(currentLibraryRoleProvider);
  return role == LibraryRole.owner || role == LibraryRole.editor;
});

/// Provider that returns whether the user owns the current library.
final isCurrentLibraryOwnerProvider = Provider<bool>((ref) {
  final role = ref.watch(currentLibraryRoleProvider);
  return role == LibraryRole.owner;
});
