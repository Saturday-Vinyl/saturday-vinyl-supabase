# Audit: Crate Firmware - Flat Capability Commands & Re-register

**Date:** 2026-02-20
**Context:** The hub firmware (ESP32-H2 Thread Border Router) has been refactored with two changes that affect Crate (Thread mesh node) firmware. First, commands sent via `POST /cmd` now use a flat format — `{"cmd": "get_dataset"}` instead of `{"cmd": "run_test", "capability": "thread", "test_name": "get_dataset"}`. Second, the hub now gracefully handles unregistered heartbeats and actively nudges nodes to re-register via a new `register` command and 4.01 response codes. The Crate firmware must adapt its `/cmd` parser and heartbeat send path to work with these changes. See [CoAP Mesh Protocol v1.1.0](../protocols/coap_mesh_protocol.md) and [Device Command Protocol v1.3.0](../protocols/device_command_protocol.md) for the full specification.

## What Changed (Hub Side)

1. **`POST /cmd` payload simplified** — CBOR map now contains only `"id"` (tstr), `"cmd"` (tstr), and optional `"params"` (map). The `"capability"` and `"test_name"` keys are no longer sent.
2. **New `register` command** — the hub sends `{"id": "00000000-0000-0000-0000-000000000000", "cmd": "register"}` via CON `POST /cmd` to nodes that send heartbeats without being in the registration cache
3. **4.01 response to unregistered heartbeats** — if the hub doesn't recognize a heartbeat sender, it now responds with 4.01 Unauthorized (instead of silently dropping or rejecting). This signals "re-register required."
4. **Hub gracefully accepts unregistered heartbeats** — telemetry is forwarded to the cloud even from unregistered nodes (with `mac="unknown"`, `unit_id="unknown"`), but the 4.01 + nudge tells the node to fix this
5. **`command_not_found` replaces `test_not_found`** as the standard error code for unknown commands

## Audit Checklist

Search the codebase for each of the following patterns. For each match found, describe the file, line number, what it currently does, and what change is needed.

### 1. `/cmd` CBOR parser — remove `capability` and `test_name` parsing

The Crate's CoAP `/cmd` resource handler currently parses `"capability"` and `"test_name"` keys from the incoming CBOR map to determine which command to execute.

**Search patterns:**
- `capability` as a CBOR map key string
- `test_name` as a CBOR map key string
- `run_test` in command parsing code
- `cbor_value_text_string` or equivalent CBOR text extraction near "capability" or "test_name"

**Current CBOR parse (old format):**
```c
// Old: parse capability + test_name for routing
cbor_value_map_find("cmd", ...)     // "run_test"
cbor_value_map_find("capability", ...) // "thread"
cbor_value_map_find("test_name", ...)  // "get_dataset"
```

**New CBOR parse (flat format):**
```c
// New: parse only id, cmd, optional params
cbor_value_map_find("id", ...)      // "550e8400-..." (UUID string)
cbor_value_map_find("cmd", ...)     // "get_dataset" (flat command name)
cbor_value_map_find("params", ...)  // optional parameter map
```

**Required change:** Remove all parsing of `"capability"` and `"test_name"` keys. The `"cmd"` value now directly contains the command name. Extract `"id"` (required — needed for command acknowledgement heartbeats) and `"params"` (optional). Per the protocol's forward-compatibility rule, the parser MUST ignore unknown keys in the CBOR map.

### 2. Command dispatch table — flatten to single-level

The Crate likely has a two-level dispatch: first routing by capability name, then by test name within that capability.

**Search patterns:**
- `strcmp` chains or switch statements comparing capability names
- Nested dispatch: outer `if (capability == "thread")` → inner `if (test_name == "get_dataset")`
- Function names like `handle_capability_command`, `dispatch_test`, `run_capability_test`

**Current dispatch (two-level):**
```c
if (strcmp(capability, "thread") == 0) {
    if (strcmp(test_name, "get_dataset") == 0) { ... }
    else if (strcmp(test_name, "join") == 0) { ... }
}
```

**New dispatch (flat):**
```c
if (strcmp(cmd, "get_dataset") == 0) {
    handle_thread_get_dataset(params);
} else if (strcmp(cmd, "join") == 0) {
    handle_thread_join(params);
} else if (strcmp(cmd, "register") == 0) {
    handle_register(params);
} else if (strcmp(cmd, "reboot") == 0) {
    handle_reboot();
} else if (strcmp(cmd, "get_status") == 0) {
    handle_get_status();
} else {
    // Unknown command — respond 4.04
    send_coap_response(OT_COAP_CODE_NOT_FOUND);
}
```

**Required change:** Collapse to a single flat dispatch on `"cmd"`. All known commands — both core (`reboot`, `get_status`) and capability-specific (`get_dataset`, `join`, `register`) — are peers in the dispatch table. See [Device Command Protocol - Capability Commands](../protocols/device_command_protocol.md#capability-commands) for the full command list relevant to the Crate's capabilities.

### 3. Command ID extraction and acknowledgement

The `"id"` field in the CBOR command payload must be extracted and echoed back in `command_ack` and `command_result` heartbeats.

**Search patterns:**
- `cmd_id` or `command_id` in heartbeat construction
- `command_ack` or `command_result` in heartbeat type handling
- The `/cmd` handler's response path — does it extract and store the command ID?

**Required behavior:**
1. Extract `"id"` (tstr) from the incoming CBOR `/cmd` payload
2. Immediately send a `command_ack` heartbeat: `{"v": 1, "type": "command_ack", "cmd_id": "<id>", ...telemetry...}`
3. Execute the command
4. Send a `command_result` heartbeat: `{"v": 1, "type": "command_result", "cmd_id": "<id>", "result": {"status": "completed"|"failed", ...}}`

**Required change:** If the Crate doesn't currently extract `"id"`, add parsing for it. If it already implements `command_ack`/`command_result` heartbeats, verify the `"cmd_id"` field is populated correctly.

### 4. Unknown command response — return 4.04

The CoAP transport-level response for an unrecognized `"cmd"` value must be 4.04 Not Found.

**Search patterns:**
- CoAP response code constants: `OT_COAP_CODE_NOT_FOUND`, `COAP_404`, or similar
- Default/fallback branch in the command dispatch
- Any code that silently drops unknown commands (this should be changed to 4.04)

**Required change:** The final `else` branch in the command dispatch must send a CoAP 4.04 response. Do NOT silently drop the CON message — that would trigger CoAP retransmission (up to 4 retries over ~45 seconds).

### 5. Heartbeat 4.01 response handling — trigger re-registration

This is the **most critical change**. When the hub restarts, its registration cache clears. The Crate's heartbeats will receive 4.01 responses until the Crate re-registers. Currently, the Crate likely ignores the heartbeat response code.

**Search patterns:**
- Heartbeat send function: `otCoapSendRequest`, `coap_send`, or similar for `POST /heartbeat`
- Response callback for heartbeat sends
- `OT_COAP_CODE_UNAUTHORIZED` or `4.01` or `UNAUTHORIZED` constants
- The function that sends `POST /register` (this needs a new call site)

**Current behavior (presumed):**
```c
// Sends heartbeat, ignores response
otCoapSendRequest(instance, message, &message_info, NULL, NULL);
// or: response callback exists but doesn't check for 4.01
```

**New behavior:**
```c
// Heartbeat response callback
static void heartbeat_response_handler(void *context, otMessage *message,
                                        const otMessageInfo *message_info,
                                        otError result) {
    if (result == OT_ERROR_NONE && message != NULL) {
        otCoapCode code = otCoapMessageGetCode(message);
        if (code == OT_COAP_CODE_UNAUTHORIZED) {  // 4.01
            ESP_LOGW(TAG, "Hub responded 4.01 — re-registering");
            send_register();  // Trigger POST /register
        }
    }
}
```

**Required change:** Add (or update) a response callback on heartbeat sends that checks for 4.01 Unauthorized. On 4.01, immediately call the existing `send_register()` function (the same one used on Thread attach). Note: even though heartbeats use NON messages, the hub still sends a response; the CoAP stack delivers it to the response callback.

### 6. New `register` command handler

The hub now sends a `POST /cmd` with `{"cmd": "register"}` to actively nudge unregistered nodes. The Crate must handle this as a valid command.

**Search patterns:**
- The command dispatch table (from item 2 above) — verify `register` is listed
- The function that sends `POST /register` — it needs to be callable from the command handler

**CBOR payload the Crate will receive:**
```cbor-diag
{
  "id": "00000000-0000-0000-0000-000000000000",
  "cmd": "register"
}
```

**Required implementation:**
```c
static void handle_register_command(const char *cmd_id) {
    // 1. Send CoAP 2.04 response (transport ack)
    send_coap_response(OT_COAP_CODE_CHANGED);

    // 2. Send command_ack heartbeat
    send_command_ack_heartbeat(cmd_id);

    // 3. Execute: send POST /register to hub
    esp_err_t err = send_register();

    // 4. Send command_result heartbeat
    bool success = (err == ESP_OK);
    send_command_result_heartbeat(cmd_id, success ? "completed" : "failed",
                                  /* data: */ success ? "{\"registered\":true}" : NULL,
                                  /* error: */ success ? NULL : "Registration failed");
}
```

**Required change:** Add `"register"` to the flat command dispatch table. The handler calls the existing `send_register()` function and reports the result via `command_result` heartbeat. The result schema expects `{"registered": true|false}` in the result data (see [Capability Schema - thread commands](../schemas/capability_schema.md#thread)).

### 7. Legacy `run_test` alias (optional)

The hub no longer sends `run_test` to mesh nodes (the CBOR encoder normalizes to flat commands). However, if the Crate can receive commands from any other source that might use the old format (e.g., direct UART during development), a backwards-compat alias is recommended.

**Search patterns:**
- `run_test` in the command dispatch

**Optional implementation:**
```c
else if (strcmp(cmd, "run_test") == 0) {
    // Deprecated alias: extract test_name and re-dispatch
    const char *test_name = cbor_get_string(params_map, "test_name");
    if (test_name != NULL) {
        // Recursive dispatch with test_name as the command
        dispatch_command(cmd_id, test_name, params_map);
    } else {
        send_coap_response(OT_COAP_CODE_BAD_REQUEST);
    }
}
```

**Required change:** Optional. If the Crate only receives commands from the hub (via CoAP), the hub already normalizes to flat format, so this alias is unnecessary. Add it only if UART or other command sources still use the old format.

## Expected Outcome

After this audit, the Crate firmware should:
- Parse flat `POST /cmd` payloads: `{"id": "...", "cmd": "...", "params": {...}}`
- Dispatch commands via a single flat `strcmp` table (no capability routing layer)
- Handle `register` command by sending `POST /register` and reporting result
- React to 4.01 heartbeat responses by triggering `POST /register`
- Extract and echo command `"id"` in `command_ack` and `command_result` heartbeats
- Return 4.04 for unrecognized commands
- No longer parse `"capability"` or `"test_name"` keys from `/cmd` payloads

## Reference Documents

- [CoAP Mesh Protocol v1.1.0](../protocols/coap_mesh_protocol.md) — Simplified POST /cmd, unregistered device handling, register command
- [Device Command Protocol v1.3.0](../protocols/device_command_protocol.md) — Flat capability commands, deprecated `run_test`
- [Capability Schema v1.4.0](../schemas/capability_schema.md) — Thread capability commands (join, get_dataset, register)

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
