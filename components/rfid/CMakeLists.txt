idf_component_register(
    SRCS
        "yrm100_driver.c"
        "rfid_protocol.c"
        "now_playing.c"
    INCLUDE_DIRS "include"
    REQUIRES driver esp_event esp_timer
)
