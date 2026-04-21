import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/services/digikey_service.dart';

/// Provider for DigiKey connection status
final digikeyConnectionProvider =
    FutureProvider<DigiKeyConnectionStatus>((ref) async {
  return DigiKeyService.instance.getConnectionStatus();
});
