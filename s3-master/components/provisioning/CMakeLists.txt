idf_component_register(
    SRCS
        "ble_prov.c"
        "serial_prov.c"
    INCLUDE_DIRS "include"
    EMBED_TXTFILES "service_manifest.json"
    REQUIRES
        nvs_flash
        bt
        driver
        esp_timer
        freertos
    PRIV_REQUIRES
        config
        cloud
        network
        rfid
        ui
        esp_driver_usb_serial_jtag
)
