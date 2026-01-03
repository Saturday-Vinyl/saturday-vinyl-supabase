idf_component_register(
    SRCS
        "ble_prov.c"
        "serial_prov.c"
    INCLUDE_DIRS "include"
    REQUIRES nvs_flash bt
)
