idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES ui app_config rfid config esp_event network cloud provisioning h2_comm h2_flasher watchdog
    PRIV_REQUIRES nvs_flash
)
