import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// The root widget for the Saturday Consumer App.
class SaturdayApp extends ConsumerWidget {
  const SaturdayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Saturday',
      debugShowCheckedModeBanner: false,
      theme: SaturdayTheme.lightTheme,
      routerConfig: router,
    );
  }
}
