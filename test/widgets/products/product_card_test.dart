import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/widgets/products/product_card.dart';

void main() {
  group('ProductCard', () {
    late Product testProduct;

    setUp(() {
      testProduct = Product(
        id: 'prod-1',
        shopifyProductId: 'gid://shopify/Product/123',
        shopifyProductHandle: 'test-product',
        name: 'Test Product',
        productCode: 'TEST-PROD',
        description: 'Test description',
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastSyncedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
    });

    testWidgets('displays product name and code', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductCard(
              product: testProduct,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Product'), findsOneWidget);
      expect(find.text('TEST-PROD'), findsOneWidget);
    });

    testWidgets('displays sync information when available', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductCard(
              product: testProduct,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.sync), findsOneWidget);
      expect(find.textContaining('Synced'), findsOneWidget);
    });

    testWidgets('does not display sync info when not synced', (tester) async {
      final unsyncedProduct = testProduct.copyWith(lastSyncedAt: null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductCard(
              product: unsyncedProduct,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.sync), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductCard(
              product: testProduct,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      expect(tapped, true);
    });

    testWidgets('displays product icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductCard(
              product: testProduct,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });

    testWidgets('displays chevron icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductCard(
              product: testProduct,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('is wrapped in a Card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductCard(
              product: testProduct,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(Card), findsOneWidget);
    });
  });
}
