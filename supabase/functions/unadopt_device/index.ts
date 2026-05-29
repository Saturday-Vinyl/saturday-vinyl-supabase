/**
 * Edge Function: unadopt_device
 * Project: sv-hub-firmware
 * Description: Releases a Saturday device from a user account, revoking any
 *              device session tokens.
 *
 * Supersedes: unclaim-unit (this function does the unit unclaim plus device
 * session revocation).
 *
 * Notes:
 *   - The user's thread_networks row is preserved. Other devices on the
 *     account's network may still depend on those credentials. The row is
 *     only removed when the user (and the FK ON DELETE CASCADE) is deleted.
 *   - The unadopted Hub itself should clear its NVS state via the firmware
 *     consumer_reset command, which also issues H2_CLEAR_CREDENTIALS over
 *     UART.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders, jsonResponse } from '../_shared/cors.ts'
import { getAdminClient, resolveCaller } from '../_shared/auth.ts'
import { revokeDeviceSession } from '../_shared/device_sessions.ts'

interface UnadoptRequest {
  mac_address?: string
  serial_number?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const admin = getAdminClient()
    const caller = await resolveCaller(req, admin)
    if (!caller) {
      return jsonResponse({ error: 'unauthenticated' }, 401)
    }
    if (caller.kind !== 'user') {
      return jsonResponse({ error: 'user_auth_required' }, 403)
    }

    const body = await readJson<UnadoptRequest>(req)
    if (!body || (!body.mac_address && !body.serial_number)) {
      return jsonResponse(
        { error: 'mac_address or serial_number required' },
        400,
      )
    }

    // Resolve unit + device.
    let unit: any | null = null
    let device: any | null = null

    if (body.mac_address) {
      const { data: d } = await admin
        .from('devices')
        .select('id, unit_id')
        .eq('mac_address', body.mac_address)
        .maybeSingle()
      device = d
      if (!device?.unit_id) {
        return jsonResponse({ error: 'device_not_found' }, 404)
      }
      const { data: u } = await admin
        .from('units')
        .select('id, consumer_user_id')
        .eq('id', device.unit_id)
        .maybeSingle()
      unit = u
    } else {
      const { data: u } = await admin
        .from('units')
        .select('id, consumer_user_id')
        .eq('serial_number', body.serial_number)
        .maybeSingle()
      unit = u
      if (unit) {
        const { data: d } = await admin
          .from('devices')
          .select('id, unit_id')
          .eq('unit_id', unit.id)
          .maybeSingle()
        device = d ?? null
      }
    }

    if (!unit) {
      return jsonResponse({ error: 'device_not_found' }, 404)
    }
    if (unit.consumer_user_id !== caller.databaseUserId) {
      return jsonResponse({ error: 'not_owner' }, 403)
    }

    // Clear unit ownership.
    const { error: unitErr } = await admin
      .from('units')
      .update({
        consumer_user_id: null,
        status: 'factory_provisioned',
      })
      .eq('id', unit.id)
    if (unitErr) {
      console.error('unit unclaim error', unitErr)
      return jsonResponse({ error: 'unclaim_failed' }, 500)
    }

    // Clear device consumer-provisioning fields.
    if (device) {
      const { error: devErr } = await admin
        .from('devices')
        .update({
          consumer_provisioned_at: null,
          consumer_provisioned_by: null,
        })
        .eq('id', device.id)
      if (devErr) {
        console.error('device clear error', devErr)
      }

      // Revoke any active session for this device.
      await revokeDeviceSession(admin, device.id)
    }

    return jsonResponse({ ok: true })
  } catch (err) {
    console.error('unadopt_device unexpected error', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})

async function readJson<T>(req: Request): Promise<T | null> {
  try {
    return await req.json() as T
  } catch {
    return null
  }
}
