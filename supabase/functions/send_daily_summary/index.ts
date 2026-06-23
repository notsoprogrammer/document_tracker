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
          data: { type: 'daily_summary' },
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

    // Philippine Standard Time offset: UTC+8
    const PHT_OFFSET_MS = 8 * 60 * 60 * 1000
    const nowUtc = Date.now()
    const nowPht = new Date(nowUtc + PHT_OFFSET_MS)
    const todayPhtStr = nowPht.toISOString().slice(0, 10) // 'YYYY-MM-DD'

    // Today's window in UTC
    const todayStartUtc = new Date(`${todayPhtStr}T00:00:00+08:00`).toISOString()
    const todayEndUtc   = new Date(`${todayPhtStr}T23:59:59+08:00`).toISOString()

    // Fetch today's activities
    const { data: activities } = await supabase
      .from('activities')
      .select('title, start_time')
      .gte('start_time', todayStartUtc)
      .lte('start_time', todayEndUtc)
      .order('start_time', { ascending: true })

    // Fetch documents with calendar deadline today
    const { data: calendarDocs } = await supabase
      .from('documents')
      .select('title, calendar_deadline')
      .gte('calendar_deadline', todayStartUtc)
      .lte('calendar_deadline', todayEndUtc)

    const actCount  = activities?.length  ?? 0
    const docCount  = calendarDocs?.length ?? 0
    const total     = actCount + docCount

    if (total === 0) {
      return new Response(
        JSON.stringify({ message: 'No events today, skipping daily summary' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const notifTitle = total === 1 ? '1 Event Today' : `${total} Events Today`
    const firstEvent = activities?.[0]?.title ?? calendarDocs?.[0]?.title ?? 'Event'
    const notifBody  = total === 1 ? firstEvent : `${firstEvent} and ${total - 1} more`

    // Get all FCM tokens
    const { data: tokens } = await supabase.from('device_tokens').select('token')
    if (!tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({ message: 'No device tokens' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // @ts-ignore
    const serviceAccountJson = Deno.env.get('SERVICE_ACCOUNT_JSON')
    if (!serviceAccountJson) throw new Error('SERVICE_ACCOUNT_JSON secret not found')
    const serviceAccount: ServiceAccount = JSON.parse(serviceAccountJson)
    const accessToken = await getAccessToken(serviceAccount)

    const results = []
    for (const { token } of tokens) {
      const result = await sendFCMNotification(
        accessToken, serviceAccount.project_id, token, notifTitle, notifBody
      )
      results.push(result)
    }

    return new Response(
      JSON.stringify({ message: 'Daily summary sent', total, results }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('send_daily_summary error:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
