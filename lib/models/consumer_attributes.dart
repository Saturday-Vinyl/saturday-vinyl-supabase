import 'package:equatable/equatable.dart';

/// WiFi configuration for consumer provisioning.
class WifiConfig extends Equatable {
  /// Network SSID.
  final String ssid;

  /// Network password (stored encrypted in database).
  final String? password;

  const WifiConfig({
    required this.ssid,
    this.password,
  });

  factory WifiConfig.fromJson(Map<String, dynamic> json) {
    return WifiConfig(
      ssid: json['ssid'] as String,
      password: json['password'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ssid': ssid,
      if (password != null) 'password': password,
    };
  }

  @override
  List<Object?> get props => [ssid, password];
}

/// Thread network configuration for consumer provisioning.
class ThreadConfig extends Equatable {
  /// Thread network name.
  final String networkName;

  /// Thread network key (operational dataset).
  final String? networkKey;

  /// Full Thread dataset (hex-encoded).
  final String? dataset;

  const ThreadConfig({
    required this.networkName,
    this.networkKey,
    this.dataset,
  });

  factory ThreadConfig.fromJson(Map<String, dynamic> json) {
    return ThreadConfig(
      networkName: json['network_name'] as String,
      networkKey: json['network_key'] as String?,
      dataset: json['dataset'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'network_name': networkName,
      if (networkKey != null) 'network_key': networkKey,
      if (dataset != null) 'dataset': dataset,
    };
  }

  @override
  List<Object?> get props => [networkName, networkKey, dataset];
}

/// Consumer provisioning attributes (DEPRECATED).
///
/// Use [ProvisionData] instead for the new flattened schema.
@Deprecated('Use ProvisionData instead')
class ConsumerAttributes extends Equatable {
  /// WiFi configuration (for hubs).
  final WifiConfig? wifi;

  /// Thread configuration (for crates).
  final ThreadConfig? thread;

  const ConsumerAttributes({
    this.wifi,
    this.thread,
  });

  /// Whether WiFi is configured.
  bool get hasWifi => wifi != null;

  /// Whether Thread is configured.
  bool get hasThread => thread != null;

  factory ConsumerAttributes.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ConsumerAttributes();
    return ConsumerAttributes(
      wifi: json['wifi'] != null
          ? WifiConfig.fromJson(json['wifi'] as Map<String, dynamic>)
          : null,
      thread: json['thread'] != null
          ? ThreadConfig.fromJson(json['thread'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (wifi != null) {
      json['wifi'] = wifi!.toJson();
    }
    if (thread != null) {
      json['thread'] = thread!.toJson();
    }
    return json;
  }

  ConsumerAttributes copyWith({
    WifiConfig? wifi,
    ThreadConfig? thread,
  }) {
    return ConsumerAttributes(
      wifi: wifi ?? this.wifi,
      thread: thread ?? this.thread,
    );
  }

  @override
  List<Object?> get props => [wifi, thread];
}

/// Consumer provisioning data.
///
/// Stored in the devices.provision_data column after
/// the consumer completes BLE provisioning.
///
/// This uses a flattened JSONB structure (not nested). Per the Device Command
/// Protocol, both consumer_input (sent to device) and consumer_output (returned
/// by device) are merged at the top level.
class ProvisionData extends Equatable {
  /// WiFi network SSID (for hubs).
  final String? wifiSsid;

  /// Thread network name (for crates).
  final String? threadNetworkName;

  /// Thread dataset hex string (for crates).
  final String? threadDataset;

  /// Additional data returned from the device after provisioning (consumer_output).
  /// Merged at the top level of provision_data per the Device Command Protocol.
  final Map<String, dynamic>? consumerOutput;

  const ProvisionData({
    this.wifiSsid,
    this.threadNetworkName,
    this.threadDataset,
    this.consumerOutput,
  });

  /// Creates provision data for a hub with WiFi credentials.
  const ProvisionData.wifi({
    required String ssid,
    this.consumerOutput,
  })  : wifiSsid = ssid,
        threadNetworkName = null,
        threadDataset = null;

  /// Creates provision data for a crate with Thread credentials.
  const ProvisionData.thread({
    required String dataset,
    String? networkName,
    this.consumerOutput,
  })  : wifiSsid = null,
        threadNetworkName = networkName,
        threadDataset = dataset;

  /// Whether WiFi is configured.
  bool get hasWifi => wifiSsid != null;

  /// Whether Thread is configured.
  bool get hasThread => threadDataset != null;

  factory ProvisionData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ProvisionData();
    return ProvisionData(
      wifiSsid: json['wifi_ssid'] as String?,
      threadNetworkName: json['thread_network_name'] as String?,
      threadDataset: json['thread_dataset'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (wifiSsid != null) {
      json['wifi_ssid'] = wifiSsid;
    }
    if (threadNetworkName != null) {
      json['thread_network_name'] = threadNetworkName;
    }
    if (threadDataset != null) {
      json['thread_dataset'] = threadDataset;
    }
    if (consumerOutput != null) {
      json.addAll(consumerOutput!);
    }
    return json;
  }

  ProvisionData copyWith({
    String? wifiSsid,
    String? threadNetworkName,
    String? threadDataset,
    Map<String, dynamic>? consumerOutput,
  }) {
    return ProvisionData(
      wifiSsid: wifiSsid ?? this.wifiSsid,
      threadNetworkName: threadNetworkName ?? this.threadNetworkName,
      threadDataset: threadDataset ?? this.threadDataset,
      consumerOutput: consumerOutput ?? this.consumerOutput,
    );
  }

  @override
  List<Object?> get props =>
      [wifiSsid, threadNetworkName, threadDataset, consumerOutput];
}
