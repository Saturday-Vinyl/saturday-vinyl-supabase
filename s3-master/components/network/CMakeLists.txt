# Network component for ESP32-S3 Master
# WiFi and HTTP client only - no Thread (handled by H2)

idf_component_register(
    SRCS
        "wifi_manager.c"
        "http_client.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_wifi esp_netif esp_event nvs_flash esp_timer esp_http_client lwip
    PRIV_REQUIRES config esp-tls
)
