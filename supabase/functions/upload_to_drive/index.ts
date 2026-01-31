import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Access secrets in your Edge Function
    const projectId = Deno.env.get("GOOGLE_PROJECT_ID");
    const clientEmail = Deno.env.get("GOOGLE_CLIENT_EMAIL");
    const privateKey = Deno.env.get("GOOGLE_PRIVATE_KEY")?.replace(/\\n/g, "\n");
    const tokenUri = Deno.env.get("GOOGLE_TOKEN_URI");

    if (!projectId || !clientEmail || !privateKey || !tokenUri) {
      throw new Error("Missing Google service account environment variables");
    }

    const credentials = {
      type: "service_account",
      project_id: projectId,
      private_key_id: "4f6f1b0f8bb9f2de4b7e3a55fa6b0721bb3dc1bb",
      private_key: privateKey,
      client_email: clientEmail,
      client_id: "100439715314966147294",
      auth_uri: "https://accounts.google.com/o/oauth2/auth",
      token_uri: tokenUri,
      auth_provider_x509_cert_url: "https://www.googleapis.com/oauth2/v1/certs",
      client_x509_cert_url: `https://www.googleapis.com/robot/v1/metadata/x509/${encodeURIComponent(clientEmail)}`,
      universe_domain: "googleapis.com"
    };

    // Create JWT for Google OAuth2
    const jwt = await createJWT(credentials);

    // Exchange JWT for access token
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    });

    const tokenData = await tokenResponse.json();
    if (!tokenData.access_token) {
      throw new Error(`Failed to get access token: ${JSON.stringify(tokenData)}`);
    }
    const accessToken = tokenData.access_token;

    // Parse request body
    const { fileName, fileData, folderId, mimeType } = await req.json();

    // Upload to Google Drive
  const driveResponse = await fetch(
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "multipart/related; boundary=boundary123",
      },
      body: createMultipartBody(fileName, fileData, folderId, mimeType),
    },
  );

    if (!driveResponse.ok) {
      const text = await driveResponse.text();
      throw new Error(`Drive upload failed: ${text}`);
    }

    const driveResult = await driveResponse.json();

    // Make file public
    await fetch(
      `https://www.googleapis.com/drive/v3/files/${driveResult.id}/permissions`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ role: "reader", type: "anyone" }),
      },
    );

    return new Response(
      JSON.stringify({
        success: true,
        fileId: driveResult.id,
        publicUrl: `https://drive.google.com/uc?id=${driveResult.id}`,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
    );
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
    );
  }
});

// --- Helpers ---

async function createJWT(credentials: any) {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: credentials.client_email,
    scope: "https://www.googleapis.com/auth/drive.file",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encoder = new TextEncoder();
  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(payload));
  const message = `${headerB64}.${payloadB64}`;

  const privateKey = credentials.private_key.replace(/\\n/g, "\n");
  const keyData = pemToDer(privateKey);

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", cryptoKey, encoder.encode(message));
  const signatureB64 = base64urlBytes(new Uint8Array(signature));

  return `${message}.${signatureB64}`;
}

function pemToDer(pem: string) {
  const pemContents = pem.replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  return Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
}

function base64url(str: string) {
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlBytes(bytes: Uint8Array) {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function createMultipartBody(fileName: string, fileData: string, folderId: string, mimeType: string) {
  const boundary = "boundary123";
  const metadata = { name: fileName, parents: [folderId] };

  const encoder = new TextEncoder();
  const fileBytes = Uint8Array.from(atob(fileData), (c) => c.charCodeAt(0));

  const parts: Uint8Array[] = [];
  parts.push(encoder.encode(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n`));
  parts.push(encoder.encode(JSON.stringify(metadata) + "\r\n"));
  parts.push(encoder.encode(`--${boundary}\r\nContent-Type: ${mimeType}\r\n\r\n`));
  parts.push(fileBytes);
  parts.push(encoder.encode(`\r\n--${boundary}--`));

  const totalLength = parts.reduce((sum, p) => sum + p.length, 0);
  const body = new Uint8Array(totalLength);
  let offset = 0;
  for (const p of parts) {
    body.set(p, offset);
    offset += p.length;
  }
  return body;
}