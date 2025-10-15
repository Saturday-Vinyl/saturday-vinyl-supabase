import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/services/qr_code_fetch_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for QRCodeFetchService
final qrCodeFetchServiceProvider = Provider<QRCodeFetchService>((ref) {
  return QRCodeFetchService(Supabase.instance.client);
});
