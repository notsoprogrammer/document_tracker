import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ServiceAccount {
  type: string
  project_id: string
  private_key_id: string
  private_key: string
  client_email: string
  client_id: string
  auth_uri: string
  token_uri: string
  auth_provider_x509_cert_url: string
  client_x509_cert_url: string
  universe_domain: string
}

async function generateJWT(serviceAccount: ServiceAccount): Promise<string> {
  const header = { alg: 'RS256', typ: 'JWT' }
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: serviceAccount.token_uri,
    exp: now + 3600,
    iat: now,
  }
  const encode = (obj: object) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
  const signingInput = `${encode(header)}.${encode(payload)}`
  const privateKeyPem = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')
  const privateKeyDer = Uint8Array.from(atob(privateKeyPem), c => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8', privateKeyDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign']
  )
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signingInput))
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
  return `${signingInput}.${sigB64}`
}

async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const jwt = await generateJWT(serviceAccount)
  const response = await fetch(serviceAccount.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  const data = await response.json()
  return data.access_token
}

async function sendFCMNotification(
  accessToken: string, projectId: string, token: string,
  title: string, body: string
): Promise<any> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: { type: 'assignment' },
        },
      }),
    }
  )
  return await response.json()
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // @ts-ignore
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // Find pending notifications whose notify_at has passed
    const { data: pending, error } = await supabase
      .from('pending_assignment_notifications')
      .select('*')
      .lte('notify_at', new Date().toISOString())
      .eq('sent', false)

    if (error) throw error
    if (!pending || pending.length === 0) {
      return new Response(
        JSON.stringify({ message: 'No pending assignment notifications' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // @ts-ignore
    const serviceAccountJson = Deno.env.get('SERVICE_ACCOUNT_JSON')
    if (!serviceAccountJson) throw new Error('SERVICE_ACCOUNT_JSON secret not found')
    const serviceAccount: ServiceAccount = JSON.parse(serviceAccountJson)
    const accessToken = await getAccessToken(serviceAccount)

    const results = []

    for (const notif of pending) {
      const assignees: string[] = notif.assignees ?? []
      const docCode: string = notif.document_code
      const docTitle: string = notif.document_title ?? 'Document'

      // Look up FCM tokens for these specific assignees
      const { data: tokenRows } = await supabase
        .from('device_tokens')
        .select('token')
        .in('username', assignees)

      const tokens: string[] = (tokenRows ?? []).map((r: any) => r.token)

      const fcmResults = []
      for (const token of tokens) {
        const result = await sendFCMNotification(
          accessToken,
          serviceAccount.project_id,
          token,
          'Document Assigned to You',
          `${docTitle} (${docCode}) has been addressed to you.`,
        )
        fcmResults.push(result)
      }

      // Mark as sent
      await supabase
        .from('pending_assignment_notifications')
        .update({ sent: true })
        .eq('id', notif.id)

      results.push({ id: notif.id, docCode, assignees, fcmResults })
    }

    return new Response(
      JSON.stringify({ message: 'Assignment notifications sent', results }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('send_assignment_notification error:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
