# H2 Communication Component for ESP32-S3 Master
# Handles UART protocol communication with ESP32-H2 Thread co-processor

idf_component_register(
    SRCS
        "h2_comm.c"
    INCLUDE_DIRS "include"
    REQUIRES driver esp_event esp_timer freertos shared
)
