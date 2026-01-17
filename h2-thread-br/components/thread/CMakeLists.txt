# Thread Border Router component for ESP32-H2
# Dedicated Thread co-processor firmware
#
# Note: For ESP32-H2, OpenThread BR library is built from source as part of
# the openthread component. The prebuilt libopenthread_br.a doesn't exist for H2.

idf_component_register(
    SRCS
        "thread_br.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_netif esp_event nvs_flash esp_timer lwip openthread ieee802154 espressif__mdns
    PRIV_REQUIRES esp-tls
)
