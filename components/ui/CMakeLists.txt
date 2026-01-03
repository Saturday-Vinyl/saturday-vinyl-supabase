idf_component_register(
    SRCS
        "led_manager.c"
        "button_handler.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_driver_gpio esp_timer led_strip
)
