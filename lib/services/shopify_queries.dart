/// Shopify GraphQL queries for the Saturday! Admin App
class ShopifyQueries {
  /// Query to fetch products with variants
  /// Supports pagination with cursor-based approach
  /// Shopify returns max 250 products at a time
  static const String productsQuery = r'''
    query GetProducts($first: Int!, $after: String) {
      products(first: $first, after: $after) {
        pageInfo {
          hasNextPage
          endCursor
        }
        edges {
          cursor
          node {
            id
            handle
            title
            description
            createdAt
            updatedAt
            variants(first: 100) {
              edges {
                node {
                  id
                  sku
                  title
                  price
                  selectedOptions {
                    name
                    value
                  }
                }
              }
            }
          }
        }
      }
    }
  ''';

  /// Query to fetch a single product by ID
  static const String productQuery = r'''
    query GetProduct($id: ID!) {
      product(id: $id) {
        id
        handle
        title
        description
        createdAt
        updatedAt
        variants(first: 100) {
          edges {
            node {
              id
              sku
              title
              price
              selectedOptions {
                name
                value
              }
            }
          }
        }
      }
    }
  ''';

  /// Query to fetch orders with customer info
  /// Note: Customer PII (email, firstName, lastName) requires Shopify Plus/Advanced plan
  /// This query works on all plans by making customer fields optional
  static const String ordersQuery = r'''
    query GetOrders($first: Int!, $after: String, $query: String) {
      orders(first: $first, after: $after, query: $query) {
        pageInfo {
          hasNextPage
          endCursor
        }
        edges {
          cursor
          node {
            id
            name
            createdAt
            displayFulfillmentStatus
            displayFinancialStatus
            tags
            currentTotalPriceSet {
              shopMoney {
                amount
                currencyCode
              }
            }
            lineItems(first: 50) {
              edges {
                node {
                  id
                  title
                  quantity
                  originalUnitPriceSet {
                    shopMoney {
                      amount
                      currencyCode
                    }
                  }
                  variant {
                    id
                    sku
                    title
                    selectedOptions {
                      name
                      value
                    }
                    product {
                      id
                      handle
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  ''';

  /// Query to fetch a single order by ID
  /// Note: Customer PII requires Shopify Plus/Advanced plan
  static const String orderQuery = r'''
    query GetOrder($id: ID!) {
      order(id: $id) {
        id
        name
        createdAt
        displayFulfillmentStatus
        lineItems(first: 50) {
          edges {
            node {
              id
              title
              quantity
              variant {
                id
                sku
                product {
                  id
                  handle
                }
              }
            }
          }
        }
      }
    }
  ''';
}
