idf_component_register(
    SRCS
        "supabase_client.c"
        "event_reporter.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_http_client esp_event esp_timer nvs_flash
    PRIV_REQUIRES rfid network mbedtls config
    EMBED_TXTFILES supabase_ca.pem
)
