import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// iPhone 14 Pro logical size — default surface for screen goldens.
const Size kIPhone14Pro = Size(393, 852);

/// Loads bundled fonts (Bevan, Roboto for body text, and Material/Cupertino
/// icon fonts) into the test engine so goldens render real glyphs instead
/// of Ahem boxes. Call from `setUpAll` — file/asset I/O hangs inside
/// `testWidgets` due to the fake-async zone.
Future<void> loadGoldenFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> loadFromAssets(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  Future<void> loadFromFiles(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await loadFromAssets('Bevan', const ['assets/fonts/Bevan-Regular.ttf']);
  await loadFromAssets('MaterialIcons', const ['fonts/MaterialIcons-Regular.otf']);
  await loadFromAssets('packages/cupertino_icons/CupertinoIcons',
      const ['packages/cupertino_icons/assets/CupertinoIcons.ttf']);

  // Body text font — not bundled in production (system font is used at
  // runtime); shipped only for golden tests so non-Bevan text renders
  // legibly instead of as Ahem boxes.
  await loadFromFiles('Roboto', const [
    'test/fonts/Roboto-Regular.ttf',
    'test/fonts/Roboto-Medium.ttf',
    'test/fonts/Roboto-Bold.ttf',
  ]);
}

/// Returns a copy of the app theme with Roboto as the default font family
/// for any text style that doesn't explicitly set one (production uses the
/// system font here, which is Ahem in the test engine). Bevan headline
/// styles set fontFamily explicitly, so they're unaffected.
ThemeData _testTheme() {
  final base = SaturdayTheme.lightTheme;
  return base.copyWith(
    // ThemeData.fontFamily applies to any TextStyle that doesn't set one.
    // We can't pass it via copyWith, so build a fresh ThemeData inheriting
    // from base and just override the textTheme + a default text style.
  ).copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto').copyWith(
          displayLarge: base.textTheme.displayLarge,
          displayMedium: base.textTheme.displayMedium,
          displaySmall: base.textTheme.displaySmall,
          headlineLarge: base.textTheme.headlineLarge,
          headlineMedium: base.textTheme.headlineMedium,
          headlineSmall: base.textTheme.headlineSmall,
        ),
  );
}

/// Wraps a screen in a DefaultTextStyle that applies Roboto, so any inline
/// TextStyle without a fontFamily renders in Roboto rather than Ahem.
Widget _withDefaultFont(Widget child) {
  return DefaultTextStyle.merge(
    style: const TextStyle(fontFamily: 'Roboto'),
    child: child,
  );
}

/// Provider overrides that stub out auth — keeps screens that listen to
/// auth state from trying to reach Supabase during a golden render.
List<Override> defaultGoldenOverrides() => [
      authStateChangesProvider.overrideWith(
        (_) => const Stream<supabase.AuthState>.empty(),
      ),
    ];

/// Pumps a screen at iPhone 14 Pro logical size with the app's real theme
/// and stubbed providers.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = kIPhone14Pro,
  List<Override> extraOverrides = const [],
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...defaultGoldenOverrides(),
        ...extraOverrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _testTheme(),
        home: Builder(
          builder: (context) => _withDefaultFont(screen),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}
