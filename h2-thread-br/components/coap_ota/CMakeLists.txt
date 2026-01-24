idf_component_register(
    SRCS
        "coap_ota.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_event esp_timer freertos openthread s3_comm
    PRIV_REQUIRES esp_openthread
)
