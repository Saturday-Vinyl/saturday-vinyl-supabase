idf_component_register(
    SRCS
        "ota_manager.c"
    INCLUDE_DIRS "include"
    REQUIRES
        esp_https_ota
        esp_http_client
        esp_event
        esp_partition
        app_update
        nvs_flash
        json
    PRIV_REQUIRES
        app_config
        cloud
        network
        mbedtls
)
