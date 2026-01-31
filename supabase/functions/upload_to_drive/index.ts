import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get the service account key from environment variables
    const serviceAccountKey = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_KEY')
    if (!serviceAccountKey) {
      throw new Error('GOOGLE_SERVICE_ACCOUNT_KEY environment variable not set')
    }

    const credentials = JSON.parse(serviceAccountKey)

    // Get access token
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: await createJWT(credentials),
      }),
    })

    const tokenData = await tokenResponse.json()
    const accessToken = tokenData.access_token

    // Parse request body
    const { fileName, fileData, folderId, mimeType } = await req.json()

    // Upload to Google Drive
    const driveResponse = await fetch(`https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'multipart/related; boundary=boundary123',
      },
      body: createMultipartBody(fileName, fileData, folderId, mimeType),
    })

    const driveResult = await driveResponse.json()

    if (driveResult.id) {
      // Make the file public
      await fetch(`https://www.googleapis.com/drive/v3/files/${driveResult.id}/permissions`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          role: 'reader',
          type: 'anyone',
        }),
      })

      return new Response(
        JSON.stringify({
          success: true,
          fileId: driveResult.id,
          publicUrl: `https://drive.google.com/uc?id=${driveResult.id}`,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        },
      )
    } else {
      throw new Error('Failed to upload file to Google Drive')
    }

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      },
    )
  }
})

async function createJWT(credentials: any) {
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: credentials.client_email,
    scope: 'https://www.googleapis.com/auth/drive.file',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }

  const encoder = new TextEncoder()
  const headerB64 = btoa(JSON.stringify(header))
  const payloadB64 = btoa(JSON.stringify(payload))

  const message = `${headerB64}.${payloadB64}`

  const privateKey = credentials.private_key.replace(/\\n/g, '\n')

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    await crypto.subtle.importKey(
      'pkcs8',
      pemToDer(privateKey),
      {
        name: 'RSASSA-PKCS1-v1_5',
        hash: 'SHA-256',
      },
      false,
      ['sign']
    ),
    encoder.encode(message)
  )

  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))

  return `${message}.${signatureB64}`
}

function pemToDer(pem: string) {
  const pemHeader = '-----BEGIN PRIVATE KEY-----'
  const pemFooter = '-----END PRIVATE KEY-----'
  const pemContents = pem.replace(pemHeader, '').replace(pemFooter, '').replace(/\s/g, '')
  return Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))
}

function createMultipartBody(fileName: string, fileData: string, folderId: string, mimeType: string) {
  const boundary = 'boundary123'
  const metadata = {
    name: fileName,
    parents: [folderId],
  }

  let body = `--${boundary}\r\n`
  body += 'Content-Type: application/json; charset=UTF-8\r\n\r\n'
  body += JSON.stringify(metadata) + '\r\n'
  body += `--${boundary}\r\n`
  body += `Content-Type: ${mimeType}\r\n\r\n`
  body += fileData + '\r\n'
  body += `--${boundary}--`

  return body
}
