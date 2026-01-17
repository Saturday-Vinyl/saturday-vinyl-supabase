/**
 * @file now_playing.h
 * @brief Now Playing detection state machine interface
 *
 * Implements debounced "Now Playing" detection with a state machine.
 * Tracks which record is currently on the turntable and generates
 * events when records are placed or removed.
 *
 * The state machine uses configurable debounce timers to avoid
 * false triggers from brief tag passes or momentary read failures.
 *
 * States:
 * - IDLE: No tag detected
 * - TAG_CONFIRMING: Tag detected, waiting for debounce to confirm
 * - TAG_PRESENT: Tag confirmed present (now playing)
 * - TAG_REMOVING: Tag not detected, waiting for debounce to confirm removal
 */

#ifndef NOW_PLAYING_H
#define NOW_PLAYING_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "esp_event.h"
#include "rfid_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Event Definitions
 ******************************************************************************/

/**
 * @brief Now Playing event base for ESP-IDF event loop
 */
ESP_EVENT_DECLARE_BASE(NOW_PLAYING_EVENTS);

/**
 * @brief Now Playing event types
 */
typedef enum {
    NOW_PLAYING_EVENT_TAG_PLACED,   /**< Tag confirmed present on turntable */
    NOW_PLAYING_EVENT_TAG_REMOVED,  /**< Tag confirmed removed from turntable */
} now_playing_event_type_t;

/**
 * @brief Now Playing event data structure
 *
 * Passed as event_data when posting to the event loop.
 */
typedef struct {
    now_playing_event_type_t type;              /**< Event type */
    uint8_t epc[RFID_EPC_MAX_LEN];              /**< Tag EPC */
    uint8_t epc_len;                            /**< EPC length in bytes */
    int8_t rssi;                                /**< Signal strength in dBm (for placed events) */
    int64_t timestamp;                          /**< Event timestamp (microseconds since boot) */
    uint32_t duration_ms;                       /**< Play duration in ms (for removed events only) */
} now_playing_event_t;

/*******************************************************************************
 * State Machine Types
 ******************************************************************************/

/**
 * @brief Now Playing state machine states
 */
typedef enum {
    NOW_PLAYING_STATE_IDLE,             /**< No tag detected */
    NOW_PLAYING_STATE_TAG_CONFIRMING,   /**< Tag detected, confirming presence */
    NOW_PLAYING_STATE_TAG_PRESENT,      /**< Tag confirmed present (now playing) */
    NOW_PLAYING_STATE_TAG_REMOVING,     /**< Tag absent, confirming removal */
} now_playing_state_t;

/**
 * @brief Now Playing configuration
 */
typedef struct {
    uint16_t debounce_present_ms;   /**< Time tag must be present to confirm (default: 1000) */
    uint16_t debounce_absent_ms;    /**< Time tag must be absent to confirm removal (default: 2000) */
} now_playing_config_t;

/**
 * @brief Default Now Playing configuration
 */
#define NOW_PLAYING_CONFIG_DEFAULT() { \
    .debounce_present_ms = 1000, \
    .debounce_absent_ms = 2000, \
}

/**
 * @brief Now Playing status information
 */
typedef struct {
    now_playing_state_t state;                  /**< Current state */
    bool has_current_tag;                       /**< True if a tag is currently present */
    uint8_t current_epc[RFID_EPC_MAX_LEN];      /**< Current tag EPC (if present) */
    uint8_t current_epc_len;                    /**< Current tag EPC length */
    int8_t current_rssi;                        /**< Current tag RSSI in dBm */
    int64_t tag_placed_time;                    /**< When current tag was placed (us since boot) */
    uint32_t total_placed_events;               /**< Total TAG_PLACED events generated */
    uint32_t total_removed_events;              /**< Total TAG_REMOVED events generated */
} now_playing_status_t;

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize the Now Playing state machine
 *
 * Must be called before using any other Now Playing functions.
 * Creates internal timers and registers with the default event loop.
 *
 * @param config Configuration parameters (NULL for defaults)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t now_playing_init(const now_playing_config_t *config);

/**
 * @brief Deinitialize the Now Playing state machine
 *
 * Stops timers and cleans up resources.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t now_playing_deinit(void);

/**
 * @brief Process a tag detection from RFID polling
 *
 * Call this function whenever the RFID module detects a tag.
 * The state machine will handle debouncing and event generation.
 *
 * Only Saturday tags (0x5356 prefix) should be passed to this function.
 *
 * @param tag Tag data from RFID detection
 */
void now_playing_on_tag_detected(const rfid_tag_t *tag);

/**
 * @brief Process a poll cycle with no tag detected
 *
 * Call this function after each RFID poll cycle where no tag was found.
 * This is needed to detect tag removal (absence of detection).
 */
void now_playing_on_poll_complete_no_tag(void);

/**
 * @brief Get current Now Playing status
 *
 * @param status Output structure for status information
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t now_playing_get_status(now_playing_status_t *status);

/**
 * @brief Update configuration
 *
 * Can be called while running to update debounce timers.
 *
 * @param config New configuration
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t now_playing_set_config(const now_playing_config_t *config);

/**
 * @brief Reset the state machine to IDLE
 *
 * Clears current tag and resets to initial state.
 * Does not generate removal event for any current tag.
 */
void now_playing_reset(void);

/**
 * @brief Get string representation of state
 *
 * @param state State to convert
 * @return State name string
 */
const char *now_playing_state_to_string(now_playing_state_t state);

#ifdef __cplusplus
}
#endif

#endif /* NOW_PLAYING_H */
