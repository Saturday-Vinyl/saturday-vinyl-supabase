idf_component_register(
    SRCS
        "h2_flasher.c"
    INCLUDE_DIRS "include"
    REQUIRES
        esp_event
        esp_partition
        esp_timer
        driver
        espressif__esp-serial-flasher
    PRIV_REQUIRES
        app_config
)
