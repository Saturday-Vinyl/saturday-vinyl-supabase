idf_component_register(
    SRCS
        "wifi_manager.c"
        "http_client.c"
        "thread_br.c"
        "coap_server.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_wifi esp_netif esp_event nvs_flash esp_timer esp_http_client
    PRIV_REQUIRES config esp-tls
)
