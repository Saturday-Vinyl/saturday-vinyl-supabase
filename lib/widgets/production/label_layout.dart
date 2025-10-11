import 'package:flutter/material.dart';
import '../../models/production_unit.dart';

/// Widget for displaying a preview of the 1" x 1" thermal label
///
/// This widget shows exactly how the label will look when printed,
/// including QR code, unit ID, product info, and customer details.
class LabelLayout extends StatelessWidget {
  final ProductionUnit unit;
  final String productName;
  final String variantName;
  final String qrCodeUrl;
  final double scale;

  const LabelLayout({
    super.key,
    required this.unit,
    required this.productName,
    required this.variantName,
    required this.qrCodeUrl,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    // 1 inch = 72 points at 72 DPI
    // Scale up for better visibility in preview
    final displaySize = 72.0 * scale;

    return Container(
      width: displaySize,
      height: displaySize,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: EdgeInsets.all(4 * scale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // QR Code (takes most of the space)
            Expanded(
              flex: 3,
              child: Center(
                child: Image.network(
                  qrCodeUrl,
                  width: 50 * scale,
                  height: 50 * scale,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 50 * scale,
                      height: 50 * scale,
                      color: Colors.grey.shade200,
                      child: Icon(
                        Icons.qr_code,
                        size: 30 * scale,
                        color: Colors.grey,
                      ),
                    );
                  },
                ),
              ),
            ),

            SizedBox(height: 2 * scale),

            // Unit ID (bold, larger font)
            Text(
              unit.unitId,
              style: TextStyle(
                fontSize: 6 * scale,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                height: 1.0,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Product + Variant (smaller font)
            Text(
              '$productName - $variantName',
              style: TextStyle(
                fontSize: 4 * scale,
                color: Colors.black,
                height: 1.0,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Customer name (if available)
            if (unit.customerName != null)
              Text(
                unit.customerName!,
                style: TextStyle(
                  fontSize: 4 * scale,
                  color: Colors.black,
                  height: 1.0,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

            // Order number (if available)
            if (unit.shopifyOrderNumber != null)
              Text(
                'Order #${unit.shopifyOrderNumber}',
                style: TextStyle(
                  fontSize: 3 * scale,
                  color: Colors.black,
                  height: 1.0,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
