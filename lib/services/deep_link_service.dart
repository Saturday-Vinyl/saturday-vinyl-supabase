import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Handles incoming deep links for the saturday:// URI scheme.
///
/// Routes:
///   saturday://part/{partNumber}    — navigate to part detail
///   saturday://oauth/digikey?code=… — DigiKey OAuth callback
class DeepLinkService {
  static DeepLinkService? _instance;
  static DeepLinkService get instance => _instance ??= DeepLinkService._();

  DeepLinkService._();

  final _appLinks = AppLinks();

  /// Stream of incoming deep link URIs (for listeners to react to)
  final _linkController = StreamController<Uri>.broadcast();
  Stream<Uri> get linkStream => _linkController.stream;

  /// The initial link that launched the app (if any)
  Uri? _initialLink;
  Uri? get initialLink => _initialLink;

  /// Completer for OAuth callbacks — allows awaiting the redirect
  Completer<Uri>? _oauthCompleter;

  /// Initialize deep link listening. Call once from main().
  Future<void> initialize() async {
    // Check if app was launched via deep link
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        AppLogger.info('DeepLinkService: initial link: $initialUri');
        _initialLink = initialUri;
        _handleUri(initialUri);
      }
    } catch (e) {
      AppLogger.warning('DeepLinkService: no initial link ($e)');
    }

    // Listen for incoming links while app is running
    _appLinks.uriLinkStream.listen(
      (uri) {
        AppLogger.info('DeepLinkService: incoming link: $uri');
        _handleUri(uri);
      },
      onError: (e) {
        AppLogger.error(
            'DeepLinkService: link stream error', e, StackTrace.current);
      },
    );
  }

  void _handleUri(Uri uri) {
    // Check if this is an OAuth callback
    if (uri.host == 'oauth' && _oauthCompleter != null && !_oauthCompleter!.isCompleted) {
      AppLogger.info('DeepLinkService: completing OAuth callback');
      _oauthCompleter!.complete(uri);
      return;
    }

    // Forward all other links to listeners
    _linkController.add(uri);
  }

  /// Wait for an OAuth redirect to saturday://oauth/{provider}
  /// Returns the full callback URI with query parameters (code, state, etc.)
  ///
  /// Call this before launching the browser for OAuth, then await the result.
  /// Times out after [timeout] duration.
  Future<Uri> waitForOAuthCallback({
    Duration timeout = const Duration(minutes: 5),
  }) {
    _oauthCompleter = Completer<Uri>();
    return _oauthCompleter!.future.timeout(
      timeout,
      onTimeout: () {
        _oauthCompleter = null;
        throw TimeoutException('OAuth callback not received', timeout);
      },
    );
  }

  /// Cancel a pending OAuth wait
  void cancelOAuthWait() {
    if (_oauthCompleter != null && !_oauthCompleter!.isCompleted) {
      _oauthCompleter!.completeError('OAuth cancelled');
    }
    _oauthCompleter = null;
  }

  void dispose() {
    _linkController.close();
    _oauthCompleter = null;
  }
}
