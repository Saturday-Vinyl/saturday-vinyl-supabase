import 'dart:io';
import 'package:flutter/foundation.dart';

/// Shared platform detection utility.
///
/// Replaces duplicated private getters across MainScaffold, QRScanScreen, etc.
class PlatformUtils {
  PlatformUtils._();

  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
}
