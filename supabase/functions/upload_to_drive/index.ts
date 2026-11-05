import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Base64 inflates binary by ~33%, so this caps the real file at ~8MB.
const MAX_FILE_DATA_CHARS = 11 * 1024 * 1024;

// Google access tokens are valid for an hour. Minting a fresh JWT on every
// upload added a needless round-trip (and latency) to each request, so cache
// it across invocations of a warm instance.
let cachedToken: { token: string; expiresAt: number } | null = null;

async function getAccessToken(credentials: any, tokenUri: string) {
  const now = Date.now();
  // Refresh a minute early to avoid racing the expiry.
  if (cachedToken && cachedToken.expiresAt > now + 60_000) {
    return cachedToken.token;
  }

  const jwt = await createJWT(credentials);
  const tokenResponse = await fetch(tokenUri || "https://oauth2.googleapis.com/token", {
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

  cachedToken = {
    token: tokenData.access_token,
    expiresAt: now + (tokenData.expires_in ?? 3600) * 1000,
  };
  return cachedToken.token;
}

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

    const accessToken = await getAccessToken(credentials, tokenUri);

    // Parse request body
    const requestBody = await req.json();
    const { action } = requestBody;

    if (action === 'delete') {
      // Handle file deletion
      const { fileId } = requestBody;

      if (!fileId) {
        throw new Error('fileId is required for delete action');
      }

      // Delete from Google Drive
      const deleteResponse = await fetch(
        `https://www.googleapis.com/drive/v3/files/${fileId}?supportsAllDrives=true`,
        {
          method: "DELETE",
          headers: {
            Authorization: `Bearer ${accessToken}`,
          },
        },
      );

      if (!deleteResponse.ok) {
        const text = await deleteResponse.text();
        throw new Error(`Drive delete failed: ${text}`);
      }

      return new Response(
        JSON.stringify({
          success: true,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    } else if (action === "create_upload_session") {
      // Large files never pass through this function. Instead we mint a Drive
      // resumable upload session and hand the URL back; the client PUTs the
      // bytes straight to Google in chunks. That avoids base64 inflation,
      // the edge request-body ceiling, and the memory cost of buffering the
      // whole file here — and it survives a dropped connection.
      const { fileName, folderId, mimeType } = requestBody;

      if (!fileName || !folderId) {
        return new Response(
          JSON.stringify({ success: false, error: "MISSING_FIELDS" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 },
        );
      }

      const sessionResponse = await fetch(
        "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json; charset=UTF-8",
            "X-Upload-Content-Type": mimeType || "application/octet-stream",
          },
          body: JSON.stringify({ name: fileName, parents: [folderId] }),
        },
      );

      if (!sessionResponse.ok) {
        const text = await sessionResponse.text();
        throw new Error(`Drive resumable init failed: ${text}`);
      }

      const sessionUrl = sessionResponse.headers.get("Location");
      if (!sessionUrl) {
        throw new Error("Drive did not return a resumable session URL");
      }

      return new Response(
        JSON.stringify({ success: true, sessionUrl }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    } else if (action === "finalize") {
      // Called after the client finishes a resumable upload, to grant the
      // public read permission the app's image URLs rely on.
      const { fileId } = requestBody;

      if (!fileId) {
        return new Response(
          JSON.stringify({ success: false, error: "MISSING_FIELDS" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 },
        );
      }

      const permResponse = await fetch(
        `https://www.googleapis.com/drive/v3/files/${fileId}/permissions?supportsAllDrives=true`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ role: "reader", type: "anyone" }),
        },
      );

      if (!permResponse.ok) {
        const text = await permResponse.text();
        throw new Error(`Drive permission update failed: ${text}`);
      }

      return new Response(
        JSON.stringify({ success: true, fileId }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    } else {
      // Handle small-file upload inline (default action)
      const { fileName, fileData, folderId, mimeType } = requestBody;

      if (!fileData || !fileName || !folderId) {
        return new Response(
          JSON.stringify({ success: false, error: "MISSING_FIELDS" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 },
        );
      }

      // Reject oversized payloads with a clear 4xx so the client parks the
      // item instead of retrying bytes that can never succeed.
      if (fileData.length > MAX_FILE_DATA_CHARS) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "FILE_TOO_LARGE",
            maxBytes: Math.floor(MAX_FILE_DATA_CHARS * 0.75),
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 413 },
        );
      }

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
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }
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