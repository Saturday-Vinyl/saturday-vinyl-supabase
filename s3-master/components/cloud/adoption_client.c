/**
 * @file adoption_client.c
 * @brief Hub adoption / Thread credential cloud client implementation.
 *
 * See adoption_client.h and .context/thread-credential-architecture.md.
 */

#include "adoption_client.h"
#include "supabase_client.h"
#include "config_store.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "cJSON.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

static const char *TAG = "ADOPT_CLIENT";

/* Local mirror of access-token TTL set by refresh_device_session (1 hour).
 * Compute expiry as now + TTL instead of parsing the ISO 8601 string from
 * the edge function response. Use 50 minutes to refresh before actual expiry. */
#define ACCESS_TOKEN_LOCAL_TTL_MS  (50 * 60 * 1000LL)

/*******************************************************************************
 * Local helpers
 ******************************************************************************/

static int64_t now_ms(void)
{
    return esp_timer_get_time() / 1000;
}

/* Cheap unix-ms approximation: esp_timer gives us monotonic milliseconds
 * since boot. We don't have a real RTC for absolute time, so we use boot-time
 * monotonic as the basis for expiry comparisons. Comparisons against
 * stored expires_at_ms are consistent as long as both are computed the same
 * way (we always use now_ms() at issue time and at check time). */

static esp_err_t hex_decode(const char *hex, uint8_t *out, size_t out_len)
{
    if (hex == NULL || out == NULL) return ESP_ERR_INVALID_ARG;
    size_t hex_len = strlen(hex);
    if (hex_len != out_len * 2) {
        ESP_LOGE(TAG, "hex_decode: expected %zu chars, got %zu", out_len * 2, hex_len);
        return ESP_ERR_INVALID_SIZE;
    }
    for (size_t i = 0; i < out_len; i++) {
        unsigned int byte;
        if (sscanf(hex + i * 2, "%2x", &byte) != 1) {
            return ESP_ERR_INVALID_ARG;
        }
        out[i] = (uint8_t)byte;
    }
    return ESP_OK;
}

static esp_err_t parse_thread_credentials(cJSON *creds_obj,
                                          s3h2_credentials_payload_t *out)
{
    if (creds_obj == NULL || out == NULL) return ESP_ERR_INVALID_ARG;
    memset(out, 0, sizeof(*out));

    cJSON *name = cJSON_GetObjectItem(creds_obj, "network_name");
    cJSON *pan  = cJSON_GetObjectItem(creds_obj, "pan_id");
    cJSON *chan = cJSON_GetObjectItem(creds_obj, "channel");
    cJSON *nkey = cJSON_GetObjectItem(creds_obj, "network_key");
    cJSON *ext  = cJSON_GetObjectItem(creds_obj, "extended_pan_id");
    cJSON *mlp  = cJSON_GetObjectItem(creds_obj, "mesh_local_prefix");
    cJSON *pskc = cJSON_GetObjectItem(creds_obj, "pskc");

    if (!cJSON_IsString(name) || !cJSON_IsNumber(pan) || !cJSON_IsNumber(chan)
        || !cJSON_IsString(nkey) || !cJSON_IsString(ext)
        || !cJSON_IsString(mlp)  || !cJSON_IsString(pskc)) {
        ESP_LOGE(TAG, "thread_credentials missing or wrong-typed fields");
        return ESP_ERR_INVALID_ARG;
    }

    strncpy(out->network_name, name->valuestring, sizeof(out->network_name) - 1);
    out->pan_id  = (uint16_t)pan->valueint;
    out->channel = (uint8_t)chan->valueint;

    esp_err_t err;
    err = hex_decode(nkey->valuestring, out->network_key, sizeof(out->network_key));
    if (err != ESP_OK) return err;
    err = hex_decode(ext->valuestring, out->extended_pan_id, sizeof(out->extended_pan_id));
    if (err != ESP_OK) return err;
    err = hex_decode(mlp->valuestring, out->mesh_local_prefix, sizeof(out->mesh_local_prefix));
    if (err != ESP_OK) return err;
    err = hex_decode(pskc->valuestring, out->pskc, sizeof(out->pskc));
    if (err != ESP_OK) return err;

    return ESP_OK;
}

static esp_err_t copy_string(cJSON *obj, const char *key, char *out, size_t out_size)
{
    cJSON *item = cJSON_GetObjectItem(obj, key);
    if (!cJSON_IsString(item)) {
        ESP_LOGE(TAG, "missing string field '%s'", key);
        return ESP_ERR_INVALID_ARG;
    }
    if (strlen(item->valuestring) >= out_size) {
        ESP_LOGE(TAG, "field '%s' too long for buffer", key);
        return ESP_ERR_INVALID_SIZE;
    }
    strncpy(out, item->valuestring, out_size - 1);
    out[out_size - 1] = '\0';
    return ESP_OK;
}

static esp_err_t map_error_code(const char *error_str)
{
    if (error_str == NULL) return ESP_FAIL;
    if (strcmp(error_str, "device_not_factory_provisioned") == 0) return ESP_ERR_NOT_FOUND;
    if (strcmp(error_str, "device_owned_by_another_user") == 0)   return ESP_ERR_INVALID_STATE;
    if (strcmp(error_str, "no_thread_network") == 0)              return ESP_ERR_NOT_FOUND;
    if (strcmp(error_str, "invalid_refresh_token") == 0)          return ESP_ERR_INVALID_STATE;
    return ESP_FAIL;
}

/*******************************************************************************
 * adopt_device
 ******************************************************************************/

esp_err_t adoption_adopt_device(const char *mac_address,
                                const char *user_jwt,
                                s3h2_credentials_payload_t *out_creds,
                                char *out_access_token,
                                char *out_refresh_token,
                                int64_t *out_expires_at_ms)
{
    if (mac_address == NULL || user_jwt == NULL || out_creds == NULL
        || out_access_token == NULL || out_refresh_token == NULL
        || out_expires_at_ms == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    cJSON *body = cJSON_CreateObject();
    cJSON_AddStringToObject(body, "mac_address", mac_address);
    cJSON_AddBoolToObject(body, "issue_device_tokens", true);
    char *body_str = cJSON_PrintUnformatted(body);
    cJSON_Delete(body);
    if (body_str == NULL) return ESP_ERR_NO_MEM;

    supabase_response_t resp = {0};
    esp_err_t err = supabase_function_call("adopt_device", "POST",
                                           body_str, user_jwt, &resp, 0);
    free(body_str);
    if (err != ESP_OK) {
        supabase_response_free(&resp);
        return err;
    }

    cJSON *root = (resp.body != NULL) ? cJSON_Parse(resp.body) : NULL;
    if (root == NULL) {
        ESP_LOGE(TAG, "adopt_device: failed to parse response");
        supabase_response_free(&resp);
        return ESP_ERR_INVALID_RESPONSE;
    }

    if (resp.status_code < 200 || resp.status_code >= 300) {
        cJSON *error = cJSON_GetObjectItem(root, "error");
        const char *error_str = cJSON_IsString(error) ? error->valuestring : NULL;
        ESP_LOGW(TAG, "adopt_device returned %d: %s", resp.status_code,
                 error_str ? error_str : "(no error field)");
        err = map_error_code(error_str);
        cJSON_Delete(root);
        supabase_response_free(&resp);
        return err;
    }

    cJSON *creds = cJSON_GetObjectItem(root, "thread_credentials");
    if (!cJSON_IsObject(creds)) {
        ESP_LOGE(TAG, "adopt_device response missing thread_credentials");
        cJSON_Delete(root);
        supabase_response_free(&resp);
        return ESP_ERR_INVALID_RESPONSE;
    }
    err = parse_thread_credentials(creds, out_creds);
    if (err != ESP_OK) goto done;

    cJSON *tokens = cJSON_GetObjectItem(root, "device_tokens");
    if (!cJSON_IsObject(tokens)) {
        ESP_LOGE(TAG, "adopt_device response missing device_tokens");
        err = ESP_ERR_INVALID_RESPONSE;
        goto done;
    }
    err = copy_string(tokens, "access_token", out_access_token, ADOPTION_TOKEN_MAX_LEN);
    if (err != ESP_OK) goto done;
    err = copy_string(tokens, "refresh_token", out_refresh_token, ADOPTION_TOKEN_MAX_LEN);
    if (err != ESP_OK) goto done;

    /* Compute expiry locally (see comment at top of file). */
    *out_expires_at_ms = now_ms() + ACCESS_TOKEN_LOCAL_TTL_MS;

    err = ESP_OK;

done:
    cJSON_Delete(root);
    supabase_response_free(&resp);
    return err;
}

/*******************************************************************************
 * get_thread_credentials
 ******************************************************************************/

static esp_err_t call_get_thread_credentials_with_token(const char *access_token,
                                                       s3h2_credentials_payload_t *out)
{
    supabase_response_t resp = {0};
    esp_err_t err = supabase_function_call("get_thread_credentials", "GET",
                                           NULL, access_token, &resp, 0);
    if (err != ESP_OK) {
        supabase_response_free(&resp);
        return err;
    }

    cJSON *root = (resp.body != NULL) ? cJSON_Parse(resp.body) : NULL;
    if (root == NULL) {
        supabase_response_free(&resp);
        return ESP_ERR_INVALID_RESPONSE;
    }

    /* 401 -> caller should refresh and retry */
    if (resp.status_code == 401) {
        cJSON_Delete(root);
        supabase_response_free(&resp);
        return ESP_ERR_INVALID_STATE;
    }

    if (resp.status_code < 200 || resp.status_code >= 300) {
        cJSON *error = cJSON_GetObjectItem(root, "error");
        const char *error_str = cJSON_IsString(error) ? error->valuestring : NULL;
        ESP_LOGW(TAG, "get_thread_credentials returned %d: %s",
                 resp.status_code, error_str ? error_str : "(no error field)");
        err = map_error_code(error_str);
        cJSON_Delete(root);
        supabase_response_free(&resp);
        return err;
    }

    cJSON *creds = cJSON_GetObjectItem(root, "thread_credentials");
    if (!cJSON_IsObject(creds)) {
        err = ESP_ERR_INVALID_RESPONSE;
    } else {
        err = parse_thread_credentials(creds, out);
    }

    cJSON_Delete(root);
    supabase_response_free(&resp);
    return err;
}

esp_err_t adoption_get_thread_credentials(s3h2_credentials_payload_t *out_creds)
{
    if (out_creds == NULL) return ESP_ERR_INVALID_ARG;

    char access_token[ADOPTION_TOKEN_MAX_LEN] = {0};
    int64_t expires_at_ms = 0;
    esp_err_t err = config_get_device_tokens(access_token, sizeof(access_token),
                                             NULL, 0, &expires_at_ms);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "no device tokens stored: %s", esp_err_to_name(err));
        return ESP_ERR_INVALID_STATE;
    }

    /* Proactive refresh if near/past expiry. */
    if (now_ms() >= expires_at_ms) {
        ESP_LOGI(TAG, "device access token expired - refreshing before call");
        err = adoption_refresh_session();
        if (err != ESP_OK) return err;
        err = config_get_device_tokens(access_token, sizeof(access_token),
                                       NULL, 0, NULL);
        if (err != ESP_OK) return err;
    }

    err = call_get_thread_credentials_with_token(access_token, out_creds);
    if (err == ESP_ERR_INVALID_STATE) {
        /* 401: refresh and retry once. */
        ESP_LOGI(TAG, "get_thread_credentials 401 - refreshing session and retrying");
        esp_err_t refresh_err = adoption_refresh_session();
        if (refresh_err != ESP_OK) return refresh_err;
        err = config_get_device_tokens(access_token, sizeof(access_token),
                                       NULL, 0, NULL);
        if (err != ESP_OK) return err;
        err = call_get_thread_credentials_with_token(access_token, out_creds);
    }
    return err;
}

/*******************************************************************************
 * refresh_device_session
 ******************************************************************************/

esp_err_t adoption_refresh_session(void)
{
    char refresh_token[ADOPTION_TOKEN_MAX_LEN] = {0};
    esp_err_t err = config_get_device_tokens(NULL, 0,
                                             refresh_token, sizeof(refresh_token),
                                             NULL);
    if (err != ESP_OK) {
        return ESP_ERR_NOT_FOUND;
    }

    cJSON *body = cJSON_CreateObject();
    cJSON_AddStringToObject(body, "refresh_token", refresh_token);
    char *body_str = cJSON_PrintUnformatted(body);
    cJSON_Delete(body);
    if (body_str == NULL) return ESP_ERR_NO_MEM;

    supabase_response_t resp = {0};
    /* No bearer override - the refresh token in the body is the credential. */
    err = supabase_function_call("refresh_device_session", "POST",
                                 body_str, NULL, &resp, 0);
    free(body_str);
    if (err != ESP_OK) {
        supabase_response_free(&resp);
        return err;
    }

    cJSON *root = (resp.body != NULL) ? cJSON_Parse(resp.body) : NULL;
    if (root == NULL) {
        supabase_response_free(&resp);
        return ESP_ERR_INVALID_RESPONSE;
    }

    if (resp.status_code < 200 || resp.status_code >= 300) {
        cJSON *error = cJSON_GetObjectItem(root, "error");
        const char *error_str = cJSON_IsString(error) ? error->valuestring : NULL;
        ESP_LOGW(TAG, "refresh_device_session returned %d: %s",
                 resp.status_code, error_str ? error_str : "(no error field)");
        err = map_error_code(error_str);
        cJSON_Delete(root);
        supabase_response_free(&resp);
        return err;
    }

    char new_access[ADOPTION_TOKEN_MAX_LEN];
    char new_refresh[ADOPTION_TOKEN_MAX_LEN];
    err = copy_string(root, "access_token", new_access, sizeof(new_access));
    if (err != ESP_OK) goto done;
    err = copy_string(root, "refresh_token", new_refresh, sizeof(new_refresh));
    if (err != ESP_OK) goto done;

    int64_t expires_at_ms = now_ms() + ACCESS_TOKEN_LOCAL_TTL_MS;
    err = config_set_device_tokens(new_access, new_refresh, expires_at_ms);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "failed to persist refreshed tokens: %s", esp_err_to_name(err));
    }

done:
    cJSON_Delete(root);
    supabase_response_free(&resp);
    return err;
}

/*******************************************************************************
 * unadopt_device
 ******************************************************************************/

esp_err_t adoption_unadopt_device(const char *user_jwt)
{
    if (user_jwt == NULL) return ESP_ERR_INVALID_ARG;

    uint8_t mac[6];
    esp_err_t err = esp_read_mac(mac, ESP_MAC_WIFI_STA);
    if (err != ESP_OK) return err;

    char mac_str[18];
    snprintf(mac_str, sizeof(mac_str), "%02X:%02X:%02X:%02X:%02X:%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    cJSON *body = cJSON_CreateObject();
    cJSON_AddStringToObject(body, "mac_address", mac_str);
    char *body_str = cJSON_PrintUnformatted(body);
    cJSON_Delete(body);
    if (body_str == NULL) return ESP_ERR_NO_MEM;

    supabase_response_t resp = {0};
    err = supabase_function_call("unadopt_device", "POST",
                                 body_str, user_jwt, &resp, 0);
    free(body_str);
    if (err != ESP_OK) {
        supabase_response_free(&resp);
        return err;
    }

    if (resp.status_code < 200 || resp.status_code >= 300) {
        ESP_LOGW(TAG, "unadopt_device returned %d: %s",
                 resp.status_code, resp.body ? resp.body : "(no body)");
        err = ESP_FAIL;
    }
    supabase_response_free(&resp);
    return err;
}
