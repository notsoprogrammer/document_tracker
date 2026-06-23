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
async function sendFCMNotification(accessToken: string, projectId: string, token: string, title: string, body: string, type = 'immediate'): Promise<any> {
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  const payload = {
    message: {
      token: token,
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: type,
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

    // Parse request body for optional document_code
    let requestBody: { document_code?: string } = {}
    if (req.method === 'POST') {
      try {
        requestBody = await req.json()
      } catch (e) {
        // Ignore if no body or invalid JSON
      }
    }

    // Get current time in UTC (adjust for Philippine time if needed)
    const now = new Date()
    const oneDayFromNow = new Date(now.getTime() + 24 * 60 * 60 * 1000)

    // Query documents with compliance deadlines
    let query = supabaseClient
      .from('documents')
      .select('code, title, compliance_deadline, compliance_assignee')
      .eq('status', 'For Compliance')
      .not('compliance_deadline', 'is', null)

    // If document_code is provided, filter to that specific document
    if (requestBody.document_code) {
      query = query.eq('code', requestBody.document_code)
    }

    const { data: documents, error: docError } = await query

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
      let deadlineStr = doc.compliance_deadline;
      if (!deadlineStr || deadlineStr.trim() === '') {
        console.log('Empty deadline for doc', doc.code);
        continue;
      }
      console.log('Original deadlineStr:', deadlineStr);
      if (!deadlineStr.includes('T')) {
        deadlineStr = deadlineStr.replace(' ', 'T') + 'Z';
      }
      console.log('Processed deadlineStr:', deadlineStr);
      let deadline: Date;
      try {
        deadline = new Date(deadlineStr);
        if (isNaN(deadline.getTime())) {
          throw new Error('Invalid date');
        }
        console.log('Parsed deadline:', deadline);
      } catch (e) {
        console.error('Invalid deadline for doc', doc.code, deadlineStr, e);
        continue; // Skip this document
      }
      const timeDiff = deadline.getTime() - now.getTime()
      const hoursDiff = timeDiff / (1000 * 60 * 60)

      // Always send immediate notification reflecting current state
      const immediateTitle = 'Compliance Notification'
      const immediateBody = `A document to be complied by ${doc.compliance_assignee || 'Unknown'} has been set, check out the notification.`

      // Send FCM
      const fcmResponses = []
      for (const token of tokenList) {
        const fcmResponse = await sendFCMNotification(accessToken, serviceAccount.project_id, token, immediateTitle, immediateBody)
        fcmResponses.push(fcmResponse)
      }

      // Insert history
      await supabaseClient
        .from('notifications_history')
        .insert({
          document_code: doc.code,
          notification_type: 'immediate',
          notification_id: Math.floor(Date.now() / 1000),
          scheduled_time: deadline.toISOString(),
          status: 'sent',
        })

      notificationsSent.push({
        documentCode: doc.code,
        type: 'immediate',
        title: immediateTitle,
        body: immediateBody,
        fcmResponses: fcmResponses,
      })

      if (hoursDiff > 25) {
        // Nothing more to do until we're within the 24h window
      } else if (hoursDiff > 24) {
        // 24-hour reminder window (between 25h and 24h before deadline)
        const twentyFiveHoursAgo = new Date(now.getTime() - 25 * 60 * 60 * 1000)
        const { data: recent24h } = await supabaseClient
          .from('notifications_history')
          .select('id')
          .eq('document_code', doc.code)
          .eq('notification_type', 'twenty_four_hour_reminder')
          .gte('created_at', twentyFiveHoursAgo.toISOString())
          .limit(1)

        if (!recent24h || recent24h.length === 0) {
          const title = '📋 Deadline Tomorrow'
          const body = `Document ${doc.code} is due in about 24 hours. Assigned to: ${doc.compliance_assignee || 'Unknown'}.`

          const fcmResponses = []
          for (const token of tokenList) {
            const fcmResponse = await sendFCMNotification(accessToken, serviceAccount.project_id, token, title, body, 'twenty_four_hour')
            fcmResponses.push(fcmResponse)
          }

          await supabaseClient
            .from('notifications_history')
            .insert({
              document_code: doc.code,
              notification_type: 'twenty_four_hour_reminder',
              notification_id: Math.floor(Date.now() / 1000),
              scheduled_time: deadline.toISOString(),
              status: 'sent',
            })

          notificationsSent.push({
            documentCode: doc.code,
            type: 'twenty_four_hour_reminder',
            title,
            body,
            fcmResponses,
          })
        }
      } else if (hoursDiff > 6) {
        if (hoursDiff <= 24) {
          // Send 6_hours_reminder
          const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000)
          const { data: recent } = await supabaseClient
            .from('notifications_history')
            .select('id')
            .eq('document_code', doc.code)
            .eq('notification_type', '6_hours_reminder')
            .gte('created_at', twentyFourHoursAgo.toISOString())
            .limit(1)

          if (!recent || recent.length === 0) {
            const title = '📑 Compliance Reminder'
            const body = `Document ${doc.code} is due in 6 hours.`

            const fcmResponses = []
            for (const token of tokenList) {
              const fcmResponse = await sendFCMNotification(accessToken, serviceAccount.project_id, token, title, body, 'immediate')
              fcmResponses.push(fcmResponse)
            }

            await supabaseClient
              .from('notifications_history')
              .insert({
                document_code: doc.code,
                notification_type: '6_hours_reminder',
                notification_id: Math.floor(Date.now() / 1000),
                scheduled_time: deadline.toISOString(),
                status: 'sent',
              })

            notificationsSent.push({
              documentCode: doc.code,
              type: '6_hours_reminder',
              title: title,
              body: body,
              fcmResponses: fcmResponses,
            })
          }
        }
      } else if (hoursDiff > 0) {
        // Send due_soon
        const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000)
        const { data: recent } = await supabaseClient
          .from('notifications_history')
          .select('id')
          .eq('document_code', doc.code)
          .eq('notification_type', 'due_soon')
          .gte('created_at', twentyFourHoursAgo.toISOString())
          .limit(1)

        if (!recent || recent.length === 0) {
          const title = '📑 Compliance Reminder'
          const body = `Document ${doc.code} is due very soon.`

          const fcmResponses = []
          for (const token of tokenList) {
            const fcmResponse = await sendFCMNotification(accessToken, serviceAccount.project_id, token, title, body)
            fcmResponses.push(fcmResponse)
          }

          await supabaseClient
            .from('notifications_history')
            .insert({
              document_code: doc.code,
              notification_type: 'due_soon',
              notification_id: Math.floor(Date.now() / 1000),
              scheduled_time: deadline.toISOString(),
              status: 'sent',
            })

          notificationsSent.push({
            documentCode: doc.code,
            type: 'due_soon',
            title: title,
            body: body,
            fcmResponses: fcmResponses,
          })
        }
      } else {
        // Overdue
        const overdueHours = -hoursDiff
        if (overdueHours < 24) {
          const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000)
          const { data: recent } = await supabaseClient
            .from('notifications_history')
            .select('id')
            .eq('document_code', doc.code)
            .eq('notification_type', 'overdue_hours')
            .gte('created_at', twentyFourHoursAgo.toISOString())
            .limit(1)

          if (!recent || recent.length === 0) {
            const title = '🚨 Compliance Overdue'
            const body = `Document ${doc.code} is overdue by ${Math.ceil(overdueHours)} hours.`

            const fcmResponses = []
            for (const token of tokenList) {
              const fcmResponse = await sendFCMNotification(accessToken, serviceAccount.project_id, token, title, body, 'overdue')
              fcmResponses.push(fcmResponse)
            }

            await supabaseClient
              .from('notifications_history')
              .insert({
                document_code: doc.code,
                notification_type: 'overdue_hours',
                notification_id: Math.floor(Date.now() / 1000),
                scheduled_time: deadline.toISOString(),
                status: 'sent',
              })

            notificationsSent.push({
              documentCode: doc.code,
              type: 'overdue_hours',
              title: title,
              body: body,
              fcmResponses: fcmResponses,
            })
          }
        } else {
          const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000)
          const { data: recent } = await supabaseClient
            .from('notifications_history')
            .select('id')
            .eq('document_code', doc.code)
            .eq('notification_type', 'overdue_days')
            .gte('created_at', twentyFourHoursAgo.toISOString())
            .limit(1)

          if (!recent || recent.length === 0) {
            const title = '🚨 Compliance Overdue'
            const body = `Document ${doc.code} is overdue by ${Math.ceil(overdueHours / 24)} days.`

            const fcmResponses = []
            for (const token of tokenList) {
              const fcmResponse = await sendFCMNotification(accessToken, serviceAccount.project_id, token, title, body, 'overdue')
              fcmResponses.push(fcmResponse)
            }

            await supabaseClient
              .from('notifications_history')
              .insert({
                document_code: doc.code,
                notification_type: 'overdue_days',
                notification_id: Math.floor(Date.now() / 1000),
                scheduled_time: deadline.toISOString(),
                status: 'sent',
              })

            notificationsSent.push({
              documentCode: doc.code,
              type: 'overdue_days',
              title: title,
              body: body,
              fcmResponses: fcmResponses,
            })
          }
        }
      }
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
