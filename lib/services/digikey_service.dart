import 'package:supabase_flutter/supabase_flutter.dart' show HttpMethod;
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// A product returned from the DigiKey API
class DigiKeyProduct {
  final String? digikeyPn;
  final String? manufacturerPn;
  final String? manufacturer;
  final String? description;
  final double? unitPrice;
  final int? quantityAvailable;
  final String? category;
  final String? family;
  final String? package;
  final String? datasheetUrl;
  final String? productUrl;
  final String? imageUrl;

  const DigiKeyProduct({
    this.digikeyPn,
    this.manufacturerPn,
    this.manufacturer,
    this.description,
    this.unitPrice,
    this.quantityAvailable,
    this.category,
    this.family,
    this.package,
    this.datasheetUrl,
    this.productUrl,
    this.imageUrl,
  });

  factory DigiKeyProduct.fromJson(Map<String, dynamic> json) {
    return DigiKeyProduct(
      digikeyPn: json['digikey_pn'] as String?,
      manufacturerPn: json['manufacturer_pn'] as String?,
      manufacturer: json['manufacturer'] as String?,
      description: json['description'] as String?,
      unitPrice: json['unit_price'] != null
          ? (json['unit_price'] as num).toDouble()
          : null,
      quantityAvailable: json['quantity_available'] as int?,
      category: json['category'] as String?,
      family: json['family'] as String?,
      package: json['package'] as String?,
      datasheetUrl: json['datasheet_url'] as String?,
      productUrl: json['product_url'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }
}

/// Client for the DigiKey integration via Supabase Edge Functions.
class DigiKeyService {
  static DigiKeyService? _instance;
  static DigiKeyService get instance => _instance ??= DigiKeyService._();

  DigiKeyService._();

  final _supabase = SupabaseService.instance.client;

  // ---- Connection status ----

  /// Check if the current user has a DigiKey connection
  Future<DigiKeyConnectionStatus> getConnectionStatus() async {
    try {
      final response = await _supabase.functions.invoke(
        'digikey-auth/status',
        method: HttpMethod.get,
      );

      if (response.status != 200) {
        return const DigiKeyConnectionStatus(connected: false);
      }

      final data = response.data as Map<String, dynamic>;
      return DigiKeyConnectionStatus(
        connected: data['connected'] as bool? ?? false,
        tokenExpired: data['token_expired'] as bool? ?? false,
        connectedAt: data['connected_at'] as String?,
      );
    } catch (e) {
      AppLogger.error('DigiKeyService: status check failed', e, StackTrace.current);
      return const DigiKeyConnectionStatus(connected: false);
    }
  }

  // ---- OAuth flow ----

  /// Start the DigiKey OAuth flow — opens browser for user consent.
  /// Returns true if the auth URL was opened successfully.
  Future<bool> connectAccount() async {
    try {
      final response = await _supabase.functions.invoke(
        'digikey-auth/initiate',
        method: HttpMethod.get,
      );

      if (response.status != 200) {
        AppLogger.error('DigiKeyService: initiate failed: ${response.status}');
        return false;
      }

      final data = response.data as Map<String, dynamic>;
      final authUrl = data['auth_url'] as String?;
      if (authUrl == null) return false;

      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.error('DigiKeyService: connect failed', e, StackTrace.current);
      return false;
    }
  }

  /// Disconnect DigiKey account (remove stored tokens)
  Future<bool> disconnectAccount() async {
    try {
      final response = await _supabase.functions.invoke(
        'digikey-auth/disconnect',
        method: HttpMethod.post,
      );
      return response.status == 200;
    } catch (e) {
      AppLogger.error('DigiKeyService: disconnect failed', e, StackTrace.current);
      return false;
    }
  }

  // ---- Part search ----

  /// Look up a part using parsed barcode fields (from ECIA DataMatrix)
  Future<List<DigiKeyProduct>> lookupByBarcode({
    String? distributorPn,
    String? manufacturerPn,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'digikey-search/barcode',
        body: {
          if (distributorPn != null) 'distributor_pn': distributorPn,
          if (manufacturerPn != null) 'manufacturer_pn': manufacturerPn,
        },
      );

      return _parseResults(response);
    } catch (e) {
      AppLogger.error('DigiKeyService: barcode lookup failed', e, StackTrace.current);
      return [];
    }
  }

  /// Search DigiKey by keyword
  Future<List<DigiKeyProduct>> searchKeyword(String query, {int limit = 10}) async {
    try {
      final response = await _supabase.functions.invoke(
        'digikey-search/keyword',
        body: {'query': query, 'limit': limit},
      );

      return _parseResults(response);
    } catch (e) {
      AppLogger.error('DigiKeyService: keyword search failed', e, StackTrace.current);
      return [];
    }
  }

  /// Look up a specific part number on DigiKey
  Future<List<DigiKeyProduct>> lookupPartNumber({
    String? digikeyPn,
    String? manufacturerPn,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'digikey-search/part',
        body: {
          if (digikeyPn != null) 'digikey_pn': digikeyPn,
          if (manufacturerPn != null) 'manufacturer_pn': manufacturerPn,
        },
      );

      return _parseResults(response);
    } catch (e) {
      AppLogger.error('DigiKeyService: part lookup failed', e, StackTrace.current);
      return [];
    }
  }

  List<DigiKeyProduct> _parseResults(dynamic response) {
    if (response.status == 403) {
      throw DigiKeyNotConnectedException();
    }

    if (response.status != 200) {
      AppLogger.warning('DigiKeyService: API returned ${response.status}');
      return [];
    }

    final data = response.data as Map<String, dynamic>;
    final results = data['results'] as List? ?? [];
    return results
        .map((r) => DigiKeyProduct.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}

class DigiKeyConnectionStatus {
  final bool connected;
  final bool tokenExpired;
  final String? connectedAt;

  const DigiKeyConnectionStatus({
    required this.connected,
    this.tokenExpired = false,
    this.connectedAt,
  });

  bool get isReady => connected && !tokenExpired;
}

class DigiKeyNotConnectedException implements Exception {
  @override
  String toString() => 'DigiKey account not connected';
}
