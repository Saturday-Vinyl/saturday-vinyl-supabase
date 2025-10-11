import 'package:equatable/equatable.dart';

/// Represents a customer from Shopify
/// This is a minimal model for now - will be expanded in Prompt 27
class Customer extends Equatable {
  final String id;
  final String shopifyCustomerId;
  final String email;
  final String? firstName;
  final String? lastName;
  final DateTime createdAt;

  const Customer({
    required this.id,
    required this.shopifyCustomerId,
    required this.email,
    this.firstName,
    this.lastName,
    required this.createdAt,
  });

  /// Get full name
  String get fullName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (firstName != null) {
      return firstName!;
    } else if (lastName != null) {
      return lastName!;
    } else {
      return email;
    }
  }

  /// Create from JSON
  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      shopifyCustomerId: json['shopify_customer_id'] as String,
      email: json['email'] as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shopify_customer_id': shopifyCustomerId,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Copy with method
  Customer copyWith({
    String? id,
    String? shopifyCustomerId,
    String? email,
    String? firstName,
    String? lastName,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      shopifyCustomerId: shopifyCustomerId ?? this.shopifyCustomerId,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        shopifyCustomerId,
        email,
        firstName,
        lastName,
        createdAt,
      ];
}
