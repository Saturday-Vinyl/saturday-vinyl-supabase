# Push Notification Firefighting

**Version:** 1.0.0
**Last Updated:** 2026-05-25
**Audience:** Saturday on-call engineers, admin operators

---

## Table of Contents

1. [Overview](#overview)
2. [Symptoms Triage](#symptoms-triage)
3. [Where the Data Lives](#where-the-data-lives)
4. [Scenarios](#scenarios)
   - [No pushes arrive for any user](#no-pushes-arrive-for-any-user)
   - [Some users get pushes, others don't](#some-users-get-pushes-others-dont)
   - [Pushes were working, then stopped suddenly](#pushes-were-working-then-stopped-suddenly)
   - [Token keeps getting deactivated](#token-keeps-getting-deactivated)
   - [Live Activity widget not updating](#live-activity-widget-not-updating)
5. [Runbooks](#runbooks)
   - [Create a new APNs Auth Key](#create-a-new-apns-auth-key)
   - [Rotate the Firebase service account](#rotate-the-firebase-service-account)
   - [Force a single device's token to refresh](#force-a-single-devices-token-to-refresh)
   - [Recover from a stuck FCM token (full reinstall)](#recover-from-a-stuck-fcm-token-full-reinstall)
6. [Diagnostic Queries](#diagnostic-queries)
7. [Tools and Where They Live](#tools-and-where-they-live)
8. [Background](#background)
9. [Version History](#version-history)

---

## Overview

This playbook covers FCM (Firebase Cloud Messaging) push notifications that reach iOS / Android devices — the user-visible alerts like "Now Playing: Album X" when a record is placed on a hub, plus device status notifications (`device_offline`, `low_battery`, etc.). It does **not** cover:

- iOS Live Activity (ActivityKit) updates — those use a different pipeline; see [Live Activity widget not updating](#live-activity-widget-not-updating) for the boundary
- Supabase Realtime broadcasts to hubs — those use `pg_notify` and don't go through Firebase

The system has been historically brittle in non-obvious ways. A 6-day silent outage in May 2026 was caused by an APNs Auth Key with the wrong environment scope; nothing alerted, ~7,250 failed pushes accumulated against one token. Most of this playbook exists because that outage was harder to diagnose than it should have been.

---

## Symptoms Triage

Start here. Spend ~5 minutes on triage before diving into a specific scenario.

**Step 1 — Is anything succeeding right now?**

```sql
select notification_type, status, count(*) as n, max(created_at) as latest
  from notification_delivery_log
 where created_at > now() - interval '1 hour'
 group by 1, 2
 order by latest desc;
```

- All `status='sent'` rows for one or more types → **partial outage** ([scenario: Some users get pushes](#some-users-get-pushes-others-dont))
- Only `status='failed'` rows → **total outage** ([scenario: No pushes arrive](#no-pushes-arrive-for-any-user))
- No rows at all in the last hour → **silent failure** — pushes aren't even being attempted. Check upstream emitters (hub heartbeat, RFID detection, `process-now-playing-event` webhook configuration).

**Step 2 — What's the dominant failure category?**

```sql
select * from admin_push_error_patterns
 where last_seen > now() - interval '1 hour'
 order by n desc;
```

The `error_category` column tells you which scenario applies:

| Category | Meaning | Goes to |
|---|---|---|
| `apns_env_mismatch` | APNs Auth Key environment doesn't match token's environment | [No pushes arrive](#no-pushes-arrive-for-any-user) |
| `fcm_auth_error` / `unauthenticated` | Firebase service account JWT rejected | [No pushes arrive](#no-pushes-arrive-for-any-user) |
| `token_unregistered` / `token_invalid` | Per-device dead token | [Some users get pushes](#some-users-get-pushes-others-dont) |
| `fcm_quota` / `rate_limited` | FCM rate limiting | Rare; usually self-corrects. Check Firebase Console quotas. |
| `other` | Doesn't match any pattern — read the raw `error_message` | — |

**Step 3 — How long has it been bad?**

```sql
select date_trunc('hour', created_at) as bucket,
       count(*) filter (where status = 'sent')   as sent,
       count(*) filter (where status = 'failed') as failed
  from notification_delivery_log
 where created_at > now() - interval '24 hours'
 group by 1
 order by 1 desc;
```

A sharp transition point (e.g. "fine through 14:00, all failing from 15:00") almost always means a **server-side change**: APNs key rotated, service account credentials changed, Firebase project setting modified. If the transition lines up with a known deploy or admin change, that's your prime suspect.

---

## Where the Data Lives

Everything you need is in Supabase, plus a few Firebase / Apple Developer consoles for the credential side.

### Tables

- `notification_delivery_log` — append-only record of every push attempt. **Source of truth.** Columns: `notification_type`, `status` (`sent`/`failed`), `error_message`, `token_id`, `source_id`, `created_at`, `sent_by_user_id` (NULL for system pushes, populated for admin-initiated ones).
- `push_notification_tokens` — FCM tokens, one per device install. Columns: `token`, `is_active`, `last_used_at`, `device_identifier`.
- `activity_push_tokens` — ActivityKit (Live Activity) tokens. Separate pipeline; see Background.

### Admin observability views (defined in `shared-supabase/supabase/migrations/20260522120000_admin_push_observability.sql`)

- `admin_push_devices` — one row per token with 7-day health metrics
- `admin_push_deliveries` — joined delivery history, filterable
- `admin_push_health_by_type` — hourly buckets per notification_type
- `admin_push_error_patterns` — failures grouped by category

All four require `is_admin = true` on the calling user.

### Admin app dashboard

The admin app should surface the above views as a live dashboard. If the dashboard exists, **always check it first** — it has the time-series charts and category breakdowns pre-built. If it doesn't yet, the SQL queries above are the manual equivalents.

### Credential consoles

- **Apple Developer** — [developer.apple.com](https://developer.apple.com) → Certificates, IDs & Profiles → Keys. APNs Auth Keys live here.
- **Firebase Console** — [console.firebase.google.com](https://console.firebase.google.com) → `saturday-consumer-app` project → Project Settings → Cloud Messaging tab. APNs Auth Keys are uploaded here, paired with the Apple-side key by Key ID.
- **GCP Console** — [console.cloud.google.com](https://console.cloud.google.com) → `saturday-consumer-app` project → IAM & Admin. Service account roles live here.

### Supabase edge function secrets

```bash
supabase secrets list --workdir shared-supabase
```

Relevant secrets (FCM-related):

| Secret | Source | Expected value |
|---|---|---|
| `FIREBASE_PROJECT_ID` | Firebase service account JSON | `saturday-consumer-app` |
| `FIREBASE_CLIENT_EMAIL` | Firebase service account JSON | `firebase-adminsdk-*@saturday-consumer-app.iam.gserviceaccount.com` |
| `FIREBASE_PRIVATE_KEY` | Firebase service account JSON | PEM-encoded RSA private key (may contain `\n` escape sequences) |

For ActivityKit (separate pipeline): `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`. As of writing, these are **not set** — Live Activity pushes silently no-op.

The CLI only shows digests, not values. To verify a secret without reading the value, hash the expected value with `printf 'expected' | shasum -a 256` and compare. For example:

```bash
printf 'saturday-consumer-app' | shasum -a 256
# Should match the FIREBASE_PROJECT_ID digest
```

---

## Scenarios

### No pushes arrive for any user

**Symptom:** `notification_delivery_log` shows almost-100% failure rate across all `notification_type`s. The dominant `error_category` is `apns_env_mismatch`, `fcm_auth_error`, or `unauthenticated`.

**Root cause:** Server-side credential or configuration problem. Always affects every push identically.

**Triage in order:**

1. **Did anyone touch credentials recently?** Check Apple Developer Keys page, Firebase Console Cloud Messaging tab, and `supabase secrets` for recent updates. Match the timing against the transition point from triage step 3.

2. **If the category is `apns_env_mismatch`:** an APNs Auth Key in Firebase Console is scoped wrong. Go to Firebase → Project Settings → Cloud Messaging → Apple app config. Click into the active APNs Auth Key, then click through to Apple Developer Keys → click the key → look at the "Enabled Services" row at the bottom. It should read:

   > Apple Push Notifications service (APNs): Team scoped (All topics) **[Sandbox & Production]**

   If it says `[Sandbox]`, `[Production]`, or any other scope, the key cannot serve every install's tokens. **Fix: [Create a new APNs Auth Key](#create-a-new-apns-auth-key)** unscoped, upload it to Firebase, delete the old one. Pushes resume within minutes.

3. **If the category is `fcm_auth_error` / `unauthenticated`:** the Firebase service account credentials are wrong. Verify the three Supabase secrets match the values in the service account JSON:

   ```bash
   # Expected: digest of "saturday-consumer-app"
   printf 'saturday-consumer-app' | shasum -a 256
   # Compare to FIREBASE_PROJECT_ID digest from `supabase secrets list`
   ```

   Repeat for `client_email`. The `private_key` is harder to verify by hash (the value contains escape sequences); if the other two match, the most likely problem is the private key not pairing with the client_email (i.e. you have an old key but a new client_email, or vice versa).

   **Fix: [Rotate the Firebase service account](#rotate-the-firebase-service-account)**.

4. **If the category is `other` or you can't tell:** read the raw `error_message` of the latest failure. Google the FCM error code (e.g. `PERMISSION_DENIED`, `INTERNAL`). FCM v1 API reference: `https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode`.

### Some users get pushes, others don't

**Symptom:** Mix of `status='sent'` and `status='failed'` in `notification_delivery_log`. Failures are clustered on specific `token_id`s rather than spread evenly. Dominant error category is `token_unregistered` or `token_invalid`.

**Root cause:** Per-device dead tokens. Normal background attrition (users uninstall apps, switch devices, reset their phones) plus some genuine bugs (FCM cache staleness after a Firebase project change).

**This is mostly self-healing now.** The fixes from May 2026:

- `send-fcm-push.ts` marks tokens with `tokenShouldDeactivate=true` for `token_unregistered` / `token_invalid` / `apns_env_mismatch` errors → `is_active=false` on the row.
- `register-push-token` returns `should_refresh=true` when re-registering a same-string dead token → the app's `PushTokenService` calls `forceRefresh()` to mint a new one.

If a specific user is complaining and the auto-recovery isn't kicking in:

```sql
select id, is_active, last_used_at, updated_at,
       (select count(*) from notification_delivery_log ndl
         where ndl.token_id = pnt.id and ndl.status='failed'
           and ndl.created_at > now() - interval '24 hours') as failures_24h
  from push_notification_tokens pnt
 where user_id = '<user uuid>';
```

If `is_active=false` and `failures_24h > 0`, the auto-rotation will trigger on the user's next app launch. If they're not opening the app, you can force it via [Force a single device's token to refresh](#force-a-single-devices-token-to-refresh).

### Pushes were working, then stopped suddenly

**Symptom:** Clean transition point in the time-series. Healthy through hour N, ~100% failure from hour N+1 onward.

This is **always a server-side change**, even when it doesn't feel like one. Walk through possibilities in order of frequency:

1. **APNs Auth Key in Firebase was rotated or expired.** Check Firebase Console → Cloud Messaging tab. If the key was uploaded recently or has changed Key ID since the outage started, that's it.
2. **APNs Auth Key scope changed.** Apple lets you edit a key's enabled services. If someone (or you, weeks earlier) clicked through the Edit Key flow and inadvertently scoped it, this presents as a sudden outage *for production-token installs* the moment a build with the production entitlement rolls out. The May 2026 outage was this exact shape.
3. **Build entitlement changed.** A new app build with different `aps-environment` in entitlements mints tokens of the wrong environment for the existing key. Check `ios/Runner/*.entitlements` for changes around the transition.
4. **Firebase service account key rotated or revoked.** Less common — usually deliberate. Confirm via the digests check or by trying to mint a fresh JWT manually.
5. **GCP project setting changed.** Cloud Messaging API disabled, service account IAM role revoked. Check IAM & Admin.

The transition point timestamp is your best evidence. Compare to: git log on the consumer-app branch (build changes), Apple Developer audit log (Keys section), Firebase Console activity log (Settings → Project Settings → bottom).

### Token keeps getting deactivated

**Symptom:** A specific token toggles `is_active` back and forth — deactivated by push failures, reactivated by the app on launch, deactivated again on next push attempt. Persists across multiple sessions.

**Root cause:** FCM-side cache stickiness. The iOS SDK keeps returning the same token string after `deleteToken()` because the underlying APNs registration hasn't actually been invalidated at iOS's level. This happens occasionally after APNs Auth Key rotations.

**Auto-rotation handling:** `register-push-token` returns `should_refresh=true` for same-string registrations against an `is_active=false` row, and the app calls `forceRefresh()` in response. If FCM hands back the **same dead string**, the app logs `"FCM may be returning a cached token; reinstall may be required"` and stops looping.

**When auto-rotation can't recover, escalate to: [Recover from a stuck FCM token (full reinstall)](#recover-from-a-stuck-fcm-token-full-reinstall).**

### Live Activity widget not updating

**Symptom:** The lock-screen "Now Playing" widget doesn't tick forward, doesn't reflect side changes, doesn't dismiss when playback stops.

**This is a different pipeline.** Live Activities use **direct APNs** (`api.push.apple.com`), not FCM. The edge function is `update-track-progression`, which uses `_shared/send-activity-push.ts`, which reads `APNS_KEY_ID` / `APNS_TEAM_ID` / `APNS_PRIVATE_KEY` / `APNS_BUNDLE_ID` from Supabase secrets.

As of writing, **none of those secrets are configured**, so the function short-circuits with `"APNs not configured, skipping push"` on every tick. Live Activities have never worked.

Until those secrets are set, this isn't actually a regression — it's an unfinished feature. See [Background → ActivityKit path](#activitykit-path-not-firefighting-yet).

---

## Runbooks

### Create a new APNs Auth Key

Use when the existing key is environment-scoped, expired, or compromised. The key Apple gives you here is paired in Firebase by Key ID.

1. Go to [developer.apple.com](https://developer.apple.com) → Certificates, IDs & Profiles → **Keys** → **+** (top right).
2. **Name:** Something descriptive like `Saturday FCM Key 2026-05`.
3. **Key Services:** Check **Apple Push Notifications service (APNs)**.
4. **Critical scope step:** when the APNs configuration UI appears, leave it as the default — **All environments / Sandbox & Production**. Do **NOT** click the "Sandbox only" or "Production only" radio buttons. The default unscoped behavior is what you want.
5. **Continue → Register.**
6. **Download the `.p8` file** to a temp directory. You can only download once.
7. Note the **Key ID** (10-character alphanumeric, e.g. `5ZL6MQ8N5K`) and your **Team ID** (10-character, e.g. `6WQAHJU2PD`).
8. Go to [console.firebase.google.com](https://console.firebase.google.com) → `saturday-consumer-app` → Project Settings → **Cloud Messaging** tab → **Apple app configuration** → APNs Authentication Key section.
9. **If an existing key is present:** click the trash icon to delete it. (Confirm in step 11 that the new one works before relying on this delete being permanent.)
10. Click **Upload**, select the `.p8`, enter the Key ID and Team ID. Save.
11. Verify with a test push from the admin app, or:
    ```bash
    # Place a record on a hub OR
    # Send a known test via the admin send-test-notification function
    ```
    Check `notification_delivery_log` for the resulting `status='sent'` row.
12. **Delete the `.p8` file from your local machine** (`shred -u key.p8` or equivalent). Apple won't let you re-download, but the file should not linger.

### Rotate the Firebase service account

Use when service account credentials are suspected wrong (digest mismatch), compromised, or being rotated as routine hygiene.

1. Go to [console.firebase.google.com](https://console.firebase.google.com) → `saturday-consumer-app` → Project Settings → **Service Accounts** tab.
2. Scroll to the Firebase Admin SDK section. Click **Generate new private key**. Confirm.
3. A JSON file downloads. Open it in a text editor.
4. Set all three Supabase secrets:
   ```bash
   # Write the values to a temp env file (single-quoted so \n escapes are preserved)
   TMPFILE=$(mktemp)
   chmod 600 "$TMPFILE"
   cat > "$TMPFILE" <<'EOF'
   FIREBASE_PROJECT_ID='saturday-consumer-app'
   FIREBASE_CLIENT_EMAIL='firebase-adminsdk-XXXXX@saturday-consumer-app.iam.gserviceaccount.com'
   FIREBASE_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----\nMII...\n-----END PRIVATE KEY-----\n'
   EOF
   supabase secrets set --env-file "$TMPFILE" --workdir shared-supabase
   rm -P "$TMPFILE" 2>/dev/null || rm "$TMPFILE"
   ```
   Replace the placeholders with values from the JSON. The `\n` sequences in the private key must be preserved literally — `send-fcm-push.ts` converts them to real newlines at runtime via `.replace(/\\n/g, '\n')`.
5. Verify the secrets changed:
   ```bash
   supabase secrets list --workdir shared-supabase | grep FIREBASE
   ```
   The digest column should change for any value that was previously different. If a digest is unchanged, that value was already correct — fine.
6. Wait ~30 seconds for edge function instances to pick up the new secrets (cold start), then test with an admin test push.
7. **Delete the downloaded JSON file from your local machine.** Service account private keys grant full FCM-send permission for the project.
8. Optionally, in Firebase Console → Service Accounts → at the bottom, **revoke the previous key** if you can identify it. (If you just regenerated, the new one is in use; the old one is still valid until you revoke.)

### Force a single device's token to refresh

Use when one user's token is dead and they're not opening the app to trigger auto-rotation.

You can't push to a phone that's not running, so the practical options are limited. From most to least invasive:

1. **Ask the user to open the app.** `PushTokenService.initialize()` runs on launch, and the `should_refresh` server signal will trigger auto-rotation. Often the simplest fix.
2. **If they're an internal admin user:** they can open the app, go to Account → Admin section → **Push Token** → tap **Refresh**. Same effect, manual.
3. **Manually unblock the row** so the next launch picks up cleanly:
   ```sql
   update push_notification_tokens
      set is_active = true
    where id = '<token uuid>';
   ```
   This is a band-aid — if the underlying token is truly dead, the next push attempt will deactivate it again. But it lets you confirm whether the issue is the token (re-deactivation will happen) or the credential path (push succeeds, problem was the inactive flag).

### Recover from a stuck FCM token (full reinstall)

Use when [Token keeps getting deactivated](#token-keeps-getting-deactivated) and auto-rotation logs `"FCM may be returning a cached token; reinstall may be required"`.

The iOS SDK is caching the token at a layer below `deleteToken()`. The only reliable reset is at the install level.

1. On the affected device: long-press the app icon → **Remove App → Delete App**. *Not* "Remove from Home Screen" — those are different. Deleting the app invalidates the underlying APNs registration.
2. Reinstall via TestFlight, App Store, or `flutter run --release` depending on the user's install method.
3. On launch, the app mints a brand-new FCM token tied to a brand-new FID (Firebase Installation ID). The DB row will get a fresh `token` string.
4. Verify in the Push Token dialog (admin builds) that the prefix has changed.
5. Wait ~2 minutes (new FCM tokens take a moment to propagate through Google's infra), then test a push.

This is the nuclear option. It works every time. The reason it's last in the runbook is that for end users, you have to convince them to do it.

---

## Diagnostic Queries

Copy-pasteable. Adjust user IDs / token IDs / time windows as needed.

```sql
-- Last hour by type and status
select notification_type, status, count(*), max(created_at) as latest
  from notification_delivery_log
 where created_at > now() - interval '1 hour'
 group by 1, 2;

-- Failure categories, last 24 hours
select * from admin_push_error_patterns
 where last_seen > now() - interval '24 hours'
 order by n desc;

-- Worst-offender tokens this week
select token_id, count(*) as failures,
       max(error_message) as sample_error
  from notification_delivery_log
 where status = 'failed' and created_at > now() - interval '7 days'
 group by 1
 order by failures desc
 limit 20;

-- Hourly trend (look for transition points)
select date_trunc('hour', created_at) as bucket,
       count(*) filter (where status = 'sent')   as sent,
       count(*) filter (where status = 'failed') as failed
  from notification_delivery_log
 where created_at > now() - interval '48 hours'
 group by 1 order by 1 desc;

-- All push tokens for a specific user
select id, platform, device_identifier, app_version, is_active,
       last_used_at, created_at,
       (select count(*) from notification_delivery_log
         where token_id = pnt.id and status='failed'
           and created_at > now() - interval '24h') as failures_24h
  from push_notification_tokens pnt
 where user_id = '<user uuid>'
 order by last_used_at desc;

-- Recent failures for a specific token (read the error_message)
select created_at, notification_type, error_message
  from notification_delivery_log
 where token_id = '<token uuid>' and status = 'failed'
 order by created_at desc
 limit 20;

-- Compare an expected value against a stored secret digest
-- (replace 'saturday-consumer-app' with whatever you want to verify)
-- printf 'saturday-consumer-app' | shasum -a 256
-- Then compare to FIREBASE_PROJECT_ID's digest from `supabase secrets list`
```

---

## Tools and Where They Live

| Tool | Where | What it's for |
|---|---|---|
| Admin dashboard | Admin app, push observability section | Live view of `admin_push_*` views; first place to look |
| Push Token dialog | Consumer app, Account → Admin section (admin email gate) | See and copy the current FCM token; force-rotate it |
| `send-test-notification` edge function | `shared-supabase/supabase/functions/send-test-notification` | Admin-initiated test push to a specific token. Reproduces a real send through the production code path. |
| `retry-notification` edge function | `shared-supabase/supabase/functions/retry-notification` | Re-send a specific historical delivery (v1 supports `now_playing`) |
| `register-push-token` edge function | `shared-supabase/supabase/functions/register-push-token` | App-called registration. Returns `should_refresh` to trigger auto-rotation when needed. |
| `_shared/send-fcm-push.ts` | `shared-supabase/supabase/functions/_shared/` | The single primitive every FCM-sending function uses. Owns error categorization. |

---

## Background

### Why two tables for push tokens

- `push_notification_tokens` — FCM tokens for alert pushes (banner / lock screen). One per device install.
- `activity_push_tokens` — ActivityKit tokens for updating an iOS Live Activity. One per Live Activity instance (not per device).

Different lifecycles, different pipelines, different credentials. Cannot share a table without bending one out of shape.

### Why two pipelines for push

- **FCM v1 (alerts)**: edge function mints OAuth2 JWT → POSTs to `fcm.googleapis.com/v1/projects/<id>/messages:send` → Firebase delivers via APNs. Uses the APNs Auth Key uploaded in Firebase Console.
- **Direct APNs (Live Activities)**: edge function mints an APNs JWT → POSTs to `api.push.apple.com/3/device/<token>`. Uses the `.p8` key directly via the `APNS_*` Supabase secrets.

Live Activities use a different APNs topic and payload shape (`<bundle>.push-type.liveactivity`, `content-state` JSON). Firebase can't proxy them, so they bypass it.

### ActivityKit path (not firefighting, yet)

`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID` Supabase secrets are unset. Until configured, `update-track-progression` short-circuits to `"APNs not configured, skipping push"` and `activity_push_tokens` accumulates rows that nothing ever delivers to.

To configure: reuse the same `.p8` you uploaded to Firebase (the unscoped one). Run:

```bash
TMPFILE=$(mktemp) && chmod 600 "$TMPFILE" && cat > "$TMPFILE" <<'EOF'
APNS_KEY_ID='5ZL6MQ8N5K'
APNS_TEAM_ID='6WQAHJU2PD'
APNS_BUNDLE_ID='com.saturdayvinyl.consumer'
APNS_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n'
EOF
supabase secrets set --env-file "$TMPFILE" --workdir shared-supabase
rm -P "$TMPFILE" 2>/dev/null || rm "$TMPFILE"
```

Once configured, Live Activity delivery becomes part of the firefighting surface and should be added to the diagnostic queries above.

### The May 2026 outage, in one paragraph

The original APNs Auth Key was created with the "Sandbox only" scope. As long as installs minted sandbox tokens (Xcode debug, certain dev builds), pushes worked. When release-mode installs started minting production tokens around 2026-05-14, the key couldn't serve them and Firebase returned `BadEnvironmentKeyInToken` (wrapped in a generic `THIRD_PARTY_AUTH_ERROR`). The edge function's error-handler at the time only deactivated tokens for substrings `"invalid"` and `"unregistered"`, so `BadEnvironmentKeyInToken` slipped through and pushes were retried every minute for 6 days, accumulating ~7,250 failures against a single token. Diagnosis was complicated by FCM-side cache stickiness that kept handing the iOS SDK the same dead token even after key replacement; only a full app uninstall reset the cache. Resilience changes that came out of this: broadened error categorization in `_shared/send-fcm-push.ts`, the admin observability surface, the `should_refresh` signal in `register-push-token`, this playbook.

---

## Related

- **Protocol:** [Playback Event Protocol](../protocols/playback_event_protocol.md) — the canonical model that drives the `now_playing` push payload via `now_playing_events` (placement) and `playback_sessions` (listening session).
- **Concept:** [Data Model](../concepts/data_model.md) — `users`, `units`, `push_notification_tokens` relationships.
- **Code:** `shared-supabase/supabase/functions/_shared/send-fcm-push.ts` — error categorization rules.
- **Migration:** `shared-supabase/supabase/migrations/20260522120000_admin_push_observability.sql` — observability views.

---

## Version History

| Version | Date | Changes |
|---|---|---|
| 1.0.0 | 2026-05-25 | Initial publication after the May 2026 push outage. Documents the FCM pipeline, scenarios, runbooks for APNs Auth Key and service account rotation, and the `should_refresh` auto-rotation mechanism. |
