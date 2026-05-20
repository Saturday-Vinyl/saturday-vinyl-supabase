/**
 * Edge Function: get_thread_credentials
 * Project: sv-hub-firmware
 * Description: Returns the caller's Thread mesh credentials. Read-only.
 *
 * Callers:
 *   - Hub firmware on boot for cache reconciliation (device access token).
 *   - Mobile app during Crate adoption to fetch credentials to write to the
 *     Crate over BLE (user JWT).
 *
 * Returns 404 with `no_thread_network` if the user has not yet adopted any
 * Hub - the network is created lazily by adopt_device on first Hub claim.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders, jsonResponse } from '../_shared/cors.ts'
import { getAdminClient, resolveCaller } from '../_shared/auth.ts'
import { decryptFromBytea, pgByteaToUint8 } from '../_shared/crypto.ts'

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

    const { data, error } = await admin
      .from('thread_networks')
      .select(
        'network_name, pan_id, channel, network_key_encrypted, extended_pan_id_encrypted, mesh_local_prefix_encrypted, pskc_encrypted',
      )
      .eq('user_id', caller.databaseUserId)
      .maybeSingle()

    if (error) {
      console.error('thread_networks read error', error)
      return jsonResponse({ error: 'read_failed' }, 500)
    }
    if (!data) {
      return jsonResponse({ error: 'no_thread_network' }, 404)
    }

    return jsonResponse({
      thread_credentials: {
        network_name: data.network_name,
        pan_id: data.pan_id,
        channel: data.channel,
        network_key: await decryptFromBytea(pgByteaToUint8(data.network_key_encrypted)),
        extended_pan_id: await decryptFromBytea(pgByteaToUint8(data.extended_pan_id_encrypted)),
        mesh_local_prefix: await decryptFromBytea(pgByteaToUint8(data.mesh_local_prefix_encrypted)),
        pskc: await decryptFromBytea(pgByteaToUint8(data.pskc_encrypted)),
      },
    })
  } catch (err) {
    console.error('get_thread_credentials unexpected error', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})
