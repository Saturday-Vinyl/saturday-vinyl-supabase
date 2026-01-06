idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES ui rfid config network cloud provisioning nvs_flash esp_system esp_event esp_driver_usb_serial_jtag
)
