/**
 * AES-256-GCM encryption helpers for Thread credentials.
 *
 * Plaintext credentials never touch the database. The adopt_device edge function
 * encrypts each sensitive field before INSERT; get_thread_credentials and friends
 * decrypt before returning to the authenticated caller over TLS.
 *
 * Storage layout per ciphertext bytea: [12-byte IV][ciphertext+auth tag].
 *
 * The encryption key is provided via the THREAD_ENCRYPTION_KEY environment
 * variable (set with `supabase secrets set THREAD_ENCRYPTION_KEY=<hex>`).
 * Generate with `openssl rand -hex 32`.
 */

const IV_BYTES = 12

let cachedKey: CryptoKey | null = null

async function getKey(): Promise<CryptoKey> {
  if (cachedKey) return cachedKey
  const keyHex = Deno.env.get('THREAD_ENCRYPTION_KEY')
  if (!keyHex) {
    throw new Error('THREAD_ENCRYPTION_KEY environment variable is not set')
  }
  const keyBytes = hexToBytes(keyHex)
  if (keyBytes.length !== 32) {
    throw new Error(`THREAD_ENCRYPTION_KEY must be 32 bytes (64 hex chars), got ${keyBytes.length}`)
  }
  cachedKey = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'AES-GCM' },
    false,
    ['encrypt', 'decrypt'],
  )
  return cachedKey
}

export async function encryptToBytea(plaintext: string): Promise<Uint8Array> {
  const key = await getKey()
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES))
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    new TextEncoder().encode(plaintext),
  )
  const out = new Uint8Array(IV_BYTES + ciphertext.byteLength)
  out.set(iv, 0)
  out.set(new Uint8Array(ciphertext), IV_BYTES)
  return out
}

export async function decryptFromBytea(blob: Uint8Array): Promise<string> {
  if (blob.length <= IV_BYTES) {
    throw new Error('Ciphertext blob too short')
  }
  const key = await getKey()
  const iv = blob.slice(0, IV_BYTES)
  const ciphertext = blob.slice(IV_BYTES)
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    ciphertext,
  )
  return new TextDecoder().decode(plaintext)
}

/**
 * Postgres bytea over PostgREST comes back as a hex string prefixed with `\x`
 * when using the JS client. Convert to Uint8Array for decryption.
 */
export function pgByteaToUint8(value: string | Uint8Array): Uint8Array {
  if (value instanceof Uint8Array) return value
  if (typeof value === 'string' && value.startsWith('\\x')) {
    return hexToBytes(value.slice(2))
  }
  throw new Error(`Unsupported bytea representation: ${typeof value}`)
}

/**
 * For INSERT/UPDATE via supabase-js, bytea is sent as a hex string `\x...`.
 */
export function uint8ToPgBytea(bytes: Uint8Array): string {
  return '\\x' + bytesToHex(bytes)
}

export function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) throw new Error('Invalid hex string length')
  const out = new Uint8Array(hex.length / 2)
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.substr(i * 2, 2), 16)
  }
  return out
}

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
}
