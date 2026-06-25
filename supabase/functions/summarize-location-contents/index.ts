/**
 * Edge Function: summarize-location-contents
 * Project: saturday-admin-app
 * Description: Generates a short, human-readable "Contents" line for a storage
 *              location label (drawer / bin / shelf) from the parts currently
 *              stored there. Keeps the Anthropic API key, model, and prompt
 *              server-side so they can change without an app release.
 *
 * Env vars:
 *   ANTHROPIC_API_KEY     (required)  Anthropic API key
 *   CLAUDE_SUMMARY_MODEL  (optional)  Model ID, default "claude-opus-4-8"
 *   CLAUDE_SUMMARY_EFFORT (optional)  "low" | "medium" | "high" | "max"
 *                                     Default "low" — this is a tiny summary.
 *
 * Request body:
 *   {
 *     parts: Array<{
 *       name: string,
 *       part_number?: string,
 *       category?: string,
 *       quantity?: number
 *     }>,
 *     location_name?: string   // optional context, e.g. "Cabinet A3 · Drawer 14"
 *   }
 *
 * Response body (200):
 *   { summary: string }   // empty string when there's nothing to summarize
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const DEFAULT_MODEL = 'claude-opus-4-8'
const DEFAULT_EFFORT = 'low'

const SYSTEM_PROMPT =
  `You write the "Contents" line printed on a small physical label for a storage drawer/bin in a furniture-and-electronics workshop. ` +
  `You are given the parts currently stored in that location. ` +
  `Write ONE short phrase (a noun phrase, ideally 3-7 words, hard max ~40 characters) that tells a worker at a glance what lives there. ` +
  `Group similar parts rather than listing every one; favour the dominant category or theme. ` +
  `No trailing punctuation, no quotes, no "Contents:" prefix, no counts unless a count is the point. ` +
  `Title case or sentence case, not ALL CAPS. If the parts don't form a clear theme, name the most prominent items.`

const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
  },
  required: ['summary'],
  additionalProperties: false,
}

interface PartInput {
  name?: string
  part_number?: string
  category?: string
  quantity?: number
}

interface SummaryRequest {
  parts?: PartInput[]
  location_name?: string
}

interface AnthropicMessageResponse {
  content?: Array<{ type: string; text?: string }>
  stop_reason?: string
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY')
    if (!anthropicKey) {
      console.error('ANTHROPIC_API_KEY is not set')
      return jsonResponse({ error: 'Server is not configured' }, 500)
    }

    const model = Deno.env.get('CLAUDE_SUMMARY_MODEL') ?? DEFAULT_MODEL
    const effort = Deno.env.get('CLAUDE_SUMMARY_EFFORT') ?? DEFAULT_EFFORT

    const body: SummaryRequest = await req.json().catch(() => ({}))
    const parts = (body.parts ?? []).filter(
      (p) => p && typeof p.name === 'string' && p.name.trim().length > 0,
    )

    // Nothing to summarize — return an empty string rather than an error so the
    // caller can simply leave the Contents line blank.
    if (parts.length === 0) {
      return jsonResponse({ summary: '' })
    }

    const lines = parts.map((p) => {
      const bits = [p.name!.trim()]
      if (p.category) bits.push(`[${p.category}]`)
      if (typeof p.quantity === 'number') bits.push(`x${p.quantity}`)
      return `- ${bits.join(' ')}`
    })

    const userText =
      (body.location_name ? `Location: ${body.location_name}\n` : '') +
      `Parts stored here:\n${lines.join('\n')}`

    const anthropicResponse = await fetch(
      'https://api.anthropic.com/v1/messages',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': anthropicKey,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({
          model,
          max_tokens: 256,
          output_config: {
            effort,
            format: { type: 'json_schema', schema: RESPONSE_SCHEMA },
          },
          system: SYSTEM_PROMPT,
          messages: [{ role: 'user', content: userText }],
        }),
      },
    )

    if (!anthropicResponse.ok) {
      const errorText = await anthropicResponse.text()
      console.error(
        `Anthropic API ${anthropicResponse.status}: ${errorText.slice(0, 500)}`,
      )
      if (anthropicResponse.status === 429) {
        return jsonResponse(
          { error: 'Rate limit exceeded. Please try again.' },
          429,
        )
      }
      return jsonResponse({ error: 'Contents summary failed' }, 502)
    }

    const data = (await anthropicResponse.json()) as AnthropicMessageResponse

    if (data.stop_reason === 'refusal') {
      return jsonResponse({ error: 'Request rejected by safety filter' }, 422)
    }

    const text = (data.content ?? [])
      .filter((b) => b.type === 'text' && typeof b.text === 'string')
      .map((b) => b.text as string)
      .join('')
      .trim()

    let summary = ''
    try {
      const parsed = JSON.parse(text) as { summary?: string }
      summary = (parsed.summary ?? '').trim()
    } catch (_) {
      // The structured-output format guarantees JSON; if parsing somehow fails,
      // fall back to the raw text so the worker still gets something usable.
      summary = text
    }

    // Strip stray wrapping quotes/punctuation a model occasionally adds.
    summary = summary.replace(/^["'`]+|["'`.]+$/g, '').trim()

    return jsonResponse({ summary })
  } catch (err) {
    console.error('summarize-location-contents error:', err)
    return jsonResponse({ error: 'Unexpected error' }, 500)
  }
})
