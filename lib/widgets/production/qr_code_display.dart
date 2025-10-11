import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/services/storage_service.dart';

/// Widget for displaying a QR code from a URL
class QRCodeDisplay extends StatelessWidget {
  final String qrCodeUrl;
  final String unitId;
  final double size;
  final VoidCallback? onRegenerate;

  const QRCodeDisplay({
    super.key,
    required this.qrCodeUrl,
    required this.unitId,
    this.size = 200,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // QR Code Image
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: FutureBuilder<String>(
                future: StorageService().getSignedUrl(qrCodeUrl),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: SaturdayColors.error,
                            size: size * 0.3,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Failed to load QR code',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }

                  final signedUrl = snapshot.data!;

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: signedUrl,
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      errorWidget: (context, url, error) => Center(
                        child: Icon(
                          Icons.qr_code,
                          size: size * 0.5,
                          color: SaturdayColors.secondaryGrey,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Unit ID
            Text(
              unitId,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: SaturdayColors.primaryDark,
                  ),
            ),

            const SizedBox(height: 8),

            // Instruction text
            Text(
              'Scan this code to track production',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
              textAlign: TextAlign.center,
            ),

            // Regenerate button (if callback provided)
            if (onRegenerate != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Regenerate QR Code'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SaturdayColors.primaryDark,
                  side: BorderSide(
                    color: SaturdayColors.primaryDark.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
