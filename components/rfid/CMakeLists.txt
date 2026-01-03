idf_component_register(
    SRCS
        "yrm100_driver.c"
        "rfid_protocol.c"
        "now_playing.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_driver_uart esp_driver_gpio esp_event esp_timer
)
