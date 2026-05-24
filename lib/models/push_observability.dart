import 'package:equatable/equatable.dart';

/// Notification types the `retry-notification` edge function supports in v1.
///
/// Other types (device_offline, low_battery, etc.) require per-type payload
/// reconstruction which isn't built yet — the function returns 400 for those.
/// Kept here so the UI can hide the Retry button rather than wasting a
/// round-trip on a request the server will reject.
const Set<String> retryableNotificationTypes = {
  'now_playing',
};

/// Delivery status as recorded in `notification_delivery_log.status`.
enum PushDeliveryStatus {
  pending,
  sent,
  failed,
  delivered;

  String get value => name;

  static PushDeliveryStatus fromString(String? value) {
    switch (value) {
      case 'pending':
        return PushDeliveryStatus.pending;
      case 'sent':
        return PushDeliveryStatus.sent;
      case 'failed':
        return PushDeliveryStatus.failed;
      case 'delivered':
        return PushDeliveryStatus.delivered;
      default:
        return PushDeliveryStatus.pending;
    }
  }

  String get displayName {
    switch (this) {
      case PushDeliveryStatus.pending:
        return 'Pending';
      case PushDeliveryStatus.sent:
        return 'Sent';
      case PushDeliveryStatus.failed:
        return 'Failed';
      case PushDeliveryStatus.delivered:
        return 'Delivered';
    }
  }
}

/// One row of `admin_push_devices` — per-token health snapshot.
class PushDevice extends Equatable {
  final String tokenId;
  final String userId;
  final String? email;
  final String? displayName;
  final String platform; // 'ios' | 'android'
  final String deviceIdentifier;
  final String? appVersion;
  final bool isActive;
  final DateTime? lastUsedAt;
  final DateTime tokenCreatedAt;
  final DateTime tokenUpdatedAt;
  final int sent7d;
  final int failed7d;
  final DateTime? lastSentAt;
  final DateTime? lastFailedAt;

  const PushDevice({
    required this.tokenId,
    required this.userId,
    this.email,
    this.displayName,
    required this.platform,
    required this.deviceIdentifier,
    this.appVersion,
    required this.isActive,
    this.lastUsedAt,
    required this.tokenCreatedAt,
    required this.tokenUpdatedAt,
    required this.sent7d,
    required this.failed7d,
    this.lastSentAt,
    this.lastFailedAt,
  });

  /// A token with recent failures and no recent sends is likely dead.
  bool get likelyDead => failed7d > 0 && sent7d == 0;

  factory PushDevice.fromJson(Map<String, dynamic> json) {
    return PushDevice(
      tokenId: json['token_id'] as String,
      userId: json['user_id'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      platform: json['platform'] as String,
      deviceIdentifier: json['device_identifier'] as String,
      appVersion: json['app_version'] as String?,
      isActive: json['is_active'] as bool,
      lastUsedAt: _parseDate(json['last_used_at']),
      tokenCreatedAt: _parseDate(json['token_created_at'])!,
      tokenUpdatedAt: _parseDate(json['token_updated_at'])!,
      sent7d: (json['sent_7d'] as num?)?.toInt() ?? 0,
      failed7d: (json['failed_7d'] as num?)?.toInt() ?? 0,
      lastSentAt: _parseDate(json['last_sent_at']),
      lastFailedAt: _parseDate(json['last_failed_at']),
    );
  }

  @override
  List<Object?> get props => [
        tokenId,
        userId,
        email,
        displayName,
        platform,
        deviceIdentifier,
        appVersion,
        isActive,
        lastUsedAt,
        tokenCreatedAt,
        tokenUpdatedAt,
        sent7d,
        failed7d,
        lastSentAt,
        lastFailedAt,
      ];
}

/// One row of `admin_push_deliveries` — a single delivery attempt.
class PushDelivery extends Equatable {
  final String id;
  final DateTime createdAt;
  final String userId;
  final String? email;
  final String? displayName;
  final String notificationType;
  final String? sourceId;
  final String? tokenId;
  final String? platform;
  final String? deviceIdentifier;
  final PushDeliveryStatus status;
  final String? errorMessage;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final String? sentByUserId;

  const PushDelivery({
    required this.id,
    required this.createdAt,
    required this.userId,
    this.email,
    this.displayName,
    required this.notificationType,
    this.sourceId,
    this.tokenId,
    this.platform,
    this.deviceIdentifier,
    required this.status,
    this.errorMessage,
    this.sentAt,
    this.deliveredAt,
    this.sentByUserId,
  });

  factory PushDelivery.fromJson(Map<String, dynamic> json) {
    return PushDelivery(
      id: json['id'] as String,
      createdAt: _parseDate(json['created_at'])!,
      userId: json['user_id'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      notificationType: json['notification_type'] as String,
      sourceId: json['source_id'] as String?,
      tokenId: json['token_id'] as String?,
      platform: json['platform'] as String?,
      deviceIdentifier: json['device_identifier'] as String?,
      status: PushDeliveryStatus.fromString(json['status'] as String?),
      errorMessage: json['error_message'] as String?,
      sentAt: _parseDate(json['sent_at']),
      deliveredAt: _parseDate(json['delivered_at']),
      sentByUserId: json['sent_by_user_id'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        createdAt,
        userId,
        email,
        displayName,
        notificationType,
        sourceId,
        tokenId,
        platform,
        deviceIdentifier,
        status,
        errorMessage,
        sentAt,
        deliveredAt,
        sentByUserId,
      ];
}

/// One row of `admin_push_health_by_type` — hourly health bucket.
class PushHealthBucket extends Equatable {
  final String notificationType;
  final DateTime bucketHour;
  final int sentCount;
  final int failedCount;
  final int totalCount;

  const PushHealthBucket({
    required this.notificationType,
    required this.bucketHour,
    required this.sentCount,
    required this.failedCount,
    required this.totalCount,
  });

  double get failureRate => totalCount == 0 ? 0 : failedCount / totalCount;

  factory PushHealthBucket.fromJson(Map<String, dynamic> json) {
    return PushHealthBucket(
      notificationType: json['notification_type'] as String,
      bucketHour: _parseDate(json['bucket_hour'])!,
      sentCount: (json['sent_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props =>
      [notificationType, bucketHour, sentCount, failedCount, totalCount];
}

/// One row of `admin_push_error_patterns` — bucketed failure category.
class PushErrorPattern extends Equatable {
  final String notificationType;
  final String errorCategory;
  final int n;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int affectedTokens;
  final int affectedUsers;

  const PushErrorPattern({
    required this.notificationType,
    required this.errorCategory,
    required this.n,
    required this.firstSeen,
    required this.lastSeen,
    required this.affectedTokens,
    required this.affectedUsers,
  });

  /// Categories that indicate a server-wide issue rather than per-token attrition.
  bool get isServerWide =>
      errorCategory == 'apns_env_mismatch' ||
      errorCategory == 'fcm_auth_error' ||
      errorCategory == 'unauthenticated';

  factory PushErrorPattern.fromJson(Map<String, dynamic> json) {
    return PushErrorPattern(
      notificationType: json['notification_type'] as String,
      errorCategory: json['error_category'] as String,
      n: (json['n'] as num?)?.toInt() ?? 0,
      firstSeen: _parseDate(json['first_seen'])!,
      lastSeen: _parseDate(json['last_seen'])!,
      affectedTokens: (json['affected_tokens'] as num?)?.toInt() ?? 0,
      affectedUsers: (json['affected_users'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        notificationType,
        errorCategory,
        n,
        firstSeen,
        lastSeen,
        affectedTokens,
        affectedUsers,
      ];
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.parse(value as String).toLocal();
}
