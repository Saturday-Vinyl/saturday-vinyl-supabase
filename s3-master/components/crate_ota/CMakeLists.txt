idf_component_register(
    SRCS
        "crate_ota.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_http_client esp_event esp_timer freertos h2_comm cloud
    PRIV_REQUIRES mbedtls
)
