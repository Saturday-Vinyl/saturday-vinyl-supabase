# CoAP Server component for ESP32-H2
# Handles crate communication over Thread mesh

idf_component_register(
    SRCS
        "coap_server.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_event esp_timer openthread
    PRIV_REQUIRES thread
)
