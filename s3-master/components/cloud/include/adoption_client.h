/**
 * @file adoption_client.h
 * @brief Hub adoption / Thread credential cloud client.
 *
 * Wraps the Supabase edge functions `adopt_device`, `get_thread_credentials`,
 * `refresh_device_session`, and `unadopt_device`. All four are deployed to
 * Supabase as part of the cloud-canonical Thread credential architecture.
 *
 * See .context/thread-credential-architecture.md and
 * shared-supabase/supabase/functions/ for the protocol contracts.
 */

#ifndef ADOPTION_CLIENT_H
#define ADOPTION_CLIENT_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "esp_err.h"
#include "s3_h2_protocol.h"  /* s3h2_credentials_payload_t */

#ifdef __cplusplus
extern "C" {
#endif

/** Buffer sizes for tokens returned by adopt_device / refresh_device_session.
 *
 * Supabase access tokens are JWTs (~700-1200 bytes); we use opaque random
 * 32-byte hex strings instead, so 128 bytes is plenty for both access and
 * refresh tokens. Sized for headroom in case the cloud schema changes. */
#define ADOPTION_TOKEN_MAX_LEN  256

/**
 * @brief Complete BLE-driven adoption by calling the cloud `adopt_device`
 *        edge function with the user's JWT.
 *
 * @param mac_address NUL-terminated MAC address string ("AA:BB:CC:DD:EE:FF").
 * @param user_jwt    Supabase user JWT received over BLE characteristic 0x0030.
 * @param out_creds   Thread credentials returned by the cloud (decoded into
 *                    s3h2_credentials_payload_t for direct push to H2).
 * @param out_access_token   Buffer for device access token (sized for ADOPTION_TOKEN_MAX_LEN).
 * @param out_refresh_token  Buffer for device refresh token.
 * @param out_expires_at_ms  Output: unix-ms timestamp when access token expires.
 *                           Computed from now + TTL since the edge function
 *                           sends an ISO 8601 string and we avoid parsing it.
 *
 * @return ESP_OK on success.
 *         ESP_ERR_NOT_FOUND if cloud says `device_not_factory_provisioned`.
 *         ESP_ERR_INVALID_STATE if cloud says `device_owned_by_another_user`.
 *         Other esp_err_t for transport / parse failures.
 */
esp_err_t adoption_adopt_device(const char *mac_address,
                                const char *user_jwt,
                                s3h2_credentials_payload_t *out_creds,
                                char *out_access_token,
                                char *out_refresh_token,
                                int64_t *out_expires_at_ms);

/**
 * @brief Fetch the user's Thread credentials from the cloud.
 *
 * Uses the device session access token from NVS as the bearer. On 401,
 * automatically calls adoption_refresh_session() once and retries.
 *
 * @param out_creds Thread credentials decoded into s3h2_credentials_payload_t.
 * @return ESP_OK on success.
 *         ESP_ERR_NOT_FOUND if cloud has no thread_networks row for this user.
 *         ESP_ERR_INVALID_STATE if no device tokens stored.
 */
esp_err_t adoption_get_thread_credentials(s3h2_credentials_payload_t *out_creds);

/**
 * @brief Rotate device session tokens using the stored refresh token.
 *
 * Reads the current refresh token from NVS, calls refresh_device_session, and
 * writes the new access/refresh/expiry triple back to NVS on success.
 *
 * @return ESP_OK on success.
 *         ESP_ERR_NOT_FOUND if no refresh token stored.
 *         ESP_ERR_INVALID_STATE if the refresh token has been revoked by the cloud.
 */
esp_err_t adoption_refresh_session(void);

/**
 * @brief Unadopt this Hub on the cloud.
 *
 * @param user_jwt User JWT (the adoption-removing user must own this device).
 * @return ESP_OK on success.
 */
esp_err_t adoption_unadopt_device(const char *user_jwt);

#ifdef __cplusplus
}
#endif

#endif /* ADOPTION_CLIENT_H */
