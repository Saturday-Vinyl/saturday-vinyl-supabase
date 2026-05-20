/**
 * Thread credential generation.
 *
 * Called once per user account, at the first Hub adoption. The generated
 * credentials persist in the thread_networks row for that user and are reused
 * by every subsequent Hub adopted to the same account, so all of a user's Hubs
 * form a single Thread mesh.
 */

import { bytesToHex } from './crypto.ts'

export interface ThreadCredentials {
  network_name: string
  pan_id: number
  channel: number
  network_key: string         // 32 hex chars (128-bit)
  extended_pan_id: string     // 16 hex chars (64-bit)
  mesh_local_prefix: string   // 16 hex chars (64-bit)
  pskc: string                // 32 hex chars (128-bit)
}

/**
 * Generate a fresh Thread credential set for a user account.
 *
 * Defaults follow the conventions in shared-docs/protocols/device_command_protocol.md
 * and the values previously hard-coded in the H2 firmware.
 */
export function generateThreadCredentials(userIdShort: string): ThreadCredentials {
  return {
    network_name: `SV-${userIdShort.slice(0, 8).toUpperCase()}`,
    // Avoid 0x0000 (reserved) and 0xFFFF (broadcast).
    pan_id: 1 + cryptoRandomInt(0xFFFE),
    // Thread 2.4 GHz channels: 11-26 inclusive.
    channel: 11 + cryptoRandomInt(16),
    network_key: randomHex(16),       // 128-bit
    extended_pan_id: randomHex(8),    // 64-bit
    mesh_local_prefix: 'fd' + randomHex(7), // ULA prefix, must start with fd
    pskc: randomHex(16),              // 128-bit
  }
}

function randomHex(byteLen: number): string {
  return bytesToHex(crypto.getRandomValues(new Uint8Array(byteLen)))
}

function cryptoRandomInt(maxExclusive: number): number {
  // Rejection-sampling unbiased random in [0, maxExclusive).
  const range = maxExclusive
  const buf = new Uint32Array(1)
  const max = Math.floor(0xFFFFFFFF / range) * range
  while (true) {
    crypto.getRandomValues(buf)
    if (buf[0] < max) return buf[0] % range
  }
}
