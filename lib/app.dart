import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// The root widget for the Saturday Consumer App.
class SaturdayApp extends StatelessWidget {
  const SaturdayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Saturday',
      debugShowCheckedModeBanner: false,
      theme: SaturdayTheme.lightTheme,
      routerConfig: appRouter,
    );
  }
}
