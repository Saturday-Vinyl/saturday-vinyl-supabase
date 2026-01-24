idf_component_register(
    SRCS
        "supabase_client.c"
        "event_reporter.c"
        "realtime_client.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_http_client esp_event esp_timer nvs_flash app_config json ota crate_ota
    PRIV_REQUIRES rfid network mbedtls esp_websocket_client
    EMBED_TXTFILES supabase_ca.pem
)
