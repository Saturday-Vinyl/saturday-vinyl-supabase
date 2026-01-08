import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';

/// Deep link path patterns.
class DeepLinkPaths {
  DeepLinkPaths._();

  /// Tag association deep link: /tags/{epc}
  static const String tags = '/tags';

  /// Album detail deep link: /albums/{id}
  static const String albums = '/albums';

  /// Library invitation deep link: /invite/{code}
  static const String invite = '/invite';
}

/// Handles deep links into the app.
///
/// Supports:
/// - Universal Links (iOS) / App Links (Android) for app.saturdayvinyl.com
/// - Custom URL scheme: saturday://
///
/// URL patterns:
/// - `/tags/{epc}` → Tag association screen (opens now playing with tag)
/// - `/albums/{id}` → Album detail screen
/// - `/invite/{code}` → Library invitation acceptance
class DeepLinkHandler {
  DeepLinkHandler._();

  static final DeepLinkHandler _instance = DeepLinkHandler._();
  static DeepLinkHandler get instance => _instance;

  final AppLinks _appLinks = AppLinks();
  GoRouter? _router;

  /// Whether the handler has been initialized.
  bool _initialized = false;

  /// Pending deep link to handle when router becomes available.
  Uri? _pendingDeepLink;

  /// Initialize the deep link handler.
  ///
  /// Call this early in app startup, before the router is available.
  Future<void> initialize() async {
    if (_initialized) return;

    // Get the initial link that launched the app (if any).
    final initialLink = await _appLinks.getInitialLink();
    if (initialLink != null) {
      _pendingDeepLink = initialLink;
      if (kDebugMode) {
        print('DeepLinkHandler: Initial link: $initialLink');
      }
    }

    // Listen for subsequent deep links while app is running.
    _appLinks.uriLinkStream.listen(_onDeepLink);

    _initialized = true;

    if (kDebugMode) {
      print('DeepLinkHandler: Initialized');
    }
  }

  /// Set the router instance for navigation.
  ///
  /// Call this after the router is created, typically in the app widget.
  void setRouter(GoRouter router) {
    _router = router;

    // Handle any pending deep link.
    if (_pendingDeepLink != null) {
      _handleDeepLink(_pendingDeepLink!);
      _pendingDeepLink = null;
    }
  }

  /// Handle an incoming deep link.
  void _onDeepLink(Uri uri) {
    if (kDebugMode) {
      print('DeepLinkHandler: Received deep link: $uri');
    }

    if (_router != null) {
      _handleDeepLink(uri);
    } else {
      // Store for later when router is available.
      _pendingDeepLink = uri;
    }
  }

  /// Parse and navigate based on the deep link URI.
  void _handleDeepLink(Uri uri) {
    if (_router == null) return;

    // Extract path and handle the link.
    final path = uri.path;
    final segments = uri.pathSegments;

    if (kDebugMode) {
      print('DeepLinkHandler: Handling path: $path, segments: $segments');
    }

    if (segments.isEmpty) {
      // Root path - just go home.
      _router!.go(RoutePaths.nowPlaying);
      return;
    }

    switch (segments[0]) {
      case 'tags':
        _handleTagLink(segments);
        break;

      case 'albums':
        _handleAlbumLink(segments);
        break;

      case 'invite':
        _handleInviteLink(segments);
        break;

      default:
        // Unknown path - go home.
        if (kDebugMode) {
          print('DeepLinkHandler: Unknown path, going home');
        }
        _router!.go(RoutePaths.nowPlaying);
    }
  }

  /// Handle tag association deep link.
  ///
  /// URL format: /tags/{epc}
  /// Where epc is the EPC code from the Saturday tag QR code.
  void _handleTagLink(List<String> segments) {
    if (segments.length < 2) {
      // Missing EPC - go to library.
      _router!.go(RoutePaths.library);
      return;
    }

    final epc = segments[1];

    if (kDebugMode) {
      print('DeepLinkHandler: Tag link with EPC: $epc');
    }

    // Navigate to tag association with the scanned EPC.
    // The tag association flow will look up the album by tag or prompt to associate.
    // For now, we'll go to now playing and let the tag lookup happen.
    // In a real implementation, this would trigger tag lookup.
    _router!.go(RoutePaths.nowPlaying);
    // TODO: Implement tag lookup by EPC and navigate to album or associate.
  }

  /// Handle album detail deep link.
  ///
  /// URL format: /albums/{id}
  /// Where id is the library album ID.
  void _handleAlbumLink(List<String> segments) {
    if (segments.length < 2) {
      // Missing album ID - go to library.
      _router!.go(RoutePaths.library);
      return;
    }

    final albumId = segments[1];

    if (kDebugMode) {
      print('DeepLinkHandler: Album link with ID: $albumId');
    }

    // Navigate to album detail.
    _router!.go('${RoutePaths.library}/album/$albumId');
  }

  /// Handle library invitation deep link.
  ///
  /// URL format: /invite/{code}
  /// Where code is the invitation code.
  void _handleInviteLink(List<String> segments) {
    if (segments.length < 2) {
      // Missing invite code - go to account.
      _router!.go(RoutePaths.account);
      return;
    }

    final inviteCode = segments[1];

    if (kDebugMode) {
      print('DeepLinkHandler: Invite link with code: $inviteCode');
    }

    // Navigate to account and show invitation dialog.
    // In a real implementation, this would trigger the invitation acceptance flow.
    _router!.go(RoutePaths.account);
    // TODO: Implement invitation acceptance flow.
  }

  /// Create a deep link URL for a tag.
  static Uri createTagLink(String epc) {
    return Uri(
      scheme: 'https',
      host: 'app.saturdayvinyl.com',
      path: '/tags/$epc',
    );
  }

  /// Create a deep link URL for an album.
  static Uri createAlbumLink(String albumId) {
    return Uri(
      scheme: 'https',
      host: 'app.saturdayvinyl.com',
      path: '/albums/$albumId',
    );
  }

  /// Create a deep link URL for a library invitation.
  static Uri createInviteLink(String code) {
    return Uri(
      scheme: 'https',
      host: 'app.saturdayvinyl.com',
      path: '/invite/$code',
    );
  }
}
