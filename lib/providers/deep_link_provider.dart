import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/utils/deep_link_handler.dart';

/// Provider for the deep link handler instance.
final deepLinkHandlerProvider = Provider<DeepLinkHandler>((ref) {
  return DeepLinkHandler.instance;
});

/// Provider to initialize deep link handling.
///
/// Watch this provider in your app to set up the router connection.
final deepLinkInitializerProvider = FutureProvider<void>((ref) async {
  await DeepLinkHandler.instance.initialize();
});
