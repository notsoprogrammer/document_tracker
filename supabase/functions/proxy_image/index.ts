import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Note: This function is designed to be publicly accessible for image proxying
    // No authorization check required as images are served from public Google Drive links
    const url = new URL(req.url);
    const fileId = url.searchParams.get("fileId");

    if (!fileId) {
      return new Response(
        JSON.stringify({ error: "Missing fileId parameter" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ---- Google Service Account Env Vars ----
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

    // ---- Create JWT + Access Token ----
    const jwt = await createJWT(credentials);

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
      throw new Error(`Token error: ${JSON.stringify(tokenData)}`);
    }

    const accessToken = tokenData.access_token;

    // ---- Fetch File From Drive (STREAMED) ----
    // Since files are made public, we can fetch without authorization
    const driveResponse = await fetch(
      `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media`,
      {
        // No authorization needed for public files
      },
    );

    if (!driveResponse.ok) {
      const text = await driveResponse.text();
      throw new Error(`Drive fetch failed: ${text}`);
    }

    // ---- MIME TYPE HANDLING ----
    const driveContentType =
      driveResponse.headers.get("content-type") ??
      "application/octet-stream";

    // Default
    let contentType = driveContentType;

    // Extract filename (if present)
    const disposition = driveResponse.headers.get("content-disposition") ?? "";
    const fileNameMatch = disposition.match(/filename\*?=(?:UTF-8'')?["']?([^"';]+)/i);
    const fileName = fileNameMatch?.[1]?.toLowerCase() ?? "";

    // Extension → MIME map
    const imageMimeMap: Record<string, string> = {
      jpg: "image/jpeg",
      jpeg: "image/jpeg",
      png: "image/png",
      gif: "image/gif",
      bmp: "image/bmp",
      webp: "image/webp",
      heif: "image/heif",
      heic: "image/heic",
    };

    // Fix cases where Drive returns octet-stream
    if (driveContentType === "application/octet-stream" && fileName) {
      const ext = fileName.split(".").pop();

      if (ext && imageMimeMap[ext]) {
        contentType = imageMimeMap[ext];
      } else if (ext === "pdf") {
        contentType = "application/pdf";
      } else if (ext === "docx") {
        contentType =
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
      } else {
        contentType = "application/octet-stream"; // final fallback
      }
    }


    // ---- Determine Content-Disposition ----
    const isImage = contentType.startsWith('image/');
    const contentDisposition = isImage ? 'inline' : 'attachment';

    // ---- Stream response directly ----
    return new Response(driveResponse.body, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": contentType,
        "Content-Disposition": contentDisposition,
        "Cache-Control": "public, max-age=3600",
      },
    });
  } catch (error) {
    console.error("proxy_image error:", error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({ success: false, error: errorMessage }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

/* ------------------------------------------------------------------ */
/* --------------------------- HELPERS --------------------------------*/
/* ------------------------------------------------------------------ */

async function createJWT(credentials: {
  client_email: string;
  private_key: string;
}) {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);

  const payload = {
    iss: credentials.client_email,
    scope: "https://www.googleapis.com/auth/drive.readonly",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encoder = new TextEncoder();
  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(payload));
  const message = `${headerB64}.${payloadB64}`;

  const keyData = pemToDer(credentials.private_key);

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    encoder.encode(message),
  );

  return `${message}.${base64urlBytes(new Uint8Array(signature))}`;
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
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
