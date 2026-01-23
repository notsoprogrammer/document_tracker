import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface Document {
  code: string
  title: string
  compliance_deadline: string
  compliance_assignee: string | null
}

interface Token {
  token: string
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

// Generate JWT for Firebase authentication using proper RSA signing
async function generateJWT(serviceAccount: ServiceAccount): Promise<string> {
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: serviceAccount.token_uri,
    exp: now + 3600, // 1 hour
    iat: now,
  }

  // Base64url encode header and payload
  const headerB64 = btoa(JSON.stringify(header))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')

  const payloadB64 = btoa(JSON.stringify(payload))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')

  // Create the signing input
  const signingInput = `${headerB64}.${payloadB64}`

  // Import the private key for signing
  const privateKeyPem = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')

  // Convert base64 PEM to ArrayBuffer
  const privateKeyDer = Uint8Array.from(atob(privateKeyPem), c => c.charCodeAt(0))

  // Import the key using Web Crypto API
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    privateKeyDer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  )

  // Sign the input
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput)
  )

  // Base64url encode the signature
  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')

  return `${headerB64}.${payloadB64}.${signatureB64}`
}

// Get access token from Google
async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const jwt = await generateJWT(serviceAccount)

  const response = await fetch(serviceAccount.token_uri, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  const data = await response.json()
  return data.access_token
}

// Send FCM notification using HTTP v1 API
async function sendFCMNotification(accessToken: string, projectId: string, token: string, title: string, body: string): Promise<any> {
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  const payload = {
    message: {
      token: token,
      notification: {
        title: title,
        body: body,
      },
    },
  }

  const response = await fetch(fcmUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  })

  return await response.json()
}

serve(async (req: Request) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Initialize Supabase client
    // @ts-ignore: Deno is available in Supabase Edge Functions
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    )

    // Get current time in UTC (adjust for Philippine time if needed)
    const now = new Date()
    const oneDayFromNow = new Date(now.getTime() + 24 * 60 * 60 * 1000)

    // Query all documents with compliance deadlines
    const { data: documents, error: docError } = await supabaseClient
      .from('documents')
      .select('code, title, compliance_deadline, compliance_assignee')
      .eq('status', 'For Compliance')
      .not('compliance_deadline', 'is', null)

    if (docError) {
      throw docError
    }

    // Get all FCM tokens
    const { data: tokens, error: tokenError } = await supabaseClient
      .from('device_tokens')
      .select('token')

    if (tokenError) {
      throw tokenError
    }

    if (!tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({ message: 'No device tokens found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const tokenList: string[] = tokens.map((t: Token) => t.token)

    // Get Firebase service account from secrets
    // @ts-ignore: Deno is available in Supabase Edge Functions
    const serviceAccountJson = Deno.env.get('SERVICE_ACCOUNT_JSON')
    if (!serviceAccountJson) {
      throw new Error('SERVICE_ACCOUNT_JSON secret not found')
    }

    const serviceAccount: ServiceAccount = JSON.parse(serviceAccountJson)

    // Get access token
    const accessToken = await getAccessToken(serviceAccount)

    const notificationsSent: any[] = []

    for (const doc of (documents as Document[]) || []) {
      const deadline = new Date(doc.compliance_deadline.replace(' ', 'T') + 'Z')
      const timeDiff = deadline.getTime() - now.getTime()
      const hoursDiff = timeDiff / (1000 * 60 * 60)

      let notificationType = ''
      let title = ''
      let body = ''

      if (hoursDiff > 24) {
        continue // Skip if more than 1 day away
      } else if (hoursDiff > 1) {
        // Future deadline within 24 hours, more than 1 hour away
        if (hoursDiff <= 5) {
          notificationType = '5_hours_reminder'
          title = '📑 Compliance Reminder'
          body = `Document ${doc.code} is due in ${Math.round(hoursDiff)} hours.`
        } else {
          notificationType = '1_day_reminder'
          title = '📑 Compliance Reminder'
          body = `Document ${doc.code} is due in ${Math.round(hoursDiff / 24)} day(s).`
        }
      } else if (hoursDiff > -24) {
        // Overdue within 1 day
        notificationType = 'overdue_hours'
        title = '🚨 Compliance Overdue'
        body = `Document ${doc.code} is overdue by ${Math.round(-hoursDiff)} hours.`
      } else {
        // Overdue by more than 1 day
        notificationType = 'overdue_days'
        title = '🚨 Compliance Overdue'
        body = `Document ${doc.code} is overdue by ${Math.round(-hoursDiff / 24)} days.`
      }

      // Check if a notification of this type was sent in the last 24 hours
      const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000)
      const { data: recentNotifications, error: recentError } = await supabaseClient
        .from('notifications_history')
        .select('id')
        .eq('document_code', doc.code)
        .eq('notification_type', notificationType)
        .gte('created_at', twentyFourHoursAgo.toISOString())
        .limit(1)

      if (recentError) {
        console.error('Error checking recent notifications:', recentError)
        continue
      }

      if (recentNotifications && recentNotifications.length > 0) {
        console.log(`Skipping notification for ${doc.code} type ${notificationType}, already sent recently`)
        continue
      }

      // Send FCM notification to each token individually
      const fcmResponses = []
      for (const token of tokenList) {
        const fcmResponse = await sendFCMNotification(accessToken, serviceAccount.project_id, token, title, body)
        fcmResponses.push(fcmResponse)
        console.log('FCM Response for token:', fcmResponse)
      }

      notificationsSent.push({
        documentCode: doc.code,
        type: notificationType,
        title: title,
        body: body,
        fcmResponses: fcmResponses,
      })

      // Log notification history
      await supabaseClient
        .from('notifications_history')
        .insert({
          document_code: doc.code,
          notification_type: notificationType,
          notification_id: Math.floor(Date.now() / 1000), // Unique integer ID (seconds since epoch)
          scheduled_time: deadline.toISOString(),
          status: 'sent',
        })
    }

    return new Response(
      JSON.stringify({
        message: 'Compliance notifications sent',
        count: notificationsSent.length,
        notifications: notificationsSent
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }
})
