/**
 * @file now_playing.c
 * @brief Now Playing detection state machine implementation
 *
 * Implements debounced "Now Playing" detection with a 4-state state machine:
 *
 * State Transitions:
 *
 *   IDLE ──[tag detected]──> TAG_CONFIRMING ──[debounce expires]──> TAG_PRESENT
 *     ^                            |                                     |
 *     |                            v (tag lost before debounce)          |
 *     |                      [return to IDLE]                            |
 *     |                                                                  v
 *     └──────[debounce expires]──── TAG_REMOVING <──[tag lost]───────────┘
 *                                        |
 *                                        v (tag returns before debounce)
 *                                  [return to TAG_PRESENT]
 *
 * Events are posted to the ESP-IDF default event loop when:
 * - TAG_PLACED: Tag transitions from IDLE → TAG_PRESENT
 * - TAG_REMOVED: Tag transitions from TAG_PRESENT → IDLE
 */

#include "now_playing.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_event.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include <string.h>

static const char *TAG = "NOW_PLAYING";

/*******************************************************************************
 * Event Base Definition
 ******************************************************************************/

ESP_EVENT_DEFINE_BASE(NOW_PLAYING_EVENTS);

/*******************************************************************************
 * Internal State
 ******************************************************************************/

typedef struct {
    /* State machine */
    now_playing_state_t state;
    now_playing_config_t config;

    /* Current/pending tag */
    uint8_t current_epc[RFID_EPC_MAX_LEN];
    uint8_t current_epc_len;
    int8_t current_rssi;
    int64_t tag_placed_time;        /* When tag was confirmed present */
    int64_t state_enter_time;       /* When we entered current confirming/removing state */

    /* Pending tag during confirmation */
    uint8_t pending_epc[RFID_EPC_MAX_LEN];
    uint8_t pending_epc_len;
    int8_t pending_rssi;

    /* Statistics */
    uint32_t total_placed_events;
    uint32_t total_removed_events;

    /* Synchronization */
    SemaphoreHandle_t mutex;

    /* Initialization flag */
    bool initialized;
} now_playing_state_internal_t;

static now_playing_state_internal_t s_np = {0};

/*******************************************************************************
 * Helper Functions
 ******************************************************************************/

static int64_t get_time_us(void)
{
    return esp_timer_get_time();
}

static int64_t get_time_ms(void)
{
    return esp_timer_get_time() / 1000;
}

static bool epc_matches(const uint8_t *epc1, uint8_t len1,
                        const uint8_t *epc2, uint8_t len2)
{
    if (len1 != len2) return false;
    return memcmp(epc1, epc2, len1) == 0;
}

static void copy_tag_data(uint8_t *dest_epc, uint8_t *dest_len, int8_t *dest_rssi,
                          const uint8_t *src_epc, uint8_t src_len, int8_t src_rssi)
{
    memcpy(dest_epc, src_epc, src_len);
    *dest_len = src_len;
    *dest_rssi = src_rssi;
}

static void clear_tag_data(uint8_t *epc, uint8_t *len, int8_t *rssi)
{
    memset(epc, 0, RFID_EPC_MAX_LEN);
    *len = 0;
    *rssi = 0;
}

static void post_event(now_playing_event_type_t type,
                       const uint8_t *epc, uint8_t epc_len, int8_t rssi,
                       uint32_t duration_ms)
{
    now_playing_event_t event = {
        .type = type,
        .epc_len = epc_len,
        .rssi = rssi,
        .timestamp = get_time_us(),
        .duration_ms = duration_ms,
    };
    memcpy(event.epc, epc, epc_len);

    esp_err_t err = esp_event_post(NOW_PLAYING_EVENTS, type, &event,
                                   sizeof(event), 0);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "Failed to post event: %s", esp_err_to_name(err));
    }
}

static void log_epc(const char *prefix, const uint8_t *epc, uint8_t len)
{
    char epc_str[25];
    rfid_epc_to_hex_string(epc, len, epc_str, sizeof(epc_str));
    ESP_LOGI(TAG, "%s: %s", prefix, epc_str);
}

/*******************************************************************************
 * State Machine Logic
 ******************************************************************************/

/**
 * @brief Handle tag detection in IDLE state
 *
 * Start confirming the new tag.
 */
static void handle_idle_tag_detected(const rfid_tag_t *tag)
{
    ESP_LOGD(TAG, "IDLE: Tag detected, starting confirmation");

    /* Store pending tag and start confirmation timer */
    copy_tag_data(s_np.pending_epc, &s_np.pending_epc_len, &s_np.pending_rssi,
                  tag->epc, tag->epc_len, rfid_rssi_to_dbm(tag->rssi));

    s_np.state_enter_time = get_time_ms();
    s_np.state = NOW_PLAYING_STATE_TAG_CONFIRMING;

    ESP_LOGD(TAG, "State: IDLE -> TAG_CONFIRMING");
}

/**
 * @brief Handle tag detection in TAG_CONFIRMING state
 *
 * If same tag still present and debounce expired, confirm it.
 * If different tag, restart confirmation.
 */
static void handle_confirming_tag_detected(const rfid_tag_t *tag)
{
    int8_t rssi_dbm = rfid_rssi_to_dbm(tag->rssi);

    if (epc_matches(tag->epc, tag->epc_len, s_np.pending_epc, s_np.pending_epc_len)) {
        /* Same tag still present - check if debounce expired */
        int64_t elapsed = get_time_ms() - s_np.state_enter_time;

        if (elapsed >= s_np.config.debounce_present_ms) {
            /* Debounce complete - tag is confirmed present */
            ESP_LOGI(TAG, "Tag confirmed present after %lld ms", elapsed);
            log_epc("Now Playing", s_np.pending_epc, s_np.pending_epc_len);

            /* Move pending to current */
            copy_tag_data(s_np.current_epc, &s_np.current_epc_len, &s_np.current_rssi,
                          s_np.pending_epc, s_np.pending_epc_len, s_np.pending_rssi);
            s_np.tag_placed_time = get_time_us();

            /* Clear pending */
            clear_tag_data(s_np.pending_epc, &s_np.pending_epc_len, &s_np.pending_rssi);

            /* Transition to TAG_PRESENT */
            s_np.state = NOW_PLAYING_STATE_TAG_PRESENT;

            /* Post TAG_PLACED event */
            post_event(NOW_PLAYING_EVENT_TAG_PLACED,
                       s_np.current_epc, s_np.current_epc_len,
                       s_np.current_rssi, 0);
            s_np.total_placed_events++;

            ESP_LOGD(TAG, "State: TAG_CONFIRMING -> TAG_PRESENT");
        } else {
            /* Still waiting for debounce - update RSSI */
            s_np.pending_rssi = rssi_dbm;
            ESP_LOGV(TAG, "TAG_CONFIRMING: waiting (%lld/%d ms)",
                     elapsed, s_np.config.debounce_present_ms);
        }
    } else {
        /* Different tag - restart confirmation */
        ESP_LOGD(TAG, "TAG_CONFIRMING: Different tag detected, restarting");
        copy_tag_data(s_np.pending_epc, &s_np.pending_epc_len, &s_np.pending_rssi,
                      tag->epc, tag->epc_len, rssi_dbm);
        s_np.state_enter_time = get_time_ms();
    }
}

/**
 * @brief Handle tag detection in TAG_PRESENT state
 *
 * If same tag, just update RSSI.
 * If different tag, this is unusual - log warning but keep current.
 */
static void handle_present_tag_detected(const rfid_tag_t *tag)
{
    if (epc_matches(tag->epc, tag->epc_len, s_np.current_epc, s_np.current_epc_len)) {
        /* Same tag - just update RSSI */
        s_np.current_rssi = rfid_rssi_to_dbm(tag->rssi);
        ESP_LOGV(TAG, "TAG_PRESENT: Same tag, RSSI=%d", s_np.current_rssi);
    } else {
        /* Different tag detected while one is playing */
        /* This shouldn't happen often - just log it */
        ESP_LOGW(TAG, "TAG_PRESENT: Different tag detected (ignoring)");
    }
}

/**
 * @brief Handle tag detection in TAG_REMOVING state
 *
 * If same tag returns, cancel removal and return to TAG_PRESENT.
 * If different tag, this is unusual - log warning.
 */
static void handle_removing_tag_detected(const rfid_tag_t *tag)
{
    if (epc_matches(tag->epc, tag->epc_len, s_np.current_epc, s_np.current_epc_len)) {
        /* Same tag came back - cancel removal */
        ESP_LOGD(TAG, "TAG_REMOVING: Tag returned, canceling removal");
        s_np.current_rssi = rfid_rssi_to_dbm(tag->rssi);
        s_np.state = NOW_PLAYING_STATE_TAG_PRESENT;

        ESP_LOGD(TAG, "State: TAG_REMOVING -> TAG_PRESENT");
    } else {
        /* Different tag appeared during removal wait */
        ESP_LOGW(TAG, "TAG_REMOVING: Different tag detected (completing removal first)");
        /* Let the removal complete on the next poll */
    }
}

/**
 * @brief Handle poll complete with no tag in IDLE state
 *
 * Nothing to do - already idle.
 */
static void handle_idle_no_tag(void)
{
    /* Nothing to do */
}

/**
 * @brief Handle poll complete with no tag in TAG_CONFIRMING state
 *
 * Tag disappeared before confirmation - return to IDLE.
 */
static void handle_confirming_no_tag(void)
{
    ESP_LOGD(TAG, "TAG_CONFIRMING: Tag lost before confirmation");

    clear_tag_data(s_np.pending_epc, &s_np.pending_epc_len, &s_np.pending_rssi);
    s_np.state = NOW_PLAYING_STATE_IDLE;

    ESP_LOGD(TAG, "State: TAG_CONFIRMING -> IDLE");
}

/**
 * @brief Handle poll complete with no tag in TAG_PRESENT state
 *
 * Tag disappeared - start removal confirmation.
 */
static void handle_present_no_tag(void)
{
    ESP_LOGD(TAG, "TAG_PRESENT: Tag lost, starting removal confirmation");

    s_np.state_enter_time = get_time_ms();
    s_np.state = NOW_PLAYING_STATE_TAG_REMOVING;

    ESP_LOGD(TAG, "State: TAG_PRESENT -> TAG_REMOVING");
}

/**
 * @brief Handle poll complete with no tag in TAG_REMOVING state
 *
 * Check if debounce expired - if so, confirm removal.
 */
static void handle_removing_no_tag(void)
{
    int64_t elapsed = get_time_ms() - s_np.state_enter_time;

    if (elapsed >= s_np.config.debounce_absent_ms) {
        /* Debounce complete - tag is confirmed removed */
        uint32_t play_duration = (uint32_t)((get_time_us() - s_np.tag_placed_time) / 1000);

        ESP_LOGI(TAG, "Tag confirmed removed after %lld ms", elapsed);
        log_epc("Stopped Playing", s_np.current_epc, s_np.current_epc_len);
        ESP_LOGI(TAG, "Play duration: %lu ms", (unsigned long)play_duration);

        /* Post TAG_REMOVED event with duration */
        post_event(NOW_PLAYING_EVENT_TAG_REMOVED,
                   s_np.current_epc, s_np.current_epc_len,
                   s_np.current_rssi, play_duration);
        s_np.total_removed_events++;

        /* Clear current tag and return to IDLE */
        clear_tag_data(s_np.current_epc, &s_np.current_epc_len, &s_np.current_rssi);
        s_np.tag_placed_time = 0;
        s_np.state = NOW_PLAYING_STATE_IDLE;

        ESP_LOGD(TAG, "State: TAG_REMOVING -> IDLE");
    } else {
        ESP_LOGV(TAG, "TAG_REMOVING: waiting (%lld/%d ms)",
                 elapsed, s_np.config.debounce_absent_ms);
    }
}

/*******************************************************************************
 * Public API Implementation
 ******************************************************************************/

esp_err_t now_playing_init(const now_playing_config_t *config)
{
    if (s_np.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_ERR_INVALID_STATE;
    }

    /* Create mutex */
    s_np.mutex = xSemaphoreCreateMutex();
    if (s_np.mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Set configuration */
    if (config != NULL) {
        s_np.config = *config;
    } else {
        s_np.config = (now_playing_config_t)NOW_PLAYING_CONFIG_DEFAULT();
    }

    /* Initialize state */
    s_np.state = NOW_PLAYING_STATE_IDLE;
    clear_tag_data(s_np.current_epc, &s_np.current_epc_len, &s_np.current_rssi);
    clear_tag_data(s_np.pending_epc, &s_np.pending_epc_len, &s_np.pending_rssi);
    s_np.tag_placed_time = 0;
    s_np.state_enter_time = 0;
    s_np.total_placed_events = 0;
    s_np.total_removed_events = 0;

    s_np.initialized = true;

    ESP_LOGI(TAG, "Initialized (debounce_present=%dms, debounce_absent=%dms)",
             s_np.config.debounce_present_ms, s_np.config.debounce_absent_ms);

    return ESP_OK;
}

esp_err_t now_playing_deinit(void)
{
    if (!s_np.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    xSemaphoreTake(s_np.mutex, portMAX_DELAY);

    /* Reset state */
    s_np.state = NOW_PLAYING_STATE_IDLE;
    clear_tag_data(s_np.current_epc, &s_np.current_epc_len, &s_np.current_rssi);
    clear_tag_data(s_np.pending_epc, &s_np.pending_epc_len, &s_np.pending_rssi);

    s_np.initialized = false;

    xSemaphoreGive(s_np.mutex);
    vSemaphoreDelete(s_np.mutex);
    s_np.mutex = NULL;

    ESP_LOGI(TAG, "Deinitialized");

    return ESP_OK;
}

void now_playing_on_tag_detected(const rfid_tag_t *tag)
{
    if (!s_np.initialized || tag == NULL) {
        return;
    }

    /* Only process Saturday tags */
    if (!tag->is_saturday_tag) {
        ESP_LOGD(TAG, "Ignoring non-Saturday tag");
        return;
    }

    xSemaphoreTake(s_np.mutex, portMAX_DELAY);

    switch (s_np.state) {
        case NOW_PLAYING_STATE_IDLE:
            handle_idle_tag_detected(tag);
            break;
        case NOW_PLAYING_STATE_TAG_CONFIRMING:
            handle_confirming_tag_detected(tag);
            break;
        case NOW_PLAYING_STATE_TAG_PRESENT:
            handle_present_tag_detected(tag);
            break;
        case NOW_PLAYING_STATE_TAG_REMOVING:
            handle_removing_tag_detected(tag);
            break;
    }

    xSemaphoreGive(s_np.mutex);
}

void now_playing_on_poll_complete_no_tag(void)
{
    if (!s_np.initialized) {
        return;
    }

    xSemaphoreTake(s_np.mutex, portMAX_DELAY);

    switch (s_np.state) {
        case NOW_PLAYING_STATE_IDLE:
            handle_idle_no_tag();
            break;
        case NOW_PLAYING_STATE_TAG_CONFIRMING:
            handle_confirming_no_tag();
            break;
        case NOW_PLAYING_STATE_TAG_PRESENT:
            handle_present_no_tag();
            break;
        case NOW_PLAYING_STATE_TAG_REMOVING:
            handle_removing_no_tag();
            break;
    }

    xSemaphoreGive(s_np.mutex);
}

esp_err_t now_playing_get_status(now_playing_status_t *status)
{
    if (!s_np.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_np.mutex, portMAX_DELAY);

    status->state = s_np.state;
    status->has_current_tag = (s_np.state == NOW_PLAYING_STATE_TAG_PRESENT ||
                               s_np.state == NOW_PLAYING_STATE_TAG_REMOVING);

    if (status->has_current_tag) {
        memcpy(status->current_epc, s_np.current_epc, s_np.current_epc_len);
        status->current_epc_len = s_np.current_epc_len;
        status->current_rssi = s_np.current_rssi;
        status->tag_placed_time = s_np.tag_placed_time;
    } else {
        memset(status->current_epc, 0, RFID_EPC_MAX_LEN);
        status->current_epc_len = 0;
        status->current_rssi = 0;
        status->tag_placed_time = 0;
    }

    status->total_placed_events = s_np.total_placed_events;
    status->total_removed_events = s_np.total_removed_events;

    xSemaphoreGive(s_np.mutex);

    return ESP_OK;
}

esp_err_t now_playing_set_config(const now_playing_config_t *config)
{
    if (!s_np.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (config == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_np.mutex, portMAX_DELAY);

    s_np.config = *config;

    ESP_LOGI(TAG, "Config updated: debounce_present=%dms, debounce_absent=%dms",
             s_np.config.debounce_present_ms, s_np.config.debounce_absent_ms);

    xSemaphoreGive(s_np.mutex);

    return ESP_OK;
}

void now_playing_reset(void)
{
    if (!s_np.initialized) {
        return;
    }

    xSemaphoreTake(s_np.mutex, portMAX_DELAY);

    s_np.state = NOW_PLAYING_STATE_IDLE;
    clear_tag_data(s_np.current_epc, &s_np.current_epc_len, &s_np.current_rssi);
    clear_tag_data(s_np.pending_epc, &s_np.pending_epc_len, &s_np.pending_rssi);
    s_np.tag_placed_time = 0;
    s_np.state_enter_time = 0;

    ESP_LOGI(TAG, "State machine reset to IDLE");

    xSemaphoreGive(s_np.mutex);
}

const char *now_playing_state_to_string(now_playing_state_t state)
{
    switch (state) {
        case NOW_PLAYING_STATE_IDLE:           return "IDLE";
        case NOW_PLAYING_STATE_TAG_CONFIRMING: return "TAG_CONFIRMING";
        case NOW_PLAYING_STATE_TAG_PRESENT:    return "TAG_PRESENT";
        case NOW_PLAYING_STATE_TAG_REMOVING:   return "TAG_REMOVING";
        default:                               return "UNKNOWN";
    }
}
