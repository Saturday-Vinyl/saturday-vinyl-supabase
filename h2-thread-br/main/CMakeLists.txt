idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES esp_event esp_netif nvs_flash freertos
    PRIV_REQUIRES s3_comm thread coap coap_ota shared
)
