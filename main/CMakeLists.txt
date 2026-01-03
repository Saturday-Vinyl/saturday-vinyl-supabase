idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES ui rfid config nvs_flash esp_system esp_event
)
