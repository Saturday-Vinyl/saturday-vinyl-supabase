# Saturday Vinyl Hub Firmware - Agent Onboarding Prompt

Use this prompt to onboard AI agents working on the sv-hub-firmware project.

---

## Prompt

```
You are working on the Saturday Vinyl Hub firmware project (sv-hub-firmware).

## Project Overview

Saturday Vinyl makes furniture with embedded technology for vinyl record enthusiasts. The Hub is an ESP32-C6-based device that:

1. **Thread Border Router** - Bridges battery-powered RFID crates (which track records stored inside) to the cloud via Wi-Fi
2. **Now Playing Detection** - Uses an integrated UHF RFID reader (YRM100 module) to detect which record is on the user's turntable

Data flows: Crates → (Thread/CoAP) → Hub → (Wi-Fi/HTTPS) → Supabase → Saturday Mobile App

## Technical Stack

- **MCU:** ESP32-C6 (Wi-Fi 6 + Thread/802.15.4 + BLE 5.0)
- **Framework:** ESP-IDF v5.2+
- **RFID:** YRM100 module via UART (115200 baud), ISO 18000-6C / EPC Gen2
- **Cloud:** Supabase (REST API over HTTPS)
- **Crate Protocol:** CoAP over Thread
- **Provisioning:** BLE (consumer) + Serial (factory)

## Key Files

Before starting work, read these documents:

1. `docs/developers_guide.md` - Comprehensive technical specification including:
   - Hardware pinouts and peripherals
   - Firmware architecture and state machines
   - YRM100 RFID protocol and frame format
   - Supabase API endpoints
   - Provisioning flows
   - LED states and button behavior

2. `docs/implementation_plan.md` - Phased development plan with:
   - 14 implementation phases (0-13)
   - Task checklists for each phase
   - Testing criteria
   - Dependencies and milestones

## Project Structure

```
sv-hub-firmware/
├── main/                    # Application entry point
├── components/
│   ├── network/             # Wi-Fi, Thread BR, CoAP server
│   ├── rfid/                # YRM100 driver, Now Playing logic
│   ├── cloud/               # Supabase client, event reporting
│   ├── provisioning/        # BLE and serial provisioning
│   ├── ui/                  # RGB LED and button handling
│   └── config/              # NVS configuration storage
├── docs/                    # Documentation
└── test/                    # Unit tests
```

## Coding Standards

- Use ESP-IDF conventions and APIs
- Use ESP_LOG macros for logging (ESP_LOGI, ESP_LOGW, ESP_LOGE)
- Use ESP-IDF event loop for inter-component communication
- Store configuration in NVS under appropriate namespaces
- Handle errors explicitly - no silent failures
- Keep functions focused and testable

## EPC Format

Saturday Vinyl RFID tags use 96-bit EPCs with prefix `5356` (ASCII "SV"):
```
5356 + 10 random bytes = 12 bytes total (24 hex chars)
Example: 5356A1B2C3D4E5F67890ABCD
```

Validate tags with: `epc[0] == 0x53 && epc[1] == 0x56 && len == 12`

## Current Status

[UPDATE THIS SECTION with current phase and completed work]

The project is currently in Phase X. Completed:
- [ ] Phase 0: Project Setup
- [ ] Phase 1: Hardware Bring-Up
- [ ] Phase 2: RFID Detection
- ...

## Your Task

[DESCRIBE THE SPECIFIC TASK HERE]

When implementing:
1. Read the relevant sections of developers_guide.md first
2. Check implementation_plan.md for the task checklist
3. Follow existing code patterns in the codebase
4. Update task checkboxes in implementation_plan.md when complete
5. Test on hardware before marking complete
```

---

## Usage Instructions

1. Copy the prompt above
2. Update the "Current Status" section with actual progress
3. Replace "Your Task" with the specific work to be done
4. Provide the prompt to the agent along with access to the codebase

## Example Task Assignments

### Example 1: Implement LED Manager

```
## Your Task

Implement the RGB LED manager (Phase 1, Task 1.1).

Create `components/ui/led_manager.c` and `led_manager.h` with:
- PWM initialization for GPIO8 (R), GPIO9 (G), GPIO10 (B)
- Functions: led_init(), led_set_color(), led_set_brightness()
- Test by cycling through colors

Refer to:
- developers_guide.md section "User Interface (LED & Button)"
- implementation_plan.md Phase 1, Task 1.1
```

### Example 2: Implement Supabase Client

```
## Your Task

Implement the Supabase client (Phase 5, Task 5.1).

Create `components/cloud/supabase_client.c` with:
- Configuration struct for URL, anon key, device secret
- Authenticated POST request function
- HTTP response handling (200, 401, 500)

The hub needs to POST to these tables:
- now_playing_events
- crate_inventory_events
- hub_heartbeats

Refer to:
- developers_guide.md section "Cloud Integration (Supabase)"
- implementation_plan.md Phase 5, Tasks 5.1-5.4
```

### Example 3: Fix a Bug

```
## Your Task

Fix: RFID tags are detected but debounce isn't working correctly. Tags are reported multiple times.

Investigation starting points:
- components/rfid/now_playing.c - state machine logic
- Check debounce timer implementation
- Verify RFID polling doesn't send duplicate notices

Expected behavior:
- Tag placed → single TAG_PLACED event after debounce_present_ms
- Tag removed → single TAG_REMOVED event after debounce_absent_ms

Refer to:
- developers_guide.md section "Now Playing Detection Logic"
- implementation_plan.md Phase 3
```

---

## Notes for Human Operators

- Always verify the agent has read the documentation before it starts coding
- If the agent asks clarifying questions, that's good - answer them
- Check that changes follow the established architecture
- Ensure tests are written or updated for new functionality
- Update implementation_plan.md checkboxes as work completes
