/**
 * Edge Function: adopt_device
 * Project: sv-hub-firmware
 * Description: Claims a Saturday device for a user account, ensures the user
 *              has a Thread network, and optionally issues device-scoped
 *              session tokens for Hub firmware.
 *
 * Supersedes: claim-unit (this function does the unit claim plus the new
 * Thread-credential and device-session work).
 *
 * Callers:
 *   - Mobile app, with the user's Supabase JWT, identifying the device by
 *     `serial_number` (typical) or `mac_address`. Used for any Saturday device
 *     (Hub, Crate, Speaker). `issue_device_tokens` is typically false/omitted
 *     for Thread-only devices that don't talk to the cloud directly.
 *
 *   - Hub firmware itself during BLE adoption, with the user JWT it received
 *     over BLE characteristic 0x0030. Identifies itself by `mac_address` and
 *     sets `issue_device_tokens: true` so it receives access/refresh tokens
 *     for its own future authenticated cloud calls.
 *
 * Behavior:
 *   1. Validate user JWT, resolve users.id.
 *   2. Resolve unit by mac_address or serial_number.
 *   3. Claim unit if unclaimed; verify ownership if already claimed.
 *   4. Find-or-create the user's thread_networks row, generating fresh
 *      AES-256-GCM-encrypted credentials when creating.
 *   5. Optionally issue a device_sessions row (Hub flow).
 *   6. Return decrypted Thread credentials + optional device tokens.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders, jsonResponse } from '../_shared/cors.ts'
import { getAdminClient, resolveCaller } from '../_shared/auth.ts'
import {
  encryptToBytea,
  decryptFromBytea,
  pgByteaToUint8,
  uint8ToPgBytea,
} from '../_shared/crypto.ts'
import {
  generateThreadCredentials,
  ThreadCredentials,
} from '../_shared/thread_creds.ts'
import { issueDeviceSession } from '../_shared/device_sessions.ts'

interface AdoptRequest {
  mac_address?: string
  serial_number?: string
  issue_device_tokens?: boolean
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
      // adopt_device is initiated by a user; a device-token caller would mean
      // an already-adopted Hub is trying to adopt something, which we don't
      // support.
      return jsonResponse({ error: 'user_auth_required' }, 403)
    }

    const body = await readJson<AdoptRequest>(req)
    if (!body || (!body.mac_address && !body.serial_number)) {
      return jsonResponse(
        { error: 'mac_address or serial_number required' },
        400,
      )
    }

    // ------------------------------------------------------------------
    // Resolve the unit and its linked device row (if any).
    // ------------------------------------------------------------------
    const unitLookup = await resolveUnit(admin, body)
    if (!unitLookup) {
      return jsonResponse({ error: 'device_not_factory_provisioned' }, 404)
    }
    const { unit, device } = unitLookup

    // ------------------------------------------------------------------
    // Verify or claim ownership.
    // ------------------------------------------------------------------
    if (unit.consumer_user_id && unit.consumer_user_id !== caller.databaseUserId) {
      return jsonResponse({ error: 'device_owned_by_another_user' }, 403)
    }

    if (!unit.consumer_user_id) {
      const { error: claimErr } = await admin
        .from('units')
        .update({
          consumer_user_id: caller.databaseUserId,
          status: 'claimed',
        })
        .eq('id', unit.id)
      if (claimErr) {
        console.error('claim error', claimErr)
        return jsonResponse({ error: 'claim_failed' }, 500)
      }
    }

    if (device) {
      const { error: provErr } = await admin
        .from('devices')
        .update({
          consumer_provisioned_at: new Date().toISOString(),
          consumer_provisioned_by: caller.databaseUserId,
        })
        .eq('id', device.id)
      if (provErr) {
        console.error('device update error', provErr)
        // Non-fatal; the claim succeeded.
      }
    }

    // ------------------------------------------------------------------
    // Find-or-create the user's thread_networks row.
    // ------------------------------------------------------------------
    const threadCreds = await ensureThreadNetwork(admin, caller.databaseUserId)

    // ------------------------------------------------------------------
    // Optionally issue device session tokens (Hub flow).
    // ------------------------------------------------------------------
    let deviceTokens: Awaited<ReturnType<typeof issueDeviceSession>> | undefined
    if (body.issue_device_tokens) {
      if (!device) {
        return jsonResponse(
          { error: 'device_required_for_token_issuance' },
          400,
        )
      }
      deviceTokens = await issueDeviceSession(admin, device.id, caller.authUserId)
    }

    return jsonResponse({
      unit: {
        id: unit.id,
        serial_number: unit.serial_number,
        status: 'claimed',
      },
      thread_credentials: threadCreds,
      device_tokens: deviceTokens,
    })
  } catch (err) {
    console.error('adopt_device unexpected error', err)
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

async function resolveUnit(
  admin: ReturnType<typeof getAdminClient>,
  body: AdoptRequest,
): Promise<{ unit: any; device: any | null } | null> {
  if (body.mac_address) {
    const { data: device } = await admin
      .from('devices')
      .select('id, unit_id, mac_address, consumer_provisioned_at')
      .eq('mac_address', body.mac_address)
      .maybeSingle()
    if (!device || !device.unit_id) return null
    const { data: unit } = await admin
      .from('units')
      .select('id, serial_number, consumer_user_id, status')
      .eq('id', device.unit_id)
      .maybeSingle()
    if (!unit) return null
    return { unit, device }
  }

  // serial_number path
  const { data: unit } = await admin
    .from('units')
    .select('id, serial_number, consumer_user_id, status')
    .eq('serial_number', body.serial_number)
    .maybeSingle()
  if (!unit) return null

  // Fetch the linked device row if it exists (some unit types may not have one).
  const { data: device } = await admin
    .from('devices')
    .select('id, unit_id, mac_address, consumer_provisioned_at')
    .eq('unit_id', unit.id)
    .maybeSingle()

  return { unit, device: device ?? null }
}

async function ensureThreadNetwork(
  admin: ReturnType<typeof getAdminClient>,
  databaseUserId: string,
): Promise<ThreadCredentials> {
  // Try to fetch existing network.
  const { data: existing } = await admin
    .from('thread_networks')
    .select(
      'network_name, pan_id, channel, network_key_encrypted, extended_pan_id_encrypted, mesh_local_prefix_encrypted, pskc_encrypted',
    )
    .eq('user_id', databaseUserId)
    .maybeSingle()

  if (existing) {
    return {
      network_name: existing.network_name,
      pan_id: existing.pan_id,
      channel: existing.channel,
      network_key: await decryptFromBytea(pgByteaToUint8(existing.network_key_encrypted)),
      extended_pan_id: await decryptFromBytea(pgByteaToUint8(existing.extended_pan_id_encrypted)),
      mesh_local_prefix: await decryptFromBytea(pgByteaToUint8(existing.mesh_local_prefix_encrypted)),
      pskc: await decryptFromBytea(pgByteaToUint8(existing.pskc_encrypted)),
    }
  }

  // Generate a fresh credential set for this user.
  const fresh = generateThreadCredentials(databaseUserId)

  const { error } = await admin.from('thread_networks').insert({
    user_id: databaseUserId,
    network_name: fresh.network_name,
    pan_id: fresh.pan_id,
    channel: fresh.channel,
    network_key_encrypted: uint8ToPgBytea(await encryptToBytea(fresh.network_key)),
    extended_pan_id_encrypted: uint8ToPgBytea(await encryptToBytea(fresh.extended_pan_id)),
    mesh_local_prefix_encrypted: uint8ToPgBytea(await encryptToBytea(fresh.mesh_local_prefix)),
    pskc_encrypted: uint8ToPgBytea(await encryptToBytea(fresh.pskc)),
  })

  if (error) {
    // Race: another concurrent adoption inserted first. Retry the read.
    if (error.code === '23505') {
      return ensureThreadNetwork(admin, databaseUserId)
    }
    throw new Error(`thread_networks insert failed: ${error.message}`)
  }

  return fresh
}
