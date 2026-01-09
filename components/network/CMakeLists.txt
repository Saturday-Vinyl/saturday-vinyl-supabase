# Network component - supports optional Thread Border Router
#
# Note: We always declare openthread/ieee802154/mdns as dependencies so they're
# available during CMake configuration. The actual code inclusion is controlled
# by CONFIG_OPENTHREAD_ENABLED at compile time via #ifdef guards in the source.

# All sources - Thread sources are compiled conditionally using #ifdef guards
set(SRCS
    "wifi_manager.c"
    "http_client.c"
    "thread_br.c"
    "coap_server.c"
)

# All dependencies - declared unconditionally
# The openthread component handles its own enable/disable via Kconfig
idf_component_register(
    SRCS ${SRCS}
    INCLUDE_DIRS "include"
    REQUIRES esp_wifi esp_netif esp_event nvs_flash esp_timer esp_http_client lwip
             openthread ieee802154 espressif__mdns
    PRIV_REQUIRES config esp-tls
)

# Fix linker order issue: libopenthread_br.a needs mdns and lwip symbols but is linked after them
# Force mdns and lwip to be linked with openthread_br using --start-group/--end-group
if(CONFIG_OPENTHREAD_BORDER_ROUTER)
    idf_component_get_property(mdns_lib espressif__mdns COMPONENT_LIB)
    idf_component_get_property(lwip_lib lwip COMPONENT_LIB)
    target_link_libraries(${COMPONENT_LIB} INTERFACE
        -Wl,--start-group
        $<TARGET_FILE:${mdns_lib}>
        $<TARGET_FILE:${lwip_lib}>
        ${IDF_PATH}/components/openthread/lib/${IDF_TARGET}/libopenthread_br.a
        -Wl,--end-group
    )
endif()
