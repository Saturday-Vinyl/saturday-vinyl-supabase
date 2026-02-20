# CoAP Server component for ESP32-H2
# Handles crate communication over Thread mesh

idf_component_register(
    SRCS
        "coap_server.c"
        "coap_cmd_client.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_event esp_timer openthread cbor
    PRIV_REQUIRES thread s3_comm
)
