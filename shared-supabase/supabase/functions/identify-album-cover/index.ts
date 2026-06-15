/**
 * Edge Function: identify-album-cover
 * Project: saturday-mobile-app
 * Description: Identifies an album from a photo of its cover using Claude's
 *              vision API. Keeps the Anthropic API key, model ID, and prompt
 *              server-side so any of them can change without an app release.
 *
 * Env vars:
 *   ANTHROPIC_API_KEY  (required)  Anthropic API key
 *   CLAUDE_VISION_MODEL (optional)  Model ID, default "claude-opus-4-8"
 *   CLAUDE_VISION_EFFORT (optional) "low" | "medium" | "high" | "max"
 *                                   Default "high" — sweet spot for vision.
 *                                   Drop to "medium" to cut cost.
 *
 * Request body:
 *   { image_base64: string, mime_type?: string }
 *
 * Response body (200):
 *   { artist: string, album: string, confidence: "high"|"medium"|"low"|"none" }
 *
 * The fields are always present. When the model cannot identify the album,
 * artist/album are empty strings and confidence is "none".
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

const DEFAULT_MODEL = 'claude-opus-4-8'
const DEFAULT_EFFORT = 'high'

const IDENTIFY_PROMPT = `You are identifying a vinyl record album cover from a photo a user just took.

The photo will typically show the record sleeve held in hand, on a table, on a shelf, or alongside other records — backgrounds vary widely (wood, fabric, painted walls, other album sleeves, lighting glare).

Steps:
1. Locate the album cover within the image. Ignore anything that isn't the front of the sleeve — table surface, other records, room context, hands, glare, reflections.
2. Identify the artist and album title from the front-cover artwork and text. The text on the cover itself is the strongest signal; do not infer from the surrounding context.
3. Decide a confidence level:
   - "high": you can clearly read the artist or title text on the cover, or recognize the artwork unambiguously.
   - "medium": the artwork is identifiable but the text is partly blurred, cropped, or at an angle.
   - "low": you are guessing from style/era/partial cues — say so honestly.
   - "none": you cannot determine the album. Return empty strings for artist and album.

If multiple albums are visible (e.g. a record being held in front of a shelf), identify only the one most prominently centered, held, or in focus.

Do not guess wildly. A "none" result is more useful than a confidently wrong one.`

const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    artist: { type: 'string' },
    album: { type: 'string' },
    confidence: {
      type: 'string',
      enum: ['high', 'medium', 'low', 'none'],
    },
  },
  required: ['artist', 'album', 'confidence'],
  additionalProperties: false,
}

interface IdentifyRequest {
  image_base64?: string
  mime_type?: string
}

interface AnthropicTextBlock {
  type: 'text'
  text: string
}
interface AnthropicThinkingBlock {
  type: 'thinking'
  thinking: string
}
type AnthropicContentBlock = AnthropicTextBlock | AnthropicThinkingBlock | {
  type: string
  [k: string]: unknown
}

interface AnthropicMessageResponse {
  content: AnthropicContentBlock[]
  stop_reason: string
  usage?: Record<string, number>
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return jsonError(401, 'Missing authorization header')
    }

    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY')
    if (!anthropicKey) {
      console.error('ANTHROPIC_API_KEY is not set')
      return jsonError(500, 'Vision service not configured')
    }

    const model = Deno.env.get('CLAUDE_VISION_MODEL') ?? DEFAULT_MODEL
    const effort = Deno.env.get('CLAUDE_VISION_EFFORT') ?? DEFAULT_EFFORT

    const body: IdentifyRequest = await req.json().catch(() => ({}))
    const imageBase64 = body.image_base64
    const mimeType = body.mime_type ?? 'image/jpeg'

    if (!imageBase64 || imageBase64.length === 0) {
      return jsonError(400, 'image_base64 is required')
    }

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
          // Headroom for adaptive thinking. The visible JSON is tiny (~80 tokens)
          // but thinking happens inside max_tokens.
          max_tokens: 4096,
          thinking: { type: 'adaptive' },
          output_config: {
            effort,
            format: {
              type: 'json_schema',
              schema: RESPONSE_SCHEMA,
            },
          },
          messages: [
            {
              role: 'user',
              content: [
                {
                  type: 'image',
                  source: {
                    type: 'base64',
                    media_type: mimeType,
                    data: imageBase64,
                  },
                },
                { type: 'text', text: IDENTIFY_PROMPT },
              ],
            },
          ],
        }),
      },
    )

    if (!anthropicResponse.ok) {
      const errorText = await anthropicResponse.text()
      console.error(
        `Anthropic API ${anthropicResponse.status}: ${errorText.slice(0, 500)}`,
      )
      if (anthropicResponse.status === 429) {
        return jsonError(429, 'Rate limit exceeded. Please try again.')
      }
      return jsonError(502, 'Vision identification failed')
    }

    const data = (await anthropicResponse.json()) as AnthropicMessageResponse

    if (data.stop_reason === 'refusal') {
      return jsonError(422, 'Image rejected by safety filter')
    }

    const textBlock = data.content.find(
      (b): b is AnthropicTextBlock => b.type === 'text',
    )
    if (!textBlock) {
      console.error(
        'No text block in Anthropic response:',
        JSON.stringify(data).slice(0, 500),
      )
      return jsonError(502, 'Vision identification returned no result')
    }

    // output_config.format guarantees parseable JSON matching the schema.
    let parsed: { artist: string; album: string; confidence: string }
    try {
      parsed = JSON.parse(textBlock.text)
    } catch (e) {
      console.error(
        'Failed to parse structured output:',
        textBlock.text.slice(0, 200),
        e,
      )
      return jsonError(502, 'Vision identification returned invalid JSON')
    }

    if (data.usage) {
      console.log(
        `model=${model} effort=${effort} usage=${JSON.stringify(data.usage)} confidence=${parsed.confidence}`,
      )
    }

    return new Response(JSON.stringify(parsed), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Unexpected error:', error)
    return jsonError(500, (error as Error).message)
  }
})

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
