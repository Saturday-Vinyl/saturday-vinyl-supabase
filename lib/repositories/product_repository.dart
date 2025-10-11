import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/models/product_variant.dart';
import 'package:saturday_app/services/shopify_service.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing products and variants
class ProductRepository {
  final _supabase = SupabaseService.instance.client;
  final _shopify = ShopifyService();
  final _uuid = const Uuid();

  /// Sync products from Shopify to Supabase
  /// Fetches all products from Shopify and upserts them to the database
  /// Returns count of products synced
  Future<int> syncProductsFromShopify() async {
    try {
      AppLogger.info('Starting product sync from Shopify');

      // Fetch products from Shopify
      final shopifyProducts = await _shopify.fetchProducts();

      int syncedCount = 0;

      for (final shopifyProduct in shopifyProducts) {
        try {
          await _syncProduct(shopifyProduct);
          syncedCount++;
        } catch (error, stackTrace) {
          AppLogger.error(
            'Failed to sync product ${shopifyProduct['id']}',
            error,
            stackTrace,
          );
          // Continue with other products
        }
      }

      AppLogger.info('Product sync completed. Synced $syncedCount/${shopifyProducts.length} products');
      return syncedCount;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to sync products from Shopify', error, stackTrace);
      rethrow;
    }
  }

  /// Sync a single product from Shopify data
  Future<void> _syncProduct(Map<String, dynamic> shopifyData) async {
    final shopifyId = shopifyData['id'] as String;
    final handle = shopifyData['handle'] as String;
    final title = shopifyData['title'] as String;
    final description = shopifyData['description'] as String?;

    // Extract product code from handle or title
    // Format: "product-name" -> "PROD-NAME"
    final productCode = _generateProductCode(handle);

    final now = DateTime.now();

    // Check if product already exists
    final existingProduct = await _supabase
        .from('products')
        .select()
        .eq('shopify_product_id', shopifyId)
        .maybeSingle();

    Product product;

    if (existingProduct != null) {
      // Update existing product
      final productId = existingProduct['id'] as String;

      await _supabase.from('products').update({
        'shopify_product_handle': handle,
        'name': title,
        'description': description,
        'last_synced_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).eq('id', productId);

      product = Product(
        id: productId,
        shopifyProductId: shopifyId,
        shopifyProductHandle: handle,
        name: title,
        productCode: existingProduct['product_code'] as String,
        description: description,
        isActive: existingProduct['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(existingProduct['created_at'] as String),
        updatedAt: now,
        lastSyncedAt: now,
      );

      AppLogger.info('Updated product: $title');
    } else {
      // Insert new product
      final productId = _uuid.v4();

      await _supabase.from('products').insert({
        'id': productId,
        'shopify_product_id': shopifyId,
        'shopify_product_handle': handle,
        'name': title,
        'product_code': productCode,
        'description': description,
        'is_active': true,
        'last_synced_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      product = Product(
        id: productId,
        shopifyProductId: shopifyId,
        shopifyProductHandle: handle,
        name: title,
        productCode: productCode,
        description: description,
        isActive: true,
        createdAt: now,
        updatedAt: now,
        lastSyncedAt: now,
      );

      AppLogger.info('Created new product: $title');
    }

    // Sync variants
    await _syncVariants(product, shopifyData);
  }

  /// Sync variants for a product
  Future<void> _syncVariants(Product product, Map<String, dynamic> shopifyData) async {
    final variantsData = shopifyData['variants'] as Map<String, dynamic>?;
    if (variantsData == null) return;

    final edges = variantsData['edges'] as List<dynamic>?;
    if (edges == null || edges.isEmpty) return;

    for (final edge in edges) {
      final variantNode = edge['node'] as Map<String, dynamic>;
      await _syncVariant(product, variantNode);
    }
  }

  /// Sync a single variant
  Future<void> _syncVariant(Product product, Map<String, dynamic> variantData) async {
    final shopifyVariantId = variantData['id'] as String;
    final sku = variantData['sku'] as String? ?? '';
    final title = variantData['title'] as String;
    final price = double.tryParse(variantData['price']?.toString() ?? '0') ?? 0.0;

    // Extract options from selectedOptions
    final selectedOptions = variantData['selectedOptions'] as List<dynamic>?;
    String? option1Name;
    String? option1Value;
    String? option2Name;
    String? option2Value;
    String? option3Name;
    String? option3Value;

    if (selectedOptions != null && selectedOptions.isNotEmpty) {
      if (selectedOptions.isNotEmpty) {
        final opt1 = selectedOptions[0] as Map<String, dynamic>;
        option1Name = opt1['name'] as String?;
        option1Value = opt1['value'] as String?;
      }
      if (selectedOptions.length > 1) {
        final opt2 = selectedOptions[1] as Map<String, dynamic>;
        option2Name = opt2['name'] as String?;
        option2Value = opt2['value'] as String?;
      }
      if (selectedOptions.length > 2) {
        final opt3 = selectedOptions[2] as Map<String, dynamic>;
        option3Name = opt3['name'] as String?;
        option3Value = opt3['value'] as String?;
      }
    }

    final now = DateTime.now();

    // Check if variant already exists
    final existingVariant = await _supabase
        .from('product_variants')
        .select()
        .eq('shopify_variant_id', shopifyVariantId)
        .maybeSingle();

    if (existingVariant != null) {
      // Update existing variant
      await _supabase.from('product_variants').update({
        'sku': sku,
        'name': title,
        'option1_name': option1Name,
        'option1_value': option1Value,
        'option2_name': option2Name,
        'option2_value': option2Value,
        'option3_name': option3Name,
        'option3_value': option3Value,
        'price': price,
        'updated_at': now.toIso8601String(),
      }).eq('id', existingVariant['id']);
    } else {
      // Insert new variant
      await _supabase.from('product_variants').insert({
        'id': _uuid.v4(),
        'product_id': product.id,
        'shopify_variant_id': shopifyVariantId,
        'sku': sku,
        'name': title,
        'option1_name': option1Name,
        'option1_value': option1Value,
        'option2_name': option2Name,
        'option2_value': option2Value,
        'option3_name': option3Name,
        'option3_value': option3Value,
        'price': price,
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }
  }

  /// Generate a product code from handle
  /// e.g., "walnut-record-player" -> "WALNUT-RECORD-PLAYER"
  String _generateProductCode(String handle) {
    return handle.toUpperCase().replaceAll('-', '-');
  }

  /// Get all products from Supabase
  Future<List<Product>> getProducts() async {
    try {
      final response = await _supabase
          .from('products')
          .select()
          .eq('is_active', true)
          .order('name');

      final products = (response as List)
          .map((json) => Product.fromJson(json as Map<String, dynamic>))
          .toList();

      return products;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch products', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single product with variants
  Future<Product?> getProduct(String productId) async {
    try {
      final response = await _supabase
          .from('products')
          .select()
          .eq('id', productId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Product.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch product $productId', error, stackTrace);
      rethrow;
    }
  }

  /// Get variants for a product
  Future<List<ProductVariant>> getProductVariants(String productId) async {
    try {
      final response = await _supabase
          .from('product_variants')
          .select()
          .eq('product_id', productId)
          .eq('is_active', true)
          .order('name');

      final variants = (response as List)
          .map((json) => ProductVariant.fromJson(json as Map<String, dynamic>))
          .toList();

      return variants;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch variants for product $productId', error, stackTrace);
      rethrow;
    }
  }

  /// Get all variants across all products
  Future<List<ProductVariant>> getAllVariants() async {
    try {
      final response = await _supabase
          .from('product_variants')
          .select()
          .eq('is_active', true)
          .order('name');

      final variants = (response as List)
          .map((json) => ProductVariant.fromJson(json as Map<String, dynamic>))
          .toList();

      return variants;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch all variants', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single variant by ID
  Future<ProductVariant?> getVariant(String variantId) async {
    try {
      final response = await _supabase
          .from('product_variants')
          .select()
          .eq('id', variantId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return ProductVariant.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch variant $variantId', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new product variant manually
  Future<ProductVariant> createVariant({
    required String productId,
    required String shopifyVariantId,
    required String sku,
    required String name,
    String? option1Name,
    String? option1Value,
    String? option2Name,
    String? option2Value,
    String? option3Name,
    String? option3Value,
    required double price,
  }) async {
    try {
      final variantId = _uuid.v4();
      final now = DateTime.now();

      await _supabase.from('product_variants').insert({
        'id': variantId,
        'product_id': productId,
        'shopify_variant_id': shopifyVariantId,
        'sku': sku,
        'name': name,
        'option1_name': option1Name,
        'option1_value': option1Value,
        'option2_name': option2Name,
        'option2_value': option2Value,
        'option3_name': option3Name,
        'option3_value': option3Value,
        'price': price,
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      AppLogger.info('Created variant: $name (SKU: $sku)');

      return ProductVariant(
        id: variantId,
        productId: productId,
        shopifyVariantId: shopifyVariantId,
        sku: sku,
        name: name,
        option1Name: option1Name,
        option1Value: option1Value,
        option2Name: option2Name,
        option2Value: option2Value,
        option3Name: option3Name,
        option3Value: option3Value,
        price: price,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create variant', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing product variant
  Future<ProductVariant> updateVariant({
    required String variantId,
    String? sku,
    String? name,
    String? option1Name,
    String? option1Value,
    String? option2Name,
    String? option2Value,
    String? option3Name,
    String? option3Value,
    double? price,
    bool? isActive,
  }) async {
    try {
      final now = DateTime.now();
      final updates = <String, dynamic>{
        'updated_at': now.toIso8601String(),
      };

      if (sku != null) updates['sku'] = sku;
      if (name != null) updates['name'] = name;
      if (option1Name != null) updates['option1_name'] = option1Name;
      if (option1Value != null) updates['option1_value'] = option1Value;
      if (option2Name != null) updates['option2_name'] = option2Name;
      if (option2Value != null) updates['option2_value'] = option2Value;
      if (option3Name != null) updates['option3_name'] = option3Name;
      if (option3Value != null) updates['option3_value'] = option3Value;
      if (price != null) updates['price'] = price;
      if (isActive != null) updates['is_active'] = isActive;

      await _supabase
          .from('product_variants')
          .update(updates)
          .eq('id', variantId);

      AppLogger.info('Updated variant: $variantId');

      // Fetch and return updated variant
      final variant = await getVariant(variantId);
      if (variant == null) {
        throw Exception('Variant not found after update');
      }

      return variant;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update variant $variantId', error, stackTrace);
      rethrow;
    }
  }

  /// Delete (soft delete) a product variant
  Future<void> deleteVariant(String variantId) async {
    try {
      await _supabase
          .from('product_variants')
          .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', variantId);

      AppLogger.info('Deleted variant: $variantId');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete variant $variantId', error, stackTrace);
      rethrow;
    }
  }

  /// Toggle product active status
  Future<Product> toggleProductActive(String productId, bool isActive) async {
    try {
      await _supabase
          .from('products')
          .update({
            'is_active': isActive,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', productId);

      AppLogger.info('Updated product $productId active status to $isActive');

      final product = await getProduct(productId);
      if (product == null) {
        throw Exception('Product not found after update');
      }

      return product;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to toggle product active status', error, stackTrace);
      rethrow;
    }
  }
}
