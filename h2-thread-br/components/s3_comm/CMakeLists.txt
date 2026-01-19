# S3 Communication component for ESP32-H2
# Handles UART protocol communication with ESP32-S3 master

idf_component_register(
    SRCS
        "s3_comm.c"
    INCLUDE_DIRS "include"
    REQUIRES driver esp_event esp_timer nvs_flash freertos shared
    PRIV_REQUIRES thread
)
