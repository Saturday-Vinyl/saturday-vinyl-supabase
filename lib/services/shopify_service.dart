import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:saturday_app/config/env_config.dart';
import 'package:saturday_app/services/shopify_queries.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Service for interacting with Shopify GraphQL Admin API
class ShopifyService {
  static final ShopifyService _instance = ShopifyService._internal();
  factory ShopifyService() => _instance;
  ShopifyService._internal();

  GraphQLClient? _client;

  /// Initialize the Shopify GraphQL client
  void initialize() {
    // Ensure the store URL has https:// protocol
    String storeUrl = EnvConfig.shopifyStoreUrl;
    if (!storeUrl.startsWith('http://') && !storeUrl.startsWith('https://')) {
      storeUrl = 'https://$storeUrl';
    }

    final graphqlEndpoint = '$storeUrl/admin/api/2024-10/graphql.json';

    AppLogger.info('Initializing Shopify client with endpoint: $graphqlEndpoint');

    final httpLink = HttpLink(
      graphqlEndpoint,
      defaultHeaders: {
        'X-Shopify-Access-Token': EnvConfig.shopifyAccessToken,
        'Content-Type': 'application/json',
      },
    );

    final link = httpLink;

    _client = GraphQLClient(
      link: link,
      cache: GraphQLCache(),
    );

    AppLogger.info('Shopify service initialized');
  }

  /// Get the GraphQL client instance
  GraphQLClient get client {
    if (_client == null) {
      throw Exception('ShopifyService not initialized. Call initialize() first.');
    }
    return _client!;
  }

  /// Fetch products with pagination
  /// Returns list of raw product data from Shopify
  /// Handles pagination automatically to fetch all products
  Future<List<Map<String, dynamic>>> fetchProducts({
    int pageSize = 250,
    int maxRetries = 3,
  }) async {
    final allProducts = <Map<String, dynamic>>[];
    String? cursor;
    bool hasNextPage = true;
    int retryCount = 0;

    AppLogger.info('Starting Shopify product fetch (pageSize: $pageSize)');

    while (hasNextPage) {
      try {
        final result = await _executeQueryWithRetry(
          ShopifyQueries.productsQuery,
          variables: {
            'first': pageSize,
            if (cursor != null) 'after': cursor,
          },
          maxRetries: maxRetries,
        );

        if (result.hasException) {
          throw Exception('GraphQL Error: ${result.exception.toString()}');
        }

        final products = result.data?['products'];
        if (products == null) {
          throw Exception('No products data in response');
        }

        final edges = products['edges'] as List<dynamic>?;
        if (edges != null) {
          for (final edge in edges) {
            final node = edge['node'] as Map<String, dynamic>;
            allProducts.add(node);
          }
        }

        // Check pagination
        final pageInfo = products['pageInfo'] as Map<String, dynamic>?;
        hasNextPage = pageInfo?['hasNextPage'] as bool? ?? false;
        cursor = pageInfo?['endCursor'] as String?;

        AppLogger.info('Fetched ${edges?.length ?? 0} products (total: ${allProducts.length})');

        // Rate limiting: wait a bit between requests
        if (hasNextPage) {
          await Future.delayed(const Duration(milliseconds: 500));
        }

        retryCount = 0; // Reset retry count on success
      } catch (error, stackTrace) {
        if (retryCount < maxRetries) {
          retryCount++;
          final delay = Duration(seconds: retryCount * 2); // Exponential backoff
          AppLogger.warning('Retry $retryCount/$maxRetries after error: $error. Waiting ${delay.inSeconds}s');
          await Future.delayed(delay);
        } else {
          AppLogger.error('Failed to fetch products after $maxRetries retries', error, stackTrace);
          rethrow;
        }
      }
    }

    AppLogger.info('Completed Shopify product fetch. Total products: ${allProducts.length}');
    return allProducts;
  }

  /// Fetch a single product by Shopify product ID
  Future<Map<String, dynamic>?> fetchProduct(String shopifyProductId) async {
    try {
      AppLogger.info('Fetching product: $shopifyProductId');

      final result = await _executeQueryWithRetry(
        ShopifyQueries.productQuery,
        variables: {'id': shopifyProductId},
      );

      if (result.hasException) {
        throw Exception('GraphQL Error: ${result.exception.toString()}');
      }

      final product = result.data?['product'] as Map<String, dynamic>?;
      AppLogger.info('Product fetched successfully');
      return product;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch product $shopifyProductId', error, stackTrace);
      rethrow;
    }
  }

  /// Fetch orders with pagination (basic implementation, will expand later)
  Future<List<Map<String, dynamic>>> fetchOrders({
    int pageSize = 250,
    String? queryFilter,
    int maxRetries = 3,
  }) async {
    final allOrders = <Map<String, dynamic>>[];
    String? cursor;
    bool hasNextPage = true;

    AppLogger.info('Starting Shopify order fetch');

    while (hasNextPage) {
      try {
        final result = await _executeQueryWithRetry(
          ShopifyQueries.ordersQuery,
          variables: {
            'first': pageSize,
            if (cursor != null) 'after': cursor,
            if (queryFilter != null) 'query': queryFilter,
          },
          maxRetries: maxRetries,
        );

        if (result.hasException) {
          throw Exception('GraphQL Error: ${result.exception.toString()}');
        }

        final orders = result.data?['orders'];
        if (orders == null) {
          throw Exception('No orders data in response');
        }

        final edges = orders['edges'] as List<dynamic>?;
        if (edges != null) {
          for (final edge in edges) {
            final node = edge['node'] as Map<String, dynamic>;
            allOrders.add(node);
          }
        }

        // Check pagination
        final pageInfo = orders['pageInfo'] as Map<String, dynamic>?;
        hasNextPage = pageInfo?['hasNextPage'] as bool? ?? false;
        cursor = pageInfo?['endCursor'] as String?;

        AppLogger.info('Fetched ${edges?.length ?? 0} orders (total: ${allOrders.length})');

        // Rate limiting
        if (hasNextPage) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (error, stackTrace) {
        AppLogger.error('Failed to fetch orders', error, stackTrace);
        rethrow;
      }
    }

    AppLogger.info('Completed Shopify order fetch. Total orders: ${allOrders.length}');
    return allOrders;
  }

  /// Execute a GraphQL query with retry logic and exponential backoff
  Future<QueryResult> _executeQueryWithRetry(
    String query, {
    Map<String, dynamic>? variables,
    int maxRetries = 3,
  }) async {
    int retryCount = 0;

    while (true) {
      try {
        final options = QueryOptions(
          document: gql(query),
          variables: variables ?? {},
          fetchPolicy: FetchPolicy.networkOnly,
        );

        final result = await client.query(options);

        // Check for GraphQL errors in the response
        if (result.hasException) {
          final exception = result.exception;
          if (exception != null) {
            // Log detailed error information
            AppLogger.error(
              'GraphQL query failed',
              exception,
              StackTrace.current,
            );

            // If it's a server exception, log more details
            if (exception.linkException != null) {
              AppLogger.error(
                'Link exception details: ${exception.linkException.runtimeType}',
                exception.linkException,
                StackTrace.current,
              );
            }
          }
        }

        return result;
      } catch (error) {
        AppLogger.error('Query execution error', error, StackTrace.current);
        if (retryCount < maxRetries) {
          retryCount++;
          final delay = Duration(seconds: retryCount * 2); // Exponential backoff
          AppLogger.warning('GraphQL query retry $retryCount/$maxRetries. Waiting ${delay.inSeconds}s');
          await Future.delayed(delay);
        } else {
          rethrow;
        }
      }
    }
  }
}
