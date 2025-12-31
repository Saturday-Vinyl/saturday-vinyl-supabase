idf_component_register(
    SRCS
        "led_manager.c"
        "button_handler.c"
    INCLUDE_DIRS "include"
    REQUIRES driver esp_timer
)
