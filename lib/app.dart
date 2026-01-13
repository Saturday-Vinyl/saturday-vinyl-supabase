import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/live_activity_provider.dart';
import 'package:saturday_consumer_app/utils/deep_link_handler.dart';

/// The root widget for the Saturday Consumer App.
class SaturdayApp extends ConsumerStatefulWidget {
  const SaturdayApp({super.key});

  @override
  ConsumerState<SaturdayApp> createState() => _SaturdayAppState();
}

class _SaturdayAppState extends ConsumerState<SaturdayApp> {
  final FocusNode _warmUpFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Warm up the keyboard after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmUpKeyboard();
    });
  }

  /// Pre-loads the iOS keyboard to avoid lag on first text input.
  void _warmUpKeyboard() {
    // Request focus to trigger keyboard initialization
    _warmUpFocusNode.requestFocus();
    // Immediately unfocus to hide it
    Future.delayed(const Duration(milliseconds: 100), () {
      _warmUpFocusNode.unfocus();
    });
  }

  @override
  void dispose() {
    _warmUpFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // Initialize Live Activity provider on iOS to react to Now Playing changes
    if (Platform.isIOS) {
      ref.watch(liveActivityProvider);
    }

    // Connect the deep link handler to the router.
    DeepLinkHandler.instance.setRouter(router);

    return MaterialApp.router(
      title: 'Saturday',
      debugShowCheckedModeBanner: false,
      theme: SaturdayTheme.lightTheme,
      routerConfig: router,
      // Uncomment to debug performance:
      // showPerformanceOverlay: true,
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            // Invisible text field for keyboard warm-up
            Positioned(
              left: -1000,
              child: SizedBox(
                width: 1,
                height: 1,
                child: TextField(
                  focusNode: _warmUpFocusNode,
                  autofocus: false,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
