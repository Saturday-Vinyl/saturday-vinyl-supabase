// Edge Function: send-library-invitation
// Sends invitation emails for library sharing
//
// This function:
// 1. Validates the authenticated user is library owner
// 2. Creates the invitation record via database function
// 3. Sends invitation email via Resend
// 4. Returns the invitation details

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface SendInvitationRequest {
  library_id: string
  email: string
  role: 'editor' | 'viewer'
}

interface InvitationResponse {
  id: string
  token: string
  invited_email: string
  role: string
  expires_at: string
  library_name: string
}

interface DbUser {
  id: string
  full_name: string | null
  email: string
}

interface Invitation {
  id: string
  library_id: string
  invited_email: string
  invited_user_id: string | null
  role: string
  status: string
  token: string
  invited_by: string
  created_at: string
  expires_at: string
  accepted_at: string | null
  finalized_user_id: string | null
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const resendApiKey = Deno.env.get('RESEND_API_KEY')

    // Authenticate user
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create client with user's token for auth verification
    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false }
    })

    const { data: { user }, error: authError } = await authClient.auth.getUser()
    if (authError || !user) {
      console.error('Auth error:', authError)
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get request body
    const body: SendInvitationRequest = await req.json()
    const { library_id, email, role } = body

    console.log('Received invitation request:', { library_id, email, role, auth_user_id: user.id })

    // Validate required fields
    if (!library_id || !email || !role) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: library_id, email, role' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate role
    if (!['editor', 'viewer'].includes(role)) {
      return new Response(
        JSON.stringify({ error: 'Invalid role. Must be "editor" or "viewer"' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate email format
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/
    if (!emailRegex.test(email)) {
      return new Response(
        JSON.stringify({ error: 'Invalid email format' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Use service role for database operations
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false }
    })

    // Get user's database ID (from auth_user_id)
    const { data: dbUser, error: userError } = await supabase
      .from('users')
      .select('id, full_name, email')
      .eq('auth_user_id', user.id)
      .single() as { data: DbUser | null; error: Error | null }

    if (userError || !dbUser) {
      console.error('User lookup error:', userError)
      return new Response(
        JSON.stringify({ error: 'User not found in database' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('Found database user:', { id: dbUser.id, email: dbUser.email })

    // Create invitation using database function
    // This function validates ownership, checks for duplicates, etc.
    const { data: invitation, error: inviteError } = await supabase
      .rpc('create_library_invitation', {
        p_library_id: library_id,
        p_email: email.toLowerCase().trim(),
        p_role: role,
        p_invited_by: dbUser.id
      }) as { data: Invitation | null; error: Error | null }

    if (inviteError) {
      console.error('Invitation creation error:', inviteError)
      return new Response(
        JSON.stringify({ error: inviteError.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!invitation) {
      return new Response(
        JSON.stringify({ error: 'Failed to create invitation' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('Created invitation:', { id: invitation.id, token: invitation.token })

    // Get library name for email
    const { data: library } = await supabase
      .from('libraries')
      .select('name')
      .eq('id', library_id)
      .single()

    const libraryName = library?.name || 'a vinyl library'

    // Build the deep link URL
    const deepLink = `https://app.saturdayvinyl.com/invite/${invitation.token}`

    // Send invitation email if Resend is configured
    if (resendApiKey) {
      try {
        await sendInvitationEmail({
          to: email,
          inviterName: dbUser.full_name || dbUser.email,
          libraryName: libraryName,
          role: role,
          deepLink: deepLink,
          apiKey: resendApiKey
        })
        console.log('Invitation email sent successfully to:', email)
      } catch (emailError) {
        // Log but don't fail - invitation was created successfully
        console.error('Failed to send invitation email:', emailError)
      }
    } else {
      console.log('RESEND_API_KEY not configured, skipping email')
      console.log('Would send invitation to:', email, 'with link:', deepLink)
    }

    // Return the invitation details
    const response: InvitationResponse = {
      id: invitation.id,
      token: invitation.token,
      invited_email: invitation.invited_email,
      role: invitation.role,
      expires_at: invitation.expires_at,
      library_name: libraryName
    }

    return new Response(
      JSON.stringify(response),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function sendInvitationEmail(params: {
  to: string
  inviterName: string
  libraryName: string
  role: string
  deepLink: string
  apiKey: string
}): Promise<void> {
  const roleDescription = params.role === 'editor'
    ? 'view and edit albums in'
    : 'view albums in'

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${params.apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Saturday Vinyl <noreply@saturdayvinyl.com>',
      to: params.to,
      subject: `${params.inviterName} invited you to "${params.libraryName}"`,
      html: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Library Invitation</title>
</head>
<body style="margin: 0; padding: 0; background-color: #E2DAD0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;">
  <table role="presentation" style="width: 100%; border-collapse: collapse;">
    <tr>
      <td align="center" style="padding: 40px 20px;">
        <table role="presentation" style="max-width: 600px; width: 100%; background-color: #ffffff; border-radius: 16px; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">
          <!-- Header -->
          <tr>
            <td style="padding: 40px 40px 20px; text-align: center;">
              <h1 style="margin: 0; color: #3F3A34; font-size: 28px; font-weight: 700;">
                You're Invited!
              </h1>
            </td>
          </tr>

          <!-- Content -->
          <tr>
            <td style="padding: 20px 40px;">
              <p style="margin: 0 0 20px; color: #3F3A34; font-size: 16px; line-height: 1.6;">
                <strong>${escapeHtml(params.inviterName)}</strong> has invited you to ${roleDescription}
                their vinyl library "<strong>${escapeHtml(params.libraryName)}</strong>" on Saturday.
              </p>

              <p style="margin: 0 0 30px; color: #666666; font-size: 14px; line-height: 1.6;">
                Saturday is the app for vinyl enthusiasts to manage their record collections,
                track what's playing, and discover new music.
              </p>
            </td>
          </tr>

          <!-- CTA Button -->
          <tr>
            <td style="padding: 0 40px 30px; text-align: center;">
              <a href="${params.deepLink}"
                 style="display: inline-block; background-color: #3F3A34; color: #ffffff; padding: 16px 32px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">
                Accept Invitation
              </a>
            </td>
          </tr>

          <!-- Expiry Notice -->
          <tr>
            <td style="padding: 0 40px 30px;">
              <p style="margin: 0; color: #999999; font-size: 13px; text-align: center;">
                This invitation expires in 7 days.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding: 20px 40px; border-top: 1px solid #E2DAD0;">
              <p style="margin: 0; color: #999999; font-size: 12px; text-align: center; line-height: 1.5;">
                If you didn't expect this invitation, you can safely ignore this email.
                <br><br>
                <a href="https://saturdayvinyl.com" style="color: #3F3A34;">Saturday Vinyl</a>
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
      `.trim(),
      text: `
${params.inviterName} invited you to "${params.libraryName}"

${params.inviterName} has invited you to ${roleDescription} their vinyl library "${params.libraryName}" on Saturday.

Saturday is the app for vinyl enthusiasts to manage their record collections, track what's playing, and discover new music.

Accept the invitation by opening this link:
${params.deepLink}

This invitation expires in 7 days.

If you didn't expect this invitation, you can safely ignore this email.
      `.trim()
    }),
  })

  if (!response.ok) {
    const errorText = await response.text()
    throw new Error(`Resend API error: ${response.status} - ${errorText}`)
  }
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}
