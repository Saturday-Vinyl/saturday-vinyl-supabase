/**
 * Edge Function: digikey-search
 * Project: saturday-admin-app
 * Description: Proxies DigiKey Product Search API calls, handling token refresh automatically.
 *
 * Endpoints:
 *   POST /digikey-search/keyword   — Keyword search (general text query)
 *   POST /digikey-search/part      — Exact part number lookup
 *   POST /digikey-search/barcode   — Look up by DigiKey barcode fields (30P or 1P)
 *
 * All endpoints require Authorization header with a valid Supabase JWT.
 *
 * Environment variables:
 *   DIGIKEY_CLIENT_ID     — OAuth client ID
 *   DIGIKEY_CLIENT_SECRET — OAuth client secret
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const DIGIKEY_API_BASE = 'https://api.digikey.com'
const DIGIKEY_TOKEN_URL = 'https://api.digikey.com/v1/oauth2/token'

function jsonResponse(body: object, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  const url = new URL(req.url)
  const pathSegments = url.pathname.split('/').filter(Boolean)
  const action = pathSegments[pathSegments.length - 1]

  try {
    // Authenticate and get user's DigiKey token
    const userId = await getAuthenticatedUserId(req)
    if (!userId) return jsonResponse({ error: 'Unauthorized' }, 401)

    const token = await getValidAccessToken(userId)
    if (!token) {
      return jsonResponse({
        error: 'DigiKey not connected',
        code: 'NOT_CONNECTED',
        message: 'Connect your DigiKey account in Settings first.',
      }, 403)
    }

    const body = await req.json()

    switch (action) {
      case 'keyword':
        return handleKeywordSearch(token, body)
      case 'part':
        return handlePartLookup(token, body)
      case 'barcode':
        return handleBarcodeLookup(token, body)
      default:
        return jsonResponse({ error: 'Unknown action', valid: ['keyword', 'part', 'barcode'] }, 404)
    }
  } catch (err) {
    console.error('digikey-search error:', err)
    return jsonResponse({ error: err.message || 'Internal error' }, 500)
  }
})

// ============================================================================
// KEYWORD SEARCH: General text search
// ============================================================================
async function handleKeywordSearch(accessToken: string, body: { query: string; limit?: number }) {
  if (!body.query) {
    return jsonResponse({ error: 'Missing "query" field' }, 400)
  }

  const clientId = Deno.env.get('DIGIKEY_CLIENT_ID')!

  const response = await fetch(`${DIGIKEY_API_BASE}/products/v4/search/keyword`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'X-DIGIKEY-Client-Id': clientId,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      Keywords: body.query,
      RecordCount: body.limit || 10,
      RecordStartPosition: 0,
      ExcludeMarketPlaceProducts: true,
    }),
  })

  if (!response.ok) {
    const errText = await response.text()
    console.error('DigiKey keyword search failed:', response.status, errText)
    return jsonResponse({ error: 'DigiKey API error', status: response.status, detail: errText }, 502)
  }

  const data = await response.json()

  // Normalize to a simpler format for the Flutter client
  const results = (data.Products || []).map(normalizeProduct)

  return jsonResponse({
    results,
    total: data.ProductsCount || 0,
  })
}

// ============================================================================
// PART LOOKUP: Exact DigiKey part number
// ============================================================================
async function handlePartLookup(accessToken: string, body: { digikey_pn?: string; manufacturer_pn?: string }) {
  const clientId = Deno.env.get('DIGIKEY_CLIENT_ID')!

  if (body.digikey_pn) {
    // Direct product details by DigiKey part number
    const encoded = encodeURIComponent(body.digikey_pn)
    const response = await fetch(`${DIGIKEY_API_BASE}/products/v4/search/${encoded}/productdetails`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'X-DIGIKEY-Client-Id': clientId,
      },
    })

    if (!response.ok) {
      const errText = await response.text()
      if (response.status === 404) {
        return jsonResponse({ results: [], total: 0 })
      }
      return jsonResponse({ error: 'DigiKey API error', status: response.status, detail: errText }, 502)
    }

    const product = await response.json()
    return jsonResponse({
      results: [normalizeProduct(product.Product || product)],
      total: 1,
    })
  }

  if (body.manufacturer_pn) {
    // Search by manufacturer part number
    return handleKeywordSearch(accessToken, { query: body.manufacturer_pn, limit: 5 })
  }

  return jsonResponse({ error: 'Provide "digikey_pn" or "manufacturer_pn"' }, 400)
}

// ============================================================================
// BARCODE LOOKUP: Match parsed barcode fields
// ============================================================================
async function handleBarcodeLookup(
  accessToken: string,
  body: { distributor_pn?: string; manufacturer_pn?: string }
) {
  // Try distributor PN (30P field) first — most precise
  if (body.distributor_pn) {
    return handlePartLookup(accessToken, { digikey_pn: body.distributor_pn })
  }

  // Fall back to manufacturer PN (1P field)
  if (body.manufacturer_pn) {
    return handlePartLookup(accessToken, { manufacturer_pn: body.manufacturer_pn })
  }

  return jsonResponse({ error: 'Provide "distributor_pn" or "manufacturer_pn"' }, 400)
}

// ============================================================================
// TOKEN MANAGEMENT
// ============================================================================

async function getValidAccessToken(userId: string): Promise<string | null> {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const { data: tokenRow, error } = await supabase
    .from('supplier_api_tokens')
    .select('*')
    .eq('user_id', userId)
    .eq('provider', 'digikey')
    .maybeSingle()

  if (error || !tokenRow) return null

  // Check if token is expired (with 5-minute buffer)
  const expiresAt = tokenRow.token_expires_at
    ? new Date(tokenRow.token_expires_at)
    : null
  const isExpired = expiresAt
    ? expiresAt.getTime() - 5 * 60 * 1000 < Date.now()
    : false

  if (!isExpired) {
    return tokenRow.access_token
  }

  // Attempt refresh
  if (!tokenRow.refresh_token) {
    console.error('Token expired and no refresh token available')
    return null
  }

  console.log('DigiKey token expired, refreshing...')

  const clientId = Deno.env.get('DIGIKEY_CLIENT_ID')!
  const clientSecret = Deno.env.get('DIGIKEY_CLIENT_SECRET')!

  const refreshResponse = await fetch(DIGIKEY_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: tokenRow.refresh_token,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  })

  if (!refreshResponse.ok) {
    const errText = await refreshResponse.text()
    console.error('DigiKey token refresh failed:', errText)
    // Token is invalid — delete it so user re-authenticates
    await supabase
      .from('supplier_api_tokens')
      .delete()
      .eq('id', tokenRow.id)
    return null
  }

  const newTokens = await refreshResponse.json()

  const newExpiresAt = newTokens.expires_in
    ? new Date(Date.now() + newTokens.expires_in * 1000).toISOString()
    : null

  // Update stored tokens
  await supabase
    .from('supplier_api_tokens')
    .update({
      access_token: newTokens.access_token,
      refresh_token: newTokens.refresh_token || tokenRow.refresh_token,
      token_expires_at: newExpiresAt,
    })
    .eq('id', tokenRow.id)

  console.log('DigiKey token refreshed successfully')
  return newTokens.access_token
}

// ============================================================================
// HELPERS
// ============================================================================

async function getAuthenticatedUserId(req: Request): Promise<string | null> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return null

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  )

  const { data: { user }, error } = await userClient.auth.getUser()
  if (error || !user) return null

  const serviceClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  const { data: appUser } = await serviceClient
    .from('users')
    .select('id')
    .eq('auth_user_id', user.id)
    .single()

  return appUser?.id || null
}

/** Normalize a DigiKey product response to a flat, Flutter-friendly format.
 *  Supports both v3 and v4 API field naming conventions. */
function normalizeProduct(p: any) {
  // v4 nests description and puts DigiKey PN inside ProductVariations
  const desc = p.Description || {}
  const firstVariation = (p.ProductVariations || [])[0]

  // DigiKey PN: v4 puts it in ProductVariations[].DigiKeyProductNumber
  const digikeyPn = p.DigiKeyPartNumber
    || p.DigiKeyProductNumber
    || firstVariation?.DigiKeyProductNumber
    || null

  // Manufacturer PN: v4 uses ManufacturerProductNumber
  const manufacturerPn = p.ManufacturerPartNumber
    || p.ManufacturerProductNumber
    || null

  // Quantity: v4 puts it per-variation
  const quantityAvailable = p.QuantityAvailable
    ?? firstVariation?.QuantityAvailableforPackageType
    ?? null

  return {
    digikey_pn: digikeyPn,
    manufacturer_pn: manufacturerPn,
    manufacturer: p.Manufacturer?.Name || p.ManufacturerName || p.Manufacturer?.Value || null,
    description: desc.ProductDescription || p.ProductDescription || desc.DetailedDescription || p.DetailedDescription || null,
    unit_price: p.UnitPrice ?? null,
    quantity_available: quantityAvailable,
    category: p.Category?.Name || p.Category?.Value || null,
    family: p.Family?.Name || p.Family?.Value || p.Series?.Name || null,
    package: p.Packaging?.Name || p.Packaging?.Value || firstVariation?.PackageType?.Name || null,
    datasheet_url: p.DatasheetUrl || p.PrimaryDatasheet || null,
    product_url: p.ProductUrl || null,
    image_url: p.PhotoUrl || p.PrimaryPhoto || null,
    rohs_status: p.RohsStatus || null,
    lead_status: p.LeadStatus || null,
    parameters: (p.Parameters || []).map((param: any) => ({
      name: param.ParameterText || param.Parameter,
      value: param.ValueText || param.Value,
    })),
  }
}
